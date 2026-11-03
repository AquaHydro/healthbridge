import Foundation
import HealthKit

/// The only path that produces a persistable anchor. Rejected receipts, cancellation,
/// or revoked consent throw before a new checkpoint can be stored.
struct PageTransfer {
  @MainActor static func acknowledgedAnchor(
    page: HealthPage,
    type: HealthType,
    allowed: () -> Bool,
    upload: (IngestBatch) async throws -> Void
  ) async throws -> Data {
    try Task.checkCancellation()
    guard allowed() else { throw CancellationError() }
    try await upload(IngestBatch(added: page.added, deleted: page.deleted, types: [type.rawValue]))
    try Task.checkCancellation()
    guard allowed() else { throw CancellationError() }
    return try NSKeyedArchiver.archivedData(
      withRootObject: page.anchor, requiringSecureCoding: true)
  }
}
