import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var googleSignInManager = GoogleSignInManager()
    @StateObject private var appleSignInManager  = AppleSignInManager()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                Text("FastTrack")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Track Your Speed")
                    .font(.title3).foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 14) {
                // Google
                Button {
                    googleSignInManager.signInWithGoogle()
                } label: {
                    Label("Sign in with Google", systemImage: "globe")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1))
                        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                }

                // Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    appleSignInManager.handleSignInResult(result)
                }
                .frame(height: 50)
                .cornerRadius(10)
            }
            .padding(.horizontal, 40)

            // Error
            if let err = googleSignInManager.error ?? appleSignInManager.error {
                Text(err)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 40)
            }

            Spacer()

            // Legal footer with tappable links (required for App Store)
            (Text("By signing in you agree to our ")
                .foregroundColor(.secondary)
             + Text("Terms of Service")
                .foregroundColor(.blue)
             + Text(" and ")
                .foregroundColor(.secondary)
             + Text("Privacy Policy")
                .foregroundColor(.blue))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .onTapGesture { }  // handled by individual Link overlays below

            HStack(spacing: 16) {
                Link("Terms of Service",
                     destination: URL(string: "https://fast.toper.dev/terms")!)
                Link("Privacy Policy",
                     destination: URL(string: "https://fast.toper.dev/privacy")!)
            }
            .font(.caption2)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

#Preview {
    SignInView().environmentObject(AuthManager.shared)
}
