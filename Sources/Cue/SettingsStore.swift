import Foundation

final class SettingsStore {
    let directoryURL: URL
    let settingsURL: URL

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directoryURL = directoryURL ?? applicationSupport.appendingPathComponent("Cue", isDirectory: true)
        settingsURL = self.directoryURL.appendingPathComponent("settings.json")
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return AppSettings() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let direct = try? decoder.decode(AppSettings.self, from: data) { return direct }

        // Forward-fill new top-level settings keys so adding a preference in
        // a later Cue build never discards workspace paths from an older
        // settings file merely because synthesized Codable sees a missing key.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let defaultsData = try? encoder.encode(AppSettings()),
              var defaults = (try? JSONSerialization.jsonObject(with: defaultsData)) as? [String: Any],
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return AppSettings()
        }
        for (key, value) in saved { defaults[key] = value }
        guard let merged = try? JSONSerialization.data(withJSONObject: defaults) else { return AppSettings() }
        return (try? decoder.decode(AppSettings.self, from: merged)) ?? AppSettings()
    }

    func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }
}
