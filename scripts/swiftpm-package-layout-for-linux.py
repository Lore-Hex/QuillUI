#!/usr/bin/env python3
"""Derive generated SwiftUI Linux target layout from SwiftPM manifest JSON."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def swift_string(value: str) -> str:
    return json.dumps(value)


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(65)


QUILLUI_PROVIDED_PRODUCTS = {
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
    "PDFKit",
    "PhotosUI",
    "QuickLook",
    "QuickLookUI",
    "QuillData",
    "QuillFoundation",
    "QuillKit",
    "QuillShims",
    "QuillUI",
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

QUILLUI_PROVIDED_PACKAGE_IDENTITIES = {
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


def dump_package(package_root: Path) -> dict:
    try:
        output = subprocess.check_output(
            ["swift", "package", "dump-package", "--package-path", str(package_root)],
            text=True,
            stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr)
        raise SystemExit(error.returncode)
    return json.loads(output)


def target_source_path(target: dict, package_root: Path, source_dir: Path) -> str:
    target_path = target.get("path") or f"Sources/{target['name']}"
    absolute = (package_root / target_path).resolve()
    try:
        return str(absolute.relative_to(source_dir))
    except ValueError:
        fail(
            f"target {target['name']} source path {absolute} is outside source dir {source_dir}; "
            "pass an explicit --target-layout-file for this package shape"
        )


def dependency_token(dependency: dict, known_targets: set[str]) -> tuple[str | None, str | None]:
    if "byName" in dependency:
        name, package = dependency["byName"][:2]
        if name in known_targets:
            return name, None
        if name in QUILLUI_PROVIDED_PRODUCTS:
            return None, None
        if package:
            return None, f"product:{name}:{package}"
        return None, name
    if "target" in dependency:
        name = dependency["target"][0]
        return name, None
    if "product" in dependency:
        name, package = dependency["product"][:2]
        if name in QUILLUI_PROVIDED_PRODUCTS:
            return None, None
        return None, f"product:{name}:{package}"
    return None, None


def package_identity_from_url(url: str) -> str:
    identity = url.split("?", 1)[0].split("#", 1)[0].rstrip("/").rsplit("/", 1)[-1]
    if identity.endswith(".git"):
        identity = identity[:-4]
    return identity.lower()


def local_dependencies(target: dict, known_targets: set[str]) -> list[str]:
    result: list[str] = []
    for dependency in target.get("dependencies", []):
        local, _ = dependency_token(dependency, known_targets)
        if local is not None:
            result.append(local)
    return result


def row_dependencies(target: dict, emitted_targets: set[str], known_targets: set[str]) -> list[str]:
    result: list[str] = []
    for dependency in target.get("dependencies", []):
        local, token = dependency_token(dependency, known_targets)
        if local is not None:
            if local in emitted_targets:
                result.append(local)
        elif token:
            result.append(token)
    return result


def package_dependency_line(dependency: dict) -> str | None:
    source_control = dependency.get("sourceControl")
    if source_control:
        item = source_control[0]
        remotes = item.get("location", {}).get("remote") or []
        if not remotes:
            return None
        url = remotes[0]["urlString"]
        if package_identity_from_url(url) in QUILLUI_PROVIDED_PACKAGE_IDENTITIES:
            return None
        requirement = item.get("requirement") or {}
        if "range" in requirement:
            lower = requirement["range"][0]["lowerBound"]
            return f".package(url: {swift_string(url)}, from: {swift_string(lower)})"
        if "exact" in requirement:
            return f".package(url: {swift_string(url)}, exact: {swift_string(requirement['exact'][0])})"
        if "branch" in requirement:
            return f".package(url: {swift_string(url)}, branch: {swift_string(requirement['branch'][0])})"
        if "revision" in requirement:
            return f".package(url: {swift_string(url)}, revision: {swift_string(requirement['revision'][0])})"
        return f".package(url: {swift_string(url)}, branch: \"main\")"

    file_system = dependency.get("fileSystem")
    if file_system:
        path = file_system[0].get("path")
        if path:
            return f".package(path: {swift_string(path)})"

    return None


def infer_entry_target(
    targets: dict[str, dict],
    package_root: Path,
    source_dir: Path,
    app_type: str,
) -> str:
    type_name = app_type.split(".")[-1]
    declaration = re.compile(rf"\b(?:struct|class|enum)\s+{re.escape(type_name)}\b")
    executable_targets = {name for name, target in targets.items() if target.get("type") == "executable"}

    matches: list[str] = []
    for swift_file in source_dir.rglob("*.swift"):
        try:
            text = swift_file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if not declaration.search(text):
            continue
        relative = swift_file.relative_to(source_dir)
        if not relative.parts:
            continue
        candidate = relative.parts[0]
        if candidate in executable_targets:
            matches.append(candidate)

    unique_matches = sorted(set(matches))
    if len(unique_matches) == 1:
        return unique_matches[0]
    if len(unique_matches) > 1:
        fail(f"app type {app_type} appears in multiple executable targets: {', '.join(unique_matches)}")

    main_targets: list[str] = []
    for name in sorted(executable_targets):
        source_path = source_dir / target_source_path(targets[name], package_root, source_dir)
        if any("@main" in path.read_text(encoding="utf-8", errors="ignore") for path in source_path.rglob("*.swift")):
            main_targets.append(name)
    if len(main_targets) == 1:
        return main_targets[0]

    fail(
        f"could not infer executable target for app type {app_type}; "
        "pass --entry-target or QUILLUI_APP_ENTRY_TARGET"
    )


def reachable_targets(entry_target: str, targets: dict[str, dict]) -> list[str]:
    known_targets = set(targets)
    visited: set[str] = set()
    ordered: list[str] = []

    def visit(name: str) -> None:
        if name in visited:
            return
        visited.add(name)
        target = targets.get(name)
        if target is None:
            fail(f"unknown target referenced by layout: {name}")
        for dependency in local_dependencies(target, known_targets):
            visit(dependency)
        if target.get("type") != "test":
            ordered.append(name)

    visit(entry_target)
    return ordered


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", required=True)
    parser.add_argument("--source-dir", required=True)
    parser.add_argument("--app-type", required=True)
    parser.add_argument("--entry-target")
    parser.add_argument("--generated-target", required=True)
    parser.add_argument("--layout-out", required=True)
    parser.add_argument("--dependencies-out", required=True)
    args = parser.parse_args()

    package_root = Path(args.package_root).resolve()
    source_dir = Path(args.source_dir).resolve()
    manifest = package_root / "Package.swift"
    if not manifest.is_file():
        fail(f"package root does not contain Package.swift: {package_root}")
    if not source_dir.is_dir():
        fail(f"source dir was not found: {source_dir}")

    package = dump_package(package_root)
    targets = {target["name"]: target for target in package.get("targets", [])}
    known_targets = set(targets)

    entry_target = args.entry_target or infer_entry_target(targets, package_root, source_dir, args.app_type)
    if entry_target not in targets:
        fail(f"entry target not found in package manifest: {entry_target}")
    if targets[entry_target].get("type") != "executable":
        fail(f"entry target must be executable, got {entry_target}: {targets[entry_target].get('type')}")

    ordered = reachable_targets(entry_target, targets)
    emitted_targets = set(ordered)
    layout_lines: list[str] = []
    for name in ordered:
        target = targets[name]
        output_name = args.generated_target if name == entry_target else name
        source_path = target_source_path(target, package_root, source_dir)
        dependencies = row_dependencies(target, emitted_targets, known_targets)
        layout_lines.append(f"{output_name}\t{source_path}\t{','.join(dependencies)}")

    dependency_lines = [
        line
        for dependency in package.get("dependencies", [])
        if (line := package_dependency_line(dependency)) is not None
    ]

    Path(args.layout_out).write_text("\n".join(layout_lines) + "\n", encoding="utf-8")
    Path(args.dependencies_out).write_text("\n".join(dependency_lines) + ("\n" if dependency_lines else ""), encoding="utf-8")


if __name__ == "__main__":
    main()
