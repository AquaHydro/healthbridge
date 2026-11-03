import Foundation
import HealthKit
import Observation
import UIKit

@MainActor @Observable final class AppModel {
  static let shared = AppModel()
  var preferences = Preferences.load()
  var overview: [HealthType: [DayValue]] = [:]
  var overviewLoading = false
  var notice: String?
  var syncing = false
  var serverStatus: ServerStatus?
  var selectedTab = 0
  var connectionSheet = false
  var consentSheet = false
  let health = HealthStore()
  private var observers: [HealthType: HKObserverQuery] = [:]
  private var syncTask: Task<Void, Never>?
  private var generation = 0
  private var maintenance = false
  private var retryTask: Task<Void, Never>?
  private var retryAttempt = 0
  private var nextTypeIndex = 0
  private var overviewTask: Task<Void, Never>?

  var isUITesting: Bool {
    #if DEBUG && targetEnvironment(simulator)
      ProcessInfo.processInfo.arguments.contains("--ui-test")
    #else
      false
    #endif
  }
  init() {
    #if DEBUG && targetEnvironment(simulator)
      let args = ProcessInfo.processInfo.arguments
      if args.contains("--ui-test") {
        preferences = Preferences()
        preferences.onboarded = !args.contains("--ui-intro")
        if args.contains("--ui-agent") {
          preferences.server = "https://example.invalid"
          selectedTab = 2
          try? Keychain.save("synthetic-writer-test")
          try? Keychain.deleteMCP(for: URL(string: preferences.server)!)
        }
        if args.contains("--ui-fixtures") {
          for type in HealthType.allCases {
            overview[type] = (0..<30).map { index in
              let day = Calendar.current.date(
                byAdding: .day, value: index - 29, to: Calendar.current.startOfDay(for: Date()))!
              let value: Double =
                type == .sleep
                ? 6.5 + Double(index % 4) / 3
                : type == .steps ? Double(4000 + index * 103) : Double(50 + index % 15)
              return DayValue(date: day, value: value)
            }
          }
        }
        if args.contains("--ui-failure") || args.contains("--ui-lock")
          || args.contains("--ui-progress") || args.contains("--ui-paused")
        {
          preferences.server = "https://example.invalid"
          preferences.consentDate = args.contains("--ui-paused") ? nil : Date()
          selectedTab = 1
          if args.contains("--ui-failure") { notice = "本次尚未完成，将在网络恢复或下次打开时重试" }
          if args.contains("--ui-lock") { notice = "iPhone 锁定时无法读取健康数据，解锁后继续" }
          if args.contains("--ui-progress") { syncing = true }
        }
      }
    #endif
  }

  var statusText: String {
    if !preferences.canSync {
      return preferences.consentDate == nil && !preferences.server.isEmpty
        ? "同步已暂停 · 已撤回共享" : "本机模式 · 未上传"
    }
    if preferences.authorizationPending { return "等待完成健康授权" }
    if syncing { return "正在同步健康数据" }
    if let notice { return notice }
    if let date = preferences.progress.values.compactMap(\.lastSuccess).max() {
      return "上次同步 \(date.formatted(.relative(presentation: .named)))"
    }
    return "等待首次同步"
  }
  func save() { if !isUITesting { preferences.save() } }
  func api() throws -> ServerAPI {
    ServerAPI(base: try ServerAPI.normalizedURL(preferences.server), token: try Keychain.read())
  }
  func connect(url: URL, token: String, status: ServerStatus, mcpToken: String? = nil) async throws
  {
    await stopSync()
    if let mcpToken { try Keychain.saveMCP(mcpToken, for: url) }
    try Keychain.save(token)
    let changed =
      preferences.server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      != url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    preferences.server = url.absoluteString
    if changed {
      preferences.consentDate = nil
      resetAnchors()
      preferences.progress = [:]
    }
    serverStatus = status
    save()
    try? Keychain.clearPendingPair(matching: token)
  }
  func grantConsent() {
    preferences.authorizationPending = true
    preferences.consentDate = Date()
    save()
  }
  func revokeConsent() async {
    preferences.consentDate = nil
    save()
    await stopSync()
    await configureObservers()
    notice = nil
  }
  func disconnect() async {
    preferences.consentDate = nil
    save()
    await stopSync()
    await configureObservers()
    if let url = try? ServerAPI.normalizedURL(preferences.server) {
      try? Keychain.deleteMCP(for: url)
    }
    Keychain.delete()
    preferences.server = ""
    resetAnchors()
    preferences.progress = [:]
    serverStatus = nil
    notice = nil
    save()
  }
  func authorize() async {
    preferences.authorizationPending = true
    save()
    await stopSync()
    do {
      try await health.authorize(preferences.selected)
      preferences.onboarded = true
      preferences.authorizationPending = false
      save()
      await configureObservers()
      refreshOverview()
      startSync()
    } catch { notice = "无法打开健康授权，请稍后重试。" }
  }
  func setType(_ type: HealthType, enabled: Bool) async {
    let previous = preferences.selected
    if enabled { preferences.authorizationPending = true }
    if enabled { preferences.selected.insert(type) } else { preferences.selected.remove(type) }
    save()
    await stopSync()
    if enabled {
      do { try await health.authorize([type]) } catch {
        preferences.selected = previous
        notice = "请在系统设置中检查健康访问权限。"
      }
      preferences.authorizationPending = false
      save()
    }
    await configureObservers()
    refreshOverview()
    startSync()
  }
  func setRange(_ days: Int) async {
    guard days != preferences.days else { return }
    let expands = days == 0 || (preferences.days != 0 && days > preferences.days)
    await stopSync()
    preferences.days = days
    if expands { resetAnchors() }
    save()
    startSync()
  }
  func resetAnchors() {
    for type in HealthType.allCases {
      UserDefaults.standard.removeObject(forKey: "anchor.\(type.rawValue)")
    }
    preferences.since = [:]
  }
  func deleteServerData() async throws {
    guard !maintenance else { return }
    maintenance = true
    defer {
      maintenance = false
      startSync()
    }
    await stopSync()
    try await api().deleteAll()
    resetAnchors()
    // A fixed lower bound prevents old history returning after an intentional purge.
    for type in HealthType.allCases {
      preferences.since[type.rawValue] = Date()
      preferences.progress[type.rawValue] = .init(message: "服务器数据已删除，之后只同步新数据")
    }
    save()
    serverStatus = try await api().ping()
    startSync()
  }
  func foreground() {
    refreshOverview()
    startSync()
  }
  func refreshOverview() {
    guard !isUITesting else { return }
    overviewTask?.cancel()
    overviewTask = Task {
      overviewLoading = true
      defer { overviewLoading = false }
      for type in HealthType.allCases where preferences.selected.contains(type) {
        do {
          let values = try await health.overview(type)
          try Task.checkCancellation()
          overview[type] = values
        } catch is CancellationError { return } catch {
          overview[type] = []
          if !UIApplication.shared.isProtectedDataAvailable { notice = "等待解锁后读取健康数据" }
        }
      }
    }
  }
  // Called synchronously from didFinishLaunching, before HealthKit delivers background events.
  func registerLaunchObservers() {
    guard !isUITesting else { return }
    guard preferences.canUpload, HKHealthStore.isHealthDataAvailable() else { return }
    for type in preferences.selected { register(type) }
  }
  private func register(_ type: HealthType) {
    guard observers[type] == nil else { return }
    let query = HKObserverQuery(sampleType: type.hkType, predicate: nil) { _, completion, error in
      Task { @MainActor in
        defer { completion() }
        if error != nil {
          self.notice = "等待解锁或下次打开后继续同步"
          return
        }
        self.startSync()
        await self.syncTask?.value
      }
    }
    observers[type] = query
    health.store.execute(query)
  }
  func configureObservers() async {
    for (type, query) in observers
    where !preferences.canSync || !preferences.selected.contains(type) {
      health.store.stop(query)
      observers.removeValue(forKey: type)
      try? await health.store.disableBackgroundDelivery(for: type.hkType)
    }
    guard preferences.canSync else {
      try? await health.store.disableAllBackgroundDelivery()
      return
    }
    for type in preferences.selected {
      register(type)
      do {
        try await health.store.enableBackgroundDelivery(for: type.hkType, frequency: .immediate)
      } catch { notice = "后台交付暂不可用，打开 App 仍可同步。" }
    }
  }
  func stopSync() async {
    generation += 1
    retryTask?.cancel()
    retryTask = nil
    let task = syncTask
    syncTask?.cancel()
    await task?.value
    syncTask = nil
    syncing = false
  }
  func startSync() {
    guard !isUITesting else { return }
    guard syncTask == nil, !maintenance, preferences.canUpload else { return }
    let epoch = generation
    syncTask = Task {
      syncing = true
      var backgroundID = UIBackgroundTaskIdentifier.invalid
      backgroundID = UIApplication.shared.beginBackgroundTask(withName: "HealthBridge sync") {
        self.syncTask?.cancel()
      }
      defer {
        if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID) }
        syncing = false
        syncTask = nil
      }
      let deadline = Date().addingTimeInterval(25)
      var shouldRetry = false
      var hadFailure = false
      let all = HealthType.allCases
      let ordered = Array(all[nextTypeIndex...]) + Array(all[..<nextTypeIndex])
      for type in ordered where preferences.selected.contains(type) {
        guard valid(epoch, type), Date() < deadline else { break }
        do {
          let api = try api()
          let since =
            preferences.since[type.rawValue]
            ?? (preferences.days == 0
              ? Date(timeIntervalSince1970: 0)
              : Calendar.current.date(byAdding: .day, value: -preferences.days, to: Date())!)
          preferences.since[type.rawValue] = since
          save()
          var anchor = loadAnchor(type)
          repeat {
            guard valid(epoch, type) else { break }
            preferences.progress[type.rawValue, default: .init()].message = "正在读取并上传"
            let page = try await health.page(type, since: since, anchor: anchor)
            try Task.checkCancellation()
            guard valid(epoch, type) else { break }
            // One HealthKit page is one server transaction; persist only its acknowledged anchor.
            let data = try await PageTransfer.acknowledgedAnchor(
              page: page, type: type, allowed: { self.valid(epoch, type) }, upload: api.upload)
            UserDefaults.standard.set(data, forKey: "anchor.\(type.rawValue)")
            anchor = page.anchor
            nextTypeIndex = (all.firstIndex(of: type)! + 1) % all.count
            preferences.progress[type.rawValue, default: .init()].uploaded += page.added.count
            preferences.progress[type.rawValue, default: .init()].lastSuccess = Date()
            preferences.progress[type.rawValue, default: .init()].message =
              page.count == 0 ? "已检查最新变化" : "已确认上传"
            save()
            notice = nil
            if page.count == 0 { break }
            if Date() >= deadline {
              shouldRetry = true
              break
            }
          } while valid(epoch, type)
        } catch is CancellationError { break } catch {
          guard valid(epoch, type) else { break }
          let message: String
          if let error = error as? BridgeError {
            message = error.localizedDescription
          } else if !UIApplication.shared.isProtectedDataAvailable {
            message = "iPhone 锁定时无法读取健康数据，解锁后继续"
          } else {
            message = "本次尚未完成，将在网络恢复或下次打开时重试"
          }
          preferences.progress[type.rawValue, default: .init()].message = message
          notice = message
          save()
          shouldRetry = true
          hadFailure = true
        }
      }
      if Date() >= deadline { shouldRetry = true }
      if shouldRetry && preferences.canSync && !Task.isCancelled {
        retryAttempt = hadFailure ? min(retryAttempt + 1, 5) : 0
        let delay = UInt64(hadFailure ? min(300, 5 * (1 << retryAttempt)) : 2)
        retryTask?.cancel()
        retryTask = Task {
          try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
          guard !Task.isCancelled else { return }
          startSync()
        }
      } else {
        retryAttempt = 0
      }
    }
  }
  private func valid(_ epoch: Int, _ type: HealthType) -> Bool {
    !Task.isCancelled && generation == epoch && preferences.canUpload
      && preferences.selected.contains(type)
  }
  private func loadAnchor(_ type: HealthType) -> HKQueryAnchor? {
    guard let data = UserDefaults.standard.data(forKey: "anchor.\(type.rawValue)") else {
      return nil
    }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
  }
}
