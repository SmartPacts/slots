import io, re, sys
# Arity scanner for Pact 5's BINARY special forms: or, and, +.
# A 3+-operand form loads, passes every static gate, and throws only when the
# branch executes. Strings and comments are masked; newlines are PRESERVED,
# including the newline a backslash escapes inside a multi-line doc string,
# so reported line numbers are real. [] and {} nest like ().
src = io.open(sys.argv[1], encoding="utf-8").read()
out, i, n, instr, incmt = [], 0, len(src), False, False
while i < n:
    c = src[i]
    if incmt:
        out.append("\n" if c == "\n" else " ")
        if c == "\n": incmt = False
    elif instr:
        if c == "\\" and i + 1 < n:
            out.append(" ")
            out.append("\n" if src[i+1] == "\n" else " ")
            i += 1
        elif c == '"':
            out.append(" "); instr = False
        else:
            out.append("\n" if c == "\n" else " ")
    else:
        if c == ';': incmt = True; out.append(" ")
        elif c == '"': instr = True; out.append(" ")
        else: out.append(c)
    i += 1
t = "".join(out)
assert len(t) == len(src) and t.count("\n") == src.count("\n"), "mask changed shape"
OPEN, CLOSE = "([{", ")]}"
def operands(start):
    d, j, ops, tok = 0, start, [], None
    while j < len(t):
        c = t[j]
        if c in OPEN:
            d += 1
            if d == 2: tok = j
        elif c in CLOSE:
            d -= 1
            # flush at 2->1 (a nested group operand) AND at 1->0 (a trailing BARE
            # token). Missing the second case was a real bug: it silently dropped
            # the last operand of every form whose final operand was not
            # parenthesised, so (+ a b c) read as arity 2 and passed.
            if d <= 1 and tok is not None: ops.append(tok); tok = None
            if d == 0: return ops
        elif d == 1:
            if c.isspace():
                if tok is not None: ops.append(tok); tok = None
            elif tok is None: tok = j
        j += 1
    return ops
bad = total = 0
for m in re.finditer(r'\((or|and|\+)(?=[\s(\[{])', t):
    total += 1
    a = len(operands(m.start())) - 1
    if a >= 3:
        bad += 1
        print("  line %d: (%s ...) has %d operands" % (t.count("\n", 0, m.start()) + 1, m.group(1), a))
print("%s: %d or/and/+ forms, %d with 3+ operands" % (sys.argv[1].split("/")[-1], total, bad))
sys.exit(1 if bad else 0)
