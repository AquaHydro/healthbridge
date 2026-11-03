import Foundation
import HealthKit
import SwiftUI

enum HealthType: String, CaseIterable, Codable, Identifiable {
  case sleep
  case heartRate = "heart_rate"
  case restingHR = "resting_hr"
  case hrv, steps
  var id: String { rawValue }
  var title: String {
    switch self {
    case .sleep: "睡眠"
    case .heartRate: "心率"
    case .restingHR: "静息心率"
    case .hrv: "心率变异性"
    case .steps: "步数"
    }
  }
  var icon: String {
    switch self {
    case .sleep: "bed.double.fill"
    case .steps: "figure.walk"
    default: "heart.fill"
    }
  }
  var color: Color {
    switch self {
    case .sleep: .indigo
    case .steps: .orange
    default: .red
    }
  }
  var unit: String? {
    switch self {
    case .sleep: nil
    case .steps: "count"
    case .hrv: "ms"
    default: "bpm"
    }
  }
  var displayUnit: String {
    switch self {
    case .sleep: "小时"
    case .steps: "步"
    case .hrv: "毫秒"
    default: "次/分"
    }
  }
  var hkType: HKSampleType {
    switch self {
    case .sleep: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    case .heartRate: HKObjectType.quantityType(forIdentifier: .heartRate)!
    case .restingHR: HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
    case .hrv: HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
    case .steps: HKObjectType.quantityType(forIdentifier: .stepCount)!
    }
  }
  var hkUnit: HKUnit {
    switch self {
    case .steps: .count()
    case .hrv: .secondUnit(with: .milli)
    default: HKUnit.count().unitDivided(by: .minute())
    }
  }
}
struct HealthSample: Codable, Sendable {
  let uuid: String
  let type: String
  let start_ms: Int64
  let end_ms: Int64
  let tz_min: Int
  let value: Double
  let unit: String?
  let source: String?
  let device: String?
  // Encode nil unit explicitly: the server requires null for sleep.
  enum CodingKeys: String, CodingKey {
    case uuid, type, start_ms, end_ms, tz_min, value, unit, source, device
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(uuid, forKey: .uuid)
    try c.encode(type, forKey: .type)
    try c.encode(start_ms, forKey: .start_ms)
    try c.encode(end_ms, forKey: .end_ms)
    try c.encode(tz_min, forKey: .tz_min)
    try c.encode(value, forKey: .value)
    try c.encode(unit, forKey: .unit)
    try c.encode(source, forKey: .source)
    try c.encode(device, forKey: .device)
  }
}
struct IngestBatch: Encodable {
  let schema_version = 1
  let added: [HealthSample]
  let deleted: [String]
  let types: [String]
}
struct ServerStatus: Decodable {
  let ok: Bool
  let version: String
  let schema_version: Int
  let counts: [String: Int]
}
struct IngestReceipt: Decodable {
  let ok: Bool
  let added: Int
  let deleted: Int
}
struct DayValue: Identifiable {
  let date: Date
  let value: Double
  var id: Date { date }
}
struct TypeProgress: Codable {
  var uploaded = 0
  var lastSuccess: Date?
  var message = "等待同步"
}
struct Preferences: Codable {
  var onboarded = false
  var authorizationPending = false
  var server = ""
  var consentDate: Date?
  var selected = Set(HealthType.allCases)
  var days = 30
  var since: [String: Date] = [:]
  var progress: [String: TypeProgress] = [:]
  var canSync: Bool { consentDate != nil && !server.isEmpty }
  var canUpload: Bool { canSync && onboarded && !authorizationPending }
  static let storageKey = "healthbridge.preferences.v1"
  static func load() -> Preferences {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
      let p = try? JSONDecoder().decode(Self.self, from: data)
    else { return .init() }
    return p
  }
  func save() {
    if let data = try? JSONEncoder().encode(self) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
extension Preferences {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
    authorizationPending = try c.decodeIfPresent(Bool.self, forKey: .authorizationPending) ?? false
    server = try c.decodeIfPresent(String.self, forKey: .server) ?? ""
    consentDate = try c.decodeIfPresent(Date.self, forKey: .consentDate)
    selected =
      try c.decodeIfPresent(Set<HealthType>.self, forKey: .selected) ?? Set(HealthType.allCases)
    days = try c.decodeIfPresent(Int.self, forKey: .days) ?? 30
    since = try c.decodeIfPresent([String: Date].self, forKey: .since) ?? [:]
    progress = try c.decodeIfPresent([String: TypeProgress].self, forKey: .progress) ?? [:]
  }
}
enum BridgeError: LocalizedError {
  case invalidURL, unauthorized, incompatible, unavailable, noHealth, keychain, invalidReceipt
  var errorDescription: String? {
    switch self {
    case .invalidURL: "请填写不含路径、账号或查询参数的 HTTPS 服务器地址。"
    case .unauthorized: "Token 无效，请重新输入写入 Token。"
    case .incompatible: "服务端版本不兼容，请更新服务端。"
    case .unavailable: "暂时无法连接，请检查网络和服务器后重试。"
    case .noHealth: "此设备无法读取健康数据。"
    case .keychain: "无法安全保存 Token，请解锁设备后重试。"
    case .invalidReceipt: "服务器未确认完整批次，稍后会安全重试。"
    }
  }
}
