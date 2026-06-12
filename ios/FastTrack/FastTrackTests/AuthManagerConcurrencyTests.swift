import XCTest
@testable import FastTrack

final class AuthManagerConcurrencyTests: XCTestCase {
    func test_keychainAccessFromNonisolatedContext() async {
        let token = await Task.detached {
            AuthManager.shared.getToken()
        }.value
        XCTAssertNoThrow(token)
    }
}
