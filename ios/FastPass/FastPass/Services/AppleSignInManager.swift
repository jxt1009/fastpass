import Foundation
import AuthenticationServices
import Combine

class AppleSignInManager: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var error: String?
    
    private let authManager = AuthManager.shared
    
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
                    try await authManager.signInWithApple(
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
            error = err.localizedDescription
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
        if let token = authManager.getToken() {
            // Token exists, verify it's still valid
            Task {
                do {
                    try await authManager.refreshTokenIfNeeded()
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
    
    func signOut() {
        authManager.clearTokens()
        isSignedIn = false
    }
}

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
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
                try await authManager.signInWithApple(
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
        self.error = error.localizedDescription
        isSignedIn = false
    }
}

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the current window
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}
