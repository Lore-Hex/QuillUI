#!/usr/bin/env bash
# Add required NSCoder initializers to disposable Signal app TSInteraction
# subclasses identified by the compiler. Swift requires this because the Linux
# TSInteraction port implements NSCoding with a required `init?(coder:)`, while
# the ObjC base did not force Swift subclasses to spell it out.
set -euo pipefail
LOG="${1:?usage: quill-signal-fix-app-required-coders.sh <build-log>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$LOG" "$ROOT" <<'PY'
import pathlib, re, sys

log, root = sys.argv[1], pathlib.Path(sys.argv[2])
pat = re.compile(r"^/qui/(?P<file>[^:]+\.swift):(?P<line>\d+):\d+: error: 'required' initializer 'init\(coder:\)' must be provided by subclass of 'TSInteraction'")
files = set()
for line in open(log, errors="replace"):
    m = pat.match(line.rstrip())
    if m:
        files.add(root / m.group("file"))

inserted = 0
for path in sorted(files):
    if not path.exists():
        continue
    text = path.read_text(errors="replace")
    if "required init?(coder: NSCoder)" in text:
        continue
    lines = text.splitlines()
    insert_at = None
    depth = 0
    class_depth = None
    for i, line in enumerate(lines):
        if class_depth is None and re.search(r'\bclass\s+\w+\s*:\s*TSInteraction\b', line):
            depth += line.count("{") - line.count("}")
            class_depth = depth
            continue
        if class_depth is not None:
            next_depth = depth + line.count("{") - line.count("}")
            if next_depth < class_depth:
                insert_at = i
                break
            depth = next_depth
        else:
            depth += line.count("{") - line.count("}")
    if insert_at is None:
        continue
    block = [
        "",
        "    public required init?(coder: NSCoder) {",
        '        fatalError("init?(coder:) is unavailable for transient interactions.")',
        "    }",
    ]
    lines[insert_at:insert_at] = block
    path.write_text("\n".join(lines) + ("\n" if text.endswith("\n") else ""))
    inserted += 1

print(f"required coder lowering: inserted {inserted} init?(coder:) implementations across {len(files)} files")
PY
