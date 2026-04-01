import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @StateObject private var appleSignInManager = AppleSignInManager()
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App Logo/Icon
            Image(systemName: "car.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
            
            // App Name
            Text("FastPass")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            
            Text("Track Your Speed")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Sign in with Apple Button
            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        handleAuthorization(authorization)
                    case .failure(let error):
                        appleSignInManager.error = error.localizedDescription
                    }
                }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .padding(.horizontal, 40)
            
            if let error = appleSignInManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
            
            Spacer()
            
            // Privacy Text
            Text("We use Sign in with Apple to protect your privacy. Your personal information is never shared.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
    }
    
    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        
        guard let identityToken = appleIDCredential.identityToken,
              let identityTokenString = String(data: identityToken, encoding: .utf8) else {
            appleSignInManager.error = "Failed to get identity token"
            return
        }
        
        let fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        
        Task {
            do {
                try await AuthManager.shared.signInWithApple(
                    identityToken: identityTokenString,
                    authCode: appleIDCredential.authorizationCode.map { String(data: $0, encoding: .utf8) } ?? nil,
                    fullName: fullName.isEmpty ? nil : fullName,
                    email: appleIDCredential.email
                )
                
                await MainActor.run {
                    appleSignInManager.isSignedIn = true
                }
            } catch {
                await MainActor.run {
                    appleSignInManager.error = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    SignInView()
}
