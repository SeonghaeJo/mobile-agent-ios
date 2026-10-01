import XCTest
@testable import OpenClawKit

final class ProtocolTests: XCTestCase {
    func testResponseFrameDecodesHelloOK() throws {
        let data = Data(#"{"type":"res","id":"1","ok":true,"payload":{"type":"hello-ok","protocol":4}}"#.utf8)
        let response = try JSONDecoder().decode(ResponseFrame.self, from: data)
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.payload?["type"]?.string, "hello-ok")
        XCTAssertEqual(response.payload?["protocol"]?.double, 4)
    }

    func testChallengeAndSessionChangedFramesDecode() throws {
        let challenge = try JSONDecoder().decode(EventFrame.self, from: Data(#"{"type":"event","event":"connect.challenge","payload":{"nonce":"n","ts":1700000000000}}"#.utf8))
        XCTAssertEqual(challenge.event, "connect.challenge")
        let changed = try JSONDecoder().decode(EventFrame.self, from: Data(#"{"type":"event","event":"sessions.changed","payload":{"reason":"updated"}}"#.utf8))
        XCTAssertEqual(changed.event, "sessions.changed")
    }
}
