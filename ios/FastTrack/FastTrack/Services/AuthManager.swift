import Foundation
import Security
import Combine

class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated: Bool = false

    private let tokenKey = "com.fasttrack.auth_token"
    private let refreshTokenKey = "com.fasttrack.refresh_token"
    private let userKey = "current_user"
    private var sessionToken: UUID = UUID()

    private init() {
        isAuthenticated = getToken() != nil
    }
    
    // MARK: - Keychain helpers

    private func keychainSave(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainLoad(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Token Management
    
    func saveToken(_ token: String) {
        keychainSave(token, forKey: tokenKey)
    }
    
    func saveRefreshToken(_ token: String) {
        keychainSave(token, forKey: refreshTokenKey)
    }
    
    func getToken() -> String? {
        return keychainLoad(forKey: tokenKey)
    }
    
    func getRefreshToken() -> String? {
        return keychainLoad(forKey: refreshTokenKey)
    }
    
    func clearTokens() {
        keychainDelete(forKey: tokenKey)
        keychainDelete(forKey: refreshTokenKey)
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
        let myToken = UUID()
        await MainActor.run { self.sessionToken = myToken }

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

        guard await MainActor.run({ self.sessionToken == myToken }) else { return }
        await completeAuthentication(with: response)
    }
    
    func refreshTokenIfNeeded() async throws {
        let myToken = UUID()
        await MainActor.run { self.sessionToken = myToken }

        guard let refreshToken = getRefreshToken() else {
            throw AuthError.noRefreshToken
        }
        
        let request = RefreshTokenRequest(refreshToken: refreshToken)
        
        let response: AuthResponse = try await APIService.shared.post(
            endpoint: "/auth/refresh",
            body: request,
            requiresAuth: false
        )

        guard await MainActor.run({ self.sessionToken == myToken }) else { return }
        await completeAuthentication(with: response)
    }

    func completeAuthentication(with response: AuthResponse) async {
        let myToken = sessionToken
        saveToken(response.token)
        saveRefreshToken(response.refreshToken)
        saveUser(response.user)
        await MainActor.run {
            guard self.sessionToken == myToken else { return }
            isAuthenticated = true
        }
        guard await MainActor.run({ self.sessionToken == myToken }) else { return }
        await restoreUserDataFromServer(serverUser: response.user)
    }

    @MainActor
    func signOut() {
        sessionToken = UUID()
        NotificationsManager.shared.cancelInFlight()
        clearSessionData()
    }

    func deleteAccount(appleAuthorizationCode: String?) async throws {
        try await APIService.shared.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
        await MainActor.run {
            self.sessionToken = UUID()
            self.clearSessionData()
        }
    }

    /// Syncs profile, garage, car stats, and display settings from the server into local storage.
    func restoreUserDataFromServer(serverUser: User) async {
        await ProfileManager.shared.restoreFromServer(serverUser: serverUser)
        await CarStatsManager.shared.restoreFromServer()
        await AppSettings.shared.restoreFromServer(
            unitSystem: serverUser.unitSystem,
            colorScheme: serverUser.colorScheme
        )
    }

    @MainActor
    private func clearSessionData() {
        ProfileManager.shared.clearProfile()
        CarStatsManager.shared.clearLocalData()
        AchievementManager.shared.resetProgress()
        AppSettings.shared.resetAccountScopedPreferences()
        clearTokens()
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

    struct DeleteAccountRequest: Codable {
        let appleAuthorizationCode: String?

        enum CodingKeys: String, CodingKey {
            case appleAuthorizationCode = "apple_authorization_code"
        }
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
    let username: String?
    let country: String?
    let avatarURL: String?
    
    // Legacy car fields
    let carMake: String?
    let carModel: String?
    let carYear: Int?
    let carTrim: String?
    
    // New garage fields
    let garage: String?
    let selectedCarID: String?
    let carStatsData: String?
    let unitSystem: String?
    let colorScheme: String?
    let isPublic: Bool

    let authProvider: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case appleUserID  = "apple_user_id"
        case googleUserID = "google_user_id"
        case email
        case fullName     = "full_name"
        case username
        case country
        case avatarURL    = "avatar_url"
        case carMake      = "car_make"
        case carModel     = "car_model"
        case carYear      = "car_year"
        case carTrim      = "car_trim"
        case garage
        case selectedCarID = "selected_car_id"
        case carStatsData = "car_stats_data"
        case unitSystem   = "unit_system"
        case colorScheme  = "color_scheme"
        case isPublic     = "is_public"
        case authProvider = "auth_provider"
        case createdAt    = "created_at"
        case updatedAt    = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(Int.self, forKey: .id)
        appleUserID  = try c.decodeIfPresent(String.self, forKey: .appleUserID)
        googleUserID = try c.decodeIfPresent(String.self, forKey: .googleUserID)
        email        = try c.decodeIfPresent(String.self, forKey: .email)
        fullName     = try c.decodeIfPresent(String.self, forKey: .fullName)
        username     = try c.decodeIfPresent(String.self, forKey: .username)
        country      = try c.decodeIfPresent(String.self, forKey: .country)
        avatarURL    = try c.decodeIfPresent(String.self, forKey: .avatarURL)
        carMake      = try c.decodeIfPresent(String.self, forKey: .carMake)
        carModel     = try c.decodeIfPresent(String.self, forKey: .carModel)
        carYear      = try c.decodeIfPresent(Int.self,    forKey: .carYear)
        carTrim      = try c.decodeIfPresent(String.self, forKey: .carTrim)
        garage       = try c.decodeIfPresent(String.self, forKey: .garage)
        selectedCarID = try c.decodeIfPresent(String.self, forKey: .selectedCarID)
        carStatsData = try c.decodeIfPresent(String.self, forKey: .carStatsData)
        unitSystem   = try c.decodeIfPresent(String.self, forKey: .unitSystem)
        colorScheme  = try c.decodeIfPresent(String.self, forKey: .colorScheme)
        isPublic     = try c.decodeIfPresent(Bool.self,   forKey: .isPublic) ?? true
        authProvider = try c.decodeIfPresent(String.self, forKey: .authProvider)
        createdAt    = try c.decode(Date.self, forKey: .createdAt)
        updatedAt    = try c.decode(Date.self, forKey: .updatedAt)
    }

    init(
        id: Int,
        appleUserID: String?,
        googleUserID: String?,
        email: String?,
        fullName: String?,
        username: String?,
        country: String?,
        avatarURL: String?,
        carMake: String?,
        carModel: String?,
        carYear: Int?,
        carTrim: String?,
        garage: String?,
        selectedCarID: String?,
        carStatsData: String?,
        unitSystem: String?,
        colorScheme: String?,
        isPublic: Bool = true,
        authProvider: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id           = id
        self.appleUserID  = appleUserID
        self.googleUserID = googleUserID
        self.email        = email
        self.fullName     = fullName
        self.username     = username
        self.country      = country
        self.avatarURL    = avatarURL
        self.carMake      = carMake
        self.carModel     = carModel
        self.carYear      = carYear
        self.carTrim      = carTrim
        self.garage       = garage
        self.selectedCarID = selectedCarID
        self.carStatsData = carStatsData
        self.unitSystem   = unitSystem
        self.colorScheme  = colorScheme
        self.isPublic     = isPublic
        self.authProvider = authProvider
        self.createdAt    = createdAt
        self.updatedAt    = updatedAt
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
