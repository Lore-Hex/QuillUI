#!/usr/bin/env python3
"""Fold same-module extension overrides into their owning class.

Apple framework classes are Objective-C imported, so macOS Swift code often
puts overrides in same-module extensions. Quill's Linux shims are native Swift
classes, where overriding a non-ObjC superclass member from an extension is not
accepted by the compiler. This pass edits only the generated source copy and
folds those extension bodies into the class declaration that owns them.
"""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from pathlib import Path


CLASS_RE = re.compile(
    r"\b(?:open|public|internal|fileprivate|private)?\s*(?:final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)\b"
)
EXTENSION_RE = re.compile(
    r"(^[ \t]*(?:open|public|internal|fileprivate|private)?[ \t]*extension[ \t]+"
    r"([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)([^{]*)\{)",
    re.MULTILINE,
)
IMPORT_RE = re.compile(r"^[ \t]*import[ \t]+[A-Za-z_][A-Za-z0-9_.]*(?:[ \t]*;[ \t]*)?$", re.MULTILINE)


def matching_brace(source: str, open_index: int) -> int | None:
    depth = 0
    i = open_index
    state = "code"
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""

        if state == "line_comment":
            if ch == "\n":
                state = "code"
        elif state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 1
        elif state == "string":
            if ch == "\\":
                i += 1
            elif ch == '"':
                state = "code"
        else:
            if ch == "/" and nxt == "/":
                state = "line_comment"
                i += 1
            elif ch == "/" and nxt == "*":
                state = "block_comment"
                i += 1
            elif ch == '"':
                state = "string"
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    return None


def swift_files(source_dir: Path) -> list[Path]:
    return sorted(path for path in source_dir.rglob("*.swift") if path.name != "Package.swift")


def import_lines(source: str) -> list[str]:
    return [match.group(0).strip() for match in IMPORT_RE.finditer(source)]


def extension_conformances(tail: str) -> list[str]:
    if "where" in tail:
        return []
    stripped = tail.strip()
    if not stripped.startswith(":"):
        return []
    protocols = []
    for item in stripped[1:].split(","):
        name = item.strip()
        if name:
            protocols.append(name)
    return protocols


def has_override_member(body: str) -> bool:
    return re.search(r"\boverride\s+(?:open|public|internal|fileprivate|private)?\s*(?:class\s+)?(?:func|var|subscript)\b", body) is not None


def find_class_body(source: str, type_name: str) -> tuple[int, int, int] | None:
    for match in CLASS_RE.finditer(source):
        if match.group(1) != type_name:
            continue
        open_index = source.find("{", match.end())
        if open_index < 0:
            continue
        close_index = matching_brace(source, open_index)
        if close_index is None:
            continue
        return match.start(), open_index, close_index
    return None


def add_imports(source: str, imports: list[str]) -> str:
    existing = set(import_lines(source))
    missing = [line for line in imports if line not in existing]
    if not missing:
        return source

    matches = list(IMPORT_RE.finditer(source))
    insertion = "\n".join(missing) + "\n"
    if matches:
        index = matches[-1].end()
        return source[:index] + "\n" + insertion + source[index:]
    return insertion + "\n" + source


def add_conformances(source: str, type_name: str, protocols: list[str]) -> str:
    if not protocols:
        return source
    location = find_class_body(source, type_name)
    if location is None:
        return source

    class_start, open_index, _ = location
    header = source[class_start:open_index]
    existing_tail = header.split(":", 1)[1] if ":" in header else ""
    existing = {item.strip() for item in existing_tail.split(",") if item.strip()}
    missing = [protocol for protocol in protocols if protocol not in existing]
    if not missing:
        return source

    insertion_index = open_index
    while insertion_index > class_start and source[insertion_index - 1].isspace():
        insertion_index -= 1
    separator = ", " if ":" in header else ": "
    return source[:insertion_index] + separator + ", ".join(missing) + source[insertion_index:]


def append_to_class(source: str, type_name: str, folded_blocks: list[tuple[str, str]]) -> str:
    if not folded_blocks:
        return source
    location = find_class_body(source, type_name)
    if location is None:
        return source
    _, _, close_index = location
    fragments = []
    for origin, body in folded_blocks:
        trimmed = body.rstrip()
        if not trimmed.strip():
            continue
        fragments.append(f"\n\n    // MARK: - QuillUI folded extension: {origin}\n{trimmed}\n")
    if not fragments:
        return source
    return source[:close_index] + "".join(fragments) + source[close_index:]


def expose_top_level_private_helpers(source: str) -> str:
    # If an override body is folded into another file, top-level `private`
    # helpers from the original extension file are no longer visible. In the
    # generated Linux copy, widen those top-level helpers to internal.
    return re.sub(
        r"(?m)^private[ \t]+(?=(?:let|var|func|class|struct|enum)\b)",
        "",
        source,
    )


def lower(source_dir: Path) -> int:
    files = swift_files(source_dir)
    contents = {path: path.read_text(encoding="utf-8") for path in files}
    class_owners: dict[str, Path] = {}
    for path, source in contents.items():
        for match in CLASS_RE.finditer(source):
            class_owners.setdefault(match.group(1), path)

    removals: dict[Path, list[tuple[int, int]]] = defaultdict(list)
    folded: dict[Path, dict[str, list[tuple[str, str]]]] = defaultdict(lambda: defaultdict(list))
    imports_for_target: dict[Path, list[str]] = defaultdict(list)
    conformances_for_target: dict[Path, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))

    folded_count = 0
    for path, source in contents.items():
        for match in EXTENSION_RE.finditer(source):
            full_type = match.group(2)
            type_name = full_type.rsplit(".", 1)[-1]
            target = class_owners.get(type_name)
            open_index = match.end() - 1
            close_index = matching_brace(source, open_index)
            if close_index is None:
                continue
            body = source[open_index + 1:close_index]
            if not has_override_member(body):
                continue

            if target is None:
                removals[path].append((match.start(), close_index + 1))
                folded_count += 1
                continue

            removals[path].append((match.start(), close_index + 1))
            folded[target][type_name].append((path.relative_to(source_dir).as_posix(), body))
            imports_for_target[target].extend(import_lines(source))
            conformances_for_target[target][type_name].extend(extension_conformances(match.group(3)))
            folded_count += 1

    for path, ranges in removals.items():
        source = contents[path]
        for start, end in sorted(ranges, reverse=True):
            replacement = "\n"
            source = source[:start] + replacement + source[end:]
        source = expose_top_level_private_helpers(source)
        contents[path] = source

    for path, imports in imports_for_target.items():
        contents[path] = add_imports(contents[path], imports)

    for path, by_type in conformances_for_target.items():
        source = contents[path]
        for type_name, protocols in by_type.items():
            source = add_conformances(source, type_name, protocols)
        contents[path] = source

    for path, by_type in folded.items():
        source = contents[path]
        for type_name, blocks in by_type.items():
            source = append_to_class(source, type_name, blocks)
        contents[path] = source

    for path, source in contents.items():
        original = path.read_text(encoding="utf-8")
        if source != original:
            path.write_text(source, encoding="utf-8")

    return folded_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    args = parser.parse_args()
    if not args.source_dir.is_dir():
        parser.error(f"source directory does not exist: {args.source_dir}")
    count = lower(args.source_dir)
    print(f"Folded extension override blocks: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
