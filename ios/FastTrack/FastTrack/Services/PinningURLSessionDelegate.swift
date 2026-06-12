import Foundation
import CryptoKit

final class PinningURLSessionDelegate: NSObject, URLSessionDelegate {

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

    private var isProcessing401 = false

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        guard host == "fast.toper.dev" else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var secResult: SecTrustResultType = .invalid
        SecTrustEvaluate(serverTrust, &secResult)
        guard let cert = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        var pubKey: SecKey?
        if #available(iOS 14.0, *) {
            pubKey = SecCertificateCopyKey(cert)
        } else {
            pubKey = SecCertificateCopyPublicKey(cert)
        }
        guard let publicKey = pubKey else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let pubKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        guard let data = pubKeyData else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let hash = Data(SHA256.hash(data: data)).base64EncodedString()
        if pinnedSPKIHashes.contains(hash) {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

extension PinningURLSessionDelegate: @preconcurrency URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: (any Error)?) {
        guard let httpResponse = task.response as? HTTPURLResponse,
              httpResponse.statusCode == 401,
              !isProcessing401 else { return }
        isProcessing401 = true
        Task { @MainActor in
            AuthManager.shared.signOut()
            ToastManager.shared.show(ToastMessage(text: "Session expired"))
            isProcessing401 = false
        }
    }
}
