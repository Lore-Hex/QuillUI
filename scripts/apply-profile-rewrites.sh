#!/usr/bin/env bash
set -euo pipefail

if (( $# != 2 )); then
  cat >&2 <<'MSG'
Usage: scripts/apply-profile-rewrites.sh SOURCE_DIR RULE_DIR

Applies profile-owned Perl rewrite rules to a lowered Swift source tree.
`__all__.pl` is applied to every Swift file. Other `*.swift.pl` files preserve
their relative path under RULE_DIR and apply only to the matching source file.
Missing source files are skipped so profiles can share optional rules.
MSG
  exit 64
fi

SOURCE_DIR="$1"
RULE_DIR="$2"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory was not found: $SOURCE_DIR" >&2
  exit 66
fi

if [[ ! -d "$RULE_DIR" ]]; then
  exit 0
fi

all_rule="$RULE_DIR/__all__.pl"
if [[ -f "$all_rule" ]]; then
  find "$SOURCE_DIR" -name '*.swift' -print0 |
    while IFS= read -r -d '' swift_file; do
      perl -0pi "$all_rule" "$swift_file"
    done
fi

rule_root="$(cd "$RULE_DIR" && pwd)"

find "$rule_root" -type f -name '*.swift.pl' -print0 |
  while IFS= read -r -d '' rule_file; do
    relative_file="${rule_file#"$rule_root"/}"
    source_file="$SOURCE_DIR/${relative_file%.pl}"
    [[ -f "$source_file" ]] || continue
    perl -0pi "$rule_file" "$source_file"
  done
