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

quillui_vendored_app_source_fingerprint_file() {
    local root_dir="$1"
    local name="$2"
    local source_dir="$root_dir/vendor/apps/$name"

    if [[ -f "$source_dir/.quillui-vendor-source-fingerprint" ]]; then
        printf '%s\n' "$source_dir/.quillui-vendor-source-fingerprint"
        return 0
    fi

    return 1
}

quillui_print_vendored_app_source_summary() {
    local root_dir="$1"
    local name="$2"
    local fingerprint_file=""
    local source_identity=""

    if fingerprint_file="$(quillui_vendored_app_source_fingerprint_file "$root_dir" "$name")"; then
        source_identity="$(awk -F= '$1 == "source" { print $2; exit }' "$fingerprint_file" 2>/dev/null || true)"
        if [[ -n "$source_identity" ]]; then
            printf '==> vendored %s source snapshot: %s\n' "$name" "$source_identity"
            return 0
        fi
    fi

    printf '==> vendored %s source snapshot: unmarked legacy copy\n' "$name"
}

quillui_upstream_app_source_dir() {
    local root_dir="$1"
    local name="$2"
    local source_dir="$root_dir/.upstream/$name"

    if [[ -d "$source_dir" ]]; then
        printf '%s\n' "$source_dir"
        return 0
    fi

    return 1
}

quillui_resolve_app_checkout_dir() {
    local root_dir="$1"
    local name="$2"
    local source_dir

    if ! quillui_vendored_source_truthy "${QUILLUI_REFRESH_VENDORED_SOURCE:-0}"; then
        if source_dir="$(quillui_vendored_app_source_dir "$root_dir" "$name")"; then
            printf '%s\n' "$source_dir"
            return 0
        fi
    fi

    if source_dir="$(quillui_upstream_app_source_dir "$root_dir" "$name")"; then
        printf '%s\n' "$source_dir"
        return 0
    fi

    quillui_vendored_app_source_dir "$root_dir" "$name"
}

quillui_resolve_app_source_dir() {
    local root_dir="$1"
    local name="$2"
    local subdir="${3:-}"
    local checkout_dir

    checkout_dir="$(quillui_resolve_app_checkout_dir "$root_dir" "$name")" || return 1
    if [[ -n "$subdir" ]]; then
        printf '%s/%s\n' "$checkout_dir" "$subdir"
        return 0
    fi

    printf '%s\n' "$checkout_dir"
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

    mkdir -p "$(dirname "$dest")"
    if command -v rsync >/dev/null 2>&1; then
        echo "==> syncing vendored $name source from vendor/apps/$name"
        mkdir -p "$dest"
        rsync -a --delete "$source_dir"/ "$dest"/
    else
        echo "==> using vendored $name source at vendor/apps/$name"
        rm -rf "$dest"
        cp -a "$source_dir" "$dest"
    fi
}
