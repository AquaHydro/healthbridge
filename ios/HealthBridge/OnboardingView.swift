import SwiftUI

let sharingText =
  "你选择的健康数据将发送到下方配置的服务器，保存在你自己的 Cloudflare 账号中。持有 MCP 只读 Token 的 AI Agent 可以查询已上传数据。你接入的 AI 服务可能按其自身政策处理这些数据。HealthBridge 不向开发者的服务器发送健康数据。你可随时撤回共享，停止之后的上传；已上传的数据仍可被 Agent 读取，需另行删除服务器数据或轮换 MCP Token。"

struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @State private var local = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(spacing: 14) {
            Image(systemName: "heart.text.clipboard.fill").font(.system(size: 56)).foregroundStyle(
              .blue
            ).frame(width: 94, height: 94).background(
              .blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
            Text("欢迎使用 HealthBridge").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("让 AI 了解你的健康，数据由你掌控。").foregroundStyle(.secondary).multilineTextAlignment(.center)
          }.frame(maxWidth: .infinity)
          HStack {
            flow("iphone", "iPhone")
            Image(systemName: "arrow.right")
            flow("cloud", "你的 Cloudflare")
            Image(systemName: "arrow.right")
            flow("sparkles", "AI Agent")
          }.foregroundStyle(.secondary).padding().background(
            .background, in: RoundedRectangle(cornerRadius: 16))
          feature("lock.shield", "数据由你掌控", "只同步到你配置的服务器，随时停止共享。")
          feature("heart", "先在本机查看", "睡眠、心率与步数概览直接读取 Apple 健康。")
          feature("arrow.triangle.2.circlepath", "自动增量同步", "后台频率由 iOS 决定，锁屏后通常在解锁时补齐。")
          NavigationLink("连接我的服务器") { ConnectionView(onboarding: true) }.buttonStyle(
            PrimaryButton())
          NavigationLink("仅在本机查看") { TypeSelectionView(onboarding: true) }.frame(
            maxWidth: .infinity)
        }.padding(20)
      }.background(Color(.systemGroupedBackground)).navigationBarTitleDisplayMode(.inline)
    }
  }
  private func flow(_ icon: String, _ text: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: icon).font(.title2)
      Text(text).font(.caption).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity)
  }
  private func feature(_ icon: String, _ title: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon).font(.title2).foregroundStyle(.blue).frame(width: 30)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.headline)
        Text(text).font(.subheadline).foregroundStyle(.secondary)
      }
    }
  }
}
struct PrimaryButton: ButtonStyle {
  @Environment(\.isEnabled) var enabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
      .foregroundStyle(.white).background(
        enabled ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: 14)
      ).opacity(configuration.isPressed ? 0.75 : 1)
  }
}
struct ConnectionView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var onboarding = false
  @State private var address = ""
  @State private var token = ""
  @State private var mcpToken = ""
  private enum Field: Hashable { case address, ingest }
  @FocusState private var editing: Field?
  @State private var showGeneration = false
  @State private var showReadToken = false
  @State private var loaded = false
  @State private var result: ServerStatus?
  @State private var message: String?
  @State private var busy = false
  @State private var advance = false
  var body: some View {
    Form {
      Section { Text("填写你自己的服务器地址和写入 Token。测试连接不会发送健康数据。").foregroundStyle(.secondary) }
      Section {
        Button("生成新 Token") { showGeneration = true }
        Text("首次部署可在这里生成；已有服务器请填写现有 Token。生成后需配置到 Cloudflare 才会生效。").font(.footnote)
          .foregroundStyle(.secondary)
      }
      Section("服务器") {
        TextField("https://你的服务.workers.dev", text: $address).textInputAutocapitalization(.never)
          .autocorrectionDisabled().keyboardType(.URL).focused($editing, equals: .address)
          .accessibilityIdentifier(
            "serverURL")
        SecureField("INGEST_TOKEN", text: $token).textInputAutocapitalization(.never)
          .autocorrectionDisabled().textContentType(.init(rawValue: "")).focused(
            $editing, equals: .ingest
          ).accessibilityIdentifier("ingestToken")
        Button {
          if let value = UIPasteboard.general.string { token = value }
        } label: {
          Label("粘贴 Token", systemImage: "doc.on.clipboard")
        }
      }
      Section {
        Button(mcpToken.isEmpty ? "添加只读 Token（选填）" : "更换只读 Token") { showReadToken = true }
        if !mcpToken.isEmpty {
          Label("只读 Token 已填写，等待连接验证", systemImage: "key")
          Button("暂不填写只读 Token") { mcpToken = "" }
        }
      } header: {
        Text("Agent 只读 Token")
      } footer: {
        Text("填写后会同时验证并保存，之后可在“连接 AI Agent”页快捷复制。也可稍后导入。")
      }
      Section {
        Button {
          Task { await test() }
        } label: {
          HStack {
            Text(busy ? "正在测试连接" : "测试连接")
            Spacer()
            if busy { ProgressView() }
          }
        }.disabled(busy || address.isEmpty || token.isEmpty)
        if let result {
          Label(
            "连接成功 · v\(result.version) · \(result.counts.values.reduce(0,+)) 条样本",
            systemImage: "checkmark.circle.fill"
          ).foregroundStyle(.green)
        }
        if let message { Label(message, systemImage: "info.circle").foregroundStyle(.secondary) }
      }
      Section {
        Button("继续") { Task { await next() } }.disabled(result == nil || busy)
        NavigationLink("如何部署服务器") { DeploymentHelpView() }
      } footer: {
        Text("两种 Token 分开保存在本机钥匙串。连接通过后才启用；生成草稿不会替换现有连接。")
      }
    }.navigationTitle("连接服务器")
      .onAppear {
        guard !loaded else { return }
        loaded = true
        address = model.preferences.server
        if !address.isEmpty {
          token = (try? Keychain.read()) ?? ""
          if let url = try? ServerAPI.normalizedURL(address) {
            mcpToken = (try? Keychain.readMCP(for: url)) ?? ""
          }
        }
      }
      .onChange(of: address) { _, _ in result = nil }
      .onChange(of: token) { _, _ in result = nil }
      .onChange(of: mcpToken) { _, _ in result = nil }
      .sheet(isPresented: $showGeneration) {
        TokenSetupView { pair in
          token = pair.ingest
          mcpToken = pair.mcp
          result = nil
        }
      }
      .sheet(isPresented: $showReadToken) {
        ReadTokenInputView(initial: mcpToken) {
          mcpToken = $0
          result = nil
        }
      }
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完成") { editing = nil }
        }
      }
      .navigationDestination(isPresented: $advance) { ConsentView(onboarding: onboarding) }
      .toolbar { if onboarding { NavigationLink("暂不连接") { TypeSelectionView(onboarding: true) } } }
  }
  private func test() async {
    busy = true
    result = nil
    message = nil
    let submittedAddress = address
    let submittedToken = token
    let submittedMCP = mcpToken
    defer { busy = false }
    do {
      let writeToken = try CredentialRules.token(submittedToken)
      let readToken = submittedMCP.isEmpty ? nil : try CredentialRules.token(submittedMCP)
      if let readToken, readToken == writeToken { throw CredentialError.sameToken }
      let base = try ServerAPI.normalizedURL(submittedAddress)
      let status = try await ServerAPI(
        base: base, token: writeToken
      ).ping()
      if let readToken { try await ServerAPI(base: base, token: readToken).verifyMCP() }
      if address == submittedAddress && token == submittedToken && mcpToken == submittedMCP {
        result = status
      }
    } catch { message = (error as? LocalizedError)?.errorDescription ?? "暂时无法连接，请检查地址与网络后重试。" }
  }
  private func next() async {
    guard let result else { return }
    do {
      try await model.connect(
        url: ServerAPI.normalizedURL(address), token: CredentialRules.token(token), status: result,
        mcpToken: mcpToken.isEmpty ? nil : CredentialRules.token(mcpToken))
      if model.preferences.canSync && !onboarding {
        await model.configureObservers()
        model.startSync()
        dismiss()
      } else {
        advance = true
      }
    } catch { message = "无法保存连接，请解锁设备后重试。" }
  }
}
struct ConsentView: View {
  @Environment(AppModel.self) private var model
  var onboarding = false
  @State private var proceed = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Image(systemName: "lock.shield.fill").font(.system(size: 48)).foregroundStyle(.blue)
        Text("共享健康数据前，请确认").font(.largeTitle.bold())
        Text(model.preferences.server).font(.footnote.monospaced()).textSelection(.enabled)
        Text(sharingText).lineSpacing(6)
        NavigationLink("阅读隐私说明") { PrivacyView() }
        Button("同意并继续") {
          model.grantConsent()
          proceed = true
        }.buttonStyle(PrimaryButton())
        Button("不同意，仅在本机查看") {
          Task {
            await model.disconnect()
            proceed = true
          }
        }.frame(maxWidth: .infinity)
      }.padding(24)
    }.background(Color(.systemGroupedBackground)).navigationTitle("数据共享同意")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(isPresented: $proceed) { TypeSelectionView(onboarding: onboarding) }
  }
}
struct TypeSelectionView: View {
  @Environment(AppModel.self) private var model
  var onboarding = false
  @State private var authorizing = false
  @State private var progress = false
  var body: some View {
    Form {
      Section("选择要读取的数据") {
        ForEach(HealthType.allCases) { type in
          Toggle(
            isOn: Binding(
              get: { model.preferences.selected.contains(type) },
              set: { value in
                if value {
                  model.preferences.selected.insert(type)
                } else {
                  model.preferences.selected.remove(type)
                }
                model.save()
              })
          ) { Label(type.title, systemImage: type.icon).foregroundStyle(type.color) }
        }
      }
      if model.preferences.canSync {
        Section("首次同步范围") {
          Picker(
            "时间范围",
            selection: Binding(
              get: { model.preferences.days },
              set: {
                let days = $0
                Task { await model.setRange(days) }
              })
          ) {
            ForEach([7, 30, 90, 365, 0], id: \.self) { Text($0 == 0 ? "全部" : "最近 \($0) 天").tag($0) }
          }
        }
      }
      Section {
        Text("下一步由 iOS 询问读取权限。HealthBridge 不写入或修改健康数据。iOS 不会告诉 App 你是否拒绝了某项读取，空数据也可能表示该范围尚无记录。")
          .foregroundStyle(.secondary)
        Button(authorizing ? "等待系统授权" : "允许读取健康数据") {
          Task {
            authorizing = true
            await model.authorize()
            authorizing = false
            if model.preferences.onboarded {
              model.connectionSheet = false
              model.consentSheet = false
              model.selectedTab = model.preferences.canSync ? 1 : 0
            }
          }
        }.disabled(authorizing || model.preferences.selected.isEmpty)
        if let notice = model.notice { Text(notice).foregroundStyle(.secondary) }
      }
    }.navigationTitle("数据类型与范围")
  }
}
struct PrivacyView: View {
  var body: some View {
    ScrollView {
      Text(
        "HealthBridge 只读取你选择的健康数据，不修改 Apple 健康记录。概览在本机计算。\n\n仅在明确同意后，所选数据、样本时间、时区与来源会通过 HTTPS 发往你配置的服务器。上传 Token 保存在本机钥匙串。应用无广告、分析或第三方追踪 SDK。\n\n持有 MCP Token 的客户端可以读取服务器数据。请仅交给可信赖的 AI 服务，并检查其隐私政策。\n\n撤回同意停止后续上传；已上传的数据仍保留。你可以删除服务器数据、断开连接，或在自己的 Cloudflare 账号中轮换 Token。Cloudflare 的备份保留遵循其服务政策，逻辑删除不代表立即清除所有备份。\n\n系统健康授权可在 iPhone 设置中的健康数据访问页面管理。"
      ).padding(24).lineSpacing(6)
    }.navigationTitle("隐私说明")
  }
}
struct DeploymentHelpView: View {
  var body: some View {
    List {
      Text("在自己的 Cloudflare 账号中创建专属 D1 数据库和 Worker，将 DB 绑定到数据库，应用仓库 server/migrations 下的迁移。")
      Text(
        "分别生成两个随机 Token，将 INGEST_TOKEN 和 MCP_TOKEN 保存为 Worker Secrets。两者不可相同。部署完成后，将 HTTPS 地址和写入 Token 填入 App。"
      )
      Text("完整命令、依赖版本、迁移与验证步骤见项目 README。请勿把 Token 放在 URL、聊天或 Git 中。")
    }.navigationTitle("部署服务器")
  }
}
