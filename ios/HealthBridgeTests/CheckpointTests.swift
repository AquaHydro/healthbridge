import HealthKit
import XCTest

@testable import HealthBridge

@MainActor final class CheckpointTests: XCTestCase {
  private var page: HealthPage {
    HealthPage(
      added: [], deleted: [UUID().uuidString], anchor: HKQueryAnchor(fromValue: 7), count: 1)
  }
  func testNoConsentNeverStartsUpload() async {
    var called = false
    do {
      _ = try await PageTransfer.acknowledgedAnchor(page: page, type: .steps, allowed: { false }) {
        _ in called = true
      }
      XCTFail("Must refuse")
    } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertFalse(called)
  }
  func testFailedReceiptProducesNoCheckpoint() async {
    do {
      _ = try await PageTransfer.acknowledgedAnchor(page: page, type: .steps, allowed: { true }) {
        _ in throw BridgeError.invalidReceipt
      }
      XCTFail("Must not commit")
    } catch { XCTAssertTrue(error is BridgeError) }
  }
  func testRevocationWhileRequestIsInFlightProducesNoCheckpoint() async {
    var consent = true
    do {
      _ = try await PageTransfer.acknowledgedAnchor(page: page, type: .steps, allowed: { consent })
      { _ in consent = false }
      XCTFail("Must not commit")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testAcknowledgedDeletionCanAdvanceAnchor() async throws {
    let data = try await PageTransfer.acknowledgedAnchor(
      page: page, type: .steps, allowed: { true }
    ) { batch in
      XCTAssertEqual(batch.deleted.count, 1)
      XCTAssertEqual(batch.types, ["steps"])
    }
    XCTAssertNotNil(try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data))
  }
  func testCancelledUploadCannotCommitEvenIfTransportReturnsSuccess() async {
    let page = page
    let task = Task {
      try await PageTransfer.acknowledgedAnchor(page: page, type: .steps, allowed: { true }) { _ in
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Must not commit")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
}
