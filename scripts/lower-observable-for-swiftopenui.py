#!/usr/bin/env python3
"""Lower Swift Observation syntax into SwiftOpenUI's ObservableObject model.

This runs only on generated Linux source copies. It preserves the app source
shape while giving SwiftOpenUI a reactivity model it already understands:

  @Observable
  final class Store { var items: [Item] = [] }

becomes:

  final class Store: QuillObservableObject { @QuillPublished var items: [Item] = [] }
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


CLASS_RE = re.compile(
    r"^(?P<indent>\s*)(?P<prefix>(?:public|internal|fileprivate|private|open|final)\s+)*"
    r"class\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)(?P<rest>[^{]*)\{(?P<tail>.*)$"
)

VAR_RE = re.compile(
    r"^(?P<indent>\s*)(?P<mainactor>@MainActor\s+)?"
    r"(?P<access>public\s+|internal\s+|fileprivate\s+|open\s+)?"
    r"var\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\b(?P<rest>.*)$"
)


def brace_delta(line: str) -> int:
    """A conservative brace counter for normal Swift source lines."""
    line = line.split("//", 1)[0]
    return line.count("{") - line.count("}")


def lower_class_declaration(line: str) -> str:
    match = CLASS_RE.match(line)
    if not match:
        return line

    rest = match.group("rest").rstrip()
    tail = match.group("tail")

    if ":" in rest:
        before_colon, after_colon = rest.split(":", 1)
        conformances = [part.strip() for part in after_colon.split(",") if part.strip()]
    else:
        before_colon = rest
        conformances = []

    lowered: list[str] = []
    has_observable = False
    for conformance in conformances:
        if conformance == "ObservableObject":
            has_observable = True
        if conformance == "Sendable":
            conformance = "@unchecked Sendable"
        lowered.append(conformance)

    if not has_observable:
        lowered.insert(0, "QuillObservableObject")

    inheritance = ": " + ", ".join(lowered) if lowered else ""
    return (
        f"{match.group('indent')}{match.group('prefix') or ''}"
        f"class {match.group('name')}{before_colon}{inheritance} {{{tail}"
    )


def is_stored_state_var(line: str) -> bool:
    stripped = line.strip()
    if not stripped or stripped.startswith("//"):
        return False
    if "@Published" in stripped:
        return False
    if stripped.startswith(("static var ", "private var ", "private(set) var ")):
        return False
    if re.match(r"^(public|internal|fileprivate|open)\s+static\s+var\b", stripped):
        return False

    match = VAR_RE.match(line)
    if not match:
        return False

    rest = match.group("rest")
    before_equals = rest.split("=", 1)[0]
    if "{" in before_equals:
        return False
    return True


def publish_var(line: str) -> str:
    match = VAR_RE.match(line)
    if not match:
        return line
    mainactor = match.group("mainactor") or ""
    access = match.group("access") or ""
    return (
        f"{match.group('indent')}{mainactor}@QuillPublished {access}"
        f"var {match.group('name')}{match.group('rest')}"
    )


def _ensure_import(text: str, module: str) -> str:
    """Insert `import <module>` if not already present, just after
    the file's last existing top-level import line.

    Keeps the import grouping tidy and avoids duplicating imports
    when the lowering script runs multiple times on the same file.
    """
    if re.search(rf"^\s*import {re.escape(module)}\b", text, re.MULTILINE):
        return text

    lines = text.splitlines(keepends=True)
    last_import = -1
    for index, line in enumerate(lines):
        if re.match(r"^\s*import\s+[A-Za-z_][A-Za-z0-9_]*\s*$", line):
            last_import = index
    if last_import >= 0:
        lines.insert(last_import + 1, f"import {module}\n")
        return "".join(lines)
    return f"import {module}\n" + text




def lower_source(text: str) -> str:
    lines = text.splitlines(keepends=True)
    output: list[str] = []
    pending_observable = False
    observable_depth: int | None = None
    depth = 0

    for line in lines:
        line_body = line[:-1] if line.endswith("\n") else line
        newline = "\n" if line.endswith("\n") else ""
        stripped = line_body.strip()

        if stripped == "@Observable":
            pending_observable = True
            continue

        if pending_observable:
            lowered = lower_class_declaration(line_body)
            if lowered != line_body:
                line_body = lowered
                observable_depth = depth + brace_delta(line_body)
                pending_observable = False
            else:
                output.append("@Observable" + newline)
                pending_observable = False

        elif observable_depth is not None and depth == observable_depth:
            if is_stored_state_var(line_body):
                line_body = publish_var(line_body)

        output.append(line_body + newline)
        depth += brace_delta(line_body)
        if observable_depth is not None and depth < observable_depth:
            observable_depth = None

    if pending_observable:
        output.append("@Observable\n")

    lowered = "".join(output)
    if lowered != text:
        # The wrapper script injects QuillShims after this pass. QuillShims
        # re-exports the SwiftUI/AppKit/UIKit compatibility surface, including
        # the lowered `QuillObservableObject` / `@QuillPublished` aliases.
        # Avoid importing QuillUI here: generated app files already import the
        # SwiftUI shim, and importing both QuillUI and QuillSwiftUICompatibility
        # exposes duplicate compatibility overloads.
        lowered = _ensure_import(lowered, "SwiftUI")
    return lowered


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: lower-observable-for-swiftopenui.py SOURCE_DIR", file=sys.stderr)
        return 64

    source_dir = Path(sys.argv[1])
    if not source_dir.is_dir():
        print(f"Source directory does not exist: {source_dir}", file=sys.stderr)
        return 66

    changed = 0
    for path in source_dir.rglob("*.swift"):
        original = path.read_text()
        lowered = lower_source(original)
        if lowered != original:
            path.write_text(lowered)
            changed += 1

    print(f"Lowered @Observable classes for SwiftOpenUI in {changed} Swift files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
