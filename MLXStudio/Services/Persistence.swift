import Foundation

struct PersistedAppState: Codable {
    var conversations: [Conversation]
    var selectedConversationID: UUID?
    var generationSettings: GenerationSettings
    var serverSettings: ServerSettings
    var selectedModelID: String
    var customHuggingFaceIDs: [String]
    var customPresets: [InferencePreset]?
    var selectedPresetID: UUID?
    var gpuCacheLimitMB: Int?
}

enum Persistence {
    static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MLXStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("state.json")
    }

    static func load() -> PersistedAppState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedAppState.self, from: data)
    }

    static func save(_ state: PersistedAppState) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
