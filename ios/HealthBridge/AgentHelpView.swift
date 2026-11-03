import SwiftUI

struct AgentHelpView: View {
  @Environment(AppModel.self) private var model
  @State private var input = ""
  @State private var saved: String?
  @State private var savedOrigin: String?
  @State private var client = AgentClient.codex
  @State private var includeToken = true
  @State private var busy = false
  @State private var message: String?
  private var url: URL? { try? ServerAPI.normalizedURL(model.preferences.server) }
  private var canCopyToken: Bool {
    saved != nil && input == saved && !busy && url.map(CredentialRules.origin) == savedOrigin
  }
  var body: some View {
    Form {
      if let url {
        Section("MCP 地址") {
          Text(url.appendingPathComponent("mcp").absoluteString).font(.footnote.monospaced())
            .textSelection(.enabled)
          Button("复制 MCP 地址") {
            copy(url.appendingPathComponent("mcp").absoluteString, label: "MCP 地址")
          }
        }
        Section {
          SecureField("MCP_TOKEN", text: $input).textContentType(.init(rawValue: ""))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled().accessibilityIdentifier("mcpToken")
          PasteButton(payloadType: String.self) { values in
            if let text = values.first { input = text }
          }
          Button {
            Task { await verify() }
          } label: {
            HStack {
              Text(busy ? "正在验证" : "验证并保存只读 Token")
              Spacer()
              if busy { ProgressView() }
            }
          }.disabled(busy || input.isEmpty).accessibilityIdentifier("saveMCPToken")
          if canCopyToken { Label("只读连接已验证", systemImage: "checkmark.shield") }
          Button("复制只读 Token") { if let saved { copy(saved, label: "只读 Token") } }.disabled(
            !canCopyToken)
        } header: {
          Text("只读 Token")
        } footer: {
          Text("导入部署时的 MCP_TOKEN，验证后按服务器分别保存在钥匙串。此页面不会复制写入 Token，也不会调用健康查询工具。")
        }
        Section("客户端配置") {
          Picker("客户端", selection: $client) {
            ForEach(AgentClient.allCases) { Text($0.rawValue).tag($0) }
          }
          Toggle("复制时包含只读 Token", isOn: $includeToken)
          Text((try? client.configuration(origin: url, token: nil)) ?? "").font(
            .caption.monospaced()
          ).textSelection(.enabled)
          Button(includeToken ? "复制完整配置" : "复制配置模板") {
            do {
              copy(
                try client.configuration(origin: url, token: includeToken ? saved : nil),
                label: includeToken ? "完整配置" : "配置模板")
            } catch { message = "无法生成配置，请检查 Token。" }
          }.disabled(includeToken && !canCopyToken).accessibilityIdentifier("copyAgentConfig")
          Text("预览始终隐藏 Token。包含 Token 的配置只粘贴到自己的客户端私有配置中，不要提交到 Git。复制内容 2 分钟后过期。").font(.footnote)
            .foregroundStyle(.secondary)
          if client == .codex { Text("粘贴到个人 config.toml。若已存在 healthbridge 配置，请替换对应段落。") }
          if client == .claude { Text("合并到 Claude Code 的个人 MCP 配置，保留其他服务器条目。") }
          if client == .generic {
            Text("用于支持 Streamable HTTP 和自定义 Authorization 头的客户端；字段位置按客户端要求调整。")
          }
        }
      } else {
        Section {
          ContentUnavailableView(
            "请先连接服务器", systemImage: "network", description: Text("连接后即可保存只读 Token 并复制 Agent 配置。"))
          Button("连接服务器") { model.connectionSheet = true }
        }
      }
      if let message {
        Section {
          Text(message).foregroundStyle(.secondary).accessibilityIdentifier("agentFeedback")
        }
      }
      Section("只读查询") {
        Text(
          "先调用 get_sync_status 检查数据新鲜度，再调用 query_samples、aggregate 或 sleep_summary。仅支持 OAuth 的连接器不能直接使用此 Token。"
        )
      }
    }.navigationTitle("连接 AI Agent")
      .task(id: model.preferences.server) {
        saved = nil
        savedOrigin = nil
        input = ""
        message = nil
        if let url {
          do {
            saved = try Keychain.readMCP(for: url)
            savedOrigin = CredentialRules.origin(url)
            input = saved ?? ""
          } catch { message = "无法读取钥匙串，请解锁后重试。" }
        }
      }
  }
  private func verify() async {
    guard let url else { return }
    let submitted = input
    let server = model.preferences.server
    busy = true
    message = nil
    defer { busy = false }
    do {
      let token = try CredentialRules.token(submitted)
      guard token != (try Keychain.read()) else { throw CredentialError.sameToken }
      try await ServerAPI(base: url, token: token).verifyMCP()
      guard input == submitted && model.preferences.server == server else { return }
      try Keychain.saveMCP(token, for: url)
      input = token
      saved = token
      savedOrigin = CredentialRules.origin(url)
      message = "只读 Token 已验证并安全保存。"
    } catch { message = (error as? LocalizedError)?.errorDescription ?? "暂时无法验证，请检查网络后重试。" }
  }
  private func copy(_ value: String, label: String) {
    SecureCopy.text(value)
    message = "已复制\(label)，请在 2 分钟内粘贴。"
  }
}
