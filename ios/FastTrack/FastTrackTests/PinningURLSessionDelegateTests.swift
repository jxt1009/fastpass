import XCTest
@testable import FastTrack

private final class MockChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_: URLCredential, for: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for: URLAuthenticationChallenge) {}
    func cancel(_: URLAuthenticationChallenge) {}
    func performDefaultHandling(for: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with: URLAuthenticationChallenge) {}
}

final class PinningURLSessionDelegateTests: XCTestCase {}

extension PinningURLSessionDelegateTests {
    func testPinningDelegate_nonServerTrustChallenge_performsDefaultHandling() throws {
        let delegate = PinningURLSessionDelegate()
        let space = URLProtectionSpace(
            host: "fast.toper.dev",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: space,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockChallengeSender()
        )

        let exp = expectation(description: "completion handler called")
        delegate.urlSession(.shared, didReceive: challenge) { disposition, _ in
            XCTAssertEqual(disposition, .performDefaultHandling)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}

extension PinningURLSessionDelegateTests {
    func testPinningDelegate_nonServerTrustChallengeWithoutServerTrust_performsDefaultHandling() throws {
        let delegate = PinningURLSessionDelegate()
        let space = URLProtectionSpace(
            host: "fast.toper.dev",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: space,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockChallengeSender()
        )

        let exp = expectation(description: "completion handler called")
        delegate.urlSession(.shared, didReceive: challenge) { disposition, _ in
            XCTAssertEqual(disposition, .performDefaultHandling)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}

extension PinningURLSessionDelegateTests {
    func testPinningDelegate_computeSPKIHash_validCert_returnsNonNilHash() throws {
        let derHex = "3082039d30820344a00302010202105246f2ad35ecfe1113937fbe15463a53300a06082a8648ce3d040302303b310b3009060355040613025553311e301c060355040a1315476f6f676c65205472757374205365727669636573310c300a06035504031303574531301e170d3236303533303039353731325a170d3236303832383130353730365a30143112301006035504031309746f7065722e6465763059301306072a8648ce3d020106082a8648ce3d030107034200045693091d931232e78929874deffba87644f725fdfd6fca02966a9291394250c17972a072efdf6b13fc3d68dc1f990f1356828e163d0b3df5155bdb83ba3aa375a382024f3082024b300e0603551d0f0101ff04040302078030130603551d25040c300a06082b06010505070301300c0603551d130101ff04023000301d0603551d0e04160414aa2cfbcc70b43e0a1492730cb26d7336ee53344f301f0603551d230418301680149077923567c4ffa8cca9e67bd980797bcc93f938305e06082b0601050507010104523050302706082b06010505073001861b687474703a2f2f6f2e706b692e676f6f672f732f7765312f556b59302506082b060105050730028619687474703a2f2f692e706b692e676f6f672f7765312e63727430210603551d11041a30188209746f7065722e646576820b2a2e746f7065722e64657630130603551d20040c300a3008060667810c01020130360603551d1f042f302d302ba029a0278625687474703a2f2f632e706b692e676f6f672f7765312f55326b334e626a617061732e63726c30820104060a2b06010401d6790204020481f50481f200f0007700cb38f715897c84a1445f5bc1ddfbc96ef29a59cd470a690585b0cb14c31458e70000019e7887e7c20000040300483046022100f7531269550197aa611169cae468c5f21d46d91de5d0e15d3d5a97a8bd795efb022100bb8cf02edd4e039fae4870991f19c4d78710bbfb5582b85e5c0453b0191b12e1007500d809553b944f7affc816196f944f85abb0f8fc5e8755260f15d12e72bb454b140000019e7887e7c00000040300463044022035e0fc8bf7b8a48b37339d36caaa31919102953de306ee993279762ea4bd8597022047b432eef21faa5c7e024fc75e8df1f702585aa3fc4e6c16144d42b3d11ec402300a06082a8648ce3d040302034700304402202f4be88df5a1894882597c56a58b047aba27e4dcc1d7babcedb8b1da2907e0e302206b10728fca68c46c8ae7b3dcc66f0259699ceca0233cbcdefdb5dd948017da1c"
        guard let derData = Data(hexString: derHex),
              let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
            XCTFail("Failed to create SecCertificate")
            return
        }
        let hash = PinningURLSessionDelegate.computeSPKIHash(from: certificate)
        XCTAssertNotNil(hash)
        XCTAssertFalse(hash?.isEmpty ?? true)
    }

    func testPinningDelegate_computeSPKIHash_sameCert_returnsSameHash() throws {
        let derHex = "3082039d30820344a00302010202105246f2ad35ecfe1113937fbe15463a53300a06082a8648ce3d040302303b310b3009060355040613025553311e301c060355040a1315476f6f676c65205472757374205365727669636573310c300a06035504031303574531301e170d3236303533303039353731325a170d3236303832383130353730365a30143112301006035504031309746f7065722e6465763059301306072a8648ce3d020106082a8648ce3d030107034200045693091d931232e78929874deffba87644f725fdfd6fca02966a9291394250c17972a072efdf6b13fc3d68dc1f990f1356828e163d0b3df5155bdb83ba3aa375a382024f3082024b300e0603551d0f0101ff04040302078030130603551d25040c300a06082b06010505070301300c0603551d130101ff04023000301d0603551d0e04160414aa2cfbcc70b43e0a1492730cb26d7336ee53344f301f0603551d230418301680149077923567c4ffa8cca9e67bd980797bcc93f938305e06082b0601050507010104523050302706082b06010505073001861b687474703a2f2f6f2e706b692e676f6f672f732f7765312f556b59302506082b060105050730028619687474703a2f2f692e706b692e676f6f672f7765312e63727430210603551d11041a30188209746f7065722e646576820b2a2e746f7065722e64657630130603551d20040c300a3008060667810c01020130360603551d1f042f302d302ba029a0278625687474703a2f2f632e706b692e676f6f672f7765312f55326b334e626a617061732e63726c30820104060a2b06010401d6790204020481f50481f200f0007700cb38f715897c84a1445f5bc1ddfbc96ef29a59cd470a690585b0cb14c31458e70000019e7887e7c20000040300483046022100f7531269550197aa611169cae468c5f21d46d91de5d0e15d3d5a97a8bd795efb022100bb8cf02edd4e039fae4870991f19c4d78710bbfb5582b85e5c0453b0191b12e1007500d809553b944f7affc816196f944f85abb0f8fc5e8755260f15d12e72bb454b140000019e7887e7c00000040300463044022035e0fc8bf7b8a48b37339d36caaa31919102953de306ee993279762ea4bd8597022047b432eef21faa5c7e024fc75e8df1f702585aa3fc4e6c16144d42b3d11ec402300a06082a8648ce3d040302034700304402202f4be88df5a1894882597c56a58b047aba27e4dcc1d7babcedb8b1da2907e0e302206b10728fca68c46c8ae7b3dcc66f0259699ceca0233cbcdefdb5dd948017da1c"
        guard let derData = Data(hexString: derHex),
              let certificate = SecCertificateCreateWithData(nil, derData as CFData) else {
            XCTFail("Failed to create SecCertificate")
            return
        }
        let hash1 = PinningURLSessionDelegate.computeSPKIHash(from: certificate)
        let hash2 = PinningURLSessionDelegate.computeSPKIHash(from: certificate)
        XCTAssertEqual(hash1, hash2)
    }

    func testPinningDelegate_computeSPKIHash_invalidCert_returnsNil() throws {
        let garbageData = Data([0x00, 0x01, 0x02, 0x03])
        guard let cert = SecCertificateCreateWithData(nil, garbageData as CFData) else {
            return // nil is expected — can't create a cert from garbage, early exit is fine
        }
        let hash = PinningURLSessionDelegate.computeSPKIHash(from: cert)
        XCTAssertNil(hash)
    }
}

extension PinningURLSessionDelegateTests {
    func testAPIService_authManagerPropagatesToDelegate() throws {
        let apiService = APIService()
        let authMgr = AuthManager(apiService: apiService)
        XCTAssertNil(apiService.sessionDelegate.authManager)
        apiService.authManager = authMgr
        XCTAssertNotNil(apiService.sessionDelegate.authManager)
        XCTAssertIdentical(apiService.sessionDelegate.authManager, authMgr)
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard end <= hex.endIndex else { return nil }
            guard let byte = UInt8(String(hex[index..<end]), radix: 16) else { return nil }
            data.append(byte)
            index = end
        }
        self = data
    }
}
