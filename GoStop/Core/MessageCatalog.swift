import Foundation
import Yams

final class MessageCatalog {
    static let shared = MessageCatalog()

    private let defaultLocale: String
    private let locales: [String: [String: Any]]

    private init(fileManager: FileManager = .default) {
        let fallbackLocale = "ko"
        guard let url = Self.resolveFileURL(fileManager: fileManager) else {
            self.defaultLocale = fallbackLocale
            self.locales = [:]
            fputs("MessageCatalog: message.yaml not found. Falling back to raw keys.\n", stderr)
            return
        }

        do {
            let yamlString = try String(contentsOf: url, encoding: .utf8)
            let loaded = try Yams.load(yaml: yamlString)
            let normalizedRoot = Self.normalizeYAMLValue(loaded)
            guard let root = normalizedRoot as? [String: Any] else {
                self.defaultLocale = fallbackLocale
                self.locales = [:]
                fputs("MessageCatalog: Invalid root structure in \(url.path)\n", stderr)
                return
            }

            self.defaultLocale = (root["default_locale"] as? String)?.lowercased() ?? fallbackLocale

            var parsedLocales: [String: [String: Any]] = [:]
            if let localeRoot = root["locales"] as? [String: Any] {
                for (locale, value) in localeRoot {
                    if let dict = value as? [String: Any] {
                        parsedLocales[locale.lowercased()] = dict
                    }
                }
            }
            self.locales = parsedLocales
        } catch {
            self.defaultLocale = fallbackLocale
            self.locales = [:]
            fputs("MessageCatalog: Failed to parse \(url.path): \(error)\n", stderr)
        }
    }

    func text(_ key: String, _ params: [String: Any] = [:]) -> String {
        let locale = selectedLocale()
        let template =
            template(for: key, locale: locale) ??
            template(for: key, locale: defaultLocale) ??
            key
        return interpolate(template: template, params: params)
    }

    private func selectedLocale() -> String {
        if let override = ProcessInfo.processInfo.environment["GOSTOP_LANGUAGE"],
           let normalized = normalizeLocaleIdentifier(override),
           locales[normalized] != nil {
            return normalized
        }
        let configuredLanguage = ConfigurationStore.shared.appLanguage()
        if let normalized = normalizeLocaleIdentifier(configuredLanguage),
           locales[normalized] != nil {
            return normalized
        }
        return defaultLocale
    }

    private func template(for key: String, locale: String) -> String? {
        guard var current: Any = locales[locale] else { return nil }
        for component in key.split(separator: ".").map(String.init) {
            guard let dict = current as? [String: Any],
                  let next = dict[component] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    private func interpolate(template: String, params: [String: Any]) -> String {
        params.reduce(template) { partial, entry in
            partial.replacingOccurrences(
                of: "{\(entry.key)}",
                with: String(describing: entry.value)
            )
        }
    }

    private func normalizeLocaleIdentifier(_ raw: String) -> String? {
        let normalized = raw
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
        if locales[normalized] != nil {
            return normalized
        }
        if let base = normalized.split(separator: "_").first.map(String.init),
           locales[base] != nil {
            return base
        }
        return nil
    }

    private static func resolveFileURL(fileManager: FileManager) -> URL? {
        if let overridePath = ProcessInfo.processInfo.environment["GOSTOP_MESSAGE_PATH"],
           !overridePath.isEmpty,
           fileManager.fileExists(atPath: overridePath) {
            return URL(fileURLWithPath: overridePath)
        }

        if let bundleURL = Bundle.main.url(forResource: "message", withExtension: "yaml") {
            return bundleURL
        }

        let roots = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        ]

        for root in roots {
            for directory in ancestorDirectories(startingAt: root, maxDepth: 6) {
                let candidates = [
                    directory.appendingPathComponent("message.yaml"),
                    directory.appendingPathComponent("GoStop/Resources/message.yaml")
                ]
                if let found = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
                    return found
                }
            }
        }

        return nil
    }

    private static func normalizeYAMLValue(_ value: Any?) -> Any {
        guard let value else { return [:] }
        if let dict = value as? [String: Any] {
            return dict.mapValues(normalizeYAMLValue)
        }
        if let dict = value as? [AnyHashable: Any] {
            return Dictionary(uniqueKeysWithValues: dict.map {
                (String(describing: $0.key), normalizeYAMLValue($0.value))
            })
        }
        if let array = value as? [Any] {
            return array.map(normalizeYAMLValue)
        }
        return value
    }

    private static func ancestorDirectories(startingAt root: URL, maxDepth: Int) -> [URL] {
        var directories: [URL] = []
        var current = root.standardizedFileURL
        var depth = 0

        while depth <= maxDepth {
            directories.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
            depth += 1
        }

        return directories
    }
}

@inline(__always)
func gameText(_ key: String, _ params: [String: Any] = [:]) -> String {
    MessageCatalog.shared.text(key, params)
}
