#!/usr/bin/env bash
# provision-game-crank.sh — install ONE game's crank on a fresh Ubuntu 24.04 machine, AND update an
# existing one. The same command does both, which is the point: an update you have to remember four
# steps for is an update that eventually gets done wrong.
#
# The game's short name comes first and decides everything that is per game: the code in
# /opt/<game>-crank, the key and settings in /etc/<game>, the service user <game>, the unit
# <game>-crank.service rendered from game-crank.service, and the module n_…<ns>.<game>. Two games on
# one machine are two runs of this script, two users, two keys, two units — nothing shared but Node.
# With GAME=roulette the result is exactly the layout provision-roulette-crank.sh produces.
#
# Run ON THE MACHINE, as root. The code arrives as a TARBALL, not a git clone, so that what runs is
# a named, checksummed artifact — built by pack-crank.sh from committed bytes only. Copy the tarball to
# the machine, then run the copy of this script that the tarball itself contains, passing the
# tarball's sha256 as pack-crank.sh printed it:
#
#     echo "<sha256>  <game>-crank-<commit>.tar.gz" | sha256sum -c     # FIRST, before extracting anything
#     tar -xzf <game>-crank-<commit>.tar.gz provision-game-crank.sh
#     bash provision-game-crank.sh <game> <game>-crank-<commit>.tar.gz <sha256>
#
# 🔴 The checksum line comes FIRST because this script lives INSIDE the tarball: the sha256 check
# below runs only after you have already extracted and started it as root. Against a corrupted
# copy that is enough; against a tampered one only the line above is. The `cmp` further down then
# proves the script you ran is the one the verified tarball contains.
#
# TO UPDATE, run exactly the same thing with the new tarball. It verifies the checksum, replaces the
# code, reinstalls dependencies from the lockfile, replaces the unit — and RESTARTS the service if it
# was running, because replacing files does not replace the process: node read its code at startup,
# so without a restart you get new files on disk and the old bot still resolving rounds, silently.
#
# What it NEVER touches: your key (/etc/<game>/crank-key.json) and your settings
# (/etc/<game>/crank.env). Both live outside /opt/<game>-crank precisely so an update cannot
# reach them. It never regenerates a key — that would orphan whatever the old account holds — and
# it never starts a bot that was not already running: enabling it is what starts sending
# transactions, and that stays a human decision.
#
# Modelled step by step on the prize-draw crank's provision-crank.sh, itself modelled on
# block-history's provisioning script, which runs this shape on a live host. The comments that
# look over-specific are all scars: read them before "simplifying" one.
set -euo pipefail

NODE_VERSION="v24.21.0"
# node-v24.21.0-linux-x64.tar.xz. This value is COPIED from prize-draw-crank/provision-crank.sh
# line 31, where it was read in full from https://nodejs.org/dist/v24.21.0/SHASUMS256.txt; the
# copy was compared to that line character by character before it was pasted here.
NODE_SHA256="fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6"
# The namespace every production game module lives in; the module is "$HOUSE_NS.$GAME". The unit
# names it explicitly because the crank has no default module. A different name for one game is set
# in /etc/<game>/crank.env (CRANK_MOD=…), which overrides the unit.
HOUSE_NS=n_48867b242317a0216a67f8c7ca26696b5878e0e3
USAGE="usage: provision-game-crank.sh <game> <tarball-path> <sha256>"
GAME="${1:?$USAGE}"
TARBALL="${2:?$USAGE}"
PIN="${3:?$USAGE}"
# The name becomes a user name, two directory names, a unit name and a sed replacement, so it is
# held to the narrowest shape that is valid as all of them: lowercase, starting with a letter.
[[ "$GAME" =~ ^[a-z][a-z0-9]{1,30}$ ]] || { printf '\n!! STOPPED: the game name must be 2-31 lowercase letters or digits, starting with a letter, got: %s\n' "$GAME" >&2; exit 1; }
APP=/opt/$GAME-crank
SVC_USER=$GAME
CONF_DIR=/etc/$GAME
KEY="$CONF_DIR/crank-key.json"
ENV_FILE="$CONF_DIR/crank.env"
UNIT=$GAME-crank.service
MOD="$HOUSE_NS.$GAME"
TEMPLATE=game-crank.service
SELF=provision-game-crank.sh
# The variables the game's older, single-game crank read: ROULETTE_HOST and so on for roulette.
LEGACY_PREFIX="${GAME^^}_"

say()  { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ok: %s\n' "$*"; }
skip() { printf '    SKIPPED: %s\n' "$*"; SKIPPED+=("$*"); }
die()  { printf '\n!! STOPPED: %s\n   Nothing after this point was done.\n' "$*" >&2; exit 1; }
SKIPPED=()

HAVE_SYSTEMD=0; [ -d /run/systemd/system ] && HAVE_SYSTEMD=1
IN_CONTAINER=0; [ -f /.dockerenv ] && IN_CONTAINER=1

# ---------------------------------------------------------------------------------------------
say "0. Preconditions"
[ "$(id -u)" = 0 ] || die "run as root"
# shellcheck source=/dev/null
. /etc/os-release
[ "${ID:-}" = ubuntu ] || die "Ubuntu required (found ${ID:-unknown})"
[ "$(uname -m)" = x86_64 ] || die "x86_64 required — the Node pin is for linux-x64"
[[ "$PIN" =~ ^[0-9a-f]{64}$ ]] || die "the pin must be the tarball's full 64-character sha256, got: $PIN"
[ -f "$TARBALL" ] && [ -r "$TARBALL" ] || die "no readable tarball at $TARBALL"
if [ $HAVE_SYSTEMD = 0 ] && [ $IN_CONTAINER = 0 ]; then die "no systemd and not a container — unsupported host"; fi
[ $IN_CONTAINER = 1 ] && echo "    NOTE: running in a CONTAINER (rehearsal). Firewall, swap and service steps will be skipped."
# Is this an update of a bot that is currently running? Decided BEFORE anything changes, because
# after the code is replaced the answer would describe the new state instead of the one we must restore.
WAS_ACTIVE=0
if [ $HAVE_SYSTEMD = 1 ] && systemctl is-active --quiet "$UNIT"; then WAS_ACTIVE=1; fi
ok "Ubuntu ${VERSION_ID:-?}, x86_64, root$([ $WAS_ACTIVE = 1 ] && echo ' — the crank is RUNNING and will be restarted at the end')"
# 🔴 A SETTING THE NEW CRANK WOULD SILENTLY IGNORE. The settings file is never edited by this
# script, and game-crank.mjs reads CRANK_*, not the older crank's ${LEGACY_PREFIX}* names: a
# ${LEGACY_PREFIX}HOST pointing a second machine at a second node would be dropped without a word
# and both cranks would share one node. Refused here, before anything is changed.
if [ -f "$ENV_FILE" ] && legacy=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${LEGACY_PREFIX}[A-Z_]*=" "$ENV_FILE"); then
  die "$ENV_FILE still sets the older crank's variables, which game-crank.mjs does not read — rename each ${LEGACY_PREFIX}X to CRANK_X (same value), then run this again:
$legacy"
fi
ok "game $GAME: $APP, $CONF_DIR, user $SVC_USER, $UNIT, module $MOD"

# ---------------------------------------------------------------------------------------------
say "1. Swap — a small box can spike past its RAM while installing"
if [ $IN_CONTAINER = 1 ]; then skip "swap (container)"
elif [ -n "$(swapon --show --noheadings 2>/dev/null)" ]; then ok "swap already present"
else
  fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  ok "1 GiB swap enabled and made permanent"
fi

# ---------------------------------------------------------------------------------------------
say "2. System packages"
# A fresh cloud host runs its own apt jobs in its first minutes. Measured on apt 2.8:
# -o DPkg::Lock::Timeout makes `install` wait for the dpkg lock but NOT `update` for the
# package-list lock, so the retry loop is what actually covers a held lock.
if command -v cloud-init >/dev/null 2>&1; then timeout 600 cloud-init status --wait >/dev/null 2>&1 || true; fi
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_SUSPEND=1
apt_retry() {
  local i out
  for i in $(seq 1 60); do
    if out=$(apt-get -o DPkg::Lock::Timeout=60 -qq "$@" 2>&1); then return 0; fi
    grep -q 'Could not get lock' <<<"$out" || { printf '%s\n' "$out" >&2; return 1; }
    [ "$i" = 1 ] && echo "    NOTE: another apt job holds a lock (normal on a fresh cloud host) — waiting for it, up to ~10 minutes"
    sleep 10
  done
  printf '%s\n' "$out" >&2; return 1
}
apt_retry update || die "apt-get update failed"
# No git: the code comes from a tarball. xz-utils is for the Node tarball.
apt_retry install -y ca-certificates curl xz-utils ufw unattended-upgrades || die "installing system packages failed"
ok "curl, xz-utils, ufw, unattended-upgrades"

say "3. Automatic security updates"
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
ok "security updates install themselves daily"

# ---------------------------------------------------------------------------------------------
say "4. Firewall — nothing listens except SSH; the crank only makes outbound connections"
if [ $IN_CONTAINER = 1 ]; then skip "firewall (container)"
else
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow OpenSSH >/dev/null
  ufw --force enable >/dev/null
  ok "inbound: SSH only"
fi

say "5. SSH — keys only"
# sshd keeps the FIRST value it reads for each setting and cloud-init writes 50-cloud-init.conf,
# so this file is named 01-… to be read first: measured on a clean Ubuntu 24.04, the same file
# named 60-… was silently overridden by cloud-init's "PasswordAuthentication yes".
# The two machines this crank is meant for already carry another bot's provisioner, and its
# 01-… drop-in: so read what sshd will ACTUALLY use first, and when password login is already off
# say so and write nothing — a second file saying the same thing is a second file to reason about.
SSHD_DROPIN=/etc/ssh/sshd_config.d/01-$GAME.conf
if ! command -v sshd >/dev/null 2>&1 || [ ! -d /etc/ssh/sshd_config.d ]; then
  skip "SSH hardening (no sshd on this host)"
else
  mkdir -p /run/sshd     # sshd -t/-T fail with "Missing privilege separation directory" without it
  # Captured first and matched without a pipe: `sshd -T | grep -q` under pipefail fails whenever
  # grep exits early and sshd -T dies of SIGPIPE.
  effective=$(sshd -T 2>/dev/null || true)
  if grep -qx 'passwordauthentication no' <<<"$effective"; then
    ok "already hardened: password login is OFF in sshd's effective configuration (an earlier provisioner did it) — no second drop-in written"
  elif [ ! -s /root/.ssh/authorized_keys ]; then
    # Refusing here is the point: turning passwords off with no key installed locks you out for good.
    skip "password login left as it was — /root/.ssh/authorized_keys is empty, and disabling passwords now would lock you out"
  elif ! pre=$(sshd -t 2>&1); then
    skip "SSH hardening — sshd's existing configuration already fails its own check, so it was left alone: ${pre:0:160}"
  else
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > "$SSHD_DROPIN"
    if ! err=$(sshd -t 2>&1); then
      rm -f "$SSHD_DROPIN"; die "the hardening made sshd's own check fail, so it was removed: ${err:0:160}"
    fi
    if ! effective=$(sshd -T 2>/dev/null); then
      rm -f "$SSHD_DROPIN"; die "could not read sshd's effective configuration, so the hardening was removed"
    fi
    if ! grep -qx 'passwordauthentication no' <<<"$effective"; then
      rm -f "$SSHD_DROPIN"; die "password login is still ON in sshd's effective configuration (another file overrides it), so the hardening was removed"
    fi
    [ $HAVE_SYSTEMD = 1 ] && { systemctl try-reload-or-restart ssh.service 2>/dev/null || systemctl try-reload-or-restart sshd.service 2>/dev/null \
        || echo "    NOTE: ssh could not be reloaded now; the setting applies the next time ssh starts"; }
    ok "password login disabled in sshd's effective configuration; your SSH key still works"
  fi
fi

# ---------------------------------------------------------------------------------------------
say "6. Node $NODE_VERSION, verified against its pinned checksum"
if [ -x "/opt/node-$NODE_VERSION/bin/node" ]; then ok "already installed"
else
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/node.tar.xz" "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.xz" || { rm -rf "$tmp"; die "could not download Node"; }
  echo "$NODE_SHA256  $tmp/node.tar.xz" | sha256sum -c - >/dev/null || { rm -rf "$tmp"; die "Node tarball checksum MISMATCH — refusing to install it"; }
  mkdir -p "/opt/node-$NODE_VERSION"
  tar -xJf "$tmp/node.tar.xz" -C "/opt/node-$NODE_VERSION" --strip-components=1
  rm -rf "$tmp"
  ok "installed from a checksum-verified tarball"
fi
for b in node npm npx; do ln -sf "/opt/node-$NODE_VERSION/bin/$b" "/usr/local/bin/$b"; done
[ "$(/usr/local/bin/node --version)" = "$NODE_VERSION" ] || die "node --version is not $NODE_VERSION"
ok "node $NODE_VERSION on the path"

# ---------------------------------------------------------------------------------------------
say "7. The service user"
# No login shell, no sudo, and it does NOT own the code: the code is root's and the service can
# only read it, so a compromised crank cannot rewrite what it runs.
if id "$SVC_USER" >/dev/null 2>&1; then ok "exists"
else useradd --system --home-dir "/var/lib/$SVC_USER" --create-home --shell /usr/sbin/nologin "$SVC_USER"; ok "created"; fi

# ---------------------------------------------------------------------------------------------
say "8. The code, from the tarball whose checksum you pinned"
# The tarball is verified, then unpacked into a STAGING directory beside $APP and checked there,
# and only a tarball that passes every check replaces the installed code: a bad update must never
# leave a half-replaced tree where a running bot's code used to be.
echo "$PIN  $TARBALL" | sha256sum -c - >/dev/null || die "the tarball's sha256 does not match the pin — a corrupted copy, or the wrong tarball"
OLD=$(cat "$APP/COMMIT" 2>/dev/null || echo none)
STAGE="$APP.new"
rm -rf "$STAGE"; install -d -m 0755 -o root -g root "$STAGE"
tar -xzf "$TARBALL" -C "$STAGE" || { rm -rf "$STAGE"; die "the tarball did not unpack"; }
chown -R root:root "$STAGE"
for f in COMMIT game-crank.mjs package.json package-lock.json crank-keygen.mjs key-backup.mjs crank.env.example "$TEMPLATE" "$SELF"; do
  [ -f "$STAGE/$f" ] || { rm -rf "$STAGE"; die "the tarball does not contain $f — not a crank tarball that pack-crank.sh built"; }
done
COMMIT=$(tr -d '[:space:]' < "$STAGE/COMMIT")
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || { rm -rf "$STAGE"; die "the tarball's COMMIT file does not hold a full 40-character commit id: $COMMIT"; }
# The script you ran must be the one the tarball contains, or the pin means nothing.
cmp -s "$0" "$STAGE/$SELF" || { rm -rf "$STAGE"; die "this script differs from the copy inside the tarball — unpack $SELF from this exact tarball and run that one"; }
[ ! -L "$STAGE/node_modules" ] || rm -f "$STAGE/node_modules"   # never a symlink into a dev checkout; npm ci builds the real one
rm -rf "$APP"
mv "$STAGE" "$APP"
if [ "$OLD" = "$COMMIT" ]; then ok "already at commit $COMMIT (the same bytes, reinstalled)"; else ok "$OLD -> $COMMIT, tarball sha256 verified, script matches the copy inside it"; fi

say "9. Dependencies, exactly as locked"
cd "$APP"
# npm verifies every package against the sha512 integrity recorded in package-lock.json. Re-run on
# every update: a new tarball can carry a new lockfile, and "it already has node_modules" is how a
# bot ends up running one version's code against another's dependencies.
npm ci --omit=dev --ignore-scripts --no-audit --no-fund --loglevel=error || die "npm ci failed"   # locked bytes, no install-time code as root
ok "installed from package-lock.json"

# ---------------------------------------------------------------------------------------------
say "10. Your settings and your key — created if missing, NEVER overwritten"
install -d -m 0700 -o "$SVC_USER" -g "$SVC_USER" "$CONF_DIR"
if [ -f "$ENV_FILE" ]; then ok "$ENV_FILE kept exactly as it is"
else
  # A game that ships its own example gets that one: the generic file sets no claim sizing, and
  # game-crank.mjs refuses to start slots without it, which stopped a fresh slots box at step 12.
  EXAMPLE=crank.env.example; [ ! -f "$APP/$GAME.env.example" ] || EXAMPLE=$GAME.env.example
  install -m 0600 -o root -g root "$APP/$EXAMPLE" "$ENV_FILE"
  ok "$ENV_FILE created from $EXAMPLE — edit it to set HEARTBEAT_URL"
fi
if [ -f "$KEY" ]; then ok "key already exists — NOT regenerated"
else
  runuser -u "$SVC_USER" -- /usr/local/bin/node "$APP/crank-keygen.mjs" "$KEY" >/dev/null || die "key generation failed"
  ok "new key generated"
fi
[ "$(stat -c '%a %U' "$KEY")" = "600 $SVC_USER" ] || die "key file must be mode 600 owned by $SVC_USER, found: $(stat -c '%a %U' "$KEY")"
# The FLAT shape game-crank.mjs reads: publicKey at the top level, no persona wrapper.
PUB=$(runuser -u "$SVC_USER" -- /usr/local/bin/node -e "process.stdout.write(String(require('$KEY').publicKey))")
[[ "$PUB" =~ ^[0-9a-f]{64}$ ]] || die "the service user could not read a valid top-level publicKey from its own key file — it must be the flat {account, publicKey, secretKey} shape crank-keygen.mjs writes"
ok "mode 600, owned by $SVC_USER, readable by the service"

# ---------------------------------------------------------------------------------------------
say "11. The service, rendered from the template for $GAME"
# Rendered, never edited by hand: an update renders it again from the new tarball's template, so a
# hand edit to the installed unit is lost at the next update. Settings belong in $ENV_FILE.
RENDERED=$(mktemp)
sed -e "s|@GAME@|$GAME|g" -e "s|@MOD@|$MOD|g" "$APP/$TEMPLATE" > "$RENDERED"
# A placeholder the substitution missed would reach systemd as a literal user or path.
! grep -n '@[A-Z]*@' "$RENDERED" || { rm -f "$RENDERED"; die "the rendered unit still holds a template placeholder (above)"; }
for want in "User=$SVC_USER" "WorkingDirectory=$APP" "Environment=GAME=$GAME" "Environment=CRANK_MOD=$MOD" \
            "Environment=CRANK_BOT_KEY=$KEY" "EnvironmentFile=-$ENV_FILE" "ExecStart=/usr/local/bin/node game-crank.mjs"; do
  grep -qxF "$want" "$RENDERED" || { rm -f "$RENDERED"; die "the rendered unit lacks the line: $want"; }
done
install -d -m 755 /etc/systemd/system
install -m 644 "$RENDERED" "/etc/systemd/system/$UNIT"
rm -f "$RENDERED"
ok "/etc/systemd/system/$UNIT rendered for $GAME"
if [ $HAVE_SYSTEMD = 1 ]; then
  systemctl daemon-reload
  systemd-analyze verify "/etc/systemd/system/$UNIT" || die "systemd rejected the unit file"
  if [ $WAS_ACTIVE = 1 ]; then
    # THE STEP THAT MAKES THIS AN UPDATE. Node read its code at startup: without this the new
    # tarball sits on disk while the old process keeps resolving rounds.
    systemctl restart "$UNIT" || die "the crank did not come back up — check: journalctl -u $UNIT -n 50"
    sleep 3
    systemctl is-active --quiet "$UNIT" || die "the crank started and then exited — check: journalctl -u $UNIT -n 50"
    ok "restarted at commit $COMMIT and running"
  elif systemctl is-enabled "$UNIT" >/dev/null 2>&1; then
    ok "installed and verified. It is ENABLED but was not running — start it when you mean to: systemctl start $UNIT"
  else
    ok "installed and verified. Deliberately NOT enabled and NOT started."
  fi
else skip "systemd registration (container) — the unit file is written but not loaded"; fi

# ---------------------------------------------------------------------------------------------
say "12. Can this machine reach the chain? (one pass under the unit's own environment)"
# Run as the service user with the unit's own environment, so a setting that would stop the crank
# shows up now rather than after you enable it. This is ONE REAL PASS: on a fresh host the key is
# unfunded, its balance is unreadable rather than zero, and the crank goes on to read the table, so
# the pass succeeds only when the module is deployed and initialised — provision AFTER those rows;
# before them the pass fails at its first read and this stage stops (stages 0-11 are done by then,
# and running the script again keeps the key and the settings). On an UPDATE of a funded, live crank
# the pass may send what any pass sends — a resolve, a claim batch, a liveness proof — alongside the
# restarted service; every one of those calls is permissionless and a collision is logged as benign,
# so the only cost is the gas of the loser of the race.
# Built as an ARRAY, never as a word-split string: one Environment= value containing a space
# would otherwise silently become two arguments and the test would run a different configuration
# from the service it is meant to be testing.
ENVS=()
while IFS= read -r line; do ENVS+=("${line#Environment=}"); done < <(grep '^Environment=' "/etc/systemd/system/$UNIT")
if [ $HAVE_SYSTEMD = 1 ]; then
  RUN=(systemd-run --quiet --wait --pipe --collect --uid="$SVC_USER" --gid="$SVC_USER"
       --working-directory="$APP" -p "EnvironmentFile=-$ENV_FILE")
  for e in "${ENVS[@]}"; do RUN+=(-E "$e"); done
else
  # Container rehearsal: there is no systemd-run, so the unit's environment is assembled by hand —
  # its Environment= lines first, then the settings file's own lines, which win exactly as they
  # do under systemd. (The prize-draw provisioner has no such branch and dies here in a container.)
  RUN=(runuser -u "$SVC_USER" -- env -C "$APP" "${ENVS[@]}")
  if [ -f "$ENV_FILE" ]; then
    while IFS= read -r line; do case "$line" in ''|'#'*) ;; *) RUN+=("$line") ;; esac; done < "$ENV_FILE"
  fi
fi
set +e
OUT=$("${RUN[@]}" /usr/local/bin/node game-crank.mjs --once 2>&1)
RC=$?
set -e
if [ $RC = 0 ]; then ok "it read the live table and made one pass"
else
  printf '%s\n' "$OUT" | tail -5 >&2
  die "the crank could not make a pass here (exit $RC) — the lines above say why"
fi

# ---------------------------------------------------------------------------------------------
cat <<EOF

================================================================================
  $GAME crank at commit $COMMIT, serving $MOD
  (tarball sha256 $PIN)

  ITS ACCOUNT (pays gas, holds no privilege, earns nothing):

      k:$PUB
================================================================================
EOF
if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo "  Skipped on this host:"; for s in "${SKIPPED[@]}"; do echo "    - $s"; done
fi
if [ $WAS_ACTIVE = 1 ]; then
  cat <<EOF

  It was running, so it has been restarted on the new commit:
      journalctl -u $UNIT -n 20 --no-pager
EOF
else
  cat <<EOF

  Next, in this order:
    1. Back up the key, and prove the backup opens:
         node $APP/key-backup.mjs save $KEY /root/$GAME-crank-key.backup
         node $APP/key-backup.mjs check /root/$GAME-crank-key.backup
       Then copy it off this machine and delete the copy here.
    2. Edit $ENV_FILE — set HEARTBEAT_URL.
    3. Fund k:$PUB on chain 2 (about 1 KDA covers a year at a busy table).
    4. Only when the contract is deployed, start sending:
         systemctl enable --now $UNIT
         journalctl -u $UNIT -f
EOF
fi
