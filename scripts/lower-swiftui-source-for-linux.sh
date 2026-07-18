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

swift_files=()
while IFS= read -r -d '' source_file; do
  swift_files+=("${source_file#$SOURCE_DIR/}")
done < <(find "$SOURCE_DIR" -name '*.swift' ! -name 'Package.swift' -print0)

if (( ${#swift_files[@]} > 0 )); then
  "$(dirname "$0")/ensure-swift-imports.sh" "$SOURCE_DIR" QuillShims "${swift_files[@]}"
fi

if (( ${#swift_files[@]} > 0 )); then
  find "$SOURCE_DIR" -name '*.swift' ! -name 'Package.swift' -print0 |
    xargs -0 perl -0pi -e '
      s/^[ \t]*\@main[ \t]*\n//gm;
      s/^[ \t]*import[ \t]+Carbon\.[A-Za-z0-9_]+[ \t]*$/import Carbon/gm;
      s/^([ \t]*)import[ \t]+(AppKit|Cocoa|SwiftUI|UIKit)\b/$1\@preconcurrency import $2/gm;
      s/^[ \t]*\@Invalidating(?:\([^\n]*\))?[ \t]*\n//gm;
      s/\n[ \t]*#Preview[\s\S]*?#endif\s*\z/\n#endif\n/s;
      s/\n[ \t]*#Preview[\s\S]*\z/\n/s;
      s/(?<!!)\bos\(macOS\)(?![ \t]*\|\|[ \t]*os\(Linux\))/(os(macOS) || os(Linux))/g;
      s/DispatchQueue\.dispatchMainIfNot[ \t]*\{/Task { \@MainActor in/g;
      s/(\bpointSize[ \t]*\+[ \t]*)([0-9]+(?:\.[0-9]+)?)/${1}CGFloat($2)/g;
      s/(\.withSymbolConfiguration\(\s*)\.init\(/$1NSImage.SymbolConfiguration(/g;
      s/(\.applying\(\s*)\.init\((?=[^)]*\b(?:pointSize|weight|scale|textStyle|paletteColors)\s*:)/$1NSImage.SymbolConfiguration(/g;
      s/: View, Sendable/: View/g;
      s/^([ \t]*)((?:(?:public|open|internal|fileprivate|private)[ \t]+)*func[ \t]+[A-Za-z_][A-Za-z0-9_]*\(controller:[ \t]*TextViewController\b)/$1\@MainActor\n$1$2/gm;
      # No keyboardType(.URL) rewrite: QuillUI mirrors Apple with a single
      # keyboardType(_ type: UIKeyboardType), so leading-dot inference handles
      # URL the same way it handles .emailAddress and .numberPad.
      s/\.textContentType\([ \t]*\.URL[ \t]*\)/.textContentType(TextContentType.URL)/g;
      s/\bNSMutableAttributedString\s*\(\s*\)/NSMutableAttributedString(string: "")/g;
      s/\bNSAttributedString\s*\(\s*\)/NSAttributedString(string: "")/g;
      s/\binit\(rawValue:[ \t]*Corners\.RawValue\)/init(rawValue: Int)/g;
      s/\.selectedRange\(\)/.selectedRange/g;
      s/(?<![A-Za-z0-9_.])abs\(([A-Za-z_][A-Za-z0-9_.]*[ \t]*-[ \t]*[A-Za-z_][A-Za-z0-9_.]*)\)/Swift.abs($1)/g;
      s/^([ \t]*)(\}[ \t]*else[ \t]+if[ \t]+let[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*([^,\n]+?)[ \t]+as\?[ \t]+NSURL[ \t]*),[ \t]*let[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*=[ \t]*\3\.absoluteString[ \t]*\{/$1$2 {\n$1    let $5 = $3.absoluteString/gm;
      s/(operation:[ \t]*\@escaping[ \t]*)\(\)[ \t]*->[ \t]*Void/${1}\@Sendable () -> Void/g;
      s/operation:[ \t]*\{[ \t]*completion\(\.success\(([A-Za-z_][A-Za-z0-9_]*)\(\)\)\)[ \t]*\}/operation: { let result = $1(); Task { \@MainActor in completion(.success(result)) } }/g;
      s/((?:\@escaping[ \t]+)?\@Sendable[ \t]*\(\)[ \t]*->[ \t]*([A-Za-z_][A-Za-z0-9_.]*)[ \t]*=[ \t]*)\2\.init\b(?![ \t]*\()/$1 . "{ " . $2 . "() }"/ge;
      s/^([ \t]*)(?!nonisolated\(unsafe\)[ \t]+)((?:public|internal|fileprivate|private)[ \t]+)?static[ \t]+var[ \t]+(?=[^\n]*=)/$1nonisolated(unsafe) $2static var /gm;
      s/^([ \t]*)(class[ \t]+[A-Za-z_][A-Za-z0-9_]*ViewModel[ \t]*:[^\n{]*\bObservableObject\b)/$1\@MainActor\n$1$2/gm;
      s/^([ \t]*)\@MainActor[ \t]*\n\1\@MainActor[ \t]*\n/$1\@MainActor\n/gm;
    '

  for source_file in "${swift_files[@]}"; do
    absolute_source="$SOURCE_DIR/$source_file"
    if grep -Eq '^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]+)*import[[:space:]]+(class[[:space:]]+)?AppKit(\.|[[:space:]]|$)|canImport\(AppKit\)' "$absolute_source"; then
      perl -0pi -e 's/(?<![A-Za-z0-9_.])NSTextStorage(?![A-Za-z0-9_])/AppKit.NSTextStorage/g' "$absolute_source"
    fi
    if grep -Eq '^[[:space:]]*import[[:space:]]+SwiftTreeSitter\b' "$absolute_source"; then
      perl -0pi -e 's/(?<![A-Za-z0-9_.])Node(?![A-Za-z0-9_])/SwiftTreeSitter.Node/g' "$absolute_source"
    fi
  done
fi

python3 "$(dirname "$0")/lower-mainactor-assignments-for-linux.py" "$SOURCE_DIR"
python3 "$(dirname "$0")/lower-linux-conditional-compilation.py" "$SOURCE_DIR"
"$(dirname "$0")/lower-extension-overrides-for-linux.py" "$SOURCE_DIR"
"$(dirname "$0")/run-quill-swiftui-lower.sh" "$SOURCE_DIR"
"$(dirname "$0")/run-quill-appkit-lower.sh" "$SOURCE_DIR"
"$(dirname "$0")/lower-objc-interop-for-linux.sh" "$SOURCE_DIR"

if (( ${#swift_files[@]} > 0 )); then
  find "$SOURCE_DIR" -name '*.swift' ! -name 'Package.swift' -print0 |
    xargs -0 perl -0pi -e '
      s/^(import[ \t]+[A-Za-z_][A-Za-z0-9_.]*)(?=public[ \t]+(?:protocol|class|struct|enum|actor|extension|func|var|let|typealias)\b)/$1\n/gm;
    '
fi

swift_files="$(find "$SOURCE_DIR" -name '*.swift' ! -name 'Package.swift' | wc -l | tr -d ' ')"
cat <<MSG
Lowered generic SwiftUI/AppKit Linux source in:
  $SOURCE_DIR
Swift files processed: $swift_files
MSG
