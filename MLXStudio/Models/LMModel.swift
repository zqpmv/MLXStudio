import Foundation
import MLXLMCommon

enum ModelKind: String, Codable, Sendable {
    case llm
    case vlm
}

struct LMModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let configuration: ModelConfiguration
    let kind: ModelKind
    let parameterSize: String
    let description: String

    var huggingFaceID: String { configuration.name ?? id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LMModel, rhs: LMModel) -> Bool {
        lhs.id == rhs.id
    }

    init(
        id: String,
        displayName: String,
        configuration: ModelConfiguration,
        kind: ModelKind,
        parameterSize: String,
        description: String
    ) {
        self.id = id
        self.displayName = displayName
        self.configuration = configuration
        self.kind = kind
        self.parameterSize = parameterSize
        self.description = description
    }
}

enum ModelCatalog {
    static let featured: [LMModel] = [
        LMModel(
            id: "qwen3-0.6b",
            displayName: "Qwen3 0.6B",
            configuration: LLMRegistry.qwen3_0_6b_4bit,
            kind: .llm,
            parameterSize: "0.6B",
            description: "Ultra-light model for quick responses on any Mac."
        ),
        LMModel(
            id: "qwen3-1.7b",
            displayName: "Qwen3 1.7B",
            configuration: LLMRegistry.qwen3_1_7b_4bit,
            kind: .llm,
            parameterSize: "1.7B",
            description: "Balanced speed and quality for everyday chat."
        ),
        LMModel(
            id: "qwen3-4b",
            displayName: "Qwen3 4B",
            configuration: LLMRegistry.qwen3_4b_4bit,
            kind: .llm,
            parameterSize: "4B",
            description: "Strong general-purpose model with good reasoning."
        ),
        LMModel(
            id: "qwen3-8b",
            displayName: "Qwen3 8B",
            configuration: LLMRegistry.qwen3_8b_4bit,
            kind: .llm,
            parameterSize: "8B",
            description: "High-quality responses; needs 16GB+ unified memory."
        ),
        LMModel(
            id: "llama3.2-1b",
            displayName: "Llama 3.2 1B",
            configuration: LLMRegistry.llama3_2_1B_4bit,
            kind: .llm,
            parameterSize: "1B",
            description: "Meta's compact model, fast on Apple Silicon."
        ),
        LMModel(
            id: "gemma3-1b",
            displayName: "Gemma 3 1B",
            configuration: LLMRegistry.gemma3_1B_qat_4bit,
            kind: .llm,
            parameterSize: "1B",
            description: "Google's efficient model for local inference."
        ),
        LMModel(
            id: "smollm-135m",
            displayName: "SmolLM 135M",
            configuration: LLMRegistry.smolLM_135M_4bit,
            kind: .llm,
            parameterSize: "135M",
            description: "Tiny model for testing and low-memory devices."
        ),
        LMModel(
            id: "qwen2.5-1.5b",
            displayName: "Qwen2.5 1.5B",
            configuration: LLMRegistry.qwen2_5_1_5b,
            kind: .llm,
            parameterSize: "1.5B",
            description: "Previous-gen Qwen, stable and well-tested."
        ),
        LMModel(
            id: "phi4",
            displayName: "Phi-4 Mini",
            configuration: LLMRegistry.phi4bit,
            kind: .llm,
            parameterSize: "3.8B",
            description: "Microsoft's compact reasoning model."
        ),
        LMModel(
            id: "gemma3n-e2b",
            displayName: "Gemma 3n E2B",
            configuration: LLMRegistry.gemma3n_E2B_it_lm_4bit,
            kind: .llm,
            parameterSize: "2B",
            description: "Efficient Gemma variant optimized for edge devices."
        ),
    ]

    static func model(forHuggingFaceID id: String) -> LMModel? {
        featured.first { $0.huggingFaceID == id || $0.id == id }
    }

    static func custom(huggingFaceID: String) -> LMModel {
        LMModel(
            id: huggingFaceID,
            displayName: huggingFaceID.split(separator: "/").last.map(String.init) ?? huggingFaceID,
            configuration: ModelConfiguration(id: huggingFaceID),
            kind: .llm,
            parameterSize: "Unknown",
            description: "Custom model from Hugging Face."
        )
    }
}
