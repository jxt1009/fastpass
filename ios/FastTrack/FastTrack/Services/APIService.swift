import Foundation
import Combine

class APIService: ObservableObject {
    #if DEBUG
    let baseURL = "https://fast.toper.dev/api/v1"
    #else
    let baseURL = "https://fast.toper.dev/api/v1"
    #endif

    let session: URLSession
    let sessionDelegate: PinningURLSessionDelegate
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    var inflightFetchDrives: Task<[Drive], Error>?
    weak var authManager: AuthManager? {
        didSet { sessionDelegate.authManager = authManager }
    }

    /// Decodes ISO 8601 dates with or without fractional seconds.
    /// The default `.iso8601` strategy rejects fractional seconds (e.g.
    /// `2026-06-18T12:34:56.789Z`), which some backend endpoints produce.
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)

        if let date = iso8601Formatter.date(from: dateString) { return date }
        if let date = fractionalFormatter.date(from: dateString) { return date }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unrecognized date format: \(dateString)"
        )
    }

    init(authManager: AuthManager? = nil) {
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024,
                                   diskCapacity: 250 * 1024 * 1024,
                                   diskPath: "fasttrack.avatar.cache")
        let delegate = PinningURLSessionDelegate()
        self.sessionDelegate = delegate
        self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = Self.dateDecodingStrategy
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.authManager = authManager
    }

    /// Test seam: inject a pre-built `URLSession` (and its delegate) so tests
    /// can install a `URLProtocol` via `configuration.protocolClasses`, which
    /// is more reliable than process-global `URLProtocol.registerClass` on
    /// some SDKs and avoids the persistent `URLCache`. Internal so it isn't
    /// part of the public API surface.
    internal init(session: URLSession, sessionDelegate: PinningURLSessionDelegate, authManager: AuthManager? = nil) {
        self.sessionDelegate = sessionDelegate
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = Self.dateDecodingStrategy
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.authManager = authManager
    }

    // MARK: - Generic Methods

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if let token = authManager?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Signs the user out and shows a "Session expired" toast. Called when
    /// token refresh fails or the retry request also returns 401.
    private func signOutAndToast() async {
        await MainActor.run {
            self.authManager?.signOut()
            ToastManager.shared.show(ToastMessage(text: "Session expired"))
        }
    }

    /// Executes `request`, and if the response is 401 on an authenticated
    /// request, attempts to refresh the access token and retries once. If the
    /// refresh fails, or the retry also returns 401, signs the user out and
    /// shows a "Session expired" toast. Non-401 retry errors surface as-is.
    private func executeWithRefreshRetry<R: Decodable>(
        _ request: URLRequest,
        decode: (Data) throws -> R
    ) async throws -> R {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if httpResponse.statusCode == 401,
           request.value(forHTTPHeaderField: "Authorization") != nil {
            do {
                try await authManager?.refreshTokenIfNeeded()
            } catch {
                await signOutAndToast()
                throw APIError.serverError(401)
            }
            var retryRequest = request
            if let token = authManager?.getToken() {
                retryRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (retryData, retryResponse) = try await session.data(for: retryRequest)
            guard let retryHttp = retryResponse as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200...299).contains(retryHttp.statusCode) else {
                if retryHttp.statusCode == 401 {
                    await signOutAndToast()
                }
                throw APIError.serverError(retryHttp.statusCode)
            }
            return try decode(retryData)
        }

        guard (200...299).contains(httpResponse.statusCode) else { throw APIError.serverError(httpResponse.statusCode) }
        return try decode(data)
    }

    func get<R: Decodable>(endpoint: String) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        return try await executeWithRefreshRetry(authorizedRequest(url: url)) { data in
            try self.decoder.decode(R.self, from: data)
        }
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
            if let token = authManager?.getToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            return try await executeWithRefreshRetry(request) { data in
                try self.decoder.decode(R.self, from: data)
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
        if let token = authManager?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        return try await executeWithRefreshRetry(request) { data in
            try self.decoder.decode(R.self, from: data)
        }
    }

    func delete(endpoint: String) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = authManager?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let _: NoDecodable = try await executeWithRefreshRetry(request) { _ in NoDecodable() }
    }

    func delete<T: Encodable>(endpoint: String, body: T) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authManager?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)
        let _: NoDecodable = try await executeWithRefreshRetry(request) { _ in NoDecodable() }
    }

    // MARK: - Drive Methods

    func createDrive(_ drive: Drive) async throws -> Drive {
        struct Envelope: Decodable {
            let drive: Drive
            let unlockedAchievements: [UserAchievement]

            enum CodingKeys: String, CodingKey {
                case drive
                case unlockedAchievements = "unlocked_achievements"
            }
        }
        let url = URL(string: "\(baseURL)/drives")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authManager?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let driveData = try encoder.encode(drive)
        var bodyDict = try JSONSerialization.jsonObject(with: driveData) as? [String: Any] ?? [:]
        bodyDict["route_data_v2"] = drive.routeData.flatMap { str -> Any? in
            guard let data = str.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return json
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        return try await executeWithRefreshRetry(request) { data in
            if let envelope = try? self.decoder.decode(Envelope.self, from: data) {
                return envelope.drive
            }
            return try self.decoder.decode(Drive.self, from: data)
        }
    }

    func fetchDrives() async throws -> [Drive] {
        if let task = inflightFetchDrives {
            return try await task.value
        }
        let task = Task<[Drive], Error> {
            defer { Task { @MainActor in self.inflightFetchDrives = nil } }
            return try await performFetchDrives()
        }
        await MainActor.run { self.inflightFetchDrives = task }
        return try await task.value
    }

    private func performFetchDrives() async throws -> [Drive] {
        // Cache-bust: add a time-based query param to avoid stale URLCache responses
        let drives: [Drive] = try await get(endpoint: "/drives?t=\(Int(Date().timeIntervalSince1970))")
        #if DEBUG
        if let first = drives.first {
            print("📡 fetchDrives: first drive id=\(first.id ?? -1), userID=\(first.userID), maxSpeed=\(first.maxSpeed)")
        } else {
            print("📡 fetchDrives: empty list")
        }
        #endif
        return drives
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

    func deleteDrive(id: Int) async throws {
        try await delete(endpoint: "/drives/\(id)")
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

    func fetchMyAchievements() async throws -> UserAchievementsResponse {
        return try await get(endpoint: "/me/achievements")
    }

    func fetchUserAchievements(username: String) async throws -> UserAchievementsResponse {
        let encoded = Self.percentEncodePathSegment(username)
        return try await get(endpoint: "/users/\(encoded)/achievements")
    }

    func fetchPublicDrive(id: Int) async throws -> Drive {
        return try await get(endpoint: "/drives/\(id)/public")
    }

    func fetchCarStats() async throws -> String {
        // Returns raw JSON string of the stats blob
        let url = URL(string: "\(baseURL)/stats")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = authManager?.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data = try await executeWithRefreshRetry(request) { d in d }
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
        var components = URLComponents(string: "\(baseURL)/leaderboard")!
        components.queryItems = [
            URLQueryItem(name: "category", value: category.rawValue),
            URLQueryItem(name: "scope", value: scope.rawValue),
            URLQueryItem(name: "period", value: period.rawValue),
        ]
        if !carMake.isEmpty {
            components.queryItems!.append(URLQueryItem(name: "car_make", value: carMake))
        }
        if !carModel.isEmpty {
            components.queryItems!.append(URLQueryItem(name: "car_model", value: carModel))
        }
        let endpoint = String(components.url!.absoluteString.dropFirst(baseURL.count))
        return try await get(endpoint: endpoint)
    }

    func fetchPublicProfile(username: String) async throws -> PublicProfile {
        let encoded = Self.percentEncodePathSegment(username)
        return try await get(endpoint: "/users/\(encoded)")
    }

    func followUser(username: String) async throws {
        struct Empty: Decodable {}
        let encoded = Self.percentEncodePathSegment(username)
        let _: Empty = try await post(endpoint: "/users/\(encoded)/follow", body: _EmptyBody())
    }

    func unfollowUser(username: String) async throws {
        let encoded = Self.percentEncodePathSegment(username)
        try await delete(endpoint: "/users/\(encoded)/follow")
    }

    func fetchFollowers(username: String) async throws -> [FollowUserEntry] {
        let encoded = Self.percentEncodePathSegment(username)
        return try await get(endpoint: "/users/\(encoded)/followers")
    }

    func fetchFollowing(username: String) async throws -> [FollowUserEntry] {
        let encoded = Self.percentEncodePathSegment(username)
        return try await get(endpoint: "/users/\(encoded)/following")
    }

    /// Percent-encodes a value for use as a single URL path segment, so
    /// `/` (and other path-significant characters) become `%2F` instead
    /// of splitting the URL into multiple segments.
    static func percentEncodePathSegment(_ value: String) -> String {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: set) ?? value
    }

    /// Test-visible alias for `percentEncodePathSegment`. Internal
    /// so `@testable import FastTrack` can call it without exposing it
    /// as part of the public API surface.
    static func percentEncodePathSegmentForTest(_ value: String) -> String {
        percentEncodePathSegment(value)
    }

    func searchUsers(query: String) async throws -> [UserSearchResult] {
        var components = URLComponents(string: "\(baseURL)/users/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let endpoint = String(components.url!.absoluteString.dropFirst(baseURL.count))
        return try await get(endpoint: endpoint)
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        let request = DeleteAccountPayload(appleAuthorizationCode: appleAuthorizationCode)
        try await delete(endpoint: "/me", body: request)
    }

    func uploadAvatar(imageData: Data) async throws {
        struct Req: Encodable { let imageData: String; enum CodingKeys: String, CodingKey { case imageData = "image_data" } }
        struct Res: Decodable { let avatarURL: String; enum CodingKeys: String, CodingKey { case avatarURL = "avatar_url" } }
        let _: Res = try await put(endpoint: "/profile/avatar", body: Req(imageData: imageData.base64EncodedString()))
    }

    // MARK: - Garage Car Photo Methods

    /// Uploads a JPEG/PNG/GIF for the given car. Returns the canonical photo
    /// URL stored on the server (it lives under `<BASE_URL>/uploads/garage_cars/`).
    func uploadCarPhoto(carId: String, data: Data) async throws -> String {
        struct Req: Encodable { let imageData: String; enum CodingKeys: String, CodingKey { case imageData = "image_data" } }
        struct Res: Decodable { let photoURL: String; enum CodingKeys: String, CodingKey { case photoURL = "photo_url" } }
        let res: Res = try await put(
            endpoint: "/garage/cars/\(carId)/photo",
            body: Req(imageData: data.base64EncodedString())
        )
        return res.photoURL
    }

    /// Deletes the photo for the given car. The matching UserCar.photo_url
    /// is cleared server-side; the file is unlinked best-effort.
    func deleteCarPhoto(carId: String) async throws {
        try await delete(endpoint: "/garage/cars/\(carId)/photo")
    }

    // MARK: - Notification Methods

    func fetchNotifications(cursor: String? = nil, limit: Int = 50) async throws -> InAppNotificationsListResponse {
        var components = URLComponents(string: "\(baseURL)/me/notifications")!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            components.queryItems!.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let endpoint = String(components.url!.absoluteString.dropFirst(baseURL.count))
        return try await get(endpoint: endpoint)
    }

    func fetchUnreadNotificationCount() async throws -> Int {
        let r: UnreadCountResponse = try await get(endpoint: "/me/notifications/unread-count")
        return r.unreadCount
    }

    func markNotificationRead(id: Int) async throws {
        struct Empty: Codable {}
        let _: Empty = try await post(endpoint: "/me/notifications/\(id)/read", body: Empty())
    }

    func markAllNotificationsRead() async throws {
        struct Empty: Codable {}
        let _: Empty = try await post(endpoint: "/me/notifications/read-all", body: Empty())
    }
}

private struct _EmptyBody: Encodable {}

private struct NoDecodable: Decodable {}

private struct UnreadCountResponse: Decodable {
    let unreadCount: Int
    enum CodingKeys: String, CodingKey { case unreadCount = "unread_count" }
}

private struct DeleteAccountPayload: Encodable {
    let appleAuthorizationCode: String?

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case locationPermissionDenied

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
        case .locationPermissionDenied:
            return "Location permission is required to record drives"
        }
    }
}

// MARK: - DriveAPI protocol

/// The subset of `APIService` that `DriveManager` actually depends on.
/// Extracted into a protocol so tests can inject a mock (e.g. for the
/// `recoverPendingDrives` retry path or the `createDrive` failure
/// surface). `APIService` conforms trivially; production code keeps the
/// concrete singleton.
protocol DriveAPI: AnyObject {
    func createDrive(_ drive: Drive) async throws -> Drive
    func fetchDrives() async throws -> [Drive]
    func deleteDrive(id: Int) async throws
    func fetchMyAchievements() async throws -> UserAchievementsResponse
}

extension APIService: DriveAPI {}
