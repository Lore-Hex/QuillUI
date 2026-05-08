#!/usr/bin/env bash
set -euo pipefail

if (( $# < 3 )); then
  cat >&2 <<'MSG'
Usage: scripts/ensure-swift-imports.sh SOURCE_DIR ModuleName Relative/File.swift [...]

Adds `import ModuleName` to each existing Swift file. Missing files are skipped,
which lets app profiles share import declarations across optional source paths.
MSG
  exit 64
fi

SOURCE_DIR="$1"
IMPORT_MODULE="$2"
shift 2

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory was not found: $SOURCE_DIR" >&2
  exit 66
fi

if [[ ! "$IMPORT_MODULE" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Invalid Swift module import name: $IMPORT_MODULE" >&2
  exit 65
fi

for relative_file in "$@"; do
  file="$SOURCE_DIR/$relative_file"
  [[ -f "$file" ]] || continue

  QUILLUI_IMPORT_MODULE="$IMPORT_MODULE" perl -0pi -e '
    my $module = $ENV{"QUILLUI_IMPORT_MODULE"};
    if ($_ =~ /^import\s+\Q$module\E(?:\s|$)/m) {
      next;
    }

    my @lines = split(/\n/, $_, -1);
    my $insert_index = -1;
    for my $index (0 .. $#lines) {
      if ($lines[$index] =~ /^import\s+[A-Za-z_][A-Za-z0-9_.]*(?:\s|$)/) {
        $insert_index = $index + 1;
        next;
      }

      if ($insert_index >= 0 && $lines[$index] !~ /^\s*$/) {
        last;
      }
    }

    if ($insert_index >= 0) {
      splice(@lines, $insert_index, 0, "import $module");
      $_ = join("\n", @lines);
    } else {
      $_ = "import $module\n" . $_;
    }
  ' "$file"
done
