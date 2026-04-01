import Foundation

class APIService {
    static let shared = APIService()
    
    // Production API endpoint - Change this before deployment
    // Development: "http://localhost:8080/api/v1"
    // Production: "https://fast.toper.dev/api/v1"
    let baseURL = "https://fast.toper.dev/api/v1"
    
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    private init() {
        self.session = URLSession.shared
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - Generic Methods

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = AuthManager.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func get<R: Decodable>(endpoint: String) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        let (data, response) = try await session.data(for: authorizedRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else { throw APIError.serverError(httpResponse.statusCode) }
        return try decoder.decode(R.self, from: data)
    }

    func post<T: Encodable, R: Decodable>(
        endpoint: String,
        body: T,
        requiresAuth: Bool = true
    ) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        
        if requiresAuth {
            if let token = AuthManager.shared.getToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        return try decoder.decode(R.self, from: data)
    }
    
    // MARK: - Drive Methods

    func createDrive(_ drive: Drive) async throws -> Drive {
        return try await post(endpoint: "/drives", body: drive, requiresAuth: true)
    }

    func fetchDrives() async throws -> [Drive] {
        return try await get(endpoint: "/drives")
    }

    func fetchDrive(id: Int) async throws -> Drive {
        return try await get(endpoint: "/drives/\(id)")
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}
