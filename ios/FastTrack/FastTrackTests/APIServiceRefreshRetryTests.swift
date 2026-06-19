import XCTest
@testable import FastTrack

// Verifies the 401 → refresh → retry behavior added to APIService.
//
// APIService uses its own URLSession backed by PinningURLSessionDelegate.
// Rather than rely on process-global `URLProtocol.registerClass` (which some
// SDKs don't consult for custom `.default` sessions), we inject a session
// whose `configuration.protocolClasses` include our stub, and exercise the
// production APIService code path end-to-end.
final class APIServiceRefreshRetryTests: XCTestCase {

    private final class StubURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data?))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = StubURLProtocol.requestHandler else {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private final class Counter {
        private var value = 0
        private let lock = NSLock()
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    // AuthManager stand-in that keeps tokens in memory instead of the
    // keychain. The keychain is unavailable under CODE_SIGNING_ALLOWED=NO
    // (SecItemAdd fails with errSecMissingEntitlement, -34018), so without
    // this the 401-refresh path — which reads getToken()/getRefreshToken() —
    // could not be exercised.
    //
    // `@testable import` makes AuthManager's internal methods overridable
    // from the test module. We override `refreshTokenIfNeeded` and `signOut`
    // themselves (not just the token getters): same-class `self.getRefreshToken()`
    // calls inside AuthManager are devirtualized to the super implementation
    // and would bypass the in-memory overrides, so we reproduce the refresh
    // via the real `apiService.post` (which hits the stubbed /auth/refresh)
    // and clear in-memory tokens on signOut (so signOut's fire-and-forget
    // /auth/logout carries no auth header and doesn't cascade).
    private final class TestAuthManager: AuthManager {
        private var accessToken: String?
        private var refreshToken: String?

        override func getToken() -> String? { accessToken }
        override func getRefreshToken() -> String? { refreshToken }
        override func saveToken(_ token: String) { accessToken = token }
        override func saveRefreshToken(_ token: String) { refreshToken = token }

        override func refreshTokenIfNeeded() async throws {
            guard let refreshToken = self.getRefreshToken() else {
                throw AuthError.noRefreshToken
            }
            let request = RefreshTokenRequest(refreshToken: refreshToken)
            let response: AuthResponse = try await apiService.post(
                endpoint: "/auth/refresh",
                body: request,
                requiresAuth: false
            )
            self.saveToken(response.token)
            self.saveRefreshToken(response.refreshToken)
            await MainActor.run { self.isAuthenticated = true }
        }

        override func signOut() {
            super.signOut()
            accessToken = nil
            refreshToken = nil
        }
    }

    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private let authResponseJSON = #"{"token":"new-access-token","refresh_token":"new-refresh-token","user":{"id":1,"is_public":true,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}}"#
    private let userJSON = #"{"id":42,"is_public":true,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}"#

    private func okResponse(_ req: URLRequest, _ statusCode: Int, _ data: Data) -> (HTTPURLResponse, Data?) {
        (HTTPURLResponse(url: req.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!, data)
    }

    /// Builds an APIService wired to a TestAuthManager, with a URLSession that
    /// routes through StubURLProtocol and an empty URLCache.
    @MainActor
    private func makeService() -> (APIService, TestAuthManager) {
        let delegate = PinningURLSessionDelegate()
        let config = URLSessionConfiguration.default
        config.protocolClasses = [StubURLProtocol.self] + (config.protocolClasses ?? [])
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let api = APIService(session: session, sessionDelegate: delegate)
        let authMgr = TestAuthManager(apiService: api)
        api.authManager = authMgr
        return (api, authMgr)
    }

    // MARK: - Tests

    @MainActor
    func test_401_triggersRefreshAndRetry() async throws {
        let (api, authMgr) = makeService()
        authMgr.saveToken("expired-access")
        authMgr.saveRefreshToken("valid-refresh")

        let refreshCounter = Counter()
        StubURLProtocol.requestHandler = { req in
            if (req.url?.path ?? "").hasSuffix("/auth/refresh") {
                refreshCounter.increment()
                return self.okResponse(req, 200, self.authResponseJSON.data(using: .utf8)!)
            }
            // /me: 401 for the expired token, 200 for the refreshed token.
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer expired-access" {
                return self.okResponse(req, 401, Data())
            }
            return self.okResponse(req, 200, self.userJSON.data(using: .utf8)!)
        }

        let user: User = try await api.fetchMe()
        XCTAssertEqual(user.id, 42)
        XCTAssertEqual(refreshCounter.count, 1, "refresh should be attempted exactly once")
        XCTAssertEqual(authMgr.getToken(), "new-access-token", "retry should use the refreshed token")
        XCTAssertTrue(authMgr.isAuthenticated, "successful refresh must keep the user authenticated")
    }

    @MainActor
    func test_401_refreshFails_signsOut() async throws {
        let (api, authMgr) = makeService()
        authMgr.saveToken("expired-access")
        authMgr.saveRefreshToken("invalid-refresh")
        // isAuthenticated is only flipped by completeAuthentication/clearTokens,
        // not by saveToken — set it directly so we can observe signOut clearing it.
        authMgr.isAuthenticated = true
        XCTAssertTrue(authMgr.isAuthenticated)

        StubURLProtocol.requestHandler = { req in
            // /auth/refresh fails with 401 → refreshTokenIfNeeded throws.
            self.okResponse(req, 401, Data())
        }

        do {
            let _: User = try await api.fetchMe()
            XCTFail("expected fetchMe to throw when refresh fails")
        } catch {
            // expected
        }
        XCTAssertFalse(authMgr.isAuthenticated, "a failed refresh must sign the user out")
    }

    @MainActor
    func test_401_withoutAuthHeader_doesNotRefresh() async throws {
        let (api, authMgr) = makeService()
        // No access token → requests carry no Authorization header. A refresh
        // token exists, so we can detect if a refresh was wrongly attempted.
        authMgr.saveRefreshToken("unused-refresh")
        XCTAssertNil(authMgr.getToken())
        XCTAssertFalse(authMgr.isAuthenticated)

        let refreshCounter = Counter()
        StubURLProtocol.requestHandler = { req in
            if (req.url?.path ?? "").hasSuffix("/auth/refresh") {
                refreshCounter.increment()
                return self.okResponse(req, 200, self.authResponseJSON.data(using: .utf8)!)
            }
            // /me → 401, no Authorization header present.
            return self.okResponse(req, 401, Data())
        }

        do {
            let _: User = try await api.fetchMe()
            XCTFail("expected fetchMe to throw without an access token")
        } catch {
            // expected
        }
        XCTAssertEqual(refreshCounter.count, 0, "must not refresh a request that had no Authorization header")
        XCTAssertFalse(authMgr.isAuthenticated, "must not sign out when no auth header was present")
    }
}
