#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  cat >&2 <<'MSG'
Usage: scripts/lower-objc-interop-for-linux.sh GENERATED_OR_FETCHED_SOURCE_DIR

Applies conservative, app-agnostic Objective-C interop source cleanup to a
generated or fetched Swift source copy before building on Linux. Do not point
this at a developer's canonical app source tree.

Currently lowers:
  @objc / @objc(...) / @IBAction / @IBOutlet / ObjC-only attributes -> removed
  #selector(Type.method(_:))                                      -> Selector("method(_:)")
  CoreFoundation bridge casts absent from swift-corelibs Foundation          -> removed
  `FetchDescriptor<T>(predicate: #Predicate { ... })`                     -> typed QuillData macro
  `.first { ... }` collection shorthand in fetched sources                  -> `.first(where: { ... })`
  `NSSortDescriptor(key: "creationDate", ...)` for PHAsset                  -> key-path initializer
  Objective-C optional UITextViewDelegate calls                             -> Swift protocol default calls
  `List { ... }` SwiftUI builders shadowed by model types named `List`      -> `SwiftUI.List { ... }`
MSG
  exit 64
fi

SOURCE_DIR="$1"
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory does not exist: $SOURCE_DIR" >&2
  exit 66
fi

python3 - "$SOURCE_DIR" <<'PY'
import os
import re
import sys

source_dir = sys.argv[1]
attributes = (
    "objc", "objcMembers",
    "IBAction", "IBOutlet", "IBInspectable", "IBDesignable",
    "NSManaged", "GKInspectable", "NSApplicationMain",
)
attribute_re = re.compile(
    r"^([ \t]*)@(" + "|".join(re.escape(a) for a in attributes) + r")(?:\([^)]*\))?[ \t]*",
    re.MULTILINE,
)

def selector_key(text: str) -> str:
    text = text.strip()
    qualifier = text.split("(", 1)[0]
    if "." in qualifier:
        dot = qualifier.rfind(".")
        return text[dot + 1 :]
    return text

def lower_selectors(src: str) -> str:
    out = []
    i = 0
    marker = "#selector("
    while True:
        start = src.find(marker, i)
        if start < 0:
            out.append(src[i:])
            break
        out.append(src[i:start])
        pos = start + len(marker)
        depth = 1
        while pos < len(src) and depth > 0:
            ch = src[pos]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            pos += 1
        if depth != 0:
            out.append(src[start:pos])
            i = pos
            continue
        inner = src[start + len(marker) : pos - 1]
        key = selector_key(inner).replace("\\", "\\\\").replace('"', '\\"')
        out.append(f'Selector("{key}")')
        i = pos
    return "".join(out)

def lower_foundation_bridge_casts(src: str) -> str:
    # swift-corelibs Foundation does not provide the Objective-C/CoreFoundation
    # toll-free bridges that Apple-platform source often writes as `as CFURL`,
    # `as CFString`, or `as CFDictionary`. The corresponding Quill shims accept
    # native Swift values, so these casts are compile-only noise on Linux.
    lowered = src
    lowered = re.sub(
        r"\]\s+as\s+\[CFString:\s*Any\]\s+as\s+CFDictionary",
        "] as [String: Any]",
        lowered,
    )
    lowered = lowered.replace(" as [CFString: Any]", "")
    lowered = lowered.replace(" as CFDictionary", "")
    lowered = lowered.replace(" as CFString", "")
    lowered = lowered.replace(" as CFURL", "")
    return lowered

def lower_imageio_option_dictionaries(src: str) -> str:
    # Once CF bridge casts are removed, mixed Bool/Int ImageIO option literals
    # need an explicit Swift dictionary context. Keep this generic to ImageIO
    # key dictionaries instead of naming IceCubes files.
    option_dictionary_re = re.compile(
        r"(let\s+\w+\s*=\s*\[[^\]]*kCGImageSource[^\]]*\])(?!\s+as\s+\[String:\s*Any\])",
        re.DOTALL,
    )
    return option_dictionary_re.sub(r"\1 as [String: Any]", src)

def lower_contextual_swiftdata_predicates(src: str) -> str:
    # Apple's `#Predicate { ... }` gets its input model from SwiftData's
    # surrounding `FetchDescriptor<Model>` context. QuillData's compatibility
    # macro is intentionally explicit, so infer that generic in generated
    # source copies rather than requiring app edits.
    fetch_descriptor_re = re.compile(
        r"(FetchDescriptor\s*<\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)\s*>\s*\(\s*predicate\s*:\s*)#Predicate\b(?!\s*<)"
    )
    lowered = fetch_descriptor_re.sub(r"\1#QuillPredicate<\2>", src)
    lowered = re.sub(r"#Predicate\s*<", "#QuillPredicate<", lowered)
    return lowered

def lower_sequence_first_shorthand(src: str) -> str:
    # On Linux Swift 6, some Set/scene expressions prefer the `first` property
    # during overload resolution. Normalize the shorthand to the labeled method.
    return re.sub(r"\.first\s*\{([^{}\n]*)\}", r".first(where: {\1})", src)

def lower_known_kvc_descriptors(src: str) -> str:
    # KVC string sort descriptors are unavailable in swift-corelibs. Known
    # portable replacements go through key paths.
    return re.sub(
        r'NSSortDescriptor\(key:\s*"creationDate",\s*ascending:\s*([^)]+)\)',
        r"NSSortDescriptor(keyPath: \\PHAsset.creationDate, ascending: \1)",
        src,
    )

def lower_known_optional_delegate_calls(src: str) -> str:
    return src.replace(
        "textView.delegate?.textViewDidChange?(textView)",
        "textView.delegate?.textViewDidChange(textView)",
    )

def lower_swiftui_list_builders(src: str) -> str:
    return re.sub(r"(?<![.\w])List\s*\{", "SwiftUI.List {", src)

count = 0
changed = 0
for root, dirs, files in os.walk(source_dir):
    dirs[:] = [d for d in dirs if not d.startswith(".")]
    for name in files:
        if not name.endswith(".swift"):
            continue
        path = os.path.join(root, name)
        with open(path, "r", encoding="utf-8") as fh:
            src = fh.read()
        lowered = attribute_re.sub(r"\1", src)
        lowered = lower_selectors(lowered)
        lowered = lower_foundation_bridge_casts(lowered)
        lowered = lower_imageio_option_dictionaries(lowered)
        lowered = lower_contextual_swiftdata_predicates(lowered)
        lowered = lower_sequence_first_shorthand(lowered)
        lowered = lower_known_kvc_descriptors(lowered)
        lowered = lower_known_optional_delegate_calls(lowered)
        lowered = lower_swiftui_list_builders(lowered)
        count += 1
        if lowered != src:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(lowered)
            changed += 1

print(f"Lowered Objective-C interop syntax in {changed}/{count} Swift files under {source_dir}")
PY
