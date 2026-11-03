# HealthBridge

将 iPhone 的 HealthKit 数据同步至用户自己的 Cloudflare Worker，供个人 AI Agent 通过 MCP 查询。
当前阶段为工程初始化，尚未实现健康数据同步或 MCP 服务。

## 开始开发

需要 Node.js 24 LTS 和 npm。iOS 开发还需要 macOS、Xcode 和用于 HealthKit 验证的 iPhone。

```sh
nvm use
npm ci
npm run dev
```

本地 Worker 默认运行在 `http://localhost:8787`。
另开终端执行 `curl -i http://localhost:8787/healthz`，应返回 `200` 和 `{"status":"ok"}`。
该接口仅检查进程存活，不代表数据库、鉴权或同步已就绪。
目前其他路径均返回 `404`。

## 常用命令

| 命令             | 用途                                                |
| ---------------- | --------------------------------------------------- |
| `npm run dev`    | 启动本地 Worker，不连接生产资源                     |
| `npm run check`  | 格式检查、类型检查、Worker 运行时测试和部署打包预检 |
| `npm test`       | 运行服务端测试                                      |
| `npm run format` | 格式化工程文件，不改已有设计稿和方案                |
| `npm run build`  | 本地打包预检，不上传、不部署                        |

## 项目导航

- [AGENTS.md](AGENTS.md)：Agent 入口与工作规则。
- [开发方案](HealthBridge-开发方案.md)：背景、范围和技术规划，当前仍待审查。
- [页面与流程](docs/design/流程与页面.md)：页面、交互状态与待确认假设。
- `designs/healthbridge/project/`：现有可编辑设计稿，保留原格式。
- `server/`：TypeScript Worker、运行时测试、迁移目录。
- [iOS 开发入口](ios/README.md)：SwiftUI 工程待创建。
- [开发流程](docs/development/workflow.md)：任务拆分、验证和交付。

本机安装的 Skills 位于 `.agents/skills/`，`.claude/skills/` 提供兼容入口，来源记录在 `skills-lock.json`。这些本机安装文件不纳入 Git，新环境按锁文件列出的来源重新安装所需 Skill。

## 当前边界

尚未配置 D1、Token、MCP 或远程部署。不得上传真实健康数据或凭据。
后续业务开发遵循两个 Token 分权、上传成功才推进 anchor、明确同意后同步的原则。
Worker 类型通过 `wrangler types` 从配置生成，类型检查时会自动生成，无需提交生成文件。

运行时和测试配置参考 [Cloudflare TypeScript 文档](https://developers.cloudflare.com/workers/languages/typescript/)及 [Workers 测试文档](https://developers.cloudflare.com/workers/testing/vitest-integration/)。
