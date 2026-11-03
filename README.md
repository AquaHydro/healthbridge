# HealthBridge

iPhone 在本机显示 HealthKit 概览，并在你明确同意后增量同步到你自己的 Cloudflare Worker + D1，供个人 AI Agent 通过只读 MCP 查询。单用户自部署，无托管账号、付费功能或服务端面板。

当前已实现服务端和 SwiftUI App，并完成真实 Cloudflare 部署、HTTPS 合成数据闭环及 MCP SDK 客户端调用。真机读取与首次上传已打通；完整验收进度见 [MVP 验收记录](docs/verification/MVP.md)。不能把模拟器或构建通过当作后台、锁屏与真机删除同步验收。

## 从全新环境开始

需要 Node.js 24 LTS、npm；iOS 需要 macOS、Xcode 及支持 HealthKit 的已配对 iPhone。Xcode 工程已提交，不需要 XcodeGen 才能构建。

```sh
nvm use
npm ci
npm run check
```

`check` 运行格式检查、类型检查、Workers 运行时测试和本地部署打包预检，不会部署远程资源。

## 本地服务端

```sh
cp server/.dev.vars.example server/.dev.vars
cd server
npx wrangler d1 migrations apply DB --local
npm run dev
```

示例 Token 只用于本机合成数据，不可部署到公网。所有端点包括 `/healthz` 都要鉴权，未授权返回 401。`/healthz` 只表示进程存活，`/v1/ping` 同时检查数据库读取。

## 在自己的 Cloudflare 账号部署

Cloudflare 插件登录和本机 Wrangler 登录互相独立。使用 CLI 时先执行 `npx wrangler login`，再用 `npx wrangler whoami` 核对账号。

```sh
cd server
npx wrangler login
npx wrangler whoami
npx wrangler d1 create healthbridge
```

当前配置的数据库 ID 属于本项目现有部署。新用户必须将它替换为自己刚创建的数据库 ID，不能沿用。将输出的 `database_id` 写入 `server/wrangler.jsonc` 对应的 `d1_databases[0]`。如账号已有同名数据库或 Worker，先核对归属；不要覆盖其他项目。多人共享 Cloudflare 账号时也需要使用你自己的专属 Worker 和数据库。

在密码管理器中分别生成并保管两个独立的 32 字节以上随机 Token。可用 `openssl rand -hex 32 | pbcopy` 将随机 Token 直接复制到 macOS 剪贴板，保存到密码管理器后再生成另一个；不要粘贴到聊天、Git、URL 或日志。

```sh
npx wrangler secret put INGEST_TOKEN
npx wrangler secret put MCP_TOKEN
npm run deploy
```

`deploy` 先运行远程 D1 迁移，再发布 Worker。首次执行 `secret put` 时，如 Wrangler 提示创建尚不存在的同名 Worker，确认它是你的专属名称后继续。两个 Token 缺失或相同会返回 503 并拒绝处理数据。

- `INGEST_TOKEN`：只交给 iPhone，用于连接检测、上传、删除和状态查询。
- `MCP_TOKEN`：只交给受信任的 AI 客户端，用于 `/mcp` 只读查询。
- Worker 配置关闭持久化请求日志，不打印请求头、请求体或样本。勿开启包含健康数据的调试日志。
- 更新 Token：再次执行对应的 `wrangler secret put`，然后更新持有该 Token 的设备或客户端。更换写入 Token 不影响原同步位置。
- 数据库变更使用新增迁移，不能修改已应用的迁移。D1 的历史恢复/备份保留按 Cloudflare 服务政策处理。

仓库当前没有公开 Git remote，因此不提供会跳向不存在仓库的一键部署按钮。未来公开后可按 [Cloudflare 部署按钮文档](https://developers.cloudflare.com/workers/platform/deploy-buttons/)配置仓库根目录和 `npm run deploy --workspace server`；本 monorepo 的 `server` 子目录依赖根锁文件，不能直接当作孤立模板目录。

## iPhone 安装与首次使用

1. 打开 `ios/HealthBridge.xcodeproj`，选择 `HealthBridge` Scheme。
2. 在 Signing & Capabilities 选自己的 Apple 开发团队、唯一 Bundle ID，保留 HealthKit 与 Background Delivery。让 Xcode 自动签名，不导入其他项目的描述文件。
3. 连接、信任并解锁 iPhone，开启开发者模式。Apple 如提示最新开发者协议，应由账号持有人在开发者网站处理。
4. Run 安装；App 中填写部署得到的 HTTPS 根地址及 `INGEST_TOKEN`，测试连接。
5. 阅读独立的数据共享说明，自己决定是否同意；选择数据类型与首次范围，然后在系统界面完成健康读取授权。
6. 首次上传显示在“同步”页，可在后台继续。概览直接读取本机数据，不依赖服务端。

未连接或不同意时可使用本机模式。iOS 不向 App 披露读取授权是否被拒绝，空数据可能是没有样本或没有读取权限，请在系统健康数据访问设置中检查。

### 构建和测试

```sh
xcodebuild -project ios/HealthBridge.xcodeproj -scheme HealthBridge \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# 替换为你自己的团队和真机 UDID，不提交个人签名文件
xcodebuild -project ios/HealthBridge.xcodeproj -scheme HealthBridge \
  -destination 'platform=iOS,id=你的设备UDID' DEVELOPMENT_TEAM=你的团队ID \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
```

需要调整工程结构时，安装 XcodeGen 并运行 `xcodegen generate --spec ios/project.yml`。普通开发直接使用已提交工程即可。

## 同步与数据管理约定

- MVP 类型：睡眠、心率、静息心率、HRV SDNN、步数。
- 默认首次范围为最近 30 天，可选 7/30/90/365 天或全部。
- 每类型使用固定的首次范围起点和独立 HealthKit anchor。每一查询页完整上传并收到匹配确认后，才持久化该页 anchor。失败安全重放，D1 按 UUID 幂等。
- 关闭类型停止后续上传，已上传记录保留；重新启用可继续补齐。扩大范围从更早起点重放，缩小范围不删已有数据。
- 撤回同意立即取消同步任务并停止后台观察；已经到达服务器的请求无法撤回，已上传的数据仍可被 Agent 查询。要阻止读取，删除服务器数据或轮换 MCP Token。
- 删除服务器全部数据保留连接，从删除时间起同步新记录；扩大回填范围可以再次主动同步历史数据。
- 断开连接清除本机 Token、地址、anchor，服务器数据保留；也可先删除服务器数据再断开。
- 后台调度由 iOS 控制，步数通知可能按小时交付。锁屏、后台预算结束、网络中断后保留已确认位置，下次唤醒、重试或前台继续。强制关闭 App 后需手动重新打开。详见 [Apple 后台交付文档](<https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)>)。
- 服务端步数聚合为原始样本求和，多设备来源可能重复，与 Apple 健康的统计可能不同。不得宣称医学诊断或 Apple 健康完全一致的去重总量。

## 连接个人 AI Agent

地址：`https://你的-worker.workers.dev/mcp`，传输为 Streamable HTTP，请求头为 `Authorization: Bearer <MCP_TOKEN>`。只读工具：

| 工具              | 用途                                                                     |
| ----------------- | ------------------------------------------------------------------------ |
| `get_sync_status` | 先检查每类型样本数、最后样本时间、最后上传时间                           |
| `query_samples`   | 原始样本，半开时间区间 `[from,to)`，最多 2000 条，可用返回的 cursor 分页 |
| `aggregate`       | 按样本本地小时/日期和时区分组，avg/min/max/sum/count                     |
| `sleep_summary`   | 18:00 分夜，单来源/设备优先阶段记录，区间合并后统计睡眠分钟              |

ISO 时间必须带时区；`YYYY-MM-DD` 按 `tz` 分钟偏移解释，省略时使用最近样本偏移。睡眠工具以本地醒来日期标记一晚，结束日期不包含。时间范围过大时返回明确错误，请缩小范围，不静默截断统计。

### Codex

在个人 `config.toml` 中加入（参考 [官方 MCP 配置](https://learn.chatgpt.com/docs/extend/mcp)）：

```toml
[mcp_servers.healthbridge]
url = "https://你的-worker.workers.dev/mcp"
bearer_token_env_var = "HEALTHBRIDGE_MCP_TOKEN"
```

从密码管理器向启动 Codex 的进程注入 `HEALTHBRIDGE_MCP_TOKEN`。桌面 App 不一定继承终端环境；需要确保实际执行 MCP 的进程可访问变量。不要把明文 Token 写入仓库配置。

### Claude Code

在个人范围的 MCP 配置中使用环境变量引用（参考 [官方 MCP 文档](https://code.claude.com/docs/en/mcp)）：

```json
{
  "mcpServers": {
    "healthbridge": {
      "type": "http",
      "url": "https://你的-worker.workers.dev/mcp",
      "headers": { "Authorization": "Bearer ${HEALTHBRIDGE_MCP_TOKEN}" }
    }
  }
}
```

启动客户端前安全注入环境变量，再用其 MCP 状态页检查工具。客户端配置片段和 SDK 端到端测试是不同证据；本仓库未声称已在每个商业客户端完成登录验收。

### 其他 MCP 客户端

选择 HTTP/Streamable HTTP，设置上述地址与 Authorization 头。仅支持 OAuth 的远程连接器无法直接使用本 MVP 的固定 Bearer Token；本期未实现 OAuth。Claude Desktop 如不支持自定义远程请求头，需使用可信赖的本地桥接客户端，本仓库不附带未经验证的桥接依赖。

## 验证部署

从安全环境注入 `INGEST_TOKEN`、`MCP_TOKEN` 和 `HEALTHBRIDGE_URL`，执行：

```sh
HEALTHBRIDGE_URL=https://你的-worker.workers.dev node scripts/verify-live.mjs
```

脚本使用合成样本验证真实 HTTPS、幂等写入、MCP 握手和四个工具，最后只删除自己创建的测试 UUID，不清空现有数据。macOS 可从服务名 `HealthBridge deployment`、账号名 `INGEST_TOKEN`/`MCP_TOKEN` 的钥匙串条目读取凭据；其他系统使用进程环境或自行接入密码管理器。

在本人真机已经明确授权上传后，可运行 `scripts/verify-device.mjs` 验证真实数据可查询。该脚本不落盘样本，不输出健康值、UUID、来源或日期，仅输出类型计数与查询通过状态。

## 工程导航

- [AGENTS.md](AGENTS.md)：工作约定。
- [开发方案](HealthBridge-开发方案.md)、[页面流程](docs/design/流程与页面.md)：原始方案与原型，包含后续范围，不能全部视为已实现。
- `designs/healthbridge/project/`：保留原格式的可编辑设计稿。
- `server/`：Worker、D1 迁移、运行时测试。
- `ios/`：SwiftUI、HealthKit、Keychain、Xcode 工程和测试。
- [隐私说明](docs/privacy.md)、[验收记录](docs/verification/MVP.md)。

不提交凭据、真实健康样本、数据库、描述文件和个人签名配置。不发布 App Store/TestFlight，不自动推送 Git。
