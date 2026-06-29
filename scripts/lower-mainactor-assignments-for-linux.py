#!/usr/bin/env python3
"""Wrap common AppKit controller assignments for Swift 6 actor checking.

This runs only on generated Linux build copies. Some AppKit projects create a
view controller, assign dependencies into its properties, then install it into
an NSWindowController. Apple's AppKit makes those view-controller properties
main-actor isolated; wrapping the simple assignment lines preserves the source
shape while keeping the shim's AppKit isolation faithful.
"""

from __future__ import annotations

import pathlib
import re
import sys


ASSIGNMENT_RE = re.compile(r"^(\s*)(controller\.[A-Za-z_][A-Za-z0-9_]*\s*=(?!=)\s*(.+))$")
NSHOSTING_CONTROLLER_RE = re.compile(
    r"(?<!MainActor\.assumeIsolated \{ )NSHostingController\(rootView: ([A-Za-z_][A-Za-z0-9_]*)\)"
)
UI_PROXY_CALL_RE = re.compile(
    r"^(\s*)((?:viewController\(\)\?\.(?:splitView\.setPosition|collapse)|controller\.moveLines(?:Up|Down)|(?:[A-Za-z_][A-Za-z0-9_]*\.)?removeKeyDownMonitor)\(.*\))$"
)
SINK_CLOSURE_HEADER_RE = re.compile(r"\.sink(?:\s*\(\s*receiveValue\s*:)?\s*\{[^\n]*\bin\s*\n")
MAIN_ACTOR_METHOD_HEADER_RE = re.compile(
    r"(?m)^([ \t]*)func (?:fileManagerUpdated|updateToolbarItem)\([^)]*\)[ \t]*\{[ \t]*\n"
)
TYPE_DECL_RE = re.compile(
    r"^(\s*)(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*"
    r"(?:(?:public|open|internal|fileprivate|private|final)\s+)*"
    r"(?:class|struct|actor)\b"
)
INIT_DECL_RE = re.compile(
    r"^(\s*)(?:(?:public|open|internal|fileprivate|private|required|convenience|override)\s+)*init\s*\("
)
INLINE_MAINACTOR_INIT_DECL_RE = re.compile(
    r"^(\s*)@MainActor\s+(?:(?:public|open|internal|fileprivate|private|required|convenience|override)\s+)*init\s*\("
)
SIMPLE_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SWIFT_LITERAL_IDENTIFIERS = {"false", "nil", "true"}
MAIN_ACTOR_BODY_NEEDLES = (
    "controller?.",
    "self?.controller?.",
    "controller.",
    "outlineView.",
    "toolbar.",
    "insertItem(withItemIdentifier:",
    "removeItem(at:",
    "shouldReloadAfterDoneEditing",
    "shouldSendSelectionUpdate",
)


def is_single_line_rhs(rhs: str) -> bool:
    stripped = rhs.strip()
    if not stripped:
        return False
    if "{" in stripped or "}" in stripped:
        return False
    if stripped.endswith((",", "(", "[", ".")):
        return False
    if stripped.count("(") != stripped.count(")"):
        return False
    if stripped.count("[") != stripped.count("]"):
        return False
    return True


def previous_nonempty(lines: list[str], index: int) -> str:
    for candidate in reversed(lines[:index]):
        stripped = candidate.strip()
        if stripped:
            return stripped
    return ""


def should_process(text: str) -> bool:
    return (
        "controller." in text
        and (
            "NSWindowController" in text
            or "NSViewController" in text
            or "NSPopover" in text
            or "contentViewController" in text
        )
        or "NSHostingController(rootView:" in text
        or "controller.view as?" in text
        or "viewController()?.splitView.setPosition" in text
        or "viewController()?.collapse" in text
        or "controller.moveLinesUp()" in text
        or "controller.moveLinesDown()" in text
        or ".removeKeyDownMonitor()" in text
        or ".sink" in text
        or "fileManagerUpdated" in text
        or "updateToolbarItem" in text
        or ("@MainActor" in text and "init(" in text)
    )


def lower_expression_isolation(text: str) -> tuple[str, bool]:
    lowered = NSHOSTING_CONTROLLER_RE.sub(
        r"MainActor.assumeIsolated { NSHostingController(rootView: \1) }",
        text,
    )
    lowered = lowered.replace(
        "controller.view as?",
        "MainActor.assumeIsolated { controller.view } as?",
    )
    return lowered, lowered != text


def matching_closing_brace(text: str, open_index: int) -> int | None:
    depth = 0
    index = open_index
    in_line_comment = False
    in_block_comment = 0
    in_string = False
    escaped = False

    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if in_line_comment:
            if char == "\n":
                in_line_comment = False
            index += 1
            continue

        if in_block_comment:
            if char == "/" and next_char == "*":
                in_block_comment += 1
                index += 2
                continue
            if char == "*" and next_char == "/":
                in_block_comment -= 1
                index += 2
                continue
            index += 1
            continue

        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "\"":
                in_string = False
            index += 1
            continue

        if char == "/" and next_char == "/":
            in_line_comment = True
            index += 2
            continue
        if char == "/" and next_char == "*":
            in_block_comment = 1
            index += 2
            continue
        if char == "\"":
            in_string = True
            index += 1
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def body_requires_main_actor_wrap(body: str) -> bool:
    return any(needle in body for needle in MAIN_ACTOR_BODY_NEEDLES)


def first_content_indent(body: str, fallback: str) -> str:
    for line in body.splitlines():
        stripped = line.strip()
        if stripped:
            return line[: len(line) - len(line.lstrip())]
    return fallback


def wrap_body_in_main_actor(body: str, fallback_indent: str) -> str:
    if "MainActor.assumeIsolated" in body:
        return body
    indent = first_content_indent(body, fallback_indent)
    if body and not body.endswith("\n"):
        body += "\n"
    indented_body = "".join(
        f"    {line}" if line.strip() else line
        for line in body.splitlines(keepends=True)
    )
    return f"{indent}MainActor.assumeIsolated {{\n{indented_body}{indent}}}\n"


def lower_mainactor_callback_bodies(text: str) -> tuple[str, bool]:
    changed = False

    def wrap_matches(source: str, regex: re.Pattern[str]) -> str:
        nonlocal changed
        matches = list(regex.finditer(source))
        for match in reversed(matches):
            open_index = source.rfind("{", match.start(), match.end())
            if open_index < 0:
                continue
            close_index = matching_closing_brace(source, open_index)
            if close_index is None:
                continue
            body_start = match.end()
            closing_line_start = source.rfind("\n", body_start, close_index) + 1
            if closing_line_start <= body_start:
                closing_line_start = close_index
            body = source[body_start:closing_line_start]
            if not body_requires_main_actor_wrap(body) or "MainActor.assumeIsolated" in body:
                continue
            line_start = source.rfind("\n", 0, match.start()) + 1
            fallback_indent = source[line_start:match.start()] + "    "
            wrapped = wrap_body_in_main_actor(body, fallback_indent)
            source = source[:body_start] + wrapped + source[closing_line_start:]
            changed = True
        return source

    text = wrap_matches(text, SINK_CLOSURE_HEADER_RE)
    text = wrap_matches(text, MAIN_ACTOR_METHOD_HEADER_RE)
    return text, changed


def swift_brace_delta(line: str) -> int:
    depth = 0
    in_line_comment = False
    in_block_comment = False
    in_string = False
    escaped = False
    index = 0

    while index < len(line):
        char = line[index]
        next_char = line[index + 1] if index + 1 < len(line) else ""
        if in_line_comment:
            break
        if in_block_comment:
            if char == "*" and next_char == "/":
                in_block_comment = False
                index += 2
                continue
            index += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "\"":
                in_string = False
            index += 1
            continue
        if char == "/" and next_char == "/":
            in_line_comment = True
            index += 2
            continue
        if char == "/" and next_char == "*":
            in_block_comment = True
            index += 2
            continue
        if char == "\"":
            in_string = True
            index += 1
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        index += 1
    return depth


def swift_paren_delta(line: str) -> int:
    depth = 0
    in_line_comment = False
    in_block_comment = False
    in_string = False
    escaped = False
    index = 0

    while index < len(line):
        char = line[index]
        next_char = line[index + 1] if index + 1 < len(line) else ""
        if in_line_comment:
            break
        if in_block_comment:
            if char == "*" and next_char == "/":
                in_block_comment = False
                index += 2
                continue
            index += 1
            continue
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "\"":
                in_string = False
            index += 1
            continue
        if char == "/" and next_char == "/":
            in_line_comment = True
            index += 2
            continue
        if char == "/" and next_char == "*":
            in_block_comment = True
            index += 2
            continue
        if char == "\"":
            in_string = True
            index += 1
            continue
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        index += 1
    return depth


def is_mainactor_sensitive_default(expression: str) -> bool:
    stripped = expression.strip()
    if not stripped or stripped in SWIFT_LITERAL_IDENTIFIERS:
        return False
    if stripped.startswith(('"', "#", "[", "{")):
        return False
    if re.match(r"^[0-9]", stripped):
        return False
    if stripped.startswith("Self."):
        return True
    return re.match(r"^(?:[A-Za-z_][A-Za-z0-9_]*\.)*[A-Z][A-Za-z0-9_]*\s*\(", stripped) is not None


def local_parameter_name(parameter_label_text: str) -> str | None:
    pieces = parameter_label_text.strip().split()
    if not pieces:
        return None
    candidate = pieces[-1]
    if candidate == "_" or not SIMPLE_IDENTIFIER_RE.match(candidate):
        return None
    return candidate


def optional_parameter_type(type_text: str) -> str | None:
    stripped = type_text.strip()
    compact = re.sub(r"\s+", "", stripped)
    if not stripped or compact.endswith("?"):
        return None
    if "->" in stripped or stripped.startswith("@") or stripped.startswith("inout ") or stripped.startswith("some "):
        return None
    if stripped.startswith("any "):
        return f"({stripped})?"
    return f"{stripped}?"


def rewrite_mainactor_default_parameter(line_body: str) -> tuple[str, tuple[str, str] | None]:
    if "=" not in line_body or ":" not in line_body or "//" in line_body:
        return line_body, None

    right_trimmed = line_body.rstrip()
    trailing_comma = "," if right_trimmed.endswith(",") else ""
    without_comma = right_trimmed[:-1].rstrip() if trailing_comma else right_trimmed
    before_default, separator, default_expression = without_comma.partition("=")
    if not separator:
        return line_body, None
    before_type, colon, type_text = before_default.partition(":")
    if not colon:
        return line_body, None

    name = local_parameter_name(before_type)
    if name is None:
        return line_body, None
    if not is_mainactor_sensitive_default(default_expression):
        return line_body, None
    optional_type = optional_parameter_type(type_text)
    if optional_type is None:
        return line_body, None

    rewritten = f"{before_type.rstrip()}: {optional_type} = nil{trailing_comma}"
    return rewritten, (name, default_expression.strip())


def rewrite_mainactor_initializer_signature(
    signature_lines: list[str],
) -> tuple[list[str], list[tuple[str, str]], bool]:
    rewritten_lines: list[str] = []
    defaults: list[tuple[str, str]] = []
    changed = False

    for line in signature_lines:
        line_body = line[:-1] if line.endswith("\n") else line
        newline = "\n" if line.endswith("\n") else ""
        rewritten, default = rewrite_mainactor_default_parameter(line_body)
        rewritten_lines.append(f"{rewritten}{newline}")
        if default is not None:
            defaults.append(default)
            changed = True

    return rewritten_lines, defaults, changed


def lower_mainactor_initializer_defaults(text: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    changed = False
    depth = 0
    mainactor_type_bases: list[int] = []
    pending_mainactor_attribute = False
    index = 0

    while index < len(lines):
        line = lines[index]
        line_body = line[:-1] if line.endswith("\n") else line
        stripped = line_body.strip()

        while mainactor_type_bases and depth <= mainactor_type_bases[-1]:
            mainactor_type_bases.pop()

        line_has_mainactor = stripped.startswith("@MainActor")
        type_is_mainactor = pending_mainactor_attribute or line_has_mainactor
        is_type_decl = TYPE_DECL_RE.match(line_body) is not None or (
            line_has_mainactor and TYPE_DECL_RE.match(stripped.removeprefix("@MainActor").lstrip()) is not None
        )
        in_mainactor_type_body = bool(mainactor_type_bases and depth == mainactor_type_bases[-1] + 1)
        previous = previous_nonempty(output, len(output))
        is_init = INIT_DECL_RE.match(line_body) is not None or INLINE_MAINACTOR_INIT_DECL_RE.match(line_body) is not None
        is_mainactor_init = in_mainactor_type_body or previous.startswith("@MainActor") or pending_mainactor_attribute

        if is_init and is_mainactor_init:
            signature_lines: list[str] = []
            paren_depth = 0
            signature_index = index
            while signature_index < len(lines):
                signature_line = lines[signature_index]
                signature_body = signature_line[:-1] if signature_line.endswith("\n") else signature_line
                signature_lines.append(signature_line)
                paren_depth += swift_paren_delta(signature_body)
                if "{" in signature_body and paren_depth <= 0:
                    break
                signature_index += 1

            rewritten_signature, defaults, signature_changed = rewrite_mainactor_initializer_signature(signature_lines)
            output.extend(rewritten_signature)
            if defaults:
                open_line = signature_lines[-1][:-1] if signature_lines[-1].endswith("\n") else signature_lines[-1]
                body_indent = open_line[: len(open_line) - len(open_line.lstrip())] + "    "
                for name, default in defaults:
                    output.append(f"{body_indent}let {name} = {name} ?? {default}\n")
            changed = changed or signature_changed
            for signature_line in signature_lines:
                signature_body = signature_line[:-1] if signature_line.endswith("\n") else signature_line
                depth += swift_brace_delta(signature_body)
            index = signature_index + 1
            pending_mainactor_attribute = False
            continue

        output.append(line)

        if is_type_decl and type_is_mainactor:
            mainactor_type_bases.append(depth)

        pending_mainactor_attribute = stripped == "@MainActor"
        depth += swift_brace_delta(line_body)
        index += 1

    return "".join(output), changed


def lower_mainactor_type_initializers(text: str) -> tuple[str, bool]:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    changed = False
    depth = 0
    mainactor_type_bases: list[int] = []
    pending_mainactor_attribute = False

    for line in lines:
        line_body = line[:-1] if line.endswith("\n") else line
        newline = "\n" if line.endswith("\n") else ""
        stripped = line_body.strip()

        while mainactor_type_bases and depth <= mainactor_type_bases[-1]:
            mainactor_type_bases.pop()

        line_has_mainactor = stripped.startswith("@MainActor")
        type_is_mainactor = pending_mainactor_attribute or line_has_mainactor
        is_type_decl = TYPE_DECL_RE.match(line_body) is not None or (
            line_has_mainactor and TYPE_DECL_RE.match(stripped.removeprefix("@MainActor").lstrip()) is not None
        )

        if mainactor_type_bases and depth == mainactor_type_bases[-1] + 1 and INIT_DECL_RE.match(line_body):
            previous = previous_nonempty(output, len(output))
            if not previous.startswith("@MainActor") and not previous.startswith("nonisolated"):
                indent = line_body[: len(line_body) - len(line_body.lstrip())]
                output.append(f"{indent}@MainActor{newline}")
                changed = True

        output.append(line)

        if is_type_decl and type_is_mainactor:
            mainactor_type_bases.append(depth)

        pending_mainactor_attribute = stripped == "@MainActor"
        depth += swift_brace_delta(line_body)

    return "".join(output), changed


def lower_file(path: pathlib.Path) -> bool:
    text = path.read_text()
    if not should_process(text):
        return False

    text, changed = lower_expression_isolation(text)
    text, callback_changed = lower_mainactor_callback_bodies(text)
    changed = changed or callback_changed
    text, initializer_changed = lower_mainactor_type_initializers(text)
    changed = changed or initializer_changed
    text, default_argument_changed = lower_mainactor_initializer_defaults(text)
    changed = changed or default_argument_changed
    lines = text.splitlines(keepends=True)
    output: list[str] = []

    for index, line in enumerate(lines):
        line_body = line[:-1] if line.endswith("\n") else line
        newline = "\n" if line.endswith("\n") else ""
        match = ASSIGNMENT_RE.match(line_body)
        previous = previous_nonempty(lines, index)
        if match and not previous.startswith("MainActor.assumeIsolated"):
            indent, assignment, rhs = match.groups()
            rhs = rhs.strip()
            if not is_single_line_rhs(rhs):
                output.append(line)
                continue
            capture_list = ""
            if SIMPLE_IDENTIFIER_RE.match(rhs) and rhs not in SWIFT_LITERAL_IDENTIFIERS:
                capture_list = f" [{rhs}] in"
            output.append(f"{indent}MainActor.assumeIsolated {{{capture_list}{newline}")
            output.append(f"{indent}    {assignment}{newline}")
            output.append(f"{indent}}}{newline}")
            changed = True
        elif match := UI_PROXY_CALL_RE.match(line_body):
            indent, call = match.groups()
            previous = previous_nonempty(lines, index)
            if previous.startswith("MainActor.assumeIsolated"):
                output.append(line)
                continue
            output.append(f"{indent}MainActor.assumeIsolated {{{newline}")
            output.append(f"{indent}    {call}{newline}")
            output.append(f"{indent}}}{newline}")
            changed = True
        else:
            output.append(line)

    if changed:
        path.write_text("".join(output))
    return changed


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: lower-mainactor-assignments-for-linux.py SOURCE_DIR", file=sys.stderr)
        return 64

    root = pathlib.Path(sys.argv[1])
    if not root.is_dir():
        print(f"source directory does not exist: {root}", file=sys.stderr)
        return 66

    changed = 0
    for path in root.rglob("*.swift"):
        if path.name == "Package.swift":
            continue
        if lower_file(path):
            changed += 1

    print(f"Lowered main-actor controller assignments in {changed} Swift files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
