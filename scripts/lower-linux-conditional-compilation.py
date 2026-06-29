#!/usr/bin/env python3
"""Resolve simple platform-only conditional compilation for Linux copies.

Generated Linux build trees can still contain inactive platform branches such
as `#if os(iOS)` inside SwiftUI modifier chains. Swift accepts those directives
in source, but later source-to-source lowering can move parentheses around them
before the compiler gets a chance to discard inactive code. This pass removes
only condition groups whose branch expressions are fully understood from a
Linux target perspective, leaving unknown conditions untouched.
"""

from __future__ import annotations

import pathlib
import re
import shutil
import sys


DIRECTIVE_RE = re.compile(r"^(\s*)#(if|elseif|else|endif)\b(.*)$")
INACTIVE_PLATFORM_SOURCE_DIRS = {"iOS", "tvOS", "watchOS", "visionOS"}
OS_RE = re.compile(r"\bos\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)")
TARGET_ENV_RE = re.compile(
    r"\btargetEnvironment\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"
)
TOKEN_RE = re.compile(r"true|false|&&|\|\||!|\(|\)")


def evaluate_platform_expression(expression: str) -> bool | None:
    """Evaluate a narrow Swift `#if` platform expression for Linux."""

    def replace_os(match: re.Match[str]) -> str:
        return "true" if match.group(1) == "Linux" else "false"

    def replace_target_environment(match: re.Match[str]) -> str:
        return "false"

    lowered = OS_RE.sub(replace_os, expression)
    lowered = TARGET_ENV_RE.sub(replace_target_environment, lowered)
    lowered = lowered.strip()
    if not lowered:
        return None

    tokens: list[str] = []
    index = 0
    while index < len(lowered):
        char = lowered[index]
        if char.isspace():
            index += 1
            continue
        match = TOKEN_RE.match(lowered, index)
        if match is None:
            return None
        tokens.append(match.group(0))
        index = match.end()

    py_tokens = {
        "true": "True",
        "false": "False",
        "&&": "and",
        "||": "or",
        "!": "not",
        "(": "(",
        ")": ")",
    }
    try:
        return bool(eval(" ".join(py_tokens[token] for token in tokens), {"__builtins__": {}}, {}))
    except Exception:
        return None


def directive_kind(line: str) -> str | None:
    match = DIRECTIVE_RE.match(line)
    return match.group(2) if match else None


def find_matching_endif(lines: list[str], if_index: int) -> int | None:
    depth = 0
    for index in range(if_index, len(lines)):
        kind = directive_kind(lines[index])
        if kind == "if":
            depth += 1
        elif kind == "endif":
            depth -= 1
            if depth == 0:
                return index
    return None


def branch_ranges(lines: list[str], if_index: int, endif_index: int) -> list[tuple[int, str | None, int, int]]:
    branches: list[tuple[int, str | None, int, int]] = []
    depth = 0
    current_directive = if_index
    current_condition = DIRECTIVE_RE.match(lines[if_index]).group(3).strip()
    current_start = if_index + 1

    for index in range(if_index + 1, endif_index):
        match = DIRECTIVE_RE.match(lines[index])
        if match is None:
            continue

        kind = match.group(2)
        if kind == "if":
            depth += 1
            continue
        if kind == "endif":
            depth -= 1
            continue
        if depth != 0 or kind not in {"elseif", "else"}:
            continue

        branches.append((current_directive, current_condition, current_start, index))
        current_directive = index
        current_condition = match.group(3).strip() if kind == "elseif" else None
        current_start = index + 1

    branches.append((current_directive, current_condition, current_start, endif_index))
    return branches


def lower_lines(lines: list[str], start: int = 0, end: int | None = None) -> list[str]:
    if end is None:
        end = len(lines)

    output: list[str] = []
    index = start
    while index < end:
        match = DIRECTIVE_RE.match(lines[index])
        if match is None or match.group(2) != "if":
            output.append(lines[index])
            index += 1
            continue

        endif_index = find_matching_endif(lines, index)
        if endif_index is None or endif_index >= end:
            output.append(lines[index])
            index += 1
            continue

        branches = branch_ranges(lines, index, endif_index)
        evaluations: list[bool | None] = [
            True if condition is None else evaluate_platform_expression(condition)
            for _, condition, _, _ in branches
        ]
        if any(value is None for value in evaluations):
            output.extend(lines[index : endif_index + 1])
            index = endif_index + 1
            continue

        selected: tuple[int, str | None, int, int] | None = None
        prior_matched = False
        for branch, value in zip(branches, evaluations):
            condition = branch[1]
            is_active = (not prior_matched) if condition is None else bool(value)
            if condition is not None and bool(value):
                prior_matched = True
            if is_active and selected is None:
                selected = branch
                break

        if selected is not None:
            _, _, branch_start, branch_end = selected
            output.extend(lower_lines(lines, branch_start, branch_end))
        index = endif_index + 1

    return output


def lower_file(path: pathlib.Path) -> bool:
    original = path.read_text(encoding="utf-8")
    lowered = "".join(lower_lines(original.splitlines(keepends=True)))
    if lowered == original:
        return False
    path.write_text(lowered, encoding="utf-8")
    return True


def prune_inactive_platform_source_dirs(source_dir: pathlib.Path) -> int:
    pruned = 0
    for path in sorted(source_dir.rglob("*"), key=lambda item: len(item.parts), reverse=True):
        if path == source_dir or not path.is_dir():
            continue
        if path.name in INACTIVE_PLATFORM_SOURCE_DIRS:
            shutil.rmtree(path)
            pruned += 1
    return pruned


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: lower-linux-conditional-compilation.py SOURCE_DIR", file=sys.stderr)
        return 64

    source_dir = pathlib.Path(argv[1])
    if not source_dir.is_dir():
        print(f"Generated source directory does not exist: {source_dir}", file=sys.stderr)
        return 66

    pruned = prune_inactive_platform_source_dirs(source_dir)
    changed = 0
    for source_file in source_dir.rglob("*.swift"):
        if source_file.name == "Package.swift":
            continue
        if lower_file(source_file):
            changed += 1

    print(f"Pruned {pruned} inactive platform source directories")
    print(f"Resolved Linux platform conditionals in {changed} Swift files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
