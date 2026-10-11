#!/usr/bin/env bash
# pack-crank.sh — build, on the dev machine, the tarball that provision-game-crank.sh installs.
#
#     bash crank/pack-crank.sh <game> <output-directory>
#
# The contents are the same for every game — the whole crank/ tree at HEAD; the game only names
# the file, <game>-crank-<commit>.tar.gz, so the tarball on a machine says which crank it is for.
#
# A machine running a crank gets a tarball rather than a clone, so that what it runs is a named,
# checksummed artifact instead of whatever a working tree happened to hold. This is the only way
# one should be made. It packs COMMITTED BYTES ONLY — `git archive` of HEAD's
# crank tree, never the working tree — and refuses to run while anything under crank/ is
# modified or untracked, so a tarball can never carry an edit that is not in git. A COMMIT file
# holding HEAD's full 40-character id rides at the root of the archive, and the provisioner reads
# it back and prints it, so a machine can always say which commit it runs. node_modules is never
# packed (this repository does not track one; the exclusion is a guard): the host builds its own
# from package-lock.json.
#
# The archive is reproducible: every entry is stamped with HEAD's commit time, so packing the same
# commit twice gives the same bytes and the same sha256. Pass that sha256 to the provisioner.
set -euo pipefail

USAGE="usage: pack-crank.sh <game> <output-directory>"
GAME="${1:?$USAGE}"
OUT_DIR="${2:?$USAGE}"
die() { printf '!! %s\n' "$*" >&2; exit 1; }
# The same shape provision-game-crank.sh accepts, checked here so a tarball is never named for a
# game the provisioner would refuse.
[[ "$GAME" =~ ^[a-z][a-z0-9]{1,30}$ ]] || die "the game name must be 2-31 lowercase letters or digits, starting with a letter, got: $GAME"

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this inside a checkout of this repository"
cd "$ROOT"
[ -f crank/game-crank.mjs ] || die "$ROOT does not look like this repository (no crank/game-crank.mjs)"

# Modified, staged, or untracked — any of them means the tarball would not match the commit.
dirty=$(git status --porcelain -- crank)
[ -z "$dirty" ] || die "crank/ is not clean; commit (or stash) first, the tarball carries committed bytes only:
$dirty"

HEAD_ID=$(git rev-parse HEAD)
SHORT=$(git rev-parse --short=12 HEAD)
STAMP="@$(git log -1 --format=%ct HEAD)"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$GAME-crank-$SHORT.tar.gz"
[ ! -e "$OUT" ] || die "$OUT already exists — remove it yourself if you mean to rebuild it"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$HEAD_ID" > "$tmp/COMMIT"
git archive --format=tar.gz --mtime="$STAMP" --add-file="$tmp/COMMIT" -o "$OUT" HEAD:crank -- . ':!node_modules'

echo "packed   $OUT"
echo "commit   $HEAD_ID"
echo "contents"; tar -tzf "$OUT" | sed 's/^/           /'
echo
echo "sha256   $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "Copy the tarball to the machine, then on the machine — CHECK THE CHECKSUM FIRST, before anything"
echo "is extracted from it (the script inside a tampered tarball would otherwise run as root before"
echo "it could check anything):"
echo "    echo \"<that sha256>  $(basename "$OUT")\" | sha256sum -c"
echo "    tar -xzf $(basename "$OUT") provision-game-crank.sh"
echo "    bash provision-game-crank.sh $GAME $(basename "$OUT") <that sha256>"
