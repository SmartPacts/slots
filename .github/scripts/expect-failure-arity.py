#!/usr/bin/env python3
"""Detect 2-argument `expect-failure` forms in Pact .repl files.

WHY THIS EXISTS
---------------
`(expect-failure "doc" (expr))` matches ANY failure, so it cannot tell "the module refused
this correctly" from "the test was malformed" — an arity error, a typo, a missing module all
make it pass. A suite full of them can be green while proving very little. The 3-argument
form, `(expect-failure "doc" "expected message" (expr))`, asserts WHY it failed.

A regex cannot count arguments reliably: forms span lines, code arguments contain `)` inside
strings and `;` comments, and `expect-failure` appears inside comments and string literals
that must NOT count. So this is a paren- and string-aware scanner.

NON-VACUITY IS ENFORCED, NOT DOCUMENTED
---------------------------------------
A self-test runs on EVERY invocation, before any file is scanned. If the scanner cannot find
the positives in its own fixture, it exits non-zero and reports nothing clean: a check that
inspected zero items must FAIL, never PASS. A file it cannot parse is SKIPPED, and a skip is a
failure too.

Usage: expect-failure-arity.py FILE_OR_GLOB...   exit 0 clean, 1 findings, 2 cannot certify
"""
import sys
import os
import glob

# --------------------------------------------------------------------------------
# Tokenizer. Handles: string literals with \-escapes, `;` line comments, [] and {}
# literals, multi-line forms, and nesting. Head symbol is not counted as an argument.
# --------------------------------------------------------------------------------


def scan(src):
    """Yield a frame dict for every `expect-failure` form found in src."""
    n = len(src)
    i = 0
    stack = []
    out = []
    in_comment = False
    while i < n:
        c = src[i]
        if in_comment:
            if c == '\n':
                in_comment = False
            i += 1
            continue
        if c == ';':
            in_comment = True
            i += 1
            continue
        if c == '"':
            start = i
            i += 1
            while i < n:
                if src[i] == '\\':
                    i += 2
                    continue
                if src[i] == '"':
                    i += 1
                    break
                i += 1
            if stack:
                stack[-1]['args'].append(('str', start, i))
            continue
        if c == '(':
            frame = {'start': i, 'args': [], 'name': None}
            if stack:
                stack[-1]['args'].append(('form', i, None))
            stack.append(frame)
            i += 1
            j = i
            while j < n and src[j] in ' \t\n\r':
                j += 1
            k = j
            while k < n and src[k] not in ' \t\n\r()[]{}";':
                k += 1
            frame['name'] = src[j:k]
            frame['head_end'] = k
            i = k
            continue
        if c in '[{':
            frame = {'start': i, 'args': [], 'name': '#lit', 'head_end': i}
            if stack:
                stack[-1]['args'].append(('form', i, None))
            stack.append(frame)
            i += 1
            continue
        if c in ')]}':
            if stack:
                frame = stack.pop()
                frame['end'] = i + 1
                if stack:
                    for idx in range(len(stack[-1]['args']) - 1, -1, -1):
                        kind, s, e = stack[-1]['args'][idx]
                        if kind == 'form' and e is None and s == frame['start']:
                            stack[-1]['args'][idx] = ('form', s, frame['end'])
                            break
                if frame['name'] == 'expect-failure':
                    out.append(frame)
            i += 1
            continue
        if c in ' \t\n\r,':
            i += 1
            continue
        start = i
        while i < n and src[i] not in ' \t\n\r()[]{}";,':
            i += 1
        if i == start:
            i += 1
            continue
        if stack and start >= stack[-1].get('head_end', -1):
            stack[-1]['args'].append(('atom', start, i))
    return out


def scan_file(path):
    with open(path, encoding='utf-8') as fh:
        src = fh.read()
    res = []
    for fr in scan(src):
        line = src.count('\n', 0, fr['start']) + 1
        text = src[fr['start']:fr.get('end', fr['start'] + 90)].split('\n')[0]
        res.append({'line': line, 'nargs': len(fr['args']), 'text': text})
    return res


# --------------------------------------------------------------------------------
# Self-test. Line numbers are load-bearing: a scanner that finds the right COUNT in
# the wrong PLACES still fails. Every tricky construct this repo actually contains
# is represented — a commented-out form, a form inside a string literal, an escaped
# quote, a `;` inside a pinned string, an inline comment inside the code argument,
# a nested form, and a bare-atom third argument.
# --------------------------------------------------------------------------------
SELFTEST_SRC = r'''
;; (expect-failure "in a comment - MUST NOT COUNT" (foo))
(expect-failure "two arg form" (foo 1 2))
(expect-failure
  "two arg across lines"
  (bar (baz "a string with ) paren") [1 2 3]))
(expect-failure "three arg form" "the pinned message" (qux))
(expect-failure "three arg, string has ; semicolon" "msg ; not a comment" (quux))
(expect-failure "esc \" quote two-arg" (r))
(let ((x "(expect-failure \"nope in a string literal\" (y))")) x)
(expect-failure "three arg, code has an inline ; comment" "pinned"
  (foo ;; a comment with ) and " in it
       1))
(begin-tx) (expect-failure "nested inside a form" "pinned" (z)) (commit-tx)
(expect-failure "arg is a bare atom, still 3" "pinned" x)
'''
SELFTEST_EXPECT = {3: 2, 4: 2, 7: 3, 8: 3, 9: 2, 11: 3, 14: 3, 15: 3}


def selftest(verbose=False):
    """Return True only if the scanner reproduces the fixture map exactly."""
    import tempfile
    with tempfile.NamedTemporaryFile('w', suffix='.repl', delete=False) as fh:
        fh.write(SELFTEST_SRC)
        p = fh.name
    try:
        got = scan_file(p)
    finally:
        os.unlink(p)
    actual = {g['line']: g['nargs'] for g in got}
    ok = (actual == SELFTEST_EXPECT) and len(actual) == len(got) and bool(got)
    if verbose or not ok:
        print("  self-test: %d forms found (%d two-arg, %d three-arg)"
              % (len(got), sum(1 for g in got if g['nargs'] == 2),
                 sum(1 for g in got if g['nargs'] == 3)))
    if not ok:
        print("  SELF-TEST FAILED — the scanner cannot find forms it is known to contain,")
        print("  so it cannot certify anything clean. Expected line->nargs %r, got %r"
              % (SELFTEST_EXPECT, actual))
    return ok


def main(argv):
    verbose = '--verbose' in argv
    args = [a for a in argv if not a.startswith('--')]

    # 1. NON-VACUITY FIRST. Nothing is scanned until the scanner proves it works.
    if not selftest(verbose):
        return 2

    # 2. Resolve the file set.
    if args:
        targets = []
        for a in args:
            targets.extend(sorted(glob.glob(a)) if any(ch in a for ch in '*?[') else [a])
    else:
        here = os.path.dirname(os.path.abspath(__file__))
        root = os.path.dirname(os.path.dirname(here))
        targets = sorted(glob.glob(os.path.join(root, 'pact', 'test', '*.repl')) +
                         glob.glob(os.path.join(root, 'pact', 'test', '*.repl-must-fail')))
    if not targets:
        print("  FAILED — no .repl files matched. A scan of nothing is not a clean scan.")
        return 2

    # 3. Scan. PER-FILE status: a file that cannot be parsed is SKIPPED and skipping is
    #    a failure. There is deliberately no shared error list — a converter
    #    used one, so after the first bad file every later file was silently dropped
    #    while the summary still counted it as done (it claimed 77, had written 66).
    findings, skipped, scanned = [], [], 0
    for t in targets:
        try:
            rs = scan_file(t)
        except Exception as exc:                                  # noqa: BLE001
            skipped.append((t, str(exc)))
            continue
        scanned += 1
        for r in rs:
            if r['nargs'] == 2:
                findings.append((t, r))
        if verbose:
            print("  %-46s %3d forms, %d two-arg"
                  % (os.path.basename(t), len(rs),
                     sum(1 for r in rs if r['nargs'] == 2)))

    for t, err in skipped:
        print("  SKIPPED %s — %s" % (t, err))

    if findings:
        print("  FAILED — %d two-argument expect-failure form(s). Each matches ANY failure,"
              % len(findings))
        print("  so it cannot tell a correct refusal from a malformed test. Use the 3-arg form")
        print("  with the error string the module ACTUALLY produces, captured from a run:")
        for t, r in findings:
            print("    %s:%d  %s" % (os.path.relpath(t), r['line'], r['text'][:100]))
    if skipped:
        print("  FAILED — %d file(s) skipped. A skipped file is not a clean file." % len(skipped))
        return 2
    if findings:
        return 1
    print("  %d files scanned, 0 two-argument expect-failure forms (self-test passed first)"
          % scanned)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
