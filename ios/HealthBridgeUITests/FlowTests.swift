import XCTest

final class FlowTests: XCTestCase {
  func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func launch(_ options: [String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-test"] + options
    app.launch()
    return app
  }
  func testIntroAndInvalidConnection() {
    let app = launch(["--ui-intro"])
    XCTAssertTrue(app.buttons["连接我的服务器"].waitForExistence(timeout: 5))
    capture("01-intro")
    app.buttons["连接我的服务器"].tap()
    XCTAssertTrue(app.textFields["serverURL"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["继续"].isEnabled)
    app.textFields["serverURL"].tap()
    app.textFields["serverURL"].typeText("http://invalid.test")
    app.secureTextFields["ingestToken"].tap()
    app.secureTextFields["ingestToken"].typeText("synthetic-test-only")
    app.buttons["测试连接"].tap()
    XCTAssertTrue(app.staticTexts["请填写不含路径、账号或查询参数的 HTTPS 服务器地址。"].waitForExistence(timeout: 3))
    capture("02-invalid-connection")
    XCTAssertFalse(app.buttons["继续"].isEnabled)
  }
  func testLocalOverviewDetailAndSettings() {
    let app = launch(["--ui-fixtures"])
    XCTAssertTrue(app.staticTexts["本机模式 · 未上传"].waitForExistence(timeout: 5))
    capture("03-local-overview")
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "睡眠")).firstMatch.tap()
    XCTAssertTrue(app.buttons["30 天"].waitForExistence(timeout: 3))
    app.buttons["30 天"].tap()
    capture("04-detail-30-days")
    app.navigationBars.buttons.firstMatch.tap()
    app.tabBars.buttons["设置"].tap()
    XCTAssertTrue(app.buttons["数据类型"].waitForExistence(timeout: 3))
    capture("05-settings")
    app.buttons["隐私说明"].tap()
    XCTAssertTrue(app.navigationBars["隐私说明"].waitForExistence(timeout: 3))
    capture("06-privacy")
  }
  func testEmptyAndSyncStates() {
    let app = launch([])
    XCTAssertTrue(app.staticTexts["暂无可读取的数据"].firstMatch.waitForExistence(timeout: 5))
    capture("07-empty")
    app.tabBars.buttons["同步"].tap()
    XCTAssertTrue(app.buttons["连接服务器"].waitForExistence(timeout: 3))
    capture("08-local-sync")
    for (argument, label, name) in [
      ("--ui-failure", "本次尚未完成，将在网络恢复或下次打开时重试", "09-failure"),
      ("--ui-lock", "iPhone 锁定时无法读取健康数据，解锁后继续", "10-lock-wait"),
      ("--ui-progress", "正在同步健康数据", "11-progress"), ("--ui-paused", "同步已暂停 · 已撤回共享", "12-paused"),
    ] {
      app.terminate()
      app.launchArguments = ["--ui-test", argument]
      app.launch()
      XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
      capture(name)
    }
  }
  func testDarkAndLargeText() {
    let app = launch([
      "--ui-fixtures", "--ui-dark", "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityXXXL",
    ])
    XCTAssertTrue(app.staticTexts["本机模式 · 未上传"].waitForExistence(timeout: 5))
    capture("13-dark-large-text")
    app.tabBars.buttons["设置"].tap()
    XCTAssertTrue(
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "服务器")).firstMatch
        .waitForExistence(timeout: 3))
    capture("14-dark-settings")
  }
}
