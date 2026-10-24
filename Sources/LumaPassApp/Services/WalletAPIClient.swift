import Foundation
import LumaPassCore

struct WalletAPIClient {
    private var baseURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "LumaPassAPIBaseURL") as? String,
            !value.isEmpty,
            let url = URL(string: value),
            url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1"
        else {
            return nil
        }
        return url
    }

    var isConfigured: Bool { baseURL != nil }

    func issue(_ draft: PassDraft, identityToken: String?) async throws -> Data {
        guard let baseURL else {
            throw WalletAPIError.demoConfiguration
        }
        let endpoint = baseURL.appending(path: "/api/v1/passes")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let identityToken {
            request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encodedContent(draft)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WalletAPIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw WalletAPIError.server(status: httpResponse.statusCode, message: apiError?.detail ?? "No se pudo generar el pase.")
        }
        guard httpResponse.value(forHTTPHeaderField: "Content-Type")?.contains("application/vnd.apple.pkpass") == true else {
            throw WalletAPIError.invalidResponse
        }
        return data
    }

    func syncPrivateDraft(_ draft: PassDraft, identityToken: String) async throws -> PrivateDraftSyncResponse {
        guard let baseURL else { throw WalletAPIError.demoConfiguration }
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/drafts/\(draft.id.uuidString)"))
        request.httpMethod = "PUT"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encodedContent(draft)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
        return try JSONDecoder().decode(PrivateDraftSyncResponse.self, from: data)
    }

    func deleteAccount(identityToken: String) async throws -> String {
        guard let baseURL else { throw WalletAPIError.demoConfiguration }
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
        return try JSONDecoder().decode(AccountDeleteResponse.self, from: data).walletNotifications
    }

    func loadCommunityAssets(
        query: String,
        category: String?,
        order: String,
        identityToken: String?
    ) async throws -> [CommunityAssetResponse] {
        guard let baseURL else { throw WalletAPIError.demoConfiguration }
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/community/assets"), resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "order", value: order)]
        if let category { queryItems.append(URLQueryItem(name: "category", value: category)) }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw WalletAPIError.invalidResponse }
        var request = URLRequest(url: url)
        if let identityToken {
            request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
        return try JSONDecoder().decode(CommunityAssetsResponse.self, from: data).items
    }

    func reportCommunityAsset(
        id: String,
        reason: String,
        identityToken: String
    ) async throws {
        guard let baseURL else { throw WalletAPIError.demoConfiguration }
        guard UUID(uuidString: id) != nil else { throw WalletAPIError.notCommunityAsset }
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/community/assets/\(id)/report"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["reason": reason, "detail": "Reporte desde la app"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
    }

    func favoriteCommunityAsset(id: String, isFavorite: Bool, identityToken: String) async throws {
        guard let baseURL, UUID(uuidString: id) != nil else { throw WalletAPIError.notCommunityAsset }
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/community/assets/\(id)/favorite"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["isFavorite": isFavorite])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
    }

    func recordCommunityAssetUse(id: String, identityToken: String?) async throws {
        guard let baseURL, UUID(uuidString: id) != nil else { throw WalletAPIError.notCommunityAsset }
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/community/assets/\(id)/use"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let identityToken {
            request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
    }

    func blockCommunityCreator(assetID: String, identityToken: String) async throws {
        guard let baseURL, UUID(uuidString: assetID) != nil else { throw WalletAPIError.notCommunityAsset }
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/community/assets/\(assetID)/block-author"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
    }

    func downloadCommunityImage(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              httpResponse.value(forHTTPHeaderField: "Content-Type")?.starts(with: "image/") == true,
              data.count <= 8 * 1_024 * 1_024
        else {
            throw WalletAPIError.invalidResponse
        }
        return data
    }

    func uploadCommunityAsset(
        imageData: Data,
        title: String,
        description: String,
        category: String,
        license: String,
        identityToken: String
    ) async throws {
        guard let baseURL else { throw WalletAPIError.demoConfiguration }
        let boundary = "LumaPass-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/community/assets"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(identityToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func appendText(_ text: String) {
            if let data = text.data(using: .utf8) { body.append(data) }
        }
        func appendField(_ name: String, _ value: String) {
            appendText("--\(boundary)\r\n")
            appendText("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            appendText("\(value)\r\n")
        }
        appendField("title", title)
        appendField("description", description)
        appendField("category", category)
        appendField("license", license)
        appendField("rights_confirmed", "true")
        appendField("tags", "")
        appendText("--\(boundary)\r\n")
        appendText("Content-Disposition: form-data; name=\"file\"; filename=\"fondo.jpg\"\r\n")
        appendText("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        appendText("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
    }

    private func encodedContent(_ draft: PassDraft) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(IssuePassRequest(draft: draft))
    }

    private func check(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { throw WalletAPIError.invalidResponse }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw WalletAPIError.server(
                status: httpResponse.statusCode,
                message: apiError?.detail ?? "El servicio no pudo completar la solicitud."
            )
        }
    }
}

private struct IssuePassRequest: Encodable {
    let draftId: UUID
    let type: String
    let title: String
    let organization: String
    let primaryLabel: String
    let primaryValue: String
    let secondaryLabel: String
    let secondaryValue: String
    let additionalLabel: String
    let additionalValue: String
    let barcodeValue: String
    let barcodeKind: String
    let backgroundHex: String
    let foregroundHex: String
    let expiresAt: Date?
    let image: String?

    init(draft: PassDraft) throws {
        draftId = draft.id
        type = draft.kind.rawValue
        title = draft.title
        organization = draft.organization
        primaryLabel = draft.primaryLabel
        primaryValue = draft.primaryValue
        secondaryLabel = draft.secondaryLabel
        secondaryValue = draft.secondaryValue
        additionalLabel = draft.additionalLabel
        additionalValue = draft.additionalValue
        barcodeValue = draft.barcodeValue
        barcodeKind = draft.barcodeKind.rawValue
        backgroundHex = draft.backgroundHex
        foregroundHex = draft.foregroundHex
        expiresAt = draft.expiresAt
        image = try PassArtworkRenderer.preparePassArt(draft)?.base64EncodedString()
    }
}

struct PrivateDraftSyncResponse: Decodable {
    let updatedPasses: Int
    let walletNotifications: String
}

private struct AccountDeleteResponse: Decodable {
    let walletNotifications: String
}

struct CommunityAssetResponse: Decodable, Identifiable, Sendable {
    let id: String
    let creatorId: String
    let title: String
    let description: String
    let category: String
    let tags: [String]
    let dominantColors: [String]
    let license: String
    let uses: Int
    let imageURL: URL
}

private struct CommunityAssetsResponse: Decodable {
    let items: [CommunityAssetResponse]
}

private struct APIErrorResponse: Decodable {
    let detail: String?
}

enum WalletAPIError: LocalizedError {
    case demoConfiguration
    case invalidResponse
    case notCommunityAsset
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .demoConfiguration:
            "La demo guarda tus diseños en este dispositivo. Para emitir un pase real, configura el backend seguro con credenciales de Pass Type ID de Apple; nunca introduzcas esos certificados en la app."
        case .invalidResponse:
            "El servidor devolvió una respuesta que no es un pase Apple Wallet válido."
        case .notCommunityAsset:
            "Esta plantilla de demostración no es un fondo subido por la comunidad."
        case let .server(status, message):
            "No se pudo generar el pase (\(status)): \(message)"
        }
    }
}
