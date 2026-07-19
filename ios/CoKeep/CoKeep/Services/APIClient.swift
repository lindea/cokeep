import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding
    case unauthorized
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding: return "Failed to decode response"
        case .unauthorized: return "Please sign in again"
        case .message(let msg): return msg
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    /// Simulator / local development. Replace for device or staging.
    var baseURL = URL(string: "http://localhost:3000")!
    var authToken: String?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: Encodable? = nil,
        query: [URLQueryItem] = [],
        authorized: Bool = true
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.message("No response") }

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            if let err = try? decoder.decode(ErrorBody.self, from: data) {
                throw APIError.message(err.error)
            }
            throw APIError.http(http.statusCode, text)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    func uploadImage(_ data: Data, filename: String = "photo.jpg") async throws -> String {
        let url = baseURL.appendingPathComponent("api/uploads")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.message("Upload failed")
        }
        let parsed = try decoder.decode(UploadResponse.self, from: responseData)
        return parsed.url
    }
}

private struct ErrorBody: Codable {
    let error: String
}

private struct UploadResponse: Codable {
    let url: String
}

private struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        self.encodeFunc = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
