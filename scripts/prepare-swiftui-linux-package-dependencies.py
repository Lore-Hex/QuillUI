#!/usr/bin/env python3
"""Prepare local SwiftPM dependencies for generated QuillUI Linux app builds."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


PACKAGE_NAME_RE = re.compile(r"\.package\(\s*name:\s*\"([^\"]+)\"", re.DOTALL)
PACKAGE_PATH_RE = re.compile(r"\.package\([^)]*\bpath:\s*\"([^\"]+)\"", re.DOTALL)
PACKAGE_URL_RE = re.compile(r"\.package\([^)]*\burl:\s*\"([^\"]+)\"", re.DOTALL)
PACKAGE_CALL_RE = re.compile(r"\.package\s*\(")
PACKAGE_CALL_PATH_RE = re.compile(r"\bpath\s*:\s*\"([^\"]+)\"")
PACKAGE_CALL_URL_RE = re.compile(r"\burl\s*:\s*\"([^\"]+)\"")
MANIFEST_PATH_ARGUMENT_RE = re.compile(r"\bpath\s*:\s*\"([^\"]+)\"")
IMPORT_RE = re.compile(
    r"^\s*(?:(?:@testable|@_exported|@_implementationOnly)\s+)*(?:public\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)\b",
    re.MULTILINE,
)
SWIFT_IF_RE = re.compile(r"^\s*#\s*if\s+(.+?)\s*(?://.*)?$")
SWIFT_ELSEIF_RE = re.compile(r"^\s*#\s*elseif\s+(.+?)\s*(?://.*)?$")
SWIFT_ELSE_RE = re.compile(r"^\s*#\s*else\b")
SWIFT_ENDIF_RE = re.compile(r"^\s*#\s*endif\b")
TARGET_CALL_RE = re.compile(r"\.(?:target|executableTarget|testTarget|macro)\s*\(")
TARGET_NAME_RE = re.compile(r"\bname\s*:\s*\"([^\"]+)\"")
TOP_LEVEL_TARGETS_RE = re.compile(r"(?m)^([ \t]*)targets\s*:\s*\[")
TOP_LEVEL_DEPENDENCIES_RE = re.compile(r"(?m)^([ \t]*)dependencies\s*:\s*\[")
TOP_LEVEL_DEPENDENCIES_VARIABLE_RE = re.compile(r"(?m)^([ \t]*)dependencies\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\s*,")
SWIFT_TOOLS_VERSION_RE = re.compile(r"(?m)^// swift-tools-version:\s*([0-9]+(?:\.[0-9]+)?)\s*$")
QUILL_PREP_PRODUCTS = {
    "ActivityIndicatorView",
    "Alamofire",
    "AppKit",
    "ApplicationServices",
    "AsyncAlgorithms",
    "AVFoundation",
    "AVKit",
    "Carbon",
    "Cocoa",
    "Combine",
    "CoreGraphics",
    "CoreImage",
    "CoreSpotlight",
    "CoreText",
    "CoreTransferable",
    "CryptoKit",
    "ExtensionFoundation",
    "ExtensionKit",
    "IOKit",
    "KeyboardShortcuts",
    "Magnet",
    "MarkdownUI",
    "Network",
    "OllamaKit",
    "OSLog",
    "PhotosUI",
    "QuartzCore",
    "Security",
    "ServiceManagement",
    "Sparkle",
    "Splash",
    "SwiftData",
    "SwiftUI",
    "SwiftUIIntrospect",
    "UIKit",
    "UniformTypeIdentifiers",
    "UserNotifications",
    "Vortex",
    "WebKit",
    "WrappingHStack",
}

PREPARED_SWIFT_SETTINGS = [
    ".swiftLanguageMode(.v5)",
    '.unsafeFlags(["-strict-concurrency=minimal"])',
]

PREPARED_FINGERPRINT_FILE = ".quillui-prepared-fingerprint"
VENDORED_PACKAGE_ALIASES = {
    "aboutwindow": ["AboutWindow"],
    "anycodable": ["AnyCodable"],
    "codeeditkit": ["CodeEditKit"],
    "codeeditlanguages": ["CodeEditLanguages"],
    "codeeditsourceeditor": ["CodeEditSourceEditor"],
    "codeeditsymbols": ["CodeEditSymbols"],
    "codeedittextview": ["CodeEditTextView"],
    "collectionconcurrencykit": ["CollectionConcurrencyKit"],
    "concurrencyplus": ["ConcurrencyPlus"],
    "fseventswrapper": ["FSEventsWrapper"],
    "jsonrpc": ["JSONRPC"],
    "languageclient": ["LanguageClient"],
    "languageserverprotocol": ["LanguageServerProtocol"],
    "logstream": ["LogStream"],
    "processenv": ["ProcessEnv"],
    "queue": ["Queue"],
    "rearrange": ["Rearrange"],
    "semaphore": ["Semaphore"],
    "swift-async-algorithms": ["AsyncAlgorithms"],
    "swift-cmark": ["SwiftCMark"],
    "swift-markdown-ui": ["MarkdownUI"],
    "swift-snapshot-testing": ["SwiftSnapshotTesting"],
    "swiftlintplugin": ["SwiftLintPlugin"],
    "swiftterm": ["SwiftTerm"],
    "swifttreesitter": ["SwiftTreeSitter"],
    "swiftui-introspect": ["SwiftUIIntrospect"],
    "textformation": ["TextFormation"],
    "textstory": ["TextStory"],
    "vortex": ["Vortex"],
    "welcomewindow": ["WelcomeWindow"],
    "wrappinghstack": ["WrappingHStack"],
    "zipfoundation": ["ZIPFoundation"],
}
QUILL_PROVIDED_PACKAGE_IDENTITIES = {
    "activityindicatorview",
    "alamofire",
    "keyboardshortcuts",
    "magnet",
    "ollamakit",
    "sparkle",
    "splash",
    "swift-markdown-ui",
    "swiftui-introspect",
    "vortex",
    "wrappinghstack",
}


@dataclass(frozen=True)
class PackageLine:
    original: str
    package_name: str | None
    path: Path | None
    url: str | None


@dataclass(frozen=True)
class LocalPackageDependency:
    raw_reference: str
    package_dir: Path
    package_name: str | None
    is_url: bool


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rewrite generated SwiftPM package dependency lines so local packages "
            "that import Apple modules build against QuillUI's Linux shadow products."
        )
    )
    parser.add_argument("--root-dir", required=True, type=Path)
    parser.add_argument("--work-root", required=True, type=Path)
    parser.add_argument("--dependencies-in", required=True, type=Path)
    parser.add_argument("--dependencies-out", required=True, type=Path)
    parser.add_argument(
        "--skip-source-lowering",
        action="store_true",
        help="Patch manifests and copy packages, but do not run QuillUI source lowering.",
    )
    parser.add_argument(
        "--require-vendored-sources",
        action="store_true",
        help="Fail if any URL dependency cannot be rewritten to a local vendored source tree.",
    )
    parser.add_argument(
        "--prepared-cache-dir",
        type=Path,
        help=(
            "Optional shared directory for QuillUI-prepared local package copies. "
            "Defaults to WORK_ROOT/prepared-packages for hermetic one-off runs."
        ),
    )
    return parser.parse_args()


def swift_string(value: Path | str) -> str:
    return json.dumps(str(value))


def parse_package_line(line: str) -> PackageLine:
    package_match = PACKAGE_NAME_RE.search(line)
    path_match = PACKAGE_PATH_RE.search(line)
    url_match = PACKAGE_URL_RE.search(line)
    return PackageLine(
        original=line,
        package_name=package_match.group(1) if package_match else None,
        path=Path(path_match.group(1)).expanduser() if path_match else None,
        url=url_match.group(1) if url_match else None,
    )


def package_name_from_manifest(package_dir: Path) -> str | None:
    manifest = package_dir / "Package.swift"
    if not manifest.is_file():
        return None
    match = re.search(r"Package\s*\(\s*name:\s*\"([^\"]+)\"", manifest.read_text(encoding="utf-8", errors="ignore"))
    return match.group(1) if match else None


def dependency_line(package_name: str | None, package_dir: Path) -> str:
    if package_name:
        return f".package(name: {json.dumps(package_name)}, path: {swift_string(package_dir)})"
    return f".package(path: {swift_string(package_dir)})"


def package_identity_from_url(url: str) -> str:
    identity = url.split("?", 1)[0].split("#", 1)[0].rstrip("/").rsplit("/", 1)[-1]
    if identity.endswith(".git"):
        identity = identity[:-4]
    return identity


def dependency_package_name(parsed: PackageLine, package_dir: Path) -> str | None:
    if parsed.package_name:
        return parsed.package_name
    if parsed.url:
        identity = package_identity_from_url(parsed.url)
        if identity:
            return identity
    return package_name_from_manifest(package_dir)


def is_quill_provided_package(parsed: PackageLine) -> bool:
    names: list[str] = []
    if parsed.url:
        names.append(package_identity_from_url(parsed.url))
    if parsed.package_name:
        names.append(parsed.package_name)
    return any(normalized_package_component(name) in QUILL_PROVIDED_PACKAGE_IDENTITIES for name in names)


def normalized_package_component(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def unique_strings(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def local_candidate_for_url(root_dir: Path, url: str, package_name: str | None) -> Path | None:
    identity = package_identity_from_url(url)
    identity_key = identity.lower()
    identities = [identity, identity_key]
    identities.extend(VENDORED_PACKAGE_ALIASES.get(identity_key, []))
    if package_name:
        identities.append(package_name)
        identities.extend(VENDORED_PACKAGE_ALIASES.get(package_name.lower(), []))
    identities = unique_strings(identities)

    candidates: list[Path] = []
    for base in ("third_party", ".upstream", "vendor/apps"):
        for item in identities:
            candidates.append(root_dir / base / item)

    for candidate in candidates:
        if (candidate / "Package.swift").is_file():
            return candidate.resolve()

    normalized_identities = {normalized_package_component(item) for item in identities}
    for base in ("third_party", ".upstream", "vendor/apps"):
        directory = root_dir / base
        if not directory.is_dir():
            continue
        for child in directory.iterdir():
            if not child.is_dir():
                continue
            if normalized_package_component(child.name) in normalized_identities and (child / "Package.swift").is_file():
                return child.resolve()
    return None


def root_declared_package_paths(root_dir: Path) -> set[Path]:
    manifest_path = root_dir / "Package.swift"
    if not manifest_path.is_file():
        return set()
    manifest = manifest_path.read_text(encoding="utf-8", errors="ignore")
    paths: set[Path] = set()
    for match in MANIFEST_PATH_ARGUMENT_RE.finditer(manifest):
        candidate = (root_dir / match.group(1)).resolve()
        if (candidate / "Package.swift").is_file():
            paths.add(candidate)
    return paths


def dump_package(package_dir: Path) -> dict:
    module_cache = Path(os.environ.get("TMPDIR", "/tmp")) / "quillui-swiftpm-module-cache"
    module_cache.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["CLANG_MODULE_CACHE_PATH"] = str(module_cache)
    try:
        output = subprocess.check_output(
            ["swift", "package", "dump-package", "--disable-sandbox", "--package-path", str(package_dir)],
            text=True,
            stderr=subprocess.PIPE,
            env=env,
        )
    except (OSError, subprocess.CalledProcessError):
        return {}
    return json.loads(output)


def target_source_dir(package_dir: Path, target: dict) -> Path:
    explicit_path = target.get("path")
    if explicit_path:
        return (package_dir / explicit_path).resolve()
    if target.get("type") == "test":
        return (package_dir / "Tests" / target["name"]).resolve()
    return (package_dir / "Sources" / target["name"]).resolve()


def swift_imports(source_dir: Path) -> set[str]:
    imports: set[str] = set()
    if not source_dir.exists():
        return imports
    for source_file in source_dir.rglob("*.swift"):
        conditional_stack: list[dict[str, bool | str]] = []
        for line in source_file.read_text(encoding="utf-8", errors="ignore").splitlines():
            if_match = SWIFT_IF_RE.match(line)
            if if_match:
                condition = swift_literal_condition(if_match.group(1))
                if condition is None:
                    conditional_stack.append({"mode": "unknown", "active": True, "taken": False})
                else:
                    conditional_stack.append({"mode": "known", "active": condition, "taken": condition})
                continue

            elseif_match = SWIFT_ELSEIF_RE.match(line)
            if elseif_match and conditional_stack:
                frame = conditional_stack[-1]
                if frame["mode"] == "unknown":
                    frame["active"] = True
                    continue
                if bool(frame["taken"]):
                    frame["active"] = False
                    continue
                condition = swift_literal_condition(elseif_match.group(1))
                is_active = condition is not False
                frame["active"] = is_active
                frame["taken"] = is_active
                if condition is None:
                    frame["mode"] = "unknown"
                continue

            if SWIFT_ELSE_RE.match(line) and conditional_stack:
                frame = conditional_stack[-1]
                if frame["mode"] == "unknown":
                    frame["active"] = True
                else:
                    frame["active"] = not bool(frame["taken"])
                    frame["taken"] = True
                continue

            if SWIFT_ENDIF_RE.match(line):
                if conditional_stack:
                    conditional_stack.pop()
                continue

            if not all(bool(frame["active"]) for frame in conditional_stack):
                continue
            imports.update(IMPORT_RE.findall(line))
    return imports


def swift_literal_condition(expression: str) -> bool | None:
    cleaned = expression.split("//", 1)[0].strip()
    if cleaned == "false":
        return False
    if cleaned == "true":
        return True
    if cleaned == "os(Linux)":
        return True
    if re.fullmatch(r"os\((iOS|tvOS|watchOS|visionOS|macCatalyst|Android|Windows)\)", cleaned):
        return False
    return None


def quill_imports_by_target(package_dir: Path) -> dict[str, set[str]]:
    package = dump_package(package_dir)
    result: dict[str, set[str]] = {}
    for target in package.get("targets", []):
        target_name = target.get("name")
        if not target_name or target.get("type") == "test":
            continue
        imports = swift_imports(target_source_dir(package_dir, target)) & QUILL_PREP_PRODUCTS
        if imports:
            result[target_name] = imports
    return result


def source_dirs_for_targets(package_dir: Path, target_names: set[str]) -> list[Path]:
    package = dump_package(package_dir)
    source_dirs: list[Path] = []
    for target in package.get("targets", []):
        target_name = target.get("name")
        if target_name in target_names:
            source_dirs.append(target_source_dir(package_dir, target))
    return source_dirs


def package_requires_quill_preparation(package_dir: Path) -> bool:
    return bool(quill_imports_by_target(package_dir))


def package_dependency_graph_requires_preparation(
    root_dir: Path,
    package_dir: Path,
    materialized: dict[Path, Path],
    seen: set[Path] | None = None,
) -> bool:
    if seen is None:
        seen = set()
    package_dir = package_dir.resolve()
    if package_dir in seen:
        return False
    seen.add(package_dir)

    for dependency in local_package_dependencies(root_dir, package_dir):
        dependency_dir = dependency.package_dir.resolve()
        if dependency_dir in materialized:
            return True
        if package_requires_quill_preparation(dependency_dir):
            return True
        if package_dependency_graph_requires_preparation(root_dir, dependency_dir, materialized, seen):
            return True
    return False


def sanitize_path_component(value: str) -> str:
    sanitized = re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip(".-")
    return sanitized or "Package"


def prepared_package_directory(
    work_root: Path,
    prepared_cache_dir: Path | None,
    safe_name: str,
    package_dir: Path,
    fingerprint: str,
) -> Path:
    if prepared_cache_dir is None:
        return work_root / "prepared-packages" / safe_name
    source_key = hashlib.sha256(str(package_dir.resolve()).encode("utf-8")).hexdigest()[:12]
    return prepared_cache_dir.resolve() / f"{safe_name}-{source_key}-{fingerprint[:16]}"


def ensure_user_writable_tree(path: Path) -> None:
    paths = [path]
    if path.is_dir():
        paths.extend(path.rglob("*"))
    for item in paths:
        if item.is_symlink():
            continue
        try:
            item.chmod(item.stat().st_mode | stat.S_IWUSR)
        except OSError:
            pass


def update_digest_with_file_contents(digest: "hashlib._Hash", path: Path, root: Path) -> None:
    try:
        relative = path.resolve().relative_to(root.resolve())
    except ValueError:
        relative = path.resolve()
    try:
        content = path.read_bytes()
    except OSError:
        return
    digest.update(str(relative).encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(len(content)).encode("utf-8"))
    digest.update(b":")
    digest.update(content)
    digest.update(b"\0")


def update_digest_with_tool_input(digest: "hashlib._Hash", path: Path, root_dir: Path) -> None:
    if path.is_file():
        update_digest_with_file_contents(digest, path, root_dir)
        return
    if not path.is_dir():
        return

    excluded_dirs = {".build", ".git", ".swiftpm", ".quillui-build"}
    for item in sorted(path.rglob("*")):
        try:
            relative = item.relative_to(path)
        except ValueError:
            continue
        if any(part in excluded_dirs for part in relative.parts):
            continue
        if item.is_file():
            update_digest_with_file_contents(digest, item, root_dir)


def package_preparation_fingerprint(root_dir: Path, package_dir: Path, skip_source_lowering: bool) -> str:
    digest = hashlib.sha256()
    digest.update(str(root_dir.resolve()).encode("utf-8"))
    digest.update(b"\0skip-source-lowering=" + str(skip_source_lowering).encode("utf-8"))

    excluded_dirs = {".build", ".git", ".swiftpm", ".quillui-build"}
    for path in sorted(package_dir.rglob("*")):
        try:
            relative = path.relative_to(package_dir)
        except ValueError:
            continue
        if any(part in excluded_dirs for part in relative.parts):
            continue
        if not path.is_file():
            continue
        update_digest_with_file_contents(digest, path, package_dir)

    tool_inputs = [
        Path(__file__),
        root_dir / "scripts/lower-swiftui-source-for-linux.sh",
        root_dir / "scripts/lower-observable-for-swiftopenui.py",
        root_dir / "scripts/ensure-swift-imports.sh",
        root_dir / "scripts/run-quill-source-lower.sh",
        root_dir / "scripts/run-quill-swiftui-lower.sh",
        root_dir / "scripts/run-quill-appkit-lower.sh",
        root_dir / "scripts/lower-mainactor-assignments-for-linux.py",
        root_dir / "scripts/lower-linux-conditional-compilation.py",
        root_dir / "scripts/lower-extension-overrides-for-linux.py",
        root_dir / "scripts/lower-objc-interop-for-linux.sh",
        root_dir / "Sources/QuillSourceLowering",
    ]
    for path in tool_inputs:
        update_digest_with_tool_input(digest, path, root_dir)

    return digest.hexdigest()


def find_matching(text: str, open_index: int, open_ch: str, close_ch: str) -> int:
    depth = 0
    in_string = False
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = open_index
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
        elif in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == "\"":
                in_string = False
        elif ch == "/" and nxt == "/":
            in_line_comment = True
            i += 1
        elif ch == "/" and nxt == "*":
            in_block_comment = True
            i += 1
        elif ch == "\"":
            in_string = True
        elif ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError(f"unmatched {open_ch}")


def line_indent(text: str, index: int) -> str:
    line_start = text.rfind("\n", 0, index) + 1
    match = re.match(r"[ \t]*", text[line_start:index])
    return match.group(0) if match else ""


def product_entries(products: set[str]) -> list[str]:
    return [f'.product(name: "{name}", package: "QuillUI")' for name in sorted(products)]


def strip_line_comments(text: str) -> str:
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def patch_dependency_array(block: str, products: set[str]) -> str:
    entries = [entry for entry in product_entries(products) if entry not in block]
    if not entries:
        return block

    dependency_match = re.search(r"\bdependencies\s*:\s*\[", block)
    if dependency_match:
        open_index = block.find("[", dependency_match.start())
        close_index = find_matching(block, open_index, "[", "]")
        dependency_indent = line_indent(block, dependency_match.start())
        entry_indent = dependency_indent + "    "
        existing = block[open_index + 1 : close_index].strip()
        if not existing:
            replacement = "[\n" + "".join(f"{entry_indent}{entry},\n" for entry in entries) + f"{dependency_indent}]"
            return block[:open_index] + replacement + block[close_index + 1 :]

        insertion = "".join(f"\n{entry_indent}{entry}," for entry in entries)
        existing_syntax = strip_line_comments(existing).rstrip()
        if existing_syntax and not existing_syntax.endswith((",", "[")):
            insertion = "," + insertion
        return block[:close_index] + insertion + "\n" + dependency_indent + block[close_index:]

    name_match = TARGET_NAME_RE.search(block)
    if not name_match:
        return block
    dependency_indent = line_indent(block, name_match.start())
    entry_indent = dependency_indent + "    "
    dependency_block = (
        f"\n{dependency_indent}dependencies: [\n"
        + "".join(f"{entry_indent}{entry},\n" for entry in entries)
        + f"{dependency_indent}],"
    )
    suffix = block[name_match.end() :]
    if suffix.lstrip().startswith(","):
        comma_index = block.find(",", name_match.end())
        return block[: comma_index + 1] + dependency_block + block[comma_index + 1 :]
    return block[: name_match.end()] + "," + dependency_block + block[name_match.end() :]


def patch_target_swift_settings(block: str) -> str:
    entries = [entry for entry in PREPARED_SWIFT_SETTINGS if entry not in block]
    if not entries:
        return block

    settings_match = re.search(r"\bswiftSettings\s*:\s*\[", block)
    if settings_match:
        open_index = block.find("[", settings_match.start())
        close_index = find_matching(block, open_index, "[", "]")
        settings_indent = line_indent(block, settings_match.start())
        entry_indent = settings_indent + "    "
        existing = block[open_index + 1 : close_index].strip()
        insertion = "".join(f"\n{entry_indent}{entry}," for entry in entries)
        existing_syntax = strip_line_comments(existing).rstrip()
        if existing_syntax and not existing_syntax.endswith((",", "[")):
            insertion = "," + insertion
        return block[:close_index] + insertion + "\n" + settings_indent + block[close_index:]

    if re.search(r"\bswiftSettings\s*:", block):
        return block

    close_index = block.rfind(")")
    if close_index < 0:
        return block
    close_indent = line_indent(block, close_index)
    settings_indent = close_indent + "    "
    entry_indent = settings_indent + "    "
    prefix = "" if block[:close_index].rstrip().endswith(",") else ","
    settings_block = (
        f"{prefix}\n{settings_indent}swiftSettings: [\n"
        + "".join(f"{entry_indent}{entry},\n" for entry in entries)
        + f"{settings_indent}]\n{close_indent}"
    )
    return block[:close_index] + settings_block + block[close_index:]


def patch_target_dependencies(manifest: str, target_products: dict[str, set[str]]) -> str:
    replacements: list[tuple[int, int, str]] = []
    for match in TARGET_CALL_RE.finditer(manifest):
        open_index = manifest.find("(", match.start())
        try:
            close_index = find_matching(manifest, open_index, "(", ")")
        except ValueError:
            continue
        block = manifest[match.start() : close_index + 1]
        name_match = TARGET_NAME_RE.search(block)
        if not name_match:
            continue
        target_name = name_match.group(1)
        products = target_products.get(target_name)
        if not products:
            continue
        patched_block = patch_dependency_array(block, products)
        patched_block = patch_target_swift_settings(patched_block)
        replacements.append((match.start(), close_index + 1, patched_block))

    patched = manifest
    for start, end, replacement in reversed(replacements):
        patched = patched[:start] + replacement + patched[end:]
    return patched


def patch_manifest_tools_version(manifest: str) -> str:
    match = SWIFT_TOOLS_VERSION_RE.search(manifest)
    if match is None:
        return "// swift-tools-version: 6.0\n" + manifest
    version_parts = tuple(int(part) for part in match.group(1).split("."))
    if version_parts >= (6, 0):
        return manifest
    return manifest[: match.start()] + "// swift-tools-version: 6.0" + manifest[match.end() :]


def insert_quill_package_dependency(manifest: str, root_dir: Path) -> str:
    if '.package(name: "QuillUI"' in manifest:
        return manifest

    entry = f'.package(name: "QuillUI", path: {swift_string(root_dir)})'
    targets_match = shallowest_package_argument_match(TOP_LEVEL_TARGETS_RE, manifest)
    dependencies_match = None
    for match in TOP_LEVEL_DEPENDENCIES_RE.finditer(manifest):
        if targets_match is None or (
            match.start() < targets_match.start()
            and len(match.group(1)) == len(targets_match.group(1))
        ):
            dependencies_match = match
            break

    if dependencies_match:
        open_index = manifest.find("[", dependencies_match.start())
        close_index = find_matching(manifest, open_index, "[", "]")
        dependency_indent = dependencies_match.group(1)
        entry_indent = dependency_indent + "    "
        existing = manifest[open_index + 1 : close_index].strip()
        if not existing:
            replacement = f"[\n{entry_indent}{entry}\n{dependency_indent}]"
            return manifest[:open_index] + replacement + manifest[close_index + 1 :]
        return manifest[: open_index + 1] + f"\n{entry_indent}{entry}," + manifest[open_index + 1 :]

    for match in TOP_LEVEL_DEPENDENCIES_VARIABLE_RE.finditer(manifest):
        if targets_match is not None and (
            match.start() > targets_match.start()
            or len(match.group(1)) != len(targets_match.group(1))
        ):
            continue
        variable_name = match.group(2)
        variable_match = re.search(
            rf"(?m)^([ \t]*)var\s+{re.escape(variable_name)}\s*:[^\n=]+=\s*\[\]\s*$",
            manifest,
        )
        if variable_match is None:
            break
        append_line = f"\n{variable_match.group(1)}{variable_name}.append({entry})"
        return manifest[: variable_match.end()] + append_line + manifest[variable_match.end() :]

    if targets_match is None:
        return manifest
    dependency_indent = targets_match.group(1)
    dependency_block = f'{dependency_indent}dependencies: [\n{dependency_indent}    {entry}\n{dependency_indent}],\n'
    return manifest[: targets_match.start()] + dependency_block + manifest[targets_match.start() :]


def shallowest_package_argument_match(pattern: re.Pattern[str], manifest: str) -> re.Match[str] | None:
    matches = list(pattern.finditer(manifest))
    if not matches:
        return None
    return min(matches, key=lambda match: (len(match.group(1)), match.start()))


def patch_manifest(package_dir: Path, root_dir: Path, imported_products: dict[str, set[str]]) -> None:
    manifest_path = package_dir / "Package.swift"
    manifest = manifest_path.read_text(encoding="utf-8")
    manifest = patch_manifest_tools_version(manifest)
    manifest = insert_quill_package_dependency(manifest, root_dir)
    manifest = patch_target_dependencies(manifest, imported_products)
    manifest_path.write_text(manifest, encoding="utf-8")


def package_call_blocks(manifest: str) -> list[tuple[int, int, str]]:
    blocks: list[tuple[int, int, str]] = []
    for match in PACKAGE_CALL_RE.finditer(manifest):
        open_index = manifest.find("(", match.start())
        try:
            close_index = find_matching(manifest, open_index, "(", ")")
        except ValueError:
            continue
        blocks.append((match.start(), close_index + 1, manifest[match.start() : close_index + 1]))
    return blocks


def local_package_dependencies(root_dir: Path, package_dir: Path) -> list[LocalPackageDependency]:
    manifest_path = package_dir / "Package.swift"
    if not manifest_path.is_file():
        return []

    dependencies: list[LocalPackageDependency] = []
    manifest = manifest_path.read_text(encoding="utf-8", errors="ignore")
    for _, _, block in package_call_blocks(manifest):
        package_match = PACKAGE_NAME_RE.search(block)
        package_name = package_match.group(1) if package_match else None

        path_match = PACKAGE_CALL_PATH_RE.search(block)
        if path_match is not None:
            raw_path = path_match.group(1)
            dependency_dir = Path(raw_path).expanduser()
            if not dependency_dir.is_absolute():
                dependency_dir = package_dir / dependency_dir
            dependency_dir = dependency_dir.resolve()
            if (dependency_dir / "Package.swift").is_file():
                dependencies.append(
                    LocalPackageDependency(
                        raw_reference=raw_path,
                        package_dir=dependency_dir,
                        package_name=package_name,
                        is_url=False,
                    )
                )
            continue

        url_match = PACKAGE_CALL_URL_RE.search(block)
        if url_match is None:
            continue
        url = url_match.group(1)
        url_package_name = package_name or package_identity_from_url(url)
        dependency_dir = local_candidate_for_url(root_dir, url, url_package_name)
        if dependency_dir is not None:
            dependencies.append(
                LocalPackageDependency(
                    raw_reference=url,
                    package_dir=dependency_dir,
                    package_name=url_package_name,
                    is_url=True,
                )
            )
    return dependencies


def rewrite_package_dependency_calls(
    manifest: str,
    path_replacements: dict[str, tuple[Path, str | None]],
    url_replacements: dict[str, tuple[Path, str | None]],
) -> str:
    rewritten = manifest
    for start, end, block in reversed(package_call_blocks(manifest)):
        path_match = PACKAGE_CALL_PATH_RE.search(block)
        if path_match is not None:
            raw_path = path_match.group(1)
            replacement = path_replacements.get(raw_path)
            if replacement is None:
                continue
            replacement_path, package_name = replacement
            rewritten = rewritten[:start] + dependency_line(package_name, replacement_path) + rewritten[end:]
            continue

        url_match = PACKAGE_CALL_URL_RE.search(block)
        if url_match is None:
            continue
        raw_url = url_match.group(1)
        replacement = url_replacements.get(raw_url)
        if replacement is None:
            continue
        replacement_path, package_name = replacement
        rewritten = rewritten[:start] + dependency_line(package_name, replacement_path) + rewritten[end:]
    return rewritten


def normalize_local_package_dependencies(
    root_dir: Path,
    work_root: Path,
    prepared_cache_dir: Path | None,
    source_package_dir: Path,
    prepared_package_dir: Path,
    skip_source_lowering: bool,
    materialized: dict[Path, Path],
    in_progress: set[Path],
    root_package_paths: set[Path],
) -> None:
    path_replacements: dict[str, tuple[Path, str | None]] = {}
    url_replacements: dict[str, tuple[Path, str | None]] = {}
    for dependency in local_package_dependencies(root_dir, source_package_dir):
        package_name = dependency.package_name or package_name_from_manifest(dependency.package_dir)
        if (
            dependency.package_dir in root_package_paths
            and not package_requires_quill_preparation(dependency.package_dir)
            and not package_dependency_graph_requires_preparation(root_dir, dependency.package_dir, materialized)
        ):
            replacement = dependency.package_dir
        else:
            prepared_dependency = prepare_package(
                root_dir,
                work_root,
                prepared_cache_dir,
                dependency.package_dir,
                package_name,
                skip_source_lowering,
                materialized,
                in_progress,
                root_package_paths,
                force=True,
            )
            if prepared_dependency is not None:
                replacement = prepared_dependency
            else:
                continue

        if dependency.is_url:
            url_replacements[dependency.raw_reference] = (replacement, package_name)
        else:
            path_replacements[dependency.raw_reference] = (replacement, package_name)

    if not path_replacements and not url_replacements:
        return

    manifest_path = prepared_package_dir / "Package.swift"
    manifest = manifest_path.read_text(encoding="utf-8")
    manifest_path.write_text(
        rewrite_package_dependency_calls(manifest, path_replacements, url_replacements),
        encoding="utf-8",
    )


def record_reused_prepared_dependency_graph(
    root_dir: Path,
    source_package_dir: Path,
    prepared_package_dir: Path,
    materialized: dict[Path, Path],
    seen: set[Path] | None = None,
) -> None:
    if seen is None:
        seen = set()

    source_package_dir = source_package_dir.resolve()
    prepared_package_dir = prepared_package_dir.resolve()
    if source_package_dir in seen:
        return
    seen.add(source_package_dir)

    prepared_dependencies: dict[str, Path] = {}
    for dependency in local_package_dependencies(root_dir, prepared_package_dir):
        package_name = dependency.package_name or package_name_from_manifest(dependency.package_dir)
        if package_name:
            prepared_dependencies[normalized_package_component(package_name)] = dependency.package_dir.resolve()

    if not prepared_dependencies:
        return

    for dependency in local_package_dependencies(root_dir, source_package_dir):
        package_name = dependency.package_name or package_name_from_manifest(dependency.package_dir)
        if not package_name:
            continue
        prepared_dependency = prepared_dependencies.get(normalized_package_component(package_name))
        if prepared_dependency is None:
            continue
        source_dependency = dependency.package_dir.resolve()
        if prepared_dependency == source_dependency:
            continue
        if (prepared_dependency / "Package.swift").is_file():
            materialized[source_dependency] = prepared_dependency
            record_reused_prepared_dependency_graph(
                root_dir,
                source_dependency,
                prepared_dependency,
                materialized,
                seen,
            )


def prepare_package(
    root_dir: Path,
    work_root: Path,
    prepared_cache_dir: Path | None,
    package_dir: Path,
    package_name: str | None,
    skip_source_lowering: bool,
    materialized: dict[Path, Path],
    in_progress: set[Path],
    root_package_paths: set[Path],
    force: bool = False,
) -> Path | None:
    package_dir = package_dir.resolve()
    if package_dir in materialized:
        return materialized[package_dir]

    imports = quill_imports_by_target(package_dir)
    dependency_graph_requires_preparation = package_dependency_graph_requires_preparation(root_dir, package_dir, materialized)
    if package_dir in root_package_paths and not imports and not force and not dependency_graph_requires_preparation:
        return None
    if not imports and not force and not dependency_graph_requires_preparation:
        return None

    safe_name = sanitize_path_component(package_name or package_name_from_manifest(package_dir) or package_dir.name)
    fingerprint = package_preparation_fingerprint(root_dir, package_dir, skip_source_lowering)
    prepared_dir = prepared_package_directory(work_root, prepared_cache_dir, safe_name, package_dir, fingerprint)
    fingerprint_path = prepared_dir / PREPARED_FINGERPRINT_FILE
    if prepared_dir.exists() and fingerprint_path.is_file():
        try:
            if fingerprint_path.read_text(encoding="utf-8").strip() == fingerprint:
                materialized[package_dir] = prepared_dir
                record_reused_prepared_dependency_graph(root_dir, package_dir, prepared_dir, materialized)
                print(f"reused prepared local SwiftPM dependency for QuillUI Linux build: {package_dir} -> {prepared_dir}", file=sys.stderr)
                return prepared_dir
        except OSError:
            pass
    if prepared_dir.exists():
        shutil.rmtree(prepared_dir)
    prepared_dir.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(package_dir, prepared_dir, symlinks=True)
    ensure_user_writable_tree(prepared_dir)
    materialized[package_dir] = prepared_dir

    if package_dir in in_progress:
        return prepared_dir
    in_progress.add(package_dir)

    target_products = {name: set(products) | {"QuillShims"} for name, products in imports.items()}

    if not skip_source_lowering:
        for source_dir in source_dirs_for_targets(prepared_dir, set(imports)):
            if source_dir.is_dir():
                subprocess.run(
                    [str(root_dir / "scripts/lower-swiftui-source-for-linux.sh"), str(source_dir)],
                    check=True,
                )

    normalize_local_package_dependencies(
        root_dir,
        work_root,
        prepared_cache_dir,
        package_dir,
        prepared_dir,
        skip_source_lowering,
        materialized,
        in_progress,
        root_package_paths,
    )
    if imports:
        patch_manifest(prepared_dir, root_dir, target_products)
    in_progress.remove(package_dir)
    fingerprint_path.write_text(fingerprint + "\n", encoding="utf-8")
    print(f"prepared local SwiftPM dependency for QuillUI Linux build: {package_dir} -> {prepared_dir}", file=sys.stderr)
    return prepared_dir


def resolved_package_dir(root_dir: Path, parsed: PackageLine) -> Path | None:
    package_dir = parsed.path.resolve() if parsed.path else None
    if package_dir is None and parsed.url:
        package_dir = local_candidate_for_url(root_dir, parsed.url, parsed.package_name)
    if package_dir is None or not (package_dir / "Package.swift").is_file():
        return None
    return package_dir.resolve()


def rewritten_line(
    root_dir: Path,
    work_root: Path,
    line: str,
    skip_source_lowering: bool,
    materialized: dict[Path, Path],
) -> str:
    parsed = parse_package_line(line)
    package_dir = resolved_package_dir(root_dir, parsed)
    if package_dir is None or not (package_dir / "Package.swift").is_file():
        return parsed.original

    package_name = dependency_package_name(parsed, package_dir)
    prepared_dir = materialized.get(package_dir)
    if prepared_dir is not None:
        return dependency_line(package_name, prepared_dir)
    if parsed.url:
        return dependency_line(package_name, package_dir)
    return parsed.original


def main() -> int:
    args = parse_args()
    root_dir = args.root_dir.resolve()
    work_root = args.work_root.resolve()
    prepared_cache_dir = args.prepared_cache_dir.resolve() if args.prepared_cache_dir else None
    require_vendored_sources = (
        args.require_vendored_sources
        or os.environ.get("QUILLUI_REQUIRE_VENDORED_SOURCES", "").lower() in {"1", "true", "yes"}
    )
    input_lines = args.dependencies_in.read_text(encoding="utf-8").splitlines()
    stripped_lines: list[str] = []
    materialized: dict[Path, Path] = {}
    in_progress: set[Path] = set()
    root_package_paths = root_declared_package_paths(root_dir)
    unresolved_remote_dependencies: list[str] = []

    for line in input_lines:
        stripped = line.split("#", 1)[0].strip()
        if not stripped:
            continue
        stripped_lines.append(stripped)
        parsed = parse_package_line(stripped)
        if is_quill_provided_package(parsed):
            continue
        package_dir = resolved_package_dir(root_dir, parsed)
        if package_dir is None:
            if require_vendored_sources and parsed.url:
                unresolved_remote_dependencies.append(parsed.original)
            continue
        prepare_package(
            root_dir,
            work_root,
            prepared_cache_dir,
            package_dir,
            dependency_package_name(parsed, package_dir),
            args.skip_source_lowering,
            materialized,
            in_progress,
            root_package_paths,
        )

    while True:
        prepared_count = len(materialized)
        for stripped in stripped_lines:
            parsed = parse_package_line(stripped)
            if is_quill_provided_package(parsed):
                continue
            package_dir = resolved_package_dir(root_dir, parsed)
            if package_dir is None or package_dir in materialized:
                continue
            prepare_package(
                root_dir,
                work_root,
                prepared_cache_dir,
                package_dir,
                dependency_package_name(parsed, package_dir),
                args.skip_source_lowering,
                materialized,
                in_progress,
                root_package_paths,
            )
        if len(materialized) == prepared_count:
            break

    output_lines: list[str] = []
    seen_output_lines: set[str] = set()
    for stripped in stripped_lines:
        if is_quill_provided_package(parse_package_line(stripped)):
            continue
        rewritten = rewritten_line(root_dir, work_root, stripped, args.skip_source_lowering, materialized)
        if require_vendored_sources and PACKAGE_URL_RE.search(rewritten):
            unresolved_remote_dependencies.append(rewritten)
        if rewritten in seen_output_lines:
            continue
        seen_output_lines.add(rewritten)
        output_lines.append(rewritten)
    if unresolved_remote_dependencies:
        print(
            "error: SwiftPM URL dependencies remain after vendored-source preparation. "
            "Run scripts/vendor-swiftpm-sources.sh --package-resolved <Package.resolved> "
            "or add the package under third_party/.",
            file=sys.stderr,
        )
        for dependency in dict.fromkeys(unresolved_remote_dependencies):
            print(f"  {dependency}", file=sys.stderr)
        return 66
    args.dependencies_out.parent.mkdir(parents=True, exist_ok=True)
    args.dependencies_out.write_text("".join(f"{line}\n" for line in output_lines), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
