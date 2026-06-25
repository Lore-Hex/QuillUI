#!/usr/bin/env bash

quillui_vendored_source_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

quillui_vendored_app_source_dir() {
    local root_dir="$1"
    local name="$2"
    local source_dir="$root_dir/vendor/apps/$name"

    if [[ -d "$source_dir" ]]; then
        printf '%s\n' "$source_dir"
        return 0
    fi

    return 1
}

quillui_has_vendored_app_source() {
    local root_dir="$1"
    local name="$2"

    quillui_vendored_app_source_dir "$root_dir" "$name" >/dev/null
}

quillui_materialize_vendored_app_source() {
    local root_dir="$1"
    local name="$2"
    local dest="$3"
    local source_dir

    if quillui_vendored_source_truthy "${QUILLUI_REFRESH_VENDORED_SOURCE:-0}"; then
        return 1
    fi

    source_dir="$(quillui_vendored_app_source_dir "$root_dir" "$name")" || return 1

    case "$dest" in
        "$root_dir/.upstream"/*) ;;
        *)
            echo "error: refusing to materialize vendored $name outside .upstream: $dest" >&2
            return 2
            ;;
    esac

    echo "==> using vendored $name source at vendor/apps/$name"
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -a "$source_dir" "$dest"
}
