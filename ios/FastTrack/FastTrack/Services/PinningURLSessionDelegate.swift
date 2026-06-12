import Foundation
import CryptoKit
import OSLog
import os.lock

final class PinningURLSessionDelegate: NSObject, URLSessionDelegate {
    private let log = Logger(subsystem: "app.fasttrack", category: "sslPinning")

    weak var authManager: AuthManager?

    // SPKI pin for fast.toper.dev — update when the leaf cert rotates.
    // Generated from:
    //   openssl s_client -connect fast.toper.dev:443 -servername fast.toper.dev </dev/null 2>/dev/null \
    //     | openssl x509 -pubkey -noout 2>/dev/null \
    //     | openssl pkey -pubin -outform DER 2>/dev/null \
    //     | openssl dgst -sha256 -binary 2>/dev/null \
    //     | base64
    // Current hash (2026-06-13): 8Pq14p0SF7i6pX268DDe8owa5TD+PGKhCfAasxKzM/E=
    private let pinnedSPKIHashes: Set<String> = [
        "8Pq14p0SF7i6pX268DDe8owa5TD+PGKhCfAasxKzM/E="
    ]

    private var _lock = os_unfair_lock()
    private var _isProcessing401 = false

    private var isProcessing401: Bool {
        get { os_unfair_lock_lock(&_lock); defer { os_unfair_lock_unlock(&_lock) }; return _isProcessing401 }
        set { os_unfair_lock_lock(&_lock); defer { os_unfair_lock_unlock(&_lock) }; _isProcessing401 = newValue }
    }

    /// Computes the SHA-256 hash of a certificate's Subject Public Key Info (SPKI).
    /// Returns the base64-encoded hash, or `nil` if the public key cannot be extracted.
    static func computeSPKIHash(from certificate: SecCertificate) -> String? {
        var pubKey: SecKey?
        if #available(iOS 14.0, *) {
            pubKey = SecCertificateCopyKey(certificate)
        } else {
            pubKey = SecCertificateCopyPublicKey(certificate)
        }
        guard let publicKey = pubKey else { return nil }
        guard let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { return nil }
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let host = challenge.protectionSpace.host
        log.debug("authChallenge: method=\(method, privacy: .public) host=\(host, privacy: .public)")

        guard method == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            log.debug("authChallenge: not serverTrust, performing default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard host == "fast.toper.dev" else {
            log.debug("authChallenge: host \(host, privacy: .public) not pinned, performing default")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let cert = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            log.error("authChallenge: no certificate at index 0")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let hash = Self.computeSPKIHash(from: cert) else {
            log.error("authChallenge: failed to compute SPKI hash")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if pinnedSPKIHashes.contains(hash) {
            log.debug("authChallenge: SPKI hash matched, allowing connection")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            log.error("authChallenge: SPKI hash mismatch — got \(hash, privacy: .public)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

extension PinningURLSessionDelegate: @preconcurrency URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: (any Error)?) {
        if let err = error {
            log.debug("taskComplete: error=\(err.localizedDescription, privacy: .public)")
        }
        if let httpResponse = task.response as? HTTPURLResponse {
            log.debug("taskComplete: status=\(httpResponse.statusCode)")
            guard httpResponse.statusCode == 401, !isProcessing401 else { return }
            isProcessing401 = true
            log.warning("taskComplete: 401 received, signing out")
            Task { @MainActor in
                authManager?.signOut()
                ToastManager.shared.show(ToastMessage(text: "Session expired"))
                isProcessing401 = false
            }
        }
    }
}
