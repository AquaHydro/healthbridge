# iOS App

此目录预留给 SwiftUI + HealthKit App，目前尚未创建 Xcode 工程。

开始 iOS 实现时：

1. 核对开发方案和设计稿，确定最低系统版本、Bundle ID 和签名团队。
2. 创建并提交 Xcode 工程与共享 Scheme，个人签名配置留在本机。
3. 使用 Keychain 保存 Token，只有用户明确同意共享后才上传数据。
4. 为纯逻辑添加测试，为引导、连接和同步流程添加 UI 测试。
5. 在模拟器验证页面，在 iPhone 真机验证 HealthKit、锁屏和后台同步。

工程创建后，将准确的构建和测试命令加入根 README 与 CI。
