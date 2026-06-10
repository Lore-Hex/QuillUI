import Foundation

private final class QuillLocalizationStore {
    private struct LocalizedTemplate {
        var value: String
        var pluralSubstitutions: [String: PluralSubstitution] = [:]
    }

    private struct PluralSubstitution {
        var one: String?
        var other: String?
    }

    static let shared = QuillLocalizationStore()

    private let lock = NSLock()
    private var loaded = false
    private var translations: [String: LocalizedTemplate] = [:]
    #if DEBUG
    private var testingCatalogURLs: [URL]?
    #endif

    func resolve(_ key: String, arguments: [String] = []) -> String {
        loadIfNeeded()
        lock.lock()
        let exact = translations[key]
        lock.unlock()

        if let exact {
            return format(exact, arguments: arguments)
        }

        if arguments.isEmpty,
           let dash = key.lastIndex(of: "-"),
           dash < key.index(before: key.endIndex) {
            let prefix = String(key[..<dash])
            let argument = String(key[key.index(after: dash)...])
            lock.lock()
            let interpolated = translations["\(prefix)-%@"]
            lock.unlock()
            if let interpolated {
                return format(interpolated, arguments: [argument])
            }
        }

        if arguments.isEmpty,
           let resolved = resolveFlattenedInterpolation(key) {
            return resolved
        }

        return key
    }

    #if DEBUG
    func configureForTesting(catalogURLs: [URL]?) {
        lock.lock()
        testingCatalogURLs = catalogURLs
        loaded = false
        translations = [:]
        lock.unlock()
    }
    #endif

    private func loadIfNeeded() {
        lock.lock()
        if loaded {
            lock.unlock()
            return
        }
        loaded = true
        lock.unlock()

        var loadedTranslations: [String: LocalizedTemplate] = [:]
        for url in localizationCatalogURLs() {
            loadCatalog(at: url, into: &loadedTranslations)
        }

        lock.lock()
        translations.merge(loadedTranslations) { current, _ in current }
        lock.unlock()
    }

    private func localizationCatalogURLs() -> [URL] {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        #if DEBUG
        lock.lock()
        let testingURLs = testingCatalogURLs
        lock.unlock()
        if let testingURLs {
            return testingURLs
        }
        #endif

        var urls: [URL] = []

        if let raw = ProcessInfo.processInfo.environment["QUILLUI_LOCALIZATION_PATHS"] {
            for path in raw.split(separator: ":").map(String.init) where !path.isEmpty {
                urls.append(URL(fileURLWithPath: path, relativeTo: cwd))
            }
        }

        urls.append(cwd.appendingPathComponent(".upstream/icecubes/IceCubesApp/Resources/Localization/Localizable.xcstrings"))
        urls.append(cwd.appendingPathComponent("Resources/Localization/Localizable.xcstrings"))
        urls.append(cwd.appendingPathComponent("Localizable.xcstrings"))
        return urls.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func loadCatalog(at url: URL, into translations: inout [String: LocalizedTemplate]) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else {
            return
        }

        let sourceLanguage = root["sourceLanguage"] as? String
        for (key, value) in strings {
            guard let item = value as? [String: Any],
                  let localizations = item["localizations"] as? [String: Any],
                  let localized = preferredValue(from: localizations, sourceLanguage: sourceLanguage) else {
                continue
            }
            translations[key] = localized
        }
    }

    private func preferredValue(from localizations: [String: Any], sourceLanguage: String?) -> LocalizedTemplate? {
        var preferred = Locale.preferredLanguages.flatMap { language -> [String] in
            var languages = [language]
            if let base = language.split(separator: "-").first.map(String.init),
               base != language {
                languages.append(base)
            }
            return languages
        }
        if let sourceLanguage {
            preferred.append(sourceLanguage)
        }
        preferred.append(contentsOf: ["en", "en-US", "en-GB"])

        var seen = Set<String>()
        for language in preferred where seen.insert(language).inserted {
            if let value = localizationTemplate(localizations[language]) {
                return value
            }
        }
        return nil
    }

    private func localizationTemplate(_ value: Any?) -> LocalizedTemplate? {
        guard let localization = value as? [String: Any],
              let stringUnit = localization["stringUnit"] as? [String: Any] else {
            return nil
        }
        guard let value = stringUnit["value"] as? String else {
            return nil
        }

        var template = LocalizedTemplate(value: value)
        if let substitutions = localization["substitutions"] as? [String: Any] {
            for (name, rawSubstitution) in substitutions {
                guard let substitution = rawSubstitution as? [String: Any],
                      let variations = substitution["variations"] as? [String: Any],
                      let plural = variations["plural"] as? [String: Any] else {
                    continue
                }
                template.pluralSubstitutions[name] = PluralSubstitution(
                    one: pluralString(in: plural["one"]),
                    other: pluralString(in: plural["other"])
                )
            }
        }
        return template
    }

    private func pluralString(in value: Any?) -> String? {
        guard let entry = value as? [String: Any],
              let stringUnit = entry["stringUnit"] as? [String: Any] else {
            return nil
        }
        return stringUnit["value"] as? String
    }

    private func format(_ template: LocalizedTemplate, arguments: [String]) -> String {
        var value = template.value
        for (name, substitution) in template.pluralSubstitutions {
            let count = arguments.first.flatMap { Double($0) } ?? 0
            let replacement = count == 1 ? (substitution.one ?? substitution.other) : (substitution.other ?? substitution.one)
            if let replacement {
                value = value.replacingOccurrences(of: "%#@\(name)@", with: replacement)
            }
        }
        return format(value, arguments: arguments)
    }

    private func format(_ template: String, arguments: [String]) -> String {
        guard !arguments.isEmpty else {
            return template
        }
        var result = template
        for (index, argument) in arguments.enumerated() {
            let position = index + 1
            for specifier in ["@", "lld", "llu", "ld", "lu", "d", "i", "f"] {
                result = result.replacingOccurrences(of: "%\(position)$\(specifier)", with: argument)
            }
        }

        var nextArgument = 0
        while nextArgument < arguments.count, let range = nextSequentialPlaceholder(in: result) {
            let argument = arguments[nextArgument]
            result.replaceSubrange(range, with: argument)
            nextArgument += 1
        }
        return result
    }

    private func nextSequentialPlaceholder(in string: String) -> Range<String.Index>? {
        let specifiers = ["%lld", "%llu", "%ld", "%lu", "%@", "%d", "%i", "%f"]
        var best: Range<String.Index>?
        for specifier in specifiers {
            guard let range = string.range(of: specifier) else {
                continue
            }
            if let current = best {
                if range.lowerBound < current.lowerBound {
                    best = range
                }
            } else {
                best = range
            }
        }
        return best
    }

    private func resolveFlattenedInterpolation(_ key: String) -> String? {
        let parts = key.split(separator: " ").map(String.init)
        guard parts.count > 1,
              let prefix = parts.first,
              prefix.contains(".") else {
            return nil
        }

        let arguments = Array(parts.dropFirst())
        let placeholders = arguments.map { argument in
            Int64(argument) != nil ? "%lld" : "%@"
        }
        let candidate = ([prefix] + placeholders).joined(separator: " ")

        lock.lock()
        let template = translations[candidate]
        lock.unlock()

        guard let template else {
            return nil
        }
        return format(template, arguments: arguments)
    }
}

public func quillResolveLocalizedString(_ key: String, arguments: [String] = []) -> String {
    QuillLocalizationStore.shared.resolve(key, arguments: arguments)
}

#if DEBUG
func quillConfigureLocalizationForTesting(catalogURLs: [URL]?) {
    QuillLocalizationStore.shared.configureForTesting(catalogURLs: catalogURLs)
}
#endif
