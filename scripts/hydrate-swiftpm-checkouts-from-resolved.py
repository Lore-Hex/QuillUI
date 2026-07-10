#!/usr/bin/env python3
"""Hydrate SwiftPM checkouts from Package.resolved pins.

This is intentionally separate from the normal vendoring path. Regular builds
should be offline and read from third_party/. When a maintainer wants to refresh
vendored app dependencies, this helper clones only the missing pinned revisions
into .build/checkouts so vendor-swiftpm-sources.sh can copy slim source trees.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


DEV_ONLY = {
    "swift-snapshot-testing",
    "swiftlintplugin",
}

SHIM_ONLY = {
    "sparkle",
}

CANONICAL_PACKAGE_NAMES = {
    "activityindicatorview": "ActivityIndicatorView",
    "aboutwindow": "AboutWindow",
    "alamofire": "Alamofire",
    "anycodable": "AnyCodable",
    "codeeditkit": "CodeEditKit",
    "codeeditlanguages": "CodeEditLanguages",
    "codeeditsourceeditor": "CodeEditSourceEditor",
    "codeeditsymbols": "CodeEditSymbols",
    "codeedittextview": "CodeEditTextView",
    "collectionconcurrencykit": "CollectionConcurrencyKit",
    "concurrencyplus": "ConcurrencyPlus",
    "fseventswrapper": "FSEventsWrapper",
    "grdb.swift": "GRDB.swift",
    "jsonrpc": "JSONRPC",
    "keyboardshortcuts": "KeyboardShortcuts",
    "languageclient": "LanguageClient",
    "languageserverprotocol": "LanguageServerProtocol",
    "logstream": "LogStream",
    "magnet": "Magnet",
    "networkimage": "NetworkImage",
    "ollamakit": "OllamaKit",
    "processenv": "ProcessEnv",
    "queue": "Queue",
    "rearrange": "Rearrange",
    "sauce": "Sauce",
    "semaphore": "Semaphore",
    "sparkle": "Sparkle",
    "splash": "Splash",
    "swift-async-algorithms": "AsyncAlgorithms",
    "swift-cmark": "SwiftCMark",
    "swift-collections": "swift-collections",
    "swift-glob": "swift-glob",
    "swift-markdown-ui": "MarkdownUI",
    "swift-snapshot-testing": "SwiftSnapshotTesting",
    "swift-syntax": "swift-syntax",
    "swiftlintplugin": "SwiftLintPlugin",
    "swiftterm": "SwiftTerm",
    "swifttreesitter": "SwiftTreeSitter",
    "swiftui-introspect": "SwiftUIIntrospect",
    "textformation": "TextFormation",
    "textstory": "TextStory",
    "tree-sitter": "tree-sitter",
    "vortex": "Vortex",
    "welcomewindow": "WelcomeWindow",
    "wrappinghstack": "WrappingHStack",
    "zipfoundation": "ZIPFoundation",
}


@dataclass(frozen=True)
class Pin:
    package: str
    key: str
    location: str
    revision: str


def truthy(value: str | None) -> bool:
    return value in {"1", "true", "TRUE", "yes", "YES", "on", "ON"}


def package_key(identity: str, location: str) -> tuple[str, str]:
    basename = location.rstrip("/").rsplit("/", 1)[-1]
    if basename.endswith(".git"):
        basename = basename[:-4]
    key = identity.lower() if identity else basename.lower()
    return key, basename


def pins_from_resolved(path: Path, include_dev_packages: bool) -> list[Pin]:
    data = json.loads(path.read_text())
    pins: list[Pin] = []
    for pin in data.get("pins", []):
        identity = str(pin.get("identity", ""))
        location = str(pin.get("location", "")).rstrip("/")
        state = pin.get("state", {})
        revision = str(state.get("revision", ""))
        key, basename = package_key(identity, location)

        if not include_dev_packages and key in DEV_ONLY:
            continue
        if key in SHIM_ONLY:
            continue
        if not location or not revision:
            print(f"warning: Package.resolved pin lacks location or revision: {identity or basename}", file=sys.stderr)
            continue

        pins.append(Pin(CANONICAL_PACKAGE_NAMES.get(key, basename), key, location, revision))

    return pins


def run(args: list[str], cwd: Path | None = None) -> None:
    subprocess.run(args, cwd=str(cwd) if cwd else None, check=True)


def remove_existing(path: Path) -> None:
    if not path.exists():
        return
    for item in path.rglob("*"):
        try:
            item.chmod(item.stat().st_mode | 0o200)
        except OSError:
            pass
    shutil.rmtree(path)


def hydrate_pin(root_dir: Path, scratch_path: Path, pin: Pin, dry_run: bool) -> None:
    checkout_dir = scratch_path / "checkouts" / pin.package
    vendored_dir = root_dir / "third_party" / pin.package

    if not truthy(os.environ.get("QUILLUI_VENDOR_FORCE")) and (vendored_dir / "Package.swift").is_file():
        print(f"already vendored {pin.package} -> third_party/{pin.package}")
        return

    if (checkout_dir / "Package.swift").is_file() and (checkout_dir / ".git").is_dir():
        print(f"already hydrated {pin.package} -> {checkout_dir}")
        return

    if dry_run:
        print(f"would hydrate {pin.package} from {pin.location} @ {pin.revision} -> {checkout_dir}")
        return

    checkout_dir.parent.mkdir(parents=True, exist_ok=True)
    remove_existing(checkout_dir)
    run(["git", "clone", "--quiet", pin.location, str(checkout_dir)])
    run(["git", "checkout", "--quiet", pin.revision], cwd=checkout_dir)
    print(f"hydrated {pin.package} -> {checkout_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root-dir", default=".", help="QuillUI repository root.")
    parser.add_argument("--scratch-path", default=".build", help="SwiftPM scratch path that owns checkouts/.")
    parser.add_argument("--package-resolved", action="append", default=[], help="Package.resolved to hydrate.")
    parser.add_argument("--dry-run", action="store_true", help="Print clones that would run.")
    args = parser.parse_args()

    root_dir = Path(args.root_dir).resolve()
    scratch_path = Path(args.scratch_path)
    if not scratch_path.is_absolute():
        scratch_path = (root_dir / scratch_path).resolve()

    include_dev_packages = truthy(os.environ.get("QUILLUI_VENDOR_INCLUDE_DEV_PACKAGES"))
    seen: set[str] = set()
    for resolved in args.package_resolved:
        resolved_path = Path(resolved)
        if not resolved_path.is_absolute():
            resolved_path = (root_dir / resolved_path).resolve()
        if not resolved_path.is_file():
            print(f"error: Package.resolved was not found: {resolved_path}", file=sys.stderr)
            return 66
        for pin in pins_from_resolved(resolved_path, include_dev_packages):
            if pin.package in seen:
                continue
            seen.add(pin.package)
            hydrate_pin(root_dir, scratch_path, pin, args.dry_run)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
