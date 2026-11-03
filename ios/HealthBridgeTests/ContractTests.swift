import XCTest

@testable import HealthBridge

final class ContractTests: XCTestCase {
  func testConnectionRequiresOriginOnlyHTTPS() throws {
    for invalid in [
      "http://example.com", "https://a:b@example.com", "https://example.com/path",
      "https://example.com?token=x", "https://example.com#token",
    ] { XCTAssertThrowsError(try ServerAPI.normalizedURL(invalid)) }
    XCTAssertEqual(try ServerAPI.normalizedURL("https://example.com/").host, "example.com")
  }
  func testSleepEncodesExplicitNullUnit() throws {
    let sample = HealthSample(
      uuid: UUID().uuidString, type: "sleep", start_ms: 0, end_ms: 1, tz_min: 0, value: 3,
      unit: nil, source: "Synthetic", device: nil)
    let data = try JSONEncoder().encode(sample)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertTrue(object["unit"] is NSNull)
  }
  func testSharingRequiresBothConnectionAndExplicitConsent() {
    var p = Preferences()
    XCTAssertFalse(p.canSync)
    p.server = "https://example.com"
    XCTAssertFalse(p.canSync)
    p.consentDate = Date()
    XCTAssertTrue(p.canSync)
    p.consentDate = nil
    XCTAssertFalse(p.canSync)
  }
}

extension ContractTests {
  func testOlderSavedPreferencesKeepConnectionAndConsent() throws {
    var p = Preferences()
    p.onboarded = true
    p.server = "https://example.com"
    p.consentDate = Date()
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
    object.removeValue(forKey: "authorizationPending")
    let restored = try JSONDecoder().decode(
      Preferences.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(restored.server, p.server)
    XCTAssertTrue(restored.canUpload)
  }
  func testIncompleteHealthSetupCannotUpload() {
    var p = Preferences()
    p.server = "https://example.com"
    p.consentDate = Date()
    XCTAssertFalse(p.canUpload)
    p.onboarded = true
    XCTAssertTrue(p.canUpload)
    p.authorizationPending = true
    XCTAssertFalse(p.canUpload)
  }
}
