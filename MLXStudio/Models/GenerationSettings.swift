import Foundation
import MLXLMCommon

struct GenerationSettings: Codable, Equatable {
    var systemPrompt: String = "You are a helpful assistant."
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var maxTokens: Int = 2048
    var repetitionPenalty: Float = 1.0

    var generateParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: maxTokens,
            temperature: Float(temperature),
            topP: Float(topP),
            repetitionPenalty: repetitionPenalty
        )
    }
}
