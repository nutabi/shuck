#!/usr/bin/env python3
"""Fails when a user-facing string literal has no String Catalog entry (NFR-L10N-001). scripts/lint.sh runs it.

A command-line build adds no keys to a catalog (only Xcode does), so a missing key goes unnoticed. This reads both
catalogs and scans shipped code: Shuck/ against the app catalog, ShuckKit's sources against the engine catalog.

A literal counts as user-facing when it is
  - the first argument of a text-taking call (Text, Button, Label, .help, String(localized:), ...), even on the
    next line, or
  - inside the body or initial value of a declaration typed LocalizedStringResource, LocalizedStringKey or Text,
    except a `case` pattern, a comparison, or a lowercase symbol-like name such as "checkmark.circle", or
  - the whole of an argument to a function, initializer or memberwise initializer whose parameter is typed
    LocalizedStringResource or LocalizedStringKey (R-09, D-161). The parameters are read from the declarations of
    the same folder and matched by the callee's name and the argument's label, or its position for an unlabeled
    parameter.
Raw strings (#"..."#) are read like any other literal.
Never checked: Text(verbatim:), Logger messages, identifiers, paths, anything in a #Preview, comment lines. A literal
that must stay as it is gets `// not localized: <reason>` on its line. Known blind spots: a literal that is only part
of an argument (a ternary, a concatenation), and a callee reached through a typealias or under another name.

Usage: scripts/strings-check.py
       scripts/strings-check.py --self-test    check the check itself on small examples (lint.sh runs it)
"""

import json, os, re, sys, tempfile

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
RESOURCE_TYPE = re.compile(r"\s*(?:LocalizedStringResource|LocalizedStringKey)\??\s*")
OPEN = re.compile(r'(#*)("""|")')
TYPE_BODY = re.compile(r"\b(struct|class|enum|actor|extension)\s+(\w+)[^{;]*\{")
FUNCTION = re.compile(r"\b(?:func\s+(\w+)|(init))\s*(?:<[^>(]*>)?\s*\(")
STORED = re.compile(r"^[ \t]*(?:[a-z]+[ \t]+)*(?:let|var)[ \t]+(\w+)[ \t]*:[ \t]*([^=\n{]*?)[ \t]*$", re.M)
CLOSERS = {")": "(", "]": "[", "}": "{"}


def normalize(text):
    return re.sub(r"%(?:\d+\$)?(?:lld|@)", "\0", text)


def parse(src):
    """Returns the literals as (start, end, text) and the code with comments and literal contents blanked."""
    code, literals, i, n = list(src), [], 0, len(src)
    while i < n:
        opening = OPEN.match(src, i) if src[i] in '"#' else None
        if src.startswith("//", i):
            j = src.find("\n", i) if "\n" in src[i:] else n
            code[i:j] = " " * (j - i)
            i = j
        elif opening:
            start, hashes, quotes = i, opening.group(1), opening.group(2)
            escape, closing = "\\" + hashes, quotes + hashes
            i = opening.end()
            depth = 0
            while i < n:
                if src.startswith(escape + "(", i):
                    depth, i = depth + 1, i + len(escape) + 1
                elif src.startswith(escape, i):
                    i += len(escape) + 1
                elif depth and src[i] == "(":
                    depth, i = depth + 1, i + 1
                elif depth and src[i] == ")":
                    depth, i = depth - 1, i + 1
                elif depth == 0 and src.startswith(closing, i):
                    i += len(closing)
                    break
                else:
                    i += 1
            literals.append((start, i, src[start:i]))
            for k in range(opening.end(), max(opening.end(), i - len(closing))):
                if code[k] != "\n":
                    code[k] = " "
        else:
            i += 1
    return literals, "".join(code)


def literal_text(raw):
    """The text Xcode extracts as the key: each \\(...) becomes \\0, escapes resolved, a multi-line string joined."""
    out, i = [], 0
    hashes = len(raw) - len(raw.lstrip("#"))
    escape = "\\" + "#" * hashes
    raw = raw[hashes : len(raw) - hashes]
    if raw.startswith('"""'):
        lines = raw[3:-3].split("\n")[1:]  # drop the line break after the opening quotes
        indent = len(lines[-1])
        raw = "\n".join(line[indent:] for line in lines[:-1]).replace(escape + "\n", "")
        raw = '"' + raw + '"'
    body = raw[1:-1]
    while i < len(body):
        if body.startswith(escape + "(", i):
            depth, i = 1, i + len(escape) + 1
            while depth:
                depth += {"(": 1, ")": -1}.get(body[i], 0)
                i += 1
            out.append("\0")
        elif body.startswith(escape, i) and i + len(escape) < len(body):
            out.append({"n": "\n", "t": "\t"}.get(body[i + len(escape)], body[i + len(escape)]))
            i += len(escape) + 1
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


def type_ranges(code):
    """(kind, name, start, end) of each type body, so a declaration can name the type it is in."""
    result = []
    for m in TYPE_BODY.finditer(code):
        depth = 0
        for j in range(m.end() - 1, len(code)):
            depth += {"{": 1, "}": -1}.get(code[j], 0)
            if depth == 0:
                result.append((m.group(1), m.group(2), m.end(), j))
                break
    return result


def enclosing_type(types, position):
    inside = [t for t in types if t[2] <= position < t[3]]
    return max(inside, key=lambda t: t[2]) if inside else None


def split_top_level(text):
    """Splits at the commas that are not inside brackets."""
    parts, depth, last = [], 0, 0
    for i, c in enumerate(text):
        depth += 1 if c in "([{<" else -1 if c in ")]}>" and text[i - 1 : i] != "-" else 0
        if c == "," and depth == 0:
            parts.append(text[last:i])
            last = i + 1
    parts.append(text[last:])
    return parts


def matching_paren(code, open_index):
    depth = 0
    for j in range(open_index, len(code)):
        depth += {"(": 1, ")": -1}.get(code[j], 0)
        if depth == 0:
            return j
    return -1


def resource_parameters(code):
    """The parameters typed LocalizedStringResource or LocalizedStringKey, as {callee: (labels, positions)}.

    A function is its name and an initializer its type's name; a struct's stored properties are its memberwise
    initializer's labels."""
    found = {}

    def add(callee, label, position):
        labels, positions = found.setdefault(callee, (set(), set()))
        if label:
            labels.add(label)
        else:
            positions.add(position)

    types = type_ranges(code)
    for m in FUNCTION.finditer(code):
        close = matching_paren(code, m.end() - 1)
        if close < 0:
            continue
        callee = m.group(1)
        if m.group(2):
            holder = enclosing_type(types, m.start())
            if not holder:
                continue
            callee = holder[1]
        for position, parameter in enumerate(split_top_level(code[m.end() : close])):
            if ":" not in parameter:
                continue
            names, kind = parameter.split(":", 1)
            if not RESOURCE_TYPE.fullmatch(kind.split("=")[0]):
                continue
            words = names.split()
            if words:
                add(callee, None if words[0] == "_" else words[0], position)
    for m in STORED.finditer(code):
        holder = enclosing_type(types, m.start())
        if holder and holder[0] == "struct" and RESOURCE_TYPE.fullmatch(m.group(2)):
            add(holder[1], m.group(1), -1)
    return found


def passed_parameter(code, start, end, parameters):
    """Whether the literal at start..end is a whole argument of a call whose parameter is a resource."""
    after = code[end : end + 40].lstrip()
    if not after[:1] in (",", ")"):
        return False
    before = code[max(0, start - 2000) : start]
    label = None
    m = re.search(r"(\w+)\s*:\s*$", before)
    if m:
        label, before = m.group(1), before[: m.start()]
    if not re.search(r"[(,]\s*$", before):
        return False
    depth, position = 0, 0
    for i in range(len(before) - 1, -1, -1):
        c = before[i]
        if c in CLOSERS:
            depth += 1
        elif c in "([{":
            if depth == 0:
                if c != "(":
                    return False
                callee = re.search(r"(\w+)\s*$", before[:i])
                if not callee:
                    return False
                labels, positions = parameters.get(callee.group(1), (set(), set()))
                return label in labels if label else position in positions
            depth -= 1
        elif c == "," and depth == 0:
            position += 1
    return False


def check(folder, catalog):
    keys = {normalize(k) for k in json.load(open(os.path.join(ROOT, catalog)))["strings"]}
    files = []
    for dirpath, _, names in os.walk(os.path.join(ROOT, folder)):
        for name in sorted(names):
            if name.endswith(".swift"):
                path = os.path.join(dirpath, name)
                src = open(path).read()
                files.append((path, src) + parse(src))
    parameters = {}
    for _, _, _, code in files:
        for callee, (labels, positions) in resource_parameters(code).items():
            known = parameters.setdefault(callee, (set(), set()))
            known[0].update(labels)
            known[1].update(positions)
    found = 0
    for path, src, literals, code in files:
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
            if not (CALL.search(before) or in_declaration or passed_parameter(code, start, end, parameters)):
                continue
            if any(a <= start < b for a, b in previews) or "// not localized:" in src[end:line_end]:
                continue
            if normalize(text) not in keys:
                line = src.count("\n", 0, start) + 1
                shown = text.replace("\0", "%")
                print(f'{os.path.relpath(path, ROOT)}:{line}: [strings] no String Catalog entry for "{shown}"')
                found += 1
    return found


def self_test():
    """Runs the check on small examples in a temporary folder: each must be reported or, for the last group, not."""
    global ROOT
    reported = {
        "Text bare": 'Text("Missing one")',
        "raw string in Text": 'Text(#"Missing raw"#)',
        "raw string with a quote": 'Text(##"Missing "raw" two"##)',
        "raw string interpolation": 'Text(#"Missing \\#(count) raw"#)',
        "raw multi-line": 'Text(#"""\n    Missing raw lines\n    """#)',
        "labeled function parameter": 'func show(title: LocalizedStringResource) {}\nshow(title: "Missing label")',
        "second labeled parameter": 'func show(id: String, title: LocalizedStringKey) {}\nshow(id: "a", title: "Missing second")',
        "unlabeled parameter": 'func show(_ title: LocalizedStringResource) {}\nshow("Missing position")',
        "unlabeled second parameter": 'func show(_ id: String, _ t: LocalizedStringResource) {}\nshow("a", "Missing two")',
        "wrapped call": 'func show(title: LocalizedStringResource) {}\nshow(\n    title:\n        "Missing wrapped")',
        "method": 'struct A { func show(title: LocalizedStringResource) {} }\nA().show(title: "Missing method")',
        "initializer": 'struct A { init(title: LocalizedStringResource) {} }\nlet a = A(title: "Missing init")',
        "memberwise": 'struct A {\n    let name: LocalizedStringResource\n}\nlet a = A(name: "Missing memberwise")',
        "optional parameter": 'func show(title: LocalizedStringResource?) {}\nshow(title: "Missing optional")',
        "default value": 'func show(title: LocalizedStringResource = "x", n: Int) {}\nshow(title: "Missing default", n: 1)',
    }
    clean = {
        "key present": 'Text("Known")',
        "raw key present": 'Text(#"Known"#)',
        "verbatim": 'Text(verbatim: "Missing")',
        "not localized comment": 'func show(title: LocalizedStringResource) {}\nshow(title: "Missing") // not localized: test',
        "string parameter": 'func show(title: String) {}\nshow(title: "Missing")',
        "same label, other callee": 'func show(title: LocalizedStringResource) {}\nfunc hide(title: String) {}\nhide(title: "Missing")',
        "known key to a parameter": 'func show(title: LocalizedStringResource) {}\nshow(title: "Known")',
        "part of an argument": 'func show(title: LocalizedStringResource) {}\nshow(title: flag ? "Missing" : "Known")',
        "struct with a string property": 'struct A { let name: String }\nlet a = A(name: "Missing")',
        "raw string outside a call": 'let pattern = #"\\d+ "Missing""#',
        "preview": '#Preview { Text("Missing") }',
    }
    failed = False
    with tempfile.TemporaryDirectory() as folder:
        os.makedirs(os.path.join(folder, "Sources"))
        catalog = os.path.join(folder, "Localizable.xcstrings")
        json.dump({"strings": {"Known": {}}}, open(catalog, "w"))
        ROOT = folder
        for expect_report, cases in ((True, reported), (False, clean)):
            for name, source in cases.items():
                with open(os.path.join(folder, "Sources", "Case.swift"), "w") as out:
                    out.write(source + "\n")
                real, sys.stdout = sys.stdout, open(os.devnull, "w")
                try:
                    count = check("Sources", "Localizable.xcstrings")
                finally:
                    sys.stdout.close()
                    sys.stdout = real
                if bool(count) != expect_report:
                    print(f"strings-check self-test: {name}: expected {'a report' if expect_report else 'no report'}")
                    failed = True
    if failed:
        return 1
    print("strings-check self-test: OK")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    total = sum(check(folder, catalog) for folder, catalog in SCOPES)
    sys.exit(1 if total else 0)
