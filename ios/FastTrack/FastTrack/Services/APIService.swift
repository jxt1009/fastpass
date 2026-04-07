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
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else { throw APIError.serverError(httpResponse.statusCode) }
        return try decoder.decode(R.self, from: data)
    }

    func put<T: Encodable, R: Decodable>(endpoint: String, body: T) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = AuthManager.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.serverError(http.statusCode) }
        return try decoder.decode(R.self, from: data)
    }

    func delete(endpoint: String) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = AuthManager.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.serverError(http.statusCode) }
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

    func updateDrive(_ drive: Drive) async throws -> Drive {
        return try await put(endpoint: "/drives/\(drive.id)", body: drive)
    }

    func updateDriveCarAssignment(driveId: Int, car: UserCar) async throws -> Drive {
        struct UpdateCarRequest: Encodable {
            let carId: String?
            let carMake: String?
            let carModel: String?
            let carYear: Int?
            let carTrim: String?
            let carNickname: String?

            enum CodingKeys: String, CodingKey {
                case carId       = "car_id"
                case carMake     = "car_make"
                case carModel    = "car_model"
                case carYear     = "car_year"
                case carTrim     = "car_trim"
                case carNickname = "car_nickname"
            }
        }
        let req = UpdateCarRequest(
            carId: car.id,
            carMake: car.make,
            carModel: car.model,
            carYear: car.year,
            carTrim: car.trim,
            carNickname: car.nickname
        )
        return try await put(endpoint: "/drives/\(driveId)", body: req)
    }

    // MARK: - Profile Methods

    func updateProfile(_ profile: UserProfile) async throws {
        struct UpdateProfileRequest: Encodable {
            let username: String
            let country: String
            let isPublic: Bool
            // Legacy fields for backward compatibility
            let carMake: String
            let carModel: String
            let carYear: Int?
            let carTrim: String
            // New garage fields
            let garage: String
            let selectedCarID: String?

            enum CodingKeys: String, CodingKey {
                case username, country
                case isPublic      = "is_public"
                case carMake       = "car_make"
                case carModel      = "car_model"
                case carYear       = "car_year"
                case carTrim       = "car_trim"
                case garage
                case selectedCarID = "selected_car_id"
            }
        }

        let garageData = try JSONEncoder().encode(profile.garage)
        let garageString = String(data: garageData, encoding: .utf8) ?? "[]"

        let req = UpdateProfileRequest(
            username: profile.username,
            country: profile.country,
            isPublic: profile.isPublic,
            carMake: profile.carMake,
            carModel: profile.carModel,
            carYear: profile.carYear,
            carTrim: profile.carTrim,
            garage: garageString,
            selectedCarID: profile.selectedCarId
        )
        let _: User = try await put(endpoint: "/profile", body: req)
    }

    func fetchMe() async throws -> User {
        return try await get(endpoint: "/me")
    }

    func fetchCarStats() async throws -> String {
        // Returns raw JSON string of the stats blob
        let url = URL(string: baseURL + "/api/v1/stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = AuthManager.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func uploadCarStats(_ statsJSON: String) async throws {
        struct Req: Encodable { let statsData: String; enum CodingKeys: String, CodingKey { case statsData = "stats_data" } }
        struct Res: Decodable { let ok: Bool }
        let _: Res = try await put(endpoint: "/stats", body: Req(statsData: statsJSON))
    }

    func uploadDisplaySettings(unitSystem: String, colorScheme: String) async throws {
        struct Req: Encodable {
            let unitSystem: String
            let colorScheme: String
            enum CodingKeys: String, CodingKey {
                case unitSystem  = "unit_system"
                case colorScheme = "color_scheme"
            }
        }
        struct Res: Decodable { let ok: Bool }
        let _: Res = try await put(endpoint: "/display-settings",
                                   body: Req(unitSystem: unitSystem, colorScheme: colorScheme))
    }

    // MARK: - Social Methods

    func fetchLeaderboard(
        category: LeaderboardCategory,
        scope: LeaderboardScope = .global,
        period: LeaderboardPeriod = .allTime,
        carMake: String = "",
        carModel: String = ""
    ) async throws -> [LeaderboardEntry] {
        var endpoint = "/leaderboard?category=\(category.rawValue)&scope=\(scope.rawValue)&period=\(period.rawValue)"
        if !carMake.isEmpty, let enc = carMake.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "&car_make=\(enc)"
        }
        if !carModel.isEmpty, let enc = carModel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            endpoint += "&car_model=\(enc)"
        }
        return try await get(endpoint: endpoint)
    }

    func fetchPublicProfile(username: String) async throws -> PublicProfile {
        return try await get(endpoint: "/users/\(username)")
    }

    func followUser(username: String) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await post(endpoint: "/users/\(username)/follow", body: _EmptyBody())
    }

    func unfollowUser(username: String) async throws {
        try await delete(endpoint: "/users/\(username)/follow")
    }

    func searchUsers(query: String) async throws -> [UserSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get(endpoint: "/users/search?q=\(encoded)")
    }

    func uploadAvatar(imageData: Data) async throws {
        struct Req: Encodable { let imageData: String; enum CodingKeys: String, CodingKey { case imageData = "image_data" } }
        struct Res: Decodable { let avatarURL: String; enum CodingKeys: String, CodingKey { case avatarURL = "avatar_url" } }
        let _: Res = try await put(endpoint: "/profile/avatar", body: Req(imageData: imageData.base64EncodedString()))
    }
}

private struct _EmptyBody: Encodable {}

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
