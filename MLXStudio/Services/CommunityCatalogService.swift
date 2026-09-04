import Foundation
import Observation

enum CommunityCatalogStatus: Equatable {
    case idle
    case loading
    case error(String)
}

@Observable
@MainActor
final class CommunityCatalogService {
    var models: [CommunityModel] = []
    var status: CommunityCatalogStatus = .idle
    var searchQuery = ""
    var hasMore = false

    private var nextURL: URL?
    private var isFetching = false

    func refresh() async {
        models = []
        nextURL = nil
        hasMore = false
        await fetch(search: trimmedSearch, url: nil)
    }

    func loadMoreIfNeeded() async {
        guard hasMore, let nextURL, !isFetching else { return }
        await fetch(search: nil, url: nextURL)
    }

    private var trimmedSearch: String? {
        let value = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func fetch(search: String?, url existing: URL?) async {
        guard !isFetching else { return }
        isFetching = true
        status = .loading

        do {
            let requestURL: URL
            if let existing {
                requestURL = existing
            } else {
                var components = URLComponents(string: "https://huggingface.co/api/models")!
                var items: [URLQueryItem] = [
                    URLQueryItem(name: "limit", value: "20"),
                    URLQueryItem(name: "author", value: "mlx-community"),
                    URLQueryItem(name: "sort", value: "downloads"),
                    URLQueryItem(name: "pipeline_tag", value: "text-generation"),
                ]
                if let search {
                    items.append(URLQueryItem(name: "search", value: search))
                }
                components.queryItems = items
                guard let url = components.url else {
                    throw URLError(.badURL)
                }
                requestURL = url
            }

            var request = URLRequest(url: requestURL)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let decoded = try JSONDecoder().decode([HuggingFaceModelDTO].self, from: data)
            let page = decoded.compactMap { $0.asCommunityModel() }
            if existing == nil {
                models = page
            } else {
                let seen = Set(models.map(\.id))
                models.append(contentsOf: page.filter { !seen.contains($0.id) })
            }

            if let link = http.value(forHTTPHeaderField: "Link") {
                nextURL = Self.parseNextLink(link)
            } else {
                nextURL = nil
            }
            hasMore = nextURL != nil
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }

        isFetching = false
    }

    private static func parseNextLink(_ header: String) -> URL? {
        for part in header.split(separator: ",") {
            let bits = part.split(separator: ";")
            guard bits.count >= 2 else { continue }
            let urlPart = bits[0].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            let rel = bits[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if rel.contains("rel=\"next\"") || rel.contains("rel=next") {
                return URL(string: urlPart)
            }
        }
        return nil
    }
}
