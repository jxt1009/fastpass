import XCTest
@testable import FastTrack

/// Regression test for P0-3: the Google OAuth callback must verify that
/// the `state` query parameter matches the value we sent in the auth URL.
/// Verifies the constant-time comparison in `verifyState(in:)` and the
/// empty-state guard.
final class GoogleSignInManagerStateTests: XCTestCase {

    func testVerifyState_MatchingStateReturnsTrue() {
        let manager = GoogleSignInManager()
        let state = UUID().uuidString
        manager.setExpectedStateForTesting(state)
        let url = URL(string: "com.toper.fasttrack:/oauth2callback?code=fake&state=\(state)")!
        XCTAssertTrue(manager.verifyState(in: url))
    }

    func testVerifyState_MismatchedStateReturnsFalse() {
        let manager = GoogleSignInManager()
        manager.setExpectedStateForTesting(UUID().uuidString)
        let url = URL(string: "com.toper.fasttrack:/oauth2callback?code=fake&state=ATTACKER_STATE")!
        XCTAssertFalse(manager.verifyState(in: url))
    }

    func testVerifyState_MissingStateReturnsFalse() {
        let manager = GoogleSignInManager()
        manager.setExpectedStateForTesting(UUID().uuidString)
        let url = URL(string: "com.toper.fasttrack:/oauth2callback?code=fake")!
        XCTAssertFalse(manager.verifyState(in: url))
    }

    func testVerifyState_EmptyExpectedReturnsFalse() {
        let manager = GoogleSignInManager()
        // Don't set expectedState; it should remain empty.
        let url = URL(string: "com.toper.fasttrack:/oauth2callback?code=fake&state=ANYTHING")!
        XCTAssertFalse(manager.verifyState(in: url))
    }
}
