import Foundation
import MLXLMCommon

struct GenerationSettings: Equatable {
    var systemPrompt: String = "You are a helpful assistant."
    var extraInstructions: String = ""
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var topK: Int = 0
    var minP: Double = 0
    var maxTokens: Int = 2048
    var repetitionPenalty: Float = 1.0
    var presencePenalty: Double = 0
    var frequencyPenalty: Double = 0
    var useSeed: Bool = false
    var seed: UInt64 = 42

    var effectiveSystemPrompt: String {
        let extra = extraInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if extra.isEmpty { return systemPrompt }
        return systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + extra
    }

    var generateParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            temperature: Float(temperature),
            topP: Float(topP),
            topK: topK,
            minP: Float(minP),
            repetitionPenalty: repetitionPenalty > 1.0 ? repetitionPenalty : nil,
            presencePenalty: presencePenalty == 0 ? nil : Float(presencePenalty),
            frequencyPenalty: frequencyPenalty == 0 ? nil : Float(frequencyPenalty),
            seed: useSeed ? seed : nil
        )
    }
}

extension GenerationSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case systemPrompt, extraInstructions, temperature, topP, topK, minP
        case maxTokens, repetitionPenalty, presencePenalty, frequencyPenalty, useSeed, seed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? "You are a helpful assistant."
        extraInstructions = try container.decodeIfPresent(String.self, forKey: .extraInstructions) ?? ""
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.7
        topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? 0.9
        topK = try container.decodeIfPresent(Int.self, forKey: .topK) ?? 0
        minP = try container.decodeIfPresent(Double.self, forKey: .minP) ?? 0
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens) ?? 2048
        repetitionPenalty = try container.decodeIfPresent(Float.self, forKey: .repetitionPenalty) ?? 1.0
        presencePenalty = try container.decodeIfPresent(Double.self, forKey: .presencePenalty) ?? 0
        frequencyPenalty = try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty) ?? 0
        useSeed = try container.decodeIfPresent(Bool.self, forKey: .useSeed) ?? false
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? 42
    }
}

extension GenerationSettings {
    static var chat: GenerationSettings { GenerationSettings() }

    static var coding: GenerationSettings {
        var settings = GenerationSettings()
        settings.systemPrompt = "You are a senior software engineer. Write correct, concise code. Explain only when asked. Prefer complete, runnable answers."
        settings.temperature = 0.2
        settings.topP = 0.95
        settings.maxTokens = 4096
        settings.repetitionPenalty = 1.05
        return settings
    }

    static var precise: GenerationSettings {
        var settings = GenerationSettings()
        settings.systemPrompt = "Answer accurately and concisely. If you are unsure, say so. Do not invent facts."
        settings.temperature = 0.1
        settings.topP = 0.8
        settings.maxTokens = 2048
        return settings
    }

    static var creative: GenerationSettings {
        var settings = GenerationSettings()
        settings.systemPrompt = "Be imaginative and expressive while staying on topic. Vary phrasing and offer original ideas."
        settings.temperature = 1.1
        settings.topP = 0.95
        settings.maxTokens = 3072
        return settings
    }

    static var reasoning: GenerationSettings {
        var settings = GenerationSettings()
        settings.systemPrompt = "Think step by step. Show brief reasoning, then give a clear final answer."
        settings.temperature = 0.4
        settings.topP = 0.9
        settings.maxTokens = 4096
        return settings
    }
}
