import Foundation

struct InferencePreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var summary: String
    var settings: GenerationSettings
    var isBuiltIn: Bool

    static let chatID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let codingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let preciseID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let creativeID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let reasoningID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!

    static let builtIn: [InferencePreset] = [
        InferencePreset(
            id: chatID,
            name: "Chat",
            summary: "Balanced everyday answers",
            settings: .chat,
            isBuiltIn: true
        ),
        InferencePreset(
            id: codingID,
            name: "Coding",
            summary: "Low temperature, precise code",
            settings: .coding,
            isBuiltIn: true
        ),
        InferencePreset(
            id: preciseID,
            name: "Precise",
            summary: "Factual, short, low randomness",
            settings: .precise,
            isBuiltIn: true
        ),
        InferencePreset(
            id: creativeID,
            name: "Creative",
            summary: "Higher temperature, varied phrasing",
            settings: .creative,
            isBuiltIn: true
        ),
        InferencePreset(
            id: reasoningID,
            name: "Reasoning",
            summary: "Step-by-step answers, longer output",
            settings: .reasoning,
            isBuiltIn: true
        ),
    ]
}

enum DeveloperPane: String, CaseIterable, Identifiable, Hashable {
    case inference = "Inference"
    case presets = "Presets"
    case playground = "Playground"
    case server = "Local Server"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inference: "slider.horizontal.3"
        case .presets: "square.stack"
        case .playground: "terminal"
        case .server: "network"
        }
    }

    var subtitle: String {
        switch self {
        case .inference: "System prompt and sampling"
        case .presets: "Tune the model for a task"
        case .playground: "Test a request with current settings"
        case .server: "mlx-lm local API"
        }
    }
}
