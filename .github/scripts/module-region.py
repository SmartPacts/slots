#!/usr/bin/env python3
# The `(module …)` form of a source file, sliced exactly as the engine slices it out of a deploy
# transaction: from `(module <name>` to its matching close paren, comments intact, nothing
# normalised, the namespace line and the create-table footer excluded.
#
#   python3 .github/scripts/module-region.py pact/modules/slots.pact slots
#   python3 .github/scripts/module-region.py --check          # both modules against deploy-bytes/
#
# WHY THIS EXISTS. deploy-bytes/<m>.pact is what the deploy transaction sent and what
# `describe-module` returns today. pact/modules/<m>.pact is that same form with a header, a
# `namespace` line and a table-creation footer around it — the lines that ran once at deploy and
# are not stored. This proves the annotated file and the published bytes are the same program,
# character for character, so the on-chain comparison reaches the file a reader actually reads.
import pathlib, re, sys

def module_region(src: str, name: str) -> str:
    m = re.search(r'^\(module %s\b' % re.escape(name), src, re.M)
    if not m:
        sys.exit(f"no (module {name} …) form in the source")
    start, depth, in_str, i = m.start(), 0, False, m.start()
    while i < len(src):
        c = src[i]
        if in_str:
            if c == '\\':
                i += 1
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == ';':                       # a line comment: skip to the newline
            nl = src.find('\n', i)
            if nl < 0:
                break
            i = nl
            continue
        if c == '"':
            in_str = True; i += 1; continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return src[start:i + 1]
        i += 1
    sys.exit(f"the (module {name} …) form is unbalanced")

if __name__ == '__main__':
    if '--check' in sys.argv:
        bad = 0
        for name in ('slots', 'drand'):
            region = module_region(pathlib.Path(f'pact/modules/{name}.pact').read_text(), name)
            published = pathlib.Path(f'deploy-bytes/{name}.pact').read_text()
            if region == published:
                print(f"   ok   pact/modules/{name}.pact's (module …) form IS "
                      f"deploy-bytes/{name}.pact ({len(region)} characters)")
            else:
                n = min(len(region), len(published))
                at = next((k for k in range(n) if region[k] != published[k]), n)
                print(f"   BAD  pact/modules/{name}.pact diverges from deploy-bytes/{name}.pact "
                      f"at character {at}")
                bad += 1
        sys.exit(1 if bad else 0)
    if len(sys.argv) < 3:
        sys.exit("usage: module-region.py <file> <module-name>   |   module-region.py --check")
    sys.stdout.write(module_region(pathlib.Path(sys.argv[1]).read_text(), sys.argv[2]))
