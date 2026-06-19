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
    // Current leaf hash (2026-06-14): FrCe0Q7tuCCohD2N9iyI63vazZRo3cH0w37GtQb4kDA=
    // Backup pin: add the intermediate CA's SPKI hash here so a leaf cert
    // rotation doesn't brick the app. To compute, run the openssl pipeline
    // in the comment above against the intermediate cert (index 1 in the chain).
    // TODO: populate with the intermediate CA SPKI hash for resilience.
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

        // Check the full certificate chain for a matching SPKI pin.
        // This allows backup pins on intermediate CA certs to keep the app
        // working if the leaf cert rotates.
        let chainCount = SecTrustGetCertificateCount(serverTrust)
        var matchedHash: String?
        for i in 0..<chainCount {
            guard let cert = SecTrustGetCertificateAtIndex(serverTrust, i),
                  let hash = Self.computeKeyHash(from: cert) else { continue }
            if pinnedSPKIHashes.contains(hash) {
                matchedHash = hash
                break
            }
        }

        if let hash = matchedHash {
            log.debug("authChallenge: key hash matched, allowing connection")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            let leafHash = (0..<chainCount).compactMap { i in
                SecTrustGetCertificateAtIndex(serverTrust, i).flatMap { Self.computeKeyHash(from: $0) }
            }.first ?? "unknown"
            log.error("authChallenge: no pinned key hash found in chain — leaf=\(leafHash, privacy: .public)")
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
