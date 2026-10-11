#!/usr/bin/env bash
# The player terms state numbers. Those numbers must BE the contract's, not a
# hand-maintained copy that drifts. This reads both and compares.
#
# The dials, floors, window, wait, refund grace and spin count are read from
# slots.pact's own defconst values. Each machine's strip counts, paytable, top
# prize, return, edge and hit rate are RECOMPUTED here from the MACHINES literal:
# the line and wild returns by weighting every symbol triple, the tumble return
# and hit rate by playing every one of the 262,144 windows, and the free-spins
# return from the fraction the contract pins (its rules suite reproduces it).
# The block-gap measurement is a pinned literal: a measurement, not a rule.
# The board's shape is read from the forms that enforce it: a board holds exactly one
# entry (validate-wager's count enforce, with its words), that one entry validated, the board's
# reserve booked at its machine's top prize and the round limit binding every board (bet).
#
# The "sized to keep" figure is the operator's rule over the bankroll simulation
# (at 1 % of the spare pot per top prize, no simulated year on any machine lost
# the room for one such board), not a contract rule, so its 1 %
# is a pinned literal here. The six example figures at a 15,000 pot are
# RECOMPUTED from the machines' top prizes (MAX-MULTS = max-units / div). The
# old open-item marker must be ABSENT.
set -uo pipefail
cd "$(dirname "$0")/../.."
DOC=docs/SLOTS-PLAYER-TERMS.md
SRC=pact/modules/slots.pact
BEACON=pact/modules/drand.pact
BAD=0; OK=0
OPEN_MARK='[SIZED-TO-KEEP: pending bankroll Q3]'
SIZED_PCT=1   # the operator's rule: 1 % of the spare pot per top prize (a simulation result, not in slots.pact)

[ -f "$DOC" ] || { echo "  BAD   $DOC is missing"; echo "  terms BAD: 1"; exit 1; }

konst () { grep -oE "\(defconst $1:[a-z]+ [^)]*\)" "${2:-$SRC}" | head -1 | grep -oE '[0-9.]+' | head -1; }
# The doc is matched with its lines joined, so a sentence the prose wraps is still one sentence.
JOINED=$(tr '\n' ' ' < "$DOC" | tr -s ' ')
want () { # want <label> <expected> <pattern-that-must-appear>
  if [ -z "$2" ] || [ -z "$3" ]; then
    printf '  BAD   %-44s could not read the expected value from the contract\n' "$1"; BAD=$((BAD+1))
  elif printf '%s' "$JOINED" | grep -qF -- "$3"; then printf '  OK    %-44s %s\n' "$1" "$2"; OK=$((OK+1))
  else printf '  BAD   %-44s doc does not say %s\n' "$1" "$3"; BAD=$((BAD+1)); fi
}
g () { python3 -c "print('%g' % ($1))"; }
grp () { python3 -c "print(f'{int($1):,}')"; }

MINBET=$(konst LAUNCH-MIN-BET); FLOOR=$(konst MIN-BET-FLOOR)
WINDOW=$(konst LAUNCH-BET-WINDOW); MINWIN=$(konst MIN-BET-WINDOW); MAXWIN=$(konst MAX-BET-WINDOW)
MARGIN=$(konst LAUNCH-DRAND-MARGIN); MINMARGIN=$(konst MIN-DRAND-MARGIN); MAXMARGIN=$(konst MAX-DRAND-MARGIN)
VOIDS=$(konst VOID-AFTER); FRAC=$(konst LAUNCH-RESERVE-FRACTION); MAXFRAC=$(konst MAX-RESERVE-FRACTION)
SPINS=$(konst MAX-SPINS); REEL=$(konst REEL-SIZE); NMACH=$(konst MACHINE-COUNT)
FREESPINS=$(konst FREE-SPINS); FREEMULT=$(konst FREE-MULT); FREEMAX=$(konst FREE-MAX); FREECAP=$(konst FREE-CAP)
TUMBLEMAX=$(konst TUMBLE-MAX); PERIOD=$(konst PERIOD "$BEACON")

# ---- the board's shape, read from validate-wager and bet ----------------------
# How many entries a board may hold is the count validate-wager enforces, resolved to a number,
# with the words a refused board is given; the one entry is then validated. The booked reserve
# and the round limit are read from the forms that do them. A form that moved or changed shape
# reads as empty and fails, never passes.
BOARD=$(python3 - "$SRC" <<'PY'
import re, sys
src = '\n'.join(l.split(';')[0] for l in open(sys.argv[1]).read().splitlines())
def fn(name):
    i = src.find('(defun %s:' % name)
    if i < 0: return ''
    j = src.find('(defun ', i + 1)
    return src[i:j if j > 0 else len(src)]
vw, bet, er = fn('validate-wager'), fn('bet'), fn('entries-reserve')
m = re.search(r'\(enforce \(= (\d+) \(length es\)\) "(a board plays one machine: it holds exactly one entry)"\)', vw)
n = m.group(1) if m and '(validate-entry (at 0 es) min-bet)' in vw else ''
words = m.group(2).split(':')[0] if m else ''
# the reserve is the entry at its own machine's maximum; the limit binds the round's exposure
# plus fee, where this board adds its whole reserve
booked = "(board-reserve (at 'machine e) (entry-total e))" in er
whole = '(own (entries-reserve es))' in bet and '(new-ex (+ ex own))' in bet and \
        '(enforce (<= (+ new-ex new-fee) cap)' in bet and '(total (validate-wager w mb))' in bet
# "|", never a tab: read collapses consecutive whitespace separators, which would shift an EMPTY field onto the next row
print(f"{n}|{words}|{'booked' if booked else ''}|{'whole' if whole else ''}")
PY
)
IFS='|' read -r NMAXE WORDS BOOKED WHOLE <<< "$BOARD"
[ "$NMAXE" = 1 ] || NMAXE=""
want "one machine per board"        "${NMAXE:-?}" "${NMAXE:+**A board plays one machine.**}"
want "one machine (round)"          "${NMAXE:-?}" "${NMAXE:+**You place a board**: one machine, a stake per spin}"
want "one machine (limit 5)"        "${NMAXE:-?}" "${NMAXE:+One board per account per round, playing one machine, signed once.}"
want "refusal words"                "${WORDS:-?}" "${WORDS:+(\"$WORDS\")}"
# a structural reading that failed leaves its flag empty: the row then reports BAD, never OK
wantif () { want "$1" "${2:-not read}" "$([ -n "$2" ] && printf '%s' "$3")"; }
wantif "reserve booked"         "$BOOKED" "every spin of the board paying its machine's top prize"
wantif "limit counts the round" "$WHOLE"  "**The round limit counts every board in the round together.**"
wantif "board fits as a whole"  "$WHOLE"  "if it does not fit, it is not placed"

WORD () { python3 -c "print({1:'one',2:'two',3:'three',4:'four',5:'five',6:'six',7:'seven',8:'eight',9:'nine',10:'ten'}[int(float('$1'))])"; }
want "machines"             "$NMACH"               "**$(python3 -c "print('$(WORD "$NMACH")'.capitalize())") slot machines run on one contract"
want "stops per strip"      "$REEL"                "public strip of **$REEL stops**"
want "spins per board"      "1..$SPINS"            "from **1 to $SPINS**"
want "spins per board (round)" "1..$SPINS"         "1 to $SPINS spins. This is the only thing you sign"
want "whole board decided"  "$SPINS"               "${NMAXE:+Up to $SPINS spins, all on one machine, are committed in the one signature}"
want "minimum per spin"     "$MINBET KDA"          "**$(g "$MINBET") KDA** minimum per spin today"
want "minimum floor"        "$FLOOR KDA"           "below **$(g "$FLOOR") KDA**"
want "minimum floor (limit 9)" "$FLOOR KDA"        "never below $(g "$FLOOR") KDA, no ceiling"
want "betting window"       "${WINDOW%.*}s"        "**Betting closes ${WINDOW%.*} seconds**"
want "window floor"         "${MINWIN%.*}s"        "never under ${MINWIN%.*} seconds, never over an hour"
want "window range (limit 9)" "[${MINWIN%.*}, ${MAXWIN%.*}]" "(${MINWIN%.*} seconds to an hour)"
want "drand margin"         "${MARGIN%.*}s"        "**${MARGIN%.*} seconds after betting closes**"
want "drand margin floor"   "${MINMARGIN%.*}s"     "never below **${MINMARGIN%.*} seconds**, never above an hour"
want "margin range (limit 9)" "[${MINMARGIN%.*}, ${MAXMARGIN%.*}]" "(${MINMARGIN%.*} seconds to an hour)"
want "margin in limit 3"    "${MARGIN%.*}s"        "(${MARGIN%.*} seconds, and never less)"
want "drand period"         "${PERIOD}s"           "a new random number every $PERIOD seconds"
want "refund grace"         "$(python3 -c "print(int(float('$VOIDS')/86400))") days" "rounds refund after $(python3 -c "print(int(float('$VOIDS')/86400))") days"
want "refund grace (who acts)" "$(python3 -c "print(int(float('$VOIDS')/86400))") days" "nobody acts for $(python3 -c "print(int(float('$VOIDS')/86400))") days"
want "table share"          "$(g "$FRAC*100")%"    "**$(g "$FRAC*100")%** of the house's spare capital"
want "table share ceiling"  "$(g "$MAXFRAC*100")%" "above **$(g "$MAXFRAC*100")%** of the pot's spare capital"
want "share range (limit 9)" "(0, $(g "$MAXFRAC*100")%]" "(above zero, at most $(g "$MAXFRAC*100")%)"
want "free spins awarded"   "$FREESPINS"           "awards **$FREESPINS free spins** that pay **$FREEMULT times** their line"
want "free spins retrigger" "$FREESPINS"           "can retrigger **$FREESPINS more**, up to **$FREEMAX free spins** per trigger"
want "free spins cap"       "$FREECAP"             "reaches **$FREECAP times** the spin's stake"
want "tumble cascades"      "$TUMBLEMAX"           "at most **$TUMBLEMAX cascades** per spin"

want "tumble lines"          "5"               "on any of **$(python3 -c "import re;s=open('$SRC').read();print(len(re.findall(r'\[\d \d \d\]', re.search(r'TUMBLE-LINES:\S+ (\[.*?\]\])', s).group(1))))") lines**"

# ---- each machine, recomputed from the MACHINES literal -----------------------------
ROWS=$(python3 - "$SRC" "$FRAC" "$SIZED_PCT" <<'PY'
import re, sys
from fractions import Fraction as F
from decimal import Decimal, ROUND_HALF_EVEN, ROUND_FLOOR
src = '\n'.join(l.split(';')[0] for l in open(sys.argv[1]).read().splitlines())
share = Decimal(sys.argv[2])
blk = src[src.index('(defconst MACHINES'):]
blk = blk[:blk.index('(defconst MACHINE-COUNT')]
ms = []
for m in re.finditer(r'\{(.*?)\}', blk, re.S):
    b = m.group(1)
    g = lambda k: re.search(r'"%s"\s*:\s*' % k + r'("[^"]*"|\[[^\]]*\]|-?\d+)', b).group(1)
    ms.append(dict(id=int(g('id')), name=g('name').strip('"'), kind=g('kind').strip('"'),
                   reel=[int(x) for x in g('reel')[1:-1].split()], pays=[int(x) for x in g('pays')[1:-1].split()],
                   maxu=int(g('max-units')), div=int(g('div')), pinned=[int(x) for x in g('pinned-return')[1:-1].split()]))
if len(ms) != 6:
    print(f"read\t{len(ms)} machines\tcould not read six machines from MACHINES"); sys.exit(0)
wild_form = src[src.index('(defun wild-pay'):]
WM = int(re.search(r'\(m \(if \(> nw 0\) (\d+) 1\)\)', wild_form).group(1))
BLANK, CHERRY, BELL, BAR, SEVEN, SPECIAL = range(6)
high = lambda s: BELL <= s <= SEVEN
base = lambda p, s: {SEVEN: p[0], BAR: p[1], BELL: p[2], CHERRY: p[3]}.get(s, 0)
def line(p, a, b, c):
    if a == b == c: return base(p, a)
    if high(a) and high(b) and high(c): return p[4]
    n = [a, b, c].count(CHERRY)
    return p[5] if n == 2 else p[6] if n == 1 else 0
def wild(p, a, b, c):
    sy = [a, b, c]; nw = sy.count(SPECIAL); rest = [x for x in sy if x != SPECIAL]; m = WM if nw else 1
    if nw == 3: return p[7]
    r0 = rest[0]
    kind = m * base(p, r0) if r0 != BLANK and rest.count(r0) == len(rest) else 0
    hi = m * p[4] if all(high(x) for x in rest) else 0
    n = sy.count(CHERRY)
    return max(kind, hi, p[5] if n == 2 else p[6] if n == 1 else 0)
LINES = [[int(x) for x in t] for t in re.findall(r'\[(\d) (\d) (\d)\]', re.search(r'TUMBLE-LINES:\S+ (\[.*?\]\])', src).group(1))]
TMAX = int(re.search(r'\(defconst TUMBLE-MAX:integer (\d+)\)', src).group(1))
def tumble(reel, p, stops):
    sym = lambda s: reel[s % 64]
    cols = [[sym(s), sym(s + 1), sym(s + 2)] for s in stops]; ptr = [s + 3 for s in stops]; units = 0
    for k in range(1, TMAX + 1):
        wins = [l for l in LINES if cols[0][l[0]] != BLANK and cols[0][l[0]] == cols[1][l[1]] == cols[2][l[2]]]
        if not wins: break
        units += k * sum(p[cols[0][l[0]] - 1] for l in wins)
        nc, np_ = [], []
        for i in range(3):
            hit = {l[i] for l in wins}
            keep = [cols[i][r] for r in range(3) if r not in hit]
            need = 3 - len(keep)
            nc.append(keep + [sym(ptr[i] + d) for d in range(need)]); np_.append(ptr[i] + need)
        cols, ptr = nc, np_
    return units
pct = lambda f, n: format((Decimal(f.numerator) * 100 / Decimal(f.denominator)).quantize(Decimal(1).scaleb(-n), rounding=ROUND_HALF_EVEN), 'f')
def num(x):
    if isinstance(x, F): x = Decimal(x.numerator) / Decimal(x.denominator)
    return format(Decimal(x).normalize(), 'f')
T = 64 ** 3
out = []
for m in ms:
    n, r, p, k = m['name'], m['reel'], m['pays'], m['kind']
    if len(r) != 64:
        out.append((f"{n} strip", f"{len(r)} stops", f"a {n} strip of 64 stops")); continue
    c = [r.count(x) for x in range(6)]
    names = [('blanks', c[0]), ('cherries', c[1]), ('bells', c[2]), ('bars', c[3]), ('sevens', c[4])]
    if c[5]: names.append(('wilds' if k == 'wild' else 'scatters', c[5]))
    strip = ', '.join(f"{v} {w}" for w, v in names if v)
    out.append((f"{n} strip counts", strip, f"**{n} strip**: {strip}."))
    top = F(m['maxu'], m['div'])
    if k == 'tumble':
        pays = ' · '.join(f"three {w} {num(Decimal(p[i]) / m['div'])}" for i, w in enumerate(['cherries', 'bells', 'bars', 'sevens']))
        out.append((f"{n} pays", pays, f"**{n} pays**, per winning line: {pays}, times the cascade's number."))
        tot = win = mx = 0; mn = None
        for a in range(64):
            for b in range(64):
                for d in range(64):
                    u = tumble(r, p, [a, b, d]); tot += u
                    if u:
                        win += 1; mx = max(mx, u); mn = u if mn is None else min(mn, u)
        ret = F(tot, T * m['div']); hits = win; minwin = F(mn, m['div'])
        if F(*m['pinned']) != ret:
            out.append((f"{n} pinned return", f"{F(*m['pinned'])}", f"the pinned return {F(*m['pinned'])} equal to the enumerated {ret}"))
        if mx != m['maxu']:
            out.append((f"{n} max units", f"{mx}", f"max-units {m['maxu']} equal to the enumerated {mx}"))
        unit = 'windows'
    else:
        fn = wild if k == 'wild' else line
        un = (lambda x: BLANK if x == SPECIAL else x) if k == 'free' else (lambda x: x)
        labels = ['three sevens', 'three bars', 'three bells', 'three cherries', 'any three high', 'two cherries', 'one cherry'] + (['three wilds'] if k == 'wild' else [])
        pays = ' · '.join(f"{w} {p[i]}" for i, w in enumerate(labels))
        out.append((f"{n} pays", pays, f"**{n} pays**: {pays}."))
        tot = win = mx = 0; mn = None
        for a in range(6):
            for b in range(6):
                for d in range(6):
                    w = c[a] * c[b] * c[d]
                    if not w: continue
                    u = fn(p, un(a), un(b), un(d)); tot += w * u
                    if u:
                        win += w; mx = max(mx, u); mn = u if mn is None else min(mn, u)
        hits = win; minwin = F(mn, m['div']); unit = 'lines'
        if k == 'free':
            ret = F(*m['pinned'])
            trig = sum(1 for s in range(64) if SPECIAL in (r[(s - 1) % 64], r[s], r[(s + 1) % 64]))
            tf = F(trig ** 3, T)
            # a triggering stop never shows a line win: every stop whose window holds a scatter is blank or scatter
            clean = all(un(r[s]) == BLANK for s in range(64) if SPECIAL in (r[(s - 1) % 64], r[s], r[(s + 1) % 64]))
            out.append((f"{n} trigger rate", f"{tf}", f"**triggers the bonus on {pct(tf, 2)}% of spins** ({tf.numerator} in {tf.denominator:,})"))
            out.append((f"{n} no line win on a trigger", "held over all 64 stops" if clean else "BROKEN: a trigger can show a line",
                        "A spin that triggers the bonus shows no line win." if clean else "a triggering spin that also pays its line"))
            out.append((f"{n} line hit rate", f"{win}/{T}", f"**{n} wins on its line on {pct(F(win, T), 2)}% of spins**"))
            if max(mx, int(re.search(r'\(defconst FREE-CAP:integer (\d+)\)', src).group(1))) != m['maxu']:
                out.append((f"{n} max units", f"{m['maxu']}", "a free-spins maximum equal to FREE-CAP"))
        else:
            ret = F(tot, T)
            if mx != m['maxu']:
                out.append((f"{n} max units", f"{mx}", f"max-units {m['maxu']} equal to the enumerated {mx}"))
    edge = 1 - ret
    if k == 'free':
        out.append((f"{n} return", f"{float(ret):.10f}", f"**{n} return: {pct(ret, 4)}%** of everything staked, an exact fraction of two {len(str(ret.numerator))}-digit numbers; **house edge {pct(edge, 4)}%**."))
    else:
        out.append((f"{n} return", f"{ret}", f"**{n} return: {ret.numerator}/{ret.denominator} = {pct(ret, 4)}%** of everything staked; **house edge {pct(edge, 4)}%**."))
        out.append((f"{n} hit rate", f"{hits}/{T}", f"**{n} wins on {pct(F(hits, T), 2)}% of spins** ({hits:,} of the 262,144 possible {unit})."))
    out.append((f"{n} top prize", f"{num(top)}x", f"**{n} top prize: {num(top)} times the spin's stake.**"))
    out.append((f"{n} smallest win", f"{num(minwin)}x", f"Its smallest win pays **{num(minwin)} times** the spin's stake."))
    if minwin <= 1:
        out.append((f"{n} every win above the stake", f"{minwin}", "a smallest win above 1x the stake"))
    divisor = Decimal(top.numerator) / top.denominator / share
    out.append((f"{n} table divisor", f"1/{int(divisor):,}", f"one {int(divisor):,}th"))
    # "sized to keep" at a 15,000 pot with nothing reserved: floor(15000 x SIZED_PCT % / top prize, 12)
    sized = (Decimal(15000) * Decimal(sys.argv[3]) / 100 * top.denominator / top.numerator).quantize(Decimal(1).scaleb(-12), rounding=ROUND_FLOOR)
    out.append((f"{n} sized to keep at 15,000", num(sized), f"**{num(sized)} KDA** on {n}"))
    if n == 'big':
        out.append(("big table at a 15,000 pot", num(Decimal(15000) * share / (Decimal(top.numerator) / top.denominator)),
                    f"a round takes about {num(Decimal(15000) * share / (Decimal(top.numerator) / top.denominator))} KDA on big"))
# the wild doubling, read from wild-pay
out.append(("wild doubles", f"x{WM}", "a win it completes pays **double**" if WM == 2 else f"a wild multiplier of {WM}"))
for label, shown, pattern in out:
    print(f"{label}\t{shown}\t{pattern}")
PY
); PYRC=$?
if [ "$PYRC" != 0 ] || [ -z "$ROWS" ]; then
  echo "  BAD   the machine recomputation failed (exit $PYRC) or produced nothing"; BAD=$((BAD+1))
fi
while IFS=$'\t' read -r L S P; do
  [ -n "$L" ] || continue
  if [ "$L" = "classic table divisor" ] || [ "$L" = "wild table divisor" ]; then
    # classic and wild share one figure, stated once for both
    want "$L" "$S" "**${P}** of the pot's spare capital on classic and wild"
  elif [ "$L" = "classic sized to keep at 15,000" ] || [ "$L" = "wild sized to keep at 15,000" ]; then
    # classic and wild share one figure, stated once for both
    want "$L" "$S" "${P% on *} on classic and wild"
  elif [[ "$L" == *"table divisor" ]]; then
    want "$L" "$S" "**${P}** on ${L% table divisor}"
  else
    want "$L" "$S" "$P"
  fi
done <<< "$ROWS"

# ---- measurements, pinned as literals (they are about Kadena, not the contract) -------
want "block gaps measured"  "120,000"             "replayed over 120,000 measured"
want "exposure measured"    "0 in 41.7 days"      "(0 in 41.7 days)"

# ---- "sized to keep": the operator's rule over the bankroll simulation, advisory ----------------
want "sized-to-keep rule"   "$SIZED_PCT% / top prize" "**$SIZED_PCT%** of the pot's spare capital divided by that machine's top prize, rounded down to 12 decimal places"
want "sized-to-keep advisory" "not enforced"      "This figure is a simulation result, not a contract rule: the contract never measures a board against it"
# the figures above divide by max-units / div; that must still BE the contract's top prize
if grep -qF "(map (lambda (m:object) (/ (dec (at 'max-units m)) (dec (at 'div m)))) MACHINES)" "$SRC"; then
  printf '  OK    %-44s %s\n' "MAX-MULTS is max-units / div" "the divisor the figures use"; OK=$((OK+1))
else
  printf '  BAD   %-44s MAX-MULTS is no longer max-units / div: recompute the sized-to-keep figures\n' "MAX-MULTS"; BAD=$((BAD+1))
fi
# the machine rows must have produced all six figures (a reader that found none must not pass)
NSIZED=$(printf '%s\n' "$ROWS" | grep -c $'^[a-z-]* sized to keep at 15,000\t')
if [ "$NSIZED" = 6 ]; then printf '  OK    %-44s %s\n' "sized-to-keep figures computed" "6 machines"; OK=$((OK+1))
else printf '  BAD   %-44s %s of 6 machines\n' "sized-to-keep figures computed" "$NSIZED"; BAD=$((BAD+1)); fi
# the old open-item marker is REQUIRED ABSENT: the figure is decided and checked above
NOPEN=$(grep -cF -- "$OPEN_MARK" "$DOC")
if [ "$NOPEN" = 0 ]; then printf '  OK    %-44s %s\n' "open-item marker absent" "the figure is decided"; OK=$((OK+1))
else printf '  BAD   %-44s the marker %s still appears %s times\n' "open-item marker absent" "$OPEN_MARK" "$NOPEN"; BAD=$((BAD+1)); fi

# a check that inspected (almost) nothing must fail, never pass
if [ "$OK" -lt 40 ]; then
  printf '  BAD   %-44s only %s checks ran OK: the reader broke\n' "check count" "$OK"; BAD=$((BAD+1))
fi
echo "  terms OK: $OK · BAD: $BAD"
[ "$BAD" = 0 ]
