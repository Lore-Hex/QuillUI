#!/usr/bin/env python3
import re
import sys
from pathlib import Path


THREAD_SELECTOR_RE = re.compile(
    r"Thread\(\s*target:\s*([A-Za-z_][A-Za-z0-9_]*)\.self,\s*"
    r"selector:\s*#selector\(\s*\1\.([A-Za-z_][A-Za-z0-9_]*)\(_:\)\s*\),\s*"
    r"object:\s*([^)]+?)\s*\)"
)
THREAD_SELECTOR_LINE_RE = re.compile(
    r"(?m)^([ \t]*)([^=\n]+=\s*)Thread\(\s*target:\s*([A-Za-z_][A-Za-z0-9_]*)\.self,\s*"
    r"selector:\s*#selector\(\s*\3\.([A-Za-z_][A-Za-z0-9_]*)\(_:\)\s*\),\s*"
    r"object:\s*(.+)\)\s*$"
)
THREAD_SELECTOR_MULTILINE_RE = re.compile(
    r"(?m)^([ \t]*)([^=\n]+=\s*)Thread\(\s*\n"
    r"[ \t]*target:\s*([A-Za-z_][A-Za-z0-9_]*)\.self,\s*\n"
    r"[ \t]*selector:\s*#selector\(\s*\3\.([A-Za-z_][A-Za-z0-9_]*)\(_:\)\s*\),\s*\n"
    r"[ \t]*object:\s*((?:.|\n)*?\n[ \t]*\))\s*\n"
    r"[ \t]*\)\s*$"
)
TIMER_SELECTOR_RE = re.compile(
    r"Timer\(\s*fireAt:\s*([^,]+),\s*interval:\s*([^,]+),\s*target:\s*([A-Za-z_][A-Za-z0-9_]*)\.self,\s*"
    r"selector:\s*#selector\(\s*\3\.([A-Za-z_][A-Za-z0-9_]*)\s*\),\s*"
    r"userInfo:\s*([^,]+),\s*repeats:\s*([^)]+)\)"
)
SELECTOR_RE = re.compile(r"#selector\(\s*([A-Za-z_][A-Za-z0-9_\.]*)(?:\(_:?\))?\s*\)")

QUARTZCORE_TOKENS = (
    "CAAnimation",
    "CAAnimationDelegate",
    "CABasicAnimation",
    "CACurrentMediaTime",
    "CASpringAnimation",
    "CALayer",
    "CAMediaTiming",
    "CATransaction",
    "CAShapeLayer",
    "CFTimeInterval",
)

COREVIDEO_TOKENS = (
    "CVDisplayLink",
    "CVPixelBuffer",
)

COREMEDIA_TOKENS = (
    "CMBlockBuffer",
    "CMAudio",
    "CMClock",
    "CMFormatDescription",
    "CMSample",
    "CMSetAttachment",
    "CMTime",
    "CMVideo",
    "kCMAttachment",
    "kCMBlockBuffer",
    "kCMSample",
)

AUDIOTOOLBOX_TOKENS = (
    "AUGraph",
    "AUNode",
    "AudioBuffer",
    "AudioComponent",
    "AudioConverter",
    "AudioDeviceID",
    "AudioObject",
    "AudioStreamBasicDescription",
    "AudioStreamPacketDescription",
    "AudioTimeStamp",
    "AudioUnit",
    "AudioValueRange",
    "UnsafeMutableAudioBufferListPointer",
    "kAudio",
    "kHALOutputParam",
    "kTimePitchParam",
)

AVFOUNDATION_TOKENS = (
    "AVSampleBufferDisplayLayer",
    "AVSampleBufferAudioRenderer",
    "AVSampleBufferRenderSynchronizer",
    "AVQueuedSampleBufferRendering",
    "AVLayerVideoGravity",
    "CMSampleBuffer",
    "CMTimebase",
)

APPKIT_TOKENS = (
    "NSImage",
    "NSColor",
    "NSView",
    "NSPoint",
    "NSRect",
    "NSSize",
    "NSEvent",
    "NSFont",
    "NSBezierPath",
    "NSWindow",
    "NSNull",
)

COREIMAGE_TOKENS = (
    "CIColorKernel",
    "CIContext",
    "CIImage",
    "CIFilter",
)

IMAGEIO_TOKENS = (
    "CGDataProvider",
    "CGImageSource",
    "CGImageDestination",
)

WEBKIT_TOKENS = (
    "WKScriptMessage",
    "WKScriptMessageHandler",
    "WKUserContentController",
    "WKWebView",
)

CORETEXT_TOKENS = (
    "CTFramesetter",
    "CTLine",
    "CTFrame",
    "CTRun",
    "CTTypesetter",
    "kCTFontAttributeName",
    "kCTForegroundColor",
)

IOKIT_TOKENS = (
    "IOServiceGetMatchingService",
    "IOServiceMatching",
    "IORegistryEntryCreateCFProperty",
    "IOObjectRelease",
    "IOServiceClose",
    "IOPSCopyPowerSources",
    "IOPSGetPowerSourceDescription",
    "kIOMasterPortDefault",
    "kIOMainPortDefault",
)

XATTR_TOKENS = (
    "getxattr",
    "setxattr",
    "removexattr",
)


def insert_import(text: str, module: str) -> str:
    if re.search(rf"^\s*import\s+{re.escape(module)}\b", text, flags=re.MULTILINE):
        return text

    lines = text.splitlines(keepends=True)
    insert_at = 0
    for index, line in enumerate(lines):
        if re.match(r"^\s*import\s+\w+\b", line):
            insert_at = index + 1
    lines.insert(insert_at, f"import {module}\n")
    return "".join(lines)


def lower_thread_selector_line(match: re.Match[str]) -> str:
    indent, prefix, class_name, method_name, object_expr = match.groups()
    object_expr = object_expr.strip()
    if object_expr == "taskQueue":
        object_expr = "self.taskQueue"
    object_name = f"quillThreadObject{class_name}{method_name}"
    return (
        f"{indent}let {object_name} = {object_expr}\n"
        f"{indent}{prefix}Thread {{ {class_name}.{method_name}({object_name}) }}"
    )


def lower_thread_selector_multiline(match: re.Match[str]) -> str:
    indent, prefix, class_name, method_name, object_expr = match.groups()
    object_expr = object_expr.strip()
    object_name = f"quillThreadObject{class_name}{method_name}"
    return (
        f"{indent}let {object_name} = {object_expr}\n"
        f"{indent}{prefix}Thread {{ {class_name}.{method_name}({object_name}) }}"
    )


def lower_swift_source(text: str) -> str:
    lowered = text

    if "os(macOS)" in lowered:
        lowered = re.sub(
            r"(?m)^([ \t]*#(?:if|elseif)\b[^\n]*?)os\(macOS\)([^\n]*)$",
            lambda match: match.group(0)
            if "os(Linux)" in match.group(0)
            else f"{match.group(1)}(os(macOS) || os(Linux)){match.group(2)}",
            lowered,
        )

    if re.search(r"(?m)^\s*import\s+Darwin\b", lowered):
        lowered = re.sub(r"(?m)^(\s*)import\s+Darwin\b", r"\1import Glibc", lowered)
        lowered = lowered.replace("Darwin.", "Glibc.")

    if "os_unfair_lock" in lowered or "OSSpinLock" in lowered:
        lowered = insert_import(lowered, "COSUnfairLock")

    # Any CF function call (CFAbsoluteTimeGetCurrent, CFRangeMake, CFRelease,
    # CFNumberCreate, ...) or CFString reference needs corelibs CoreFoundation
    # imported per-file; the Apple shims deliberately do not re-export the
    # whole module (its stub CFString/CFArray classes collide with the bridged
    # typealiases under `import Cocoa`).
    if re.search(r"\bCF[A-Z][A-Za-z]*\s*\(", lowered) or "CFString" in lowered:
        lowered = insert_import(lowered, "CoreFoundation")

    if (
        "threadPriority" in lowered
        or "arc4random" in lowered
        or "#selector" in lowered
        or "Selector(" in lowered
        or "NSSelectorFromString" in lowered
        or "performSelector" in lowered
        or "S_IRUSR" in lowered
        or "lseek(" in lowered
        or "ftruncate(" in lowered
        or "arc4random_buf" in lowered
        or "__darwin_ino64_t" in lowered
        or "MAXPATHLEN" in lowered
        or "F_GETPATH" in lowered
        or "st_mtimespec" in lowered
        or "makeFileSystemObjectSource" in lowered
        or "NSUbiquitousKeyValueStore" in lowered
        or "SecRandomCopyBytes" in lowered
        or "errSecSuccess" in lowered
        or "OSAtomicIncrement32" in lowered
        or "mappedRead" in lowered
        or "sysctlbyname" in lowered
    ):
        lowered = insert_import(lowered, "QuillFoundation")

    if any(token in lowered for token in ("UnsafeMutablePointer<DIR>", "opendir(", "readdir(", "closedir(", "DT_REG")):
        lowered = insert_import(lowered, "Glibc")

    if "MeasurementFormatter" in lowered:
        lowered = insert_import(lowered, "QuillFoundation")
        lowered = lowered.replace("MeasurementFormatter", "QuillMeasurementFormatter")

    if "appendFormat" in lowered:
        lowered = insert_import(lowered, "QuillFoundation")

    if any(token in lowered for token in QUARTZCORE_TOKENS):
        lowered = insert_import(lowered, "QuartzCore")

    if any(token in lowered for token in COREVIDEO_TOKENS):
        lowered = insert_import(lowered, "CoreVideo")

    if any(token in lowered for token in COREMEDIA_TOKENS):
        lowered = insert_import(lowered, "CoreMedia")

    if any(token in lowered for token in AUDIOTOOLBOX_TOKENS):
        lowered = insert_import(lowered, "AudioToolbox")

    if any(token in lowered for token in AVFOUNDATION_TOKENS):
        lowered = insert_import(lowered, "AVFoundation")

    if any(token in lowered for token in APPKIT_TOKENS):
        lowered = insert_import(lowered, "AppKit")

    if any(token in lowered for token in COREIMAGE_TOKENS):
        lowered = insert_import(lowered, "CoreImage")

    if any(token in lowered for token in IMAGEIO_TOKENS):
        lowered = insert_import(lowered, "ImageIO")

    if any(token in lowered for token in WEBKIT_TOKENS):
        lowered = insert_import(lowered, "WebKit")

    if any(token in lowered for token in CORETEXT_TOKENS):
        lowered = insert_import(lowered, "CoreText")

    if any(token in lowered for token in IOKIT_TOKENS):
        lowered = insert_import(lowered, "IOKit")

    if any(token in lowered for token in XATTR_TOKENS):
        lowered = insert_import(lowered, "Glibc")
        lowered = insert_import(lowered, "QuillFoundation")

    if "#imageLiteral" in lowered:
        lowered = insert_import(lowered, "AppKit")
        lowered = re.sub(
            r"#imageLiteral\(\s*resourceName:\s*\"([^\"]+)\"\s*\)",
            r'(NSImage(named: "\1") ?? NSImage(size: NSSize(width: 32, height: 32)))',
            lowered,
        )

    for corefoundation_cast in (
        "CFString",
        "CFData",
        "CFDictionary",
        "CFAttributedString",
    ):
        lowered = lowered.replace(f" as {corefoundation_cast}", "")

    if " as CFArray" in lowered:
        lowered = lowered.replace(" as CFArray", " as NSArray")

    if "@objc" in lowered:
        lowered = re.sub(r"(?m)^[ \t]*@objc(?:\([^)]*\))?[ \t]*\n", "", lowered)
        lowered = re.sub(r"@objc(?:\([^)]*\))?[ \t]+", "", lowered)

    if "#selector" in lowered:
        lowered = THREAD_SELECTOR_MULTILINE_RE.sub(lower_thread_selector_multiline, lowered)
        lowered = THREAD_SELECTOR_LINE_RE.sub(lower_thread_selector_line, lowered)
        lowered = TIMER_SELECTOR_RE.sub(
            lambda match: f"Timer(fire: {match.group(1).strip()}, interval: {match.group(2).strip()}, repeats: {match.group(6).strip()}) {{ _ in {match.group(3)}.{match.group(4)}() }}",
            lowered,
        )
        lowered = THREAD_SELECTOR_RE.sub(
            lambda match: f"Thread {{ {match.group(1)}.{match.group(2)}({match.group(3).strip()}) }}",
            lowered,
        )
        lowered = SELECTOR_RE.sub(
            lambda match: f'Selector("{match.group(1).split(".")[-1]}")',
            lowered,
        )

    if "autoreleasepool" in lowered:
        lowered = lowered.replace("autoreleasepool {", "do {")

    if "return do {" in lowered:
        lowered = lowered.replace("return do {", "do {")

    if "CFAttributedString" in lowered:
        lowered = lowered.replace(": CFAttributedString", ": NSAttributedString")
        lowered = lowered.replace("CFAttributedString?", "NSAttributedString?")

    if "CFString" in lowered:
        lowered = lowered.replace(": CFString", ": String")
        lowered = lowered.replace("CFString?", "String?")

    if "IOPSCopyPowerSourcesList" in lowered:
        lowered = re.sub(
            r"IOPSCopyPowerSourcesList\(([^)]*)\)\.takeRetainedValue\(\)\s+as\s+Array",
            r"(IOPSCopyPowerSourcesList(\1).takeRetainedValue() as? [AnyObject]) ?? []",
            lowered,
        )

    if "NSMutableAttributedString()" in lowered:
        lowered = lowered.replace("NSMutableAttributedString()", 'NSMutableAttributedString(string: "")')

    if "NSAttributedString()" in lowered:
        lowered = lowered.replace("NSAttributedString()", 'NSAttributedString(string: "")')

    if "NSMutableString()" in lowered:
        lowered = lowered.replace("NSMutableString()", 'NSMutableString(string: "")')

    if "Unmanaged<DispatchSourceUserDataAdd>" in lowered:
        lowered = re.sub(
            r"let\s+sourceUnmanaged\s*=\s*Unmanaged<DispatchSourceUserDataAdd>\.fromOpaque\([^)]+\)\s*\n"
            r"\s*//[^\n]*\n"
            r"\s*sourceUnmanaged\.takeUnretainedValue\(\)\.add\(data:\s*1\)",
            "source.add(data: 1)",
            lowered,
        )
        lowered = lowered.replace("Unmanaged.passUnretained(source).toOpaque()", "nil")

    if "source.add(data: 1)" in lowered:
        lowered = lowered.replace("source.add(data: 1)", "callbackSource.add(data: 1)")
        lowered = lowered.replace(
            "source = DispatchSource.makeUserDataAddSource(queue: queue)\n",
            "source = DispatchSource.makeUserDataAddSource(queue: queue)\n       let callbackSource = source\n",
        )

    if "vz.init(frame:" in lowered:
        lowered = insert_import(lowered, "AppKit")
        lowered = re.sub(r"vz\.init\(frame:\s*([^\n]+)\)", r"QuillInstantiateView(vz, frame: \1)", lowered)

    if "convenience init(bufferNoCopy: MemoryBuffer)" in lowered:
        lowered = lowered.replace("bufferNoCopy.memory!, size:", "bufferNoCopy.memory, size:")
        lowered = lowered.replace("bufferNoCopy.memory, size:", "bufferNoCopy.memory, size:")
        lowered = lowered.replace("buffer.memory!, buffer.length", "buffer.memory, buffer.length")
        lowered = lowered.replace("buffer.memory, buffer.length", "buffer.memory, buffer.length")
        lowered = lowered.replace("memcpy(memory, buffer.data,", "memcpy(memory, buffer.data!,")

    if "memcpy(memory, data.data," in lowered:
        lowered = lowered.replace("memcpy(memory, data.data,", "memcpy(memory, data.data!,")

    if "observeValue(forKeyPath" in lowered:
        lowered = lowered.replace("open override func observeValue", "open func observeValue")
        lowered = lowered.replace("public override func observeValue", "public func observeValue")
        lowered = lowered.replace("override open func observeValue", "open func observeValue")
        lowered = lowered.replace("override public func observeValue", "public func observeValue")
        lowered = lowered.replace("override func observeValue", "func observeValue")

    if "isEqual(to object: Any?)" in lowered:
        lowered = lowered.replace("public override func isEqual(to object: Any?)", "public func isEqual(to object: Any?)")
        lowered = lowered.replace("override public func isEqual(to object: Any?)", "public func isEqual(to object: Any?)")
        lowered = lowered.replace("open override func isEqual(to object: Any?)", "open func isEqual(to object: Any?)")
        lowered = lowered.replace("override open func isEqual(to object: Any?)", "open func isEqual(to object: Any?)")
        lowered = lowered.replace("override func isEqual(to object: Any?)", "func isEqual(to object: Any?)")

    if "override func hitTest(_ point: NSPoint)" in lowered:
        lowered = re.sub(
            r"(?ms)(extension\s+[A-Za-z_][A-Za-z0-9_]*\s*\{\s*)open\s+override\s+func\s+hitTest\(_ point: NSPoint\)\s*->\s*NSView\?\s*\{\s*return nil\s*\}(\s*\})",
            r"\1public func quillLinuxHitTest(_ point: NSPoint) -> NSView? {\n        return nil\n    }\2",
            lowered,
        )

    if "accessibilityFocusedUIElement" in lowered:
        lowered = re.sub(
            r"\n\s*public\s+extension\s+NSView\s*\{\s*override\s+class\s+func\s+accessibilityFocusedUIElement\(\)\s*->\s*Any\?\s*\{\s*return\s+nil\s*\}\s*\}\s*",
            "\n",
            lowered,
            flags=re.DOTALL,
        )

    lowered = re.sub(
        r"\[([A-Za-z_][A-Za-z0-9_\.]*)\s*:\s*([A-Za-z_][A-Za-z0-9_\.]*)\]\(\)",
        r"Dictionary<\1, \2>()",
        lowered,
    )
    lowered = re.sub(
        r"(\$[0-9]+)\s+as\s+NSNumber",
        r"NSNumber(value: Double(\1))",
        lowered,
    )
    lowered = re.sub(
        r"([A-Za-z_][A-Za-z0-9_\.]*|(?<!\$)[0-9]+(?:\.[0-9]+)?)\s+as\s+NSNumber",
        r"NSNumber(value: Double(\1))",
        lowered,
    )
    lowered = re.sub(
        r"(\$[0-9]+)\.NSNumber\(value:\s*Double\(([A-Za-z_][A-Za-z0-9_]*)\)\)",
        r"NSNumber(value: Double(\1.\2))",
        lowered,
    )
    lowered = lowered.replace("NSNumber(value: Double(next))", "NSNumber(value: (next as? Bool) ?? false)")
    lowered = lowered.replace("true as NSNumber", "NSNumber(value: true)")
    lowered = lowered.replace("false as NSNumber", "NSNumber(value: false)")
    lowered = re.sub(r"(delegate\?\.[A-Za-z_][A-Za-z0-9_]*)\?\(", r"\1(", lowered)

    if ".selectedRange()" in lowered:
        lowered = lowered.replace(".selectedRange()", ".selectedRange")

    if ".attributedString()" in lowered:
        lowered = lowered.replace(".attributedString()", ".attributedString")

    if ".size()" in lowered:
        lowered = lowered.replace(".size()", ".size")

    if "NSScreen.main?" in lowered:
        lowered = lowered.replace("NSScreen.main?", "NSScreen.main")

    lowered = re.sub(
        r"(?m)^(\s*)if\s+let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*NSScreen\.main\s*\{",
        r"\1let \2 = NSScreen.main\n\1if true {",
        lowered,
    )
    lowered = re.sub(r",\s*screen:\s*NSScreen\.main\s*\)", ")", lowered)
    lowered = re.sub(r",\s*screen:\s*screen\s*\)", ")", lowered)

    if "NSAffineTransform()" in lowered and "import AppKit" in lowered:
        lowered = lowered.replace("NSAffineTransform()", "AppKit.NSAffineTransform()")

    if "NSHapticFeedbackManager.defaultPerformer.perform" in lowered:
        lowered = lowered.replace(
            "NSHapticFeedbackManager.defaultPerformer.perform",
            "NSHapticFeedbackManager.defaultPerformer().perform",
        )

    if "memcpy(self.data?.advanced" in lowered or "memcpy(&value, self.buffer.data?.advanced" in lowered:
        lowered = lowered.replace(
            "memcpy(self.data?.advanced(by: Int(self._size)), bytes, Int(length))",
            "memcpy(self.data!.advanced(by: Int(self._size)), bytes, Int(length))",
        )
        lowered = lowered.replace(
            "memcpy(self.data?.advanced(by: Int(self._size)), buffer.data, Int(buffer._size))",
            "memcpy(self.data!.advanced(by: Int(self._size)), buffer.data!, Int(buffer._size))",
        )
        lowered = lowered.replace(
            "memcpy(&value, self.buffer.data?.advanced(by: Int(self.offset)), count)",
            "memcpy(&value, self.buffer.data!.advanced(by: Int(self.offset)), count)",
        )

    if "scanCharacters" in lowered and "NSString?" in lowered:
        lowered = re.sub(
            r"var ([A-Za-z_][A-Za-z0-9_]*): NSString\?",
            r"var \1: String?",
            lowered,
        )

    if "setValue" in lowered and "forKeyPath:" in lowered:
        lowered = re.sub(
            r"setValue\(([^\n]+?),\s*forKeyPath:",
            r"setValue(\1, forKey:",
            lowered,
        )

    if "value(forKeyPath:" in lowered:
        lowered = lowered.replace("value(forKeyPath:", "value(forKey:")

    if "-NSNumber(" in lowered:
        lowered = re.sub(
            r"-NSNumber\(value:\s*Double\(([^)]+)\)\)",
            r"NSNumber(value: -Double(\1))",
            lowered,
        )

    if "S_IRUSR" in lowered:
        lowered = re.sub(
            r"(accessMode\s*=\s*)(S_IRUSR(?:\s*\|\s*S_IWUSR)?)",
            r"\1UInt16(\2)",
            lowered,
        )

    if "value.st_size" in lowered:
        lowered = lowered.replace("return value.st_size", "return Int64(value.st_size)")

    if "UnsafeMutablePointer<DIR>" in lowered:
        lowered = lowered.replace("UnsafeMutablePointer<DIR>", "OpaquePointer")

    if "st_mtimespec" in lowered:
        lowered = lowered.replace("st_mtimespec", "st_mtim")

    if "d_namlen" in lowered:
        lowered = lowered.replace("Int(dirp.pointee.d_namlen)", "strnlen(&dirp.pointee.d_name.0, 1024)")

    if "sqlite3_column_blob" in lowered:
        lowered = lowered.replace("memcpy(valueMemory, valueData, Int(valueLength))", "memcpy(valueMemory, valueData!, Int(valueLength))")
        lowered = lowered.replace("memcpy(key.memory, valueData, Int(valueLength))", "memcpy(key.memory, valueData!, Int(valueLength))")

    if "murMurHash32Data(" in lowered:
        lowered = re.sub(
            r"return\s+murMurHash32Data\(([^)]+)\)",
            r"return \1.withUnsafeBytes { bytes in MurMurHash32.murMurHash32(UnsafeMutableRawPointer(mutating: bytes.baseAddress!), Int32(bytes.count)) }",
            lowered,
        )

    if "postboxTransformedString(nsString" in lowered:
        lowered = re.sub(
            r"(?m)^(\s*)nsString = postboxTransformedString\(nsString, transliteration == \.transliterated, transliteration == \.combined\) as NSString$",
            r"""\1let foldedString = (nsString as String).folding(options: [.diacriticInsensitive], locale: nil)
        \1if transliteration == .combined {
        \1    nsString = "\(nsString) \(foldedString)" as NSString
        \1} else {
        \1    nsString = foldedString as NSString
        \1}""",
            lowered,
        )

    if "CFStringTokenizerCreate" in lowered:
        lowered = lowered.replace("import CoreFoundation\n", "")
        lowered = re.sub(
            r"public func stringIndexTokens\(_ string: String, transliteration: StringIndexTokenTransliteration\) -> \[ValueBoxKey\] \{.*?\n\}\n\npublic func matchStringIndexTokens",
            """public func stringIndexTokens(_ string: String, transliteration: StringIndexTokenTransliteration) -> [ValueBoxKey] {
    var nsString = string.lowercased() as NSString

    var isLatin = true
    for i in 0 ..< nsString.length {
        let c = nsString.character(at: i)
        if c >= 128 {
            isLatin = false
            break
        }
    }

    if !isLatin {
        let foldedString = (nsString as String).folding(options: [.diacriticInsensitive], locale: nil)
        if transliteration == .combined {
            nsString = "\\(nsString) \\(foldedString)" as NSString
        } else {
            nsString = foldedString as NSString
        }
    }

    var tokens: [ValueBoxKey] = []
    var addedTokens = Set<ValueBoxKey>()
    for word in (nsString as String).split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
        let units = Array(String(word).utf16)
        guard !units.isEmpty else {
            continue
        }
        let token = ValueBoxKey(length: units.count * 2)
        units.withUnsafeBufferPointer { buffer in
            memcpy(token.memory, buffer.baseAddress!, units.count * 2)
        }
        if !addedTokens.contains(token) {
            tokens.append(token)
            addedTokens.insert(token)
        }
    }
    return tokens
}

public func matchStringIndexTokens""",
            lowered,
            flags=re.DOTALL,
        )

    if "NSFont(descriptor:" in lowered:
        lowered = re.sub(
            r"if let descriptor = (.*?), let font = NSFont\(descriptor: descriptor, size: ([^)]+)\) \{",
            r"if let descriptor = \1 {\n                let font = NSFont(descriptor: descriptor, size: \2)",
            lowered,
        )
        lowered = re.sub(
            r"if let ([A-Za-z_][A-Za-z0-9_]*) = ([^\n,]+), let ([A-Za-z_][A-Za-z0-9_]*) = NSFont\(descriptor: \1, size: ([^)]+)\) \{",
            r"if let \1 = \2 {\n                let \3 = NSFont(descriptor: \1, size: \4)",
            lowered,
        )
        lowered = re.sub(
            r"if let ([A-Za-z_][A-Za-z0-9_]*) = NSFont\(descriptor: ([^,]+), size: ([^)]+)\) \{\s*return \1\s*\}",
            r"return NSFont(descriptor: \2, size: \3)",
            lowered,
        )

    lowered = re.sub(
        r"\[\(([^\n\]]+?,[^\n\]]+?)\)\]\(\)",
        r"Array<(\1)>()",
        lowered,
    )
    lowered = re.sub(
        r"\[([A-Za-z_][A-Za-z0-9_\.]*)\]\(repeating:",
        r"Array<\1>(repeating:",
        lowered,
    )

    if "public func createEmitterBehavior(type: String) -> NSObject" in lowered:
        lowered = re.sub(
            r"public func createEmitterBehavior\(type: String\) -> NSObject\s*\{.*?\n\}",
            "public func createEmitterBehavior(type: String) -> NSObject {\n    _ = type\n    return NSObject()\n}",
            lowered,
            flags=re.DOTALL,
        )

    if "convenience init(cgImage: CGImage, scale: CGFloat, orientation: UIImage.Orientation)" in lowered:
        lowered = re.sub(
            r"\n\s*enum\s+Orientation\s*\{\s*case\s+up\s*case\s+down\s*\}\s*",
            "\n",
            lowered,
            flags=re.DOTALL,
        )
        lowered = re.sub(
            r"\n\s*public\s+extension\s+NSImage\s*\{\s*convenience\s+init\(cgImage:\s*CGImage,\s*scale:\s*CGFloat,\s*orientation:\s*UIImage\.Orientation\)\s*\{\s*self\.init\(cgImage:\s*cgImage,\s*size:\s*cgImage\.systemSize\)\s*\}\s*\}\s*",
            "\n",
            lowered,
            flags=re.DOTALL,
        )

    lowered = re.sub(r"(?m)^(\s*)import\s+IOKit\.ps\b", r"\1import IOKit", lowered)
    lowered = lowered.replace("memcpy(buffer, bytes.baseAddress,", "memcpy(buffer!, bytes.baseAddress!,")
    lowered = lowered.replace("memcpy(buffer, bytes,", "memcpy(buffer!, bytes,")
    lowered = lowered.replace("memcpy(bytes, tail, copiedCount)", "memcpy(bytes, tail!, copiedCount)")
    lowered = lowered.replace("memcpy(initialBuffer, buffer.mData,", "memcpy(initialBuffer!, buffer.mData!,")
    lowered = lowered.replace("buffer.mData?.advanced(by:", "buffer.mData!.advanced(by:")
    lowered = lowered.replace("CFRunLoopMode.defaultMode", "kCFRunLoopDefaultMode")
    lowered = re.sub(
        r"getxattr\(([^,]+),\s*([^,]+),\s*nil,\s*([^,]+),\s*0,\s*0\)",
        r"getxattr(\1, \2, nil, \3)",
        lowered,
    )
    lowered = re.sub(
        r"getxattr\(([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*0,\s*0\)",
        r"getxattr(\1, \2, \3, \4)",
        lowered,
    )
    lowered = re.sub(
        r"setxattr\(([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*0,\s*0\)",
        r"setxattr(\1, \2, \3, \4, 0)",
        lowered,
    )
    lowered = re.sub(
        r"removexattr\(([^,]+),\s*([^,]+),\s*0\)",
        r"removexattr(\1, \2)",
        lowered,
    )

    return lowered


def lower_objc_source(text: str) -> str:
    lowered = text.replace("__nonnull", "").replace("__nullable", "")
    lowered = re.sub(r"\*\s+\)", "*)", lowered)
    lowered = re.sub(r"\*\s+,", "*,", lowered)
    lowered = re.sub(r"(\bvoid\s*\*\s*[A-Za-z_][A-Za-z0-9_]*\s*=\s*)nil\b", r"\1NULL", lowered)
    lowered = re.sub(r"(\.impl\s*=\s*)nil;", r"\1NULL;", lowered)
    lowered = re.sub(
        r"getxattr\(([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*0,\s*0\)",
        r"getxattr(\1, \2, \3, \4)",
        lowered,
    )
    lowered = re.sub(
        r"setxattr\(([^,]+),\s*([^,]+),\s*([^,]+),\s*([^,]+),\s*0,\s*0\)",
        r"setxattr(\1, \2, \3, \4, 0)",
        lowered,
    )
    return lowered


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: lower-telegram-linux-source.py PACKAGE_DIR")

    package_dir = Path(sys.argv[1])
    # Packages keep Objective-C public headers OUTSIDE Sources/ (e.g. Stripe's
    # PublicHeaders/ carries __nonnull annotations), so lower those roots too.
    search_roots = [
        candidate
        for candidate in (package_dir / "Sources", package_dir / "PublicHeaders", package_dir / "include")
        if candidate.exists()
    ] or [package_dir]

    def walk(suffixes):
        for root in search_roots:
            for suffix in suffixes:
                yield from root.rglob(suffix)

    for swift_file in sorted(walk(("*.swift",))):
        try:
            text = swift_file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = swift_file.read_text(encoding="utf-8", errors="ignore")
        lowered = lower_swift_source(text)
        if lowered != text:
            swift_file.write_text(lowered, encoding="utf-8")

    for objc_file in sorted(walk(("*.h", "*.m", "*.mm"))):
        try:
            text = objc_file.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            text = objc_file.read_text(encoding="utf-8", errors="ignore")
        lowered = lower_objc_source(text)
        if lowered != text:
            objc_file.write_text(lowered, encoding="utf-8")


if __name__ == "__main__":
    main()
