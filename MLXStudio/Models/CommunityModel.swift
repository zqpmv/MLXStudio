import Foundation

struct CommunityModel: Identifiable, Hashable, Sendable {
    let id: String
    let downloads: Int
    let likes: Int
    let tags: [String]
    let pipelineTag: String?

    var displayName: String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    var huggingFaceURL: URL {
        URL(string: "https://huggingface.co/\(id)")!
    }

    func asLMModel() -> LMModel {
        ModelCatalog.custom(huggingFaceID: id)
    }
}

struct HuggingFaceModelDTO: Decodable {
    let id: String
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
    let pipelineTag: String?
    let isPrivate: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case downloads
        case likes
        case tags
        case pipelineTag = "pipeline_tag"
        case isPrivate = "private"
    }

    func asCommunityModel() -> CommunityModel? {
        guard isPrivate != true, id.contains("/") else { return nil }
        return CommunityModel(
            id: id,
            downloads: downloads ?? 0,
            likes: likes ?? 0,
            tags: tags ?? [],
            pipelineTag: pipelineTag
        )
    }
}
