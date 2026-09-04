import Foundation

/// How a model's thinking on/off preference is expressed to its chat template.
/// Mirrors mlx-swift-lm `ReasoningPromptStrategy` (not yet in the 3.31.4 release).
enum ReasoningPromptStrategy: Sendable, Equatable {
    case templateFlag(key: String, defaultOn: Bool)
    case alwaysOn
    case none

    func additionalContext(forThinkingEnabled thinkingEnabled: Bool?) throws -> [String: any Sendable]? {
        switch self {
        case .templateFlag(let key, let defaultOn):
            return [key: thinkingEnabled ?? defaultOn]
        case .alwaysOn:
            if thinkingEnabled == false { throw ReasoningError.cannotDisableReasoning }
            return nil
        case .none:
            if thinkingEnabled == false { throw ReasoningError.cannotDisableReasoning }
            return nil
        }
    }
}

enum ReasoningError: Error, Equatable {
    case cannotDisableReasoning
}

/// Describes a model's chain-of-thought protocol.
/// Mirrors mlx-swift-lm `ReasoningConfig`.
struct ReasoningConfig: Sendable, Equatable {
    var startDelimiter: String
    var endDelimiter: String
    var promptStrategy: ReasoningPromptStrategy
    var implicitEndDelimiters: [String]

    init(
        startDelimiter: String,
        endDelimiter: String,
        promptStrategy: ReasoningPromptStrategy,
        implicitEndDelimiters: [String] = []
    ) {
        self.startDelimiter = startDelimiter
        self.endDelimiter = endDelimiter
        self.promptStrategy = promptStrategy
        self.implicitEndDelimiters = implicitEndDelimiters
    }

    static let thinkTagsWithEnableThinking = ReasoningConfig(
        startDelimiter: "<think>",
        endDelimiter: "</think>",
        promptStrategy: .templateFlag(key: "enable_thinking", defaultOn: true)
    )

    static let alwaysOnThinking = ReasoningConfig(
        startDelimiter: "<think>",
        endDelimiter: "</think>",
        promptStrategy: .alwaysOn
    )

    static let none = ReasoningConfig(
        startDelimiter: "<think>",
        endDelimiter: "</think>",
        promptStrategy: .none
    )
}
