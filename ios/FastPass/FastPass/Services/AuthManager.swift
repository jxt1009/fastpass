import Foundation
import Security

class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated: Bool = false

    private let tokenKey = "auth_token"
    private let refreshTokenKey = "refresh_token"
    private let userKey = "current_user"

    private init() {
        isAuthenticated = getToken() != nil
    }
    
    // MARK: - Token Management
    
    func saveToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }
    
    func saveRefreshToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: refreshTokenKey)
    }
    
    func getToken() -> String? {
        return UserDefaults.standard.string(forKey: tokenKey)
    }
    
    func getRefreshToken() -> String? {
        return UserDefaults.standard.string(forKey: refreshTokenKey)
    }
    
    func clearTokens() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: userKey)
        isAuthenticated = false
    }
    
    // MARK: - User Management
    
    func saveUser(_ user: User) {
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: userKey)
        }
    }
    
    func getUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }
    
    // MARK: - Authentication
    
    func signInWithApple(identityToken: String, authCode: String?, fullName: String?, email: String?) async throws {
        let request = AppleSignInRequest(
            identityToken: identityToken,
            authCode: authCode,
            fullName: fullName,
            email: email
        )
        
        let response: AuthResponse = try await APIService.shared.post(
            endpoint: "/auth/apple",
            body: request,
            requiresAuth: false
        )
        
        saveToken(response.token)
        saveRefreshToken(response.refreshToken)
        saveUser(response.user)
        isAuthenticated = true
    }
    
    func refreshTokenIfNeeded() async throws {
        guard let refreshToken = getRefreshToken() else {
            throw AuthError.noRefreshToken
        }
        
        let request = RefreshTokenRequest(refreshToken: refreshToken)
        
        let response: AuthResponse = try await APIService.shared.post(
            endpoint: "/auth/refresh",
            body: request,
            requiresAuth: false
        )
        
        saveToken(response.token)
        saveRefreshToken(response.refreshToken)
        saveUser(response.user)
        isAuthenticated = true
    }
    
}

// MARK: - Models

struct AppleSignInRequest: Codable {
    let identityToken: String
    let authCode: String?
    let fullName: String?
    let email: String?
    
    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case authCode = "auth_code"
        case fullName = "full_name"
        case email
    }
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String
    
    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct AuthResponse: Codable {
    let token: String
    let refreshToken: String
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case token
        case refreshToken = "refresh_token"
        case user
    }
}

struct User: Codable, Identifiable {
    let id: Int
    let appleUserID: String?
    let googleUserID: String?
    let email: String?
    let fullName: String?
    let authProvider: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case appleUserID  = "apple_user_id"
        case googleUserID = "google_user_id"
        case email
        case fullName     = "full_name"
        case authProvider = "auth_provider"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }
}

enum AuthError: Error, LocalizedError {
    case noRefreshToken
    case invalidToken
    
    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available"
        case .invalidToken:
            return "Invalid or expired token"
        }
    }
}
