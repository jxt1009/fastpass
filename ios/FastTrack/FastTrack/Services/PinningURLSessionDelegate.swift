import Foundation
import CryptoKit
import OSLog

final class PinningURLSessionDelegate: NSObject, URLSessionDelegate {
    private let log = Logger(subsystem: "app.fasttrack", category: "sslPinning")

    weak var authManager: AuthManager?

    // SPKI pin for fast.toper.dev — update when the leaf cert rotates.
    // The iOS code hashes the raw public key bytes (via SecKeyCopyExternalRepresentation),
    // NOT the full DER-encoded SubjectPublicKeyInfo. To regenerate:
    //   openssl s_client -connect fast.toper.dev:443 -servername fast.toper.dev </dev/null 2>/dev/null \
    //     | openssl x509 -pubkey -noout 2>/dev/null \
    //     | openssl ec -pubin -conv_form uncompressed -outform DER 2>/dev/null \
    //     | openssl asn1parse -inform DER -strparse 24 -noout -out /dev/stdout 2>/dev/null \
    //     | openssl dgst -sha256 -binary 2>/dev/null \
    //     | base64
    // Current hash (2026-06-14): FrCe0Q7tuCCohD2N9iyI63vazZRo3cH0w37GtQb4kDA=
    private let pinnedSPKIHashes: Set<String> = [
        "FrCe0Q7tuCCohD2N9iyI63vazZRo3cH0w37GtQb4kDA="
    ]

    /// Computes the SHA-256 hash of a certificate's raw public key bytes
    /// (as returned by SecKeyCopyExternalRepresentation, NOT the DER-encoded SPKI).
    /// Returns the base64-encoded hash, or `nil` if the public key cannot be extracted.
    static func computeKeyHash(from certificate: SecCertificate) -> String? {
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

        // Evaluate trust to populate the certificate chain so that
        // SecTrustGetCertificateAtIndex works (required by Security framework
        // docs, enforced on iOS 27+). We tolerate evaluation failure so that
        // OCSP/network issues don't block the connection — SPKI pinning is our
        // trust anchor.
        SecTrustSetNetworkFetchAllowed(serverTrust, false)
        var evalError: CFError?
        if !SecTrustEvaluateWithError(serverTrust, &evalError) {
            log.warning("authChallenge: trust evaluation failed (\(String(describing: evalError))), proceeding with SPKI check")
        }

        guard let cert = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            log.error("authChallenge: no certificate at index 0")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let hash = Self.computeKeyHash(from: cert) else {
            log.error("authChallenge: failed to compute key hash")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if pinnedSPKIHashes.contains(hash) {
            log.debug("authChallenge: key hash matched, allowing connection")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            log.error("authChallenge: key hash mismatch — got \(hash, privacy: .public)")
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
        }
    }
}
