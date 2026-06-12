import Foundation
import AuthenticationServices
import Combine

class AppleSignInManager: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var error: String?
    
    weak var authManager: AuthManager?
    private var deletionContinuation: CheckedContinuation<String, Error>?

    override init() {
    }
    
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                error = "Failed to get identity token"
                return
            }
            let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            Task {
                do {
                    try await authManager?.signInWithApple(
                        identityToken: identityToken,
                        authCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                        fullName: fullName.isEmpty ? nil : fullName,
                        email: credential.email
                    )
                    await MainActor.run { self.error = nil }
                } catch {
                    await MainActor.run { self.error = error.localizedDescription }
                }
            }
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            error = message(for: err)
        }
    }

    func signInWithApple(presentationAnchor: ASPresentationAnchor) {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    func checkSignInStatus() {
        if let token = authManager?.getToken() {
            // Token exists, verify it's still valid
            Task {
                do {
                    try await authManager?.refreshTokenIfNeeded()
                    await MainActor.run {
                        self.isSignedIn = true
                    }
                } catch {
                    await MainActor.run {
                        self.isSignedIn = false
                    }
                }
            }
        } else {
            isSignedIn = false
        }
    }
    
    @MainActor
    func signOut() {
        authManager?.signOut()
        isSignedIn = false
    }

    func reauthorizeForAccountDeletion() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            deletionContinuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        if let deletionContinuation {
            guard let authCodeData = appleIDCredential.authorizationCode,
                  let authCode = String(data: authCodeData, encoding: .utf8),
                  !authCode.isEmpty else {
                self.deletionContinuation = nil
                deletionContinuation.resume(throwing: AuthError.invalidToken)
                return
            }
            self.deletionContinuation = nil
            deletionContinuation.resume(returning: authCode)
            return
        }
        
        guard let identityToken = appleIDCredential.identityToken,
              let identityTokenString = String(data: identityToken, encoding: .utf8) else {
            error = "Failed to get identity token"
            return
        }
        
        // Get full name if available (only on first sign in)
        let fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        
        // Send to backend
        Task {
            do {
                try await authManager?.signInWithApple(
                    identityToken: identityTokenString,
                    authCode: appleIDCredential.authorizationCode.map { String(data: $0, encoding: .utf8) } ?? nil,
                    fullName: fullName.isEmpty ? nil : fullName,
                    email: appleIDCredential.email
                )
                
                await MainActor.run {
                    self.isSignedIn = true
                    self.error = nil
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isSignedIn = false
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let deletionContinuation {
            self.deletionContinuation = nil
            deletionContinuation.resume(throwing: error)
            return
        }
        if (error as? ASAuthorizationError)?.code == .canceled {
            self.error = nil
            isSignedIn = false
            return
        }
        self.error = message(for: error)
        isSignedIn = false
    }

    private func message(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == "AKAuthenticationError", nsError.code == -7026 {
            return "Apple sign-in isn't enabled for this app ID yet. Turn on the Sign in with Apple capability for the FastTrack target and refresh the provisioning profile on your device."
        }

        if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" {
            switch nsError.code {
            case 1000:
                return "Apple sign-in isn't enabled for this app ID yet. Turn on the Sign in with Apple capability for the FastTrack target and refresh the provisioning profile on your device."
            case 1001:
                return "Apple sign-in was canceled."
            default:
                break
            }
        }

        return nsError.localizedDescription
    }
}

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            DispatchQueue.main.async { self.error = "No window available for sign-in" }
            return UIWindow()
        }
        return window
    }
}
