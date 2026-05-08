#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  cat >&2 <<'MSG'
Usage: scripts/lower-swiftdata-for-quilldata.sh SOURCE_DIR OUTPUT_DIR

Creates a generated Linux source copy that keeps app sources unchanged while
lowering SwiftData-only syntax to QuillData-compatible Swift:

  @Model class Foo: Identifiable { ... }  -> class Foo: Identifiable, PersistentModel { ... }
  @Transient var value: T { ... }         -> var value: T { ... }
  #Predicate<Foo> { ... }                 -> QuillPredicate<Foo> { ... }
MSG
  exit 64
fi

SOURCE_DIR="$1"
OUTPUT_DIR="$2"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory does not exist: $SOURCE_DIR" >&2
  exit 66
fi

if [[ -e "$OUTPUT_DIR" ]]; then
  echo "Output path already exists: $OUTPUT_DIR" >&2
  echo "Choose a fresh generated directory so app sources are never overwritten." >&2
  exit 73
fi

mkdir -p "$OUTPUT_DIR"

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#$SOURCE_DIR/}"
  output_file="$OUTPUT_DIR/$relative_path"
  mkdir -p "$(dirname "$output_file")"
  cp "$source_file" "$output_file"

  if [[ "$source_file" == *.swift ]]; then
    perl -0pi -e '
      s/^[ \t]*\@Model[ \t]*\n([ \t]*(?:(?:public|internal|private|fileprivate|open)[ \t]+)?(?:final[ \t]+)?class[ \t]+\w+)([ \t]*:[ \t]*([^{\n]+))?([ \t]*\{)/
        my $decl = $1;
        my $parents = defined($3) ? $3 : "";
        my $brace = $4;
        $parents =~ s!\s+$!!;
        $brace =~ s!^\s*! !;
        if ($parents eq "") {
          "$decl: PersistentModel$brace";
        } elsif ($parents =~ m!(^|,\s*)PersistentModel(\s*,|$)!) {
          "$decl: $parents$brace";
        } else {
          "$decl: $parents, PersistentModel$brace";
        }
      /gemx;
      s/^([ \t]*)\@Transient[ \t]+var\b/${1}var/gm;
      s/#Predicate[ \t]*<[ \t]*([^>{]+?)[ \t]*>[ \t]*\{/QuillPredicate<$1> {/g;
    ' "$output_file"
  fi
done < <(find "$SOURCE_DIR" -type f -print0)

remaining="$(
  rg -n "@Model|@Transient|#Predicate" "$OUTPUT_DIR" -g "*.swift" || true
)"

if [[ -n "$remaining" ]]; then
  cat >&2 <<MSG
SwiftData lowering left unsupported syntax in the generated source:
$remaining
MSG
  exit 65
fi

swift_files="$(find "$OUTPUT_DIR" -name "*.swift" | wc -l | tr -d " ")"
cat <<MSG
Lowered $swift_files Swift files from:
  $SOURCE_DIR
to:
  $OUTPUT_DIR
MSG
