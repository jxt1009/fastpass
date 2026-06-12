import Foundation
import OSLog
import AuthenticationServices
import CryptoKit
import Combine

class GoogleSignInManager: NSObject, ObservableObject {
    @Published var error: String?

    static let clientID = Secrets.googleClientID
    static let redirectURI = "com.toper.fasttrack:/oauth2callback"

    private var codeVerifier: String = ""
    private var expectedState: String = ""
    let authManager: AuthManager
    let apiService: APIService

    init(authManager: AuthManager? = nil, apiService: APIService? = nil) {
        let api = apiService ?? APIService()
        let auth = authManager ?? AuthManager(apiService: api)
        api.authManager = auth
        self.authManager = auth
        self.apiService = api
    }

    func signInWithGoogle() {
        guard Self.clientID.contains(".apps.googleusercontent.com"),
              !Self.clientID.contains("YOUR_GOOGLE_CLIENT_ID")
        else {
            self.error = "Google Sign-In is not configured in this build"
            return
        }

        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString
        self.expectedState = state

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id",            value: Self.clientID),
            URLQueryItem(name: "redirect_uri",          value: Self.redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "openid email profile"),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state),
        ]

        guard let authURL = components.url else {
            self.error = "Failed to build auth URL"
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "com.toper.fasttrack"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                DispatchQueue.main.async { self.error = error.localizedDescription }
                return
            }

            guard let callbackURL = callbackURL else {
                DispatchQueue.main.async { self.error = "No callback URL received" }
                return
            }

            guard self.verifyState(in: callbackURL) else {
                DispatchQueue.main.async { self.error = "OAuth state mismatch — possible CSRF attack" }
                return
            }

            guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                DispatchQueue.main.async { self.error = "No authorization code received" }
                return
            }

            self.expectedState = ""  // Single-use: clear after verification
            Task { await self.exchangeCode(code) }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private func exchangeCode(_ code: String) async {
        let base = apiService.baseURL.replacingOccurrences(of: "/api/v1", with: "")
        guard let url = URL(string: "\(base)/api/v1/auth/google") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "code":          code,
            "client_id":     Self.clientID,
            "code_verifier": codeVerifier,
            "redirect_uri":  Self.redirectURI,
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                os.Logger(subsystem: "FastTrack", category: "auth")
                    .error("Sign-in error: \(String(data: data, encoding: .utf8) ?? "nil", privacy: .public)")
                await MainActor.run { self.error = "Sign in failed. Please try again." }
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let authResponse = try decoder.decode(AuthResponse.self, from: data)
            await authManager.completeAuthentication(with: authResponse)
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Verifies that the `state` query parameter on the OAuth callback matches
    /// the value we sent in the authorization URL. Prevents a CSRF attack where
    /// an attacker opens our callback scheme with their own authorization code
    /// and links their account to the victim's FastTrack user.
    func verifyState(in callbackURL: URL) -> Bool {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        else {
            return false
        }
        guard !expectedState.isEmpty,
              returnedState.count == expectedState.count
        else {
            return false
        }
        var diff = 0
        for (a, b) in zip(returnedState.utf8, expectedState.utf8) {
            diff |= Int(a) ^ Int(b)
        }
        return diff == 0
    }

#if DEBUG
    /// Test seam for injecting the expected OAuth state without going through
    /// the full sign-in flow. Compiled out of release builds.
    func setExpectedStateForTesting(_ state: String) {
        self.expectedState = state
    }
#endif
}

extension GoogleSignInManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            DispatchQueue.main.async { self.error = "No window available for sign-in" }
            return UIWindow()
        }
        return window
    }
}
