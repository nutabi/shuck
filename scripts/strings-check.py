#!/usr/bin/env python3
"""Fails when a user-facing string literal has no String Catalog entry (NFR-L10N-001). scripts/lint.sh runs it.

A command-line build adds no keys to a catalog (only Xcode does), so a missing key goes unnoticed. This reads both
catalogs and scans shipped code: Shuck/ against the app catalog, ShuckKit's sources against the engine catalog.

A literal counts as user-facing when it is
  - the first argument of a text-taking call (Text, Button, Label, .help, String(localized:), ...), even on the
    next line, or
  - inside the body or initial value of a declaration typed LocalizedStringResource, LocalizedStringKey or Text,
    except a `case` pattern, a comparison, or a lowercase symbol-like name such as "checkmark.circle".
Never checked: Text(verbatim:), Logger messages, identifiers, paths, anything in a #Preview, comment lines. A literal
that must stay as it is gets `// not localized: <reason>` on its line. Known blind spots: a bare literal passed to a
parameter typed LocalizedStringResource, and raw (#"...") strings.

Usage: scripts/strings-check.py
"""

import json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SCOPES = [  # (source folder, catalog)
    ("Shuck", "Shuck/Localizable.xcstrings"),
    ("Packages/ShuckKit/Sources/ShuckKit", "Packages/ShuckKit/Sources/ShuckKit/Resources/Localizable.xcstrings"),
]
CALLS = (r"Text|Button|Label|Toggle|Section|Picker|Menu|TextField|LabeledContent|DisclosureGroup|ContentUnavailableView"
         r"|ProgressView|LocalizedStringResource|\.help|\.alert|\.confirmationDialog"
         r"|\.navigationTitle|\.accessibilityLabel|\.accessibilityHint|\.accessibilityValue")
CALL = re.compile(r"(?:(?:%s)\(|String\(\s*localized:)\s*$" % CALLS)
TYPED = re.compile(r"(?:\blet|\bvar)\s+\w+\s*:\s*([^{=\n]*)([{=])|->\s*([^{\n]*)\{")
USER_TYPE = re.compile(r"\b(?:LocalizedStringResource|LocalizedStringKey|Text)\b")


def normalize(text):
    return re.sub(r"%(?:\d+\$)?(?:lld|@)", "\0", text)


def parse(src):
    """Returns the literals as (start, end, text) and the code with comments and literal contents blanked."""
    code, literals, i, n = list(src), [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i) if "\n" in src[i:] else n
            code[i:j] = " " * (j - i)
            i = j
        elif src[i] == '"':
            start, triple = i, src.startswith('"""', i)
            i += 3 if triple else 1
            depth = 0
            while i < n:
                if src[i] == "\\" and src[i + 1 : i + 2] == "(":
                    depth, i = depth + 1, i + 2
                elif src[i] == "\\":
                    i += 2
                elif depth and src[i] == "(":
                    depth, i = depth + 1, i + 1
                elif depth and src[i] == ")":
                    depth, i = depth - 1, i + 1
                elif depth == 0 and src.startswith('"""' if triple else '"', i):
                    i += 3 if triple else 1
                    break
                else:
                    i += 1
            literals.append((start, i, src[start:i]))
            code[start + 1 : i - 1] = [c if c == "\n" else " " for c in src[start + 1 : i - 1]]
        else:
            i += 1
    return literals, "".join(code)


def literal_text(raw):
    """The text Xcode extracts as the key: each \\(...) becomes \\0, escapes resolved, a multi-line string joined."""
    out, i = [], 0
    if raw.startswith('"""'):
        lines = raw[3:-3].split("\n")[1:]  # drop the line break after the opening quotes
        indent = len(lines[-1])
        raw = "\n".join(line[indent:] for line in lines[:-1]).replace("\\\n", "")
        raw = '"' + raw + '"'
    body = raw[1:-1]
    while i < len(body):
        if body.startswith("\\(", i):
            depth, i = 1, i + 2
            while depth:
                depth += {"(": 1, ")": -1}.get(body[i], 0)
                i += 1
            out.append("\0")
        elif body[i] == "\\":
            out.append({"n": "\n", "t": "\t"}.get(body[i + 1], body[i + 1]))
            i += 2
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def blank_ranges(code, pattern):
    """Index ranges of the `{...}` block that follows each match of pattern."""
    for m in re.finditer(pattern, code):
        i, depth = code.index("{", m.start()), 0
        for j in range(i, len(code)):
            depth += {"{": 1, "}": -1}.get(code[j], 0)
            if depth == 0:
                yield (i, j)
                break


def user_facing_ranges(code):
    ranges = []
    for m in TYPED.finditer(code):
        if not USER_TYPE.search(m.group(1) or m.group(3) or ""):
            continue
        if m.group(2) == "=":
            ranges.append((m.end(), code.find("\n", m.end())))
        else:
            start = m.end() - 1  # the opening brace
            for a, b in blank_ranges(code[start:], r"\{"):
                ranges.append((start + a, start + b))
                break
    return ranges


def check(folder, catalog):
    keys = {normalize(k) for k in json.load(open(os.path.join(ROOT, catalog)))["strings"]}
    found = 0
    for dirpath, _, names in os.walk(os.path.join(ROOT, folder)):
        for name in sorted(names):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            src = open(path).read()
            literals, code = parse(src)
            previews = list(blank_ranges(code, r"#Preview"))
            facing = user_facing_ranges(code)
            for start, end, raw in literals:
                before = code[max(0, start - 80) : start]
                line_start = src.rfind("\n", 0, start) + 1
                line_end = src.find("\n", end) if "\n" in src[end:] else len(src)
                in_declaration = any(a <= start < b for a, b in facing)
                text = literal_text(raw)
                if in_declaration:
                    line_before = code[line_start:start]
                    in_declaration = not (
                        re.match(r"\s*case\b[^:]*$", line_before)
                        or re.search(r"[=!]=\s*$", line_before)
                        or re.fullmatch(r"[a-z][a-z0-9.]*", text)
                    )
                if not (CALL.search(before) or in_declaration):
                    continue
                if any(a <= start < b for a, b in previews) or "// not localized:" in src[end:line_end]:
                    continue
                if normalize(text) not in keys:
                    line = src.count("\n", 0, start) + 1
                    shown = text.replace("\0", "%")
                    print(f'{os.path.relpath(path, ROOT)}:{line}: [strings] no String Catalog entry for "{shown}"')
                    found += 1
    return found


if __name__ == "__main__":
    total = sum(check(folder, catalog) for folder, catalog in SCOPES)
    sys.exit(1 if total else 0)
