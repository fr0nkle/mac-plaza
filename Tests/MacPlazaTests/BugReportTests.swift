import XCTest
@testable import MacPlaza

final class BugReportTests: XCTestCase {
    func testMailReportUsesRequestedRecipientAndSafelyEncodedVersion() throws {
        let url = BugReport.emailURL(version: "0.22.0 & preview")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "alexanderhosier@squidproductions.org")
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["subject"], "Mac Plaza 0.22.0 & preview bug report")
        XCTAssertTrue(values["body"]?.contains("Steps to reproduce:") == true)
        XCTAssertEqual(Set(values.keys), ["subject", "body"], "No saved data, identity, or attachment is included")
    }
}
