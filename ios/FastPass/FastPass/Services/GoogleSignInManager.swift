import Foundation
import AuthenticationServices
import CryptoKit
import Combine

class GoogleSignInManager: NSObject, ObservableObject {
    @Published var error: String?

    // Replace with your Google OAuth Client ID from https://console.cloud.google.com/
    // Application type: iOS, Bundle ID: com.toper.FastPass
    static let clientID = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
    static let redirectURI = "com.toper.fastpass:/oauth2callback"

    private var codeVerifier: String = ""

    func signInWithGoogle() {
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = UUID().uuidString

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
            callbackURLScheme: "com.toper.fastpass"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
                DispatchQueue.main.async { self.error = error.localizedDescription }
                return
            }

            guard let callbackURL = callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                DispatchQueue.main.async { self.error = "No authorization code received" }
                return
            }

            Task { await self.exchangeCode(code) }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private func exchangeCode(_ code: String) async {
        let base = APIService.shared.baseURL.replacingOccurrences(of: "/api/v1", with: "")
        guard let url = URL(string: "\(base)/api/v1/auth/google") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "code":          code,
            "code_verifier": codeVerifier,
            "redirect_uri":  Self.redirectURI,
        ]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run { self.error = "Auth failed: \(msg)" }
                return
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let authResponse = try decoder.decode(AuthResponse.self, from: data)
            AuthManager.shared.saveToken(authResponse.token)
            AuthManager.shared.saveRefreshToken(authResponse.refreshToken)
            AuthManager.shared.saveUser(authResponse.user)
            await MainActor.run { AuthManager.shared.isAuthenticated = true }
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
}

extension GoogleSignInManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}
