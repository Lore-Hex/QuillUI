#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  cat >&2 <<'MSG'
Usage: scripts/lower-swiftui-source-for-linux.sh GENERATED_SOURCE_DIR

Applies conservative, app-agnostic SwiftUI/AppKit source cleanup to a generated
source copy before building it with QuillUI on Linux. This script edits the
generated copy in place and must not be pointed at an app's upstream source
tree.
MSG
  exit 64
fi

SOURCE_DIR="$1"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Generated source directory does not exist: $SOURCE_DIR" >&2
  exit 66
fi

"$(dirname "$0")/lower-observable-for-swiftopenui.py" "$SOURCE_DIR"

swift_files=()
while IFS= read -r -d '' source_file; do
  swift_files+=("${source_file#$SOURCE_DIR/}")
done < <(find "$SOURCE_DIR" -name '*.swift' -print0)

if (( ${#swift_files[@]} > 0 )); then
  "$(dirname "$0")/ensure-swift-imports.sh" "$SOURCE_DIR" QuillShims "${swift_files[@]}"
fi

find "$SOURCE_DIR" -name '*.swift' -print0 |
  xargs -0 perl -0pi -e '
    s/^[ \t]*\@main[ \t]*\n//gm;
    s/^[ \t]*\@Observable[ \t]*\n//gm;
    s/\n[ \t]*#Preview[\s\S]*?#endif\s*\z/\n#endif\n/s;
    s/\n[ \t]*#Preview[\s\S]*\z/\n/s;
    s/(?<!!)\bos\(macOS\)(?![ \t]*\|\|[ \t]*os\(Linux\))/(os(macOS) || os(Linux))/g;
    s/([:(,][ \t]*)\@MainActor[ \t]+/$1/g;
    s/Task \{[ \t]*\@MainActor[ \t]+in/Task {/g;
    s/Task \{[ \t]*\@MainActor[ \t]+(\[[^\]]+\][ \t]+in)/Task { $1/g;
    s/^[ \t]*\@MainActor[ \t]*\n//gm;
    s/^([ \t]*)\@MainActor[ \t]+/$1/gm;
    s/: View, Sendable/: View/g;
    # No keyboardType(.URL) rewrite: the shim now exposes a single canonical
    # keyboardType(_ type: UIKeyboardType), so upstream `.keyboardType(.URL)`
    # resolves to UIKeyboardType.URL by inference — exactly like every other
    # `.keyboardType(.emailAddress)` / `.numberPad` case that was never rewritten.
    # The old rewrite qualified `.URL` to DSSC.KeyboardType.URL only to break the
    # ambiguity from a second keyboardType(KeyboardType) overload that no longer
    # exists (the bespoke KeyboardType struct was removed to mirror Apple, which
    # ships exactly one keyboard-type — UIKeyboardType). Leading-dot inference
    # needs no `import UIKit` in the lowered source.
    s/\.textContentType\([ \t]*\.URL[ \t]*\)/.textContentType(TextContentType.URL)/g;
  '

"$(dirname "$0")/run-quill-appkit-lower.sh" "$SOURCE_DIR"
"$(dirname "$0")/lower-objc-interop-for-linux.sh" "$SOURCE_DIR"

swift_files="$(find "$SOURCE_DIR" -name '*.swift' | wc -l | tr -d ' ')"
cat <<MSG
Lowered generic SwiftUI/AppKit Linux source in:
  $SOURCE_DIR
Swift files processed: $swift_files
MSG
