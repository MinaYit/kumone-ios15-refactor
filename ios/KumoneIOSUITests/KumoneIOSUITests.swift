import XCTest

final class KumoneIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLiquidGlassNavigationKeepsSearchSeparateAndTappable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingDemoTrack", "-uiTestingIOS15Root"]
        app.launch()

        let library = app.buttons["ios15Tab-4"]
        let search = app.buttons["ios15LiquidGlassSearchButton"]
        XCTAssertTrue(library.waitForExistence(timeout: 8))
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertGreaterThanOrEqual(
            search.frame.width,
            72,
            "独立搜索入口应提供扩展后的横向原生触控范围"
        )
        XCTAssertGreaterThanOrEqual(
            search.frame.height,
            72,
            "独立搜索入口应提供扩展后的纵向原生触控范围"
        )
        XCTAssertGreaterThan(
            search.frame.minX - library.frame.maxX,
            0,
            "搜索入口应与主胶囊导航保留独立间距，避免命中区重叠"
        )

        search.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.50)).tap()
        XCTAssertTrue(search.isSelected, "点击扩展命中区左缘后应立即切换至搜索标签")
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.50)).tap()
        XCTAssertTrue(search.isSelected, "点击扩展命中区右缘后仍应停留在干净的搜索根页")
    }

    @MainActor
    func testMiniPlayerShowsCurrentAndTotalPlaybackTime() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingDemoTrack", "-uiTestingIOS15Root"]
        app.launch()

        let progress = app.sliders["miniPlayerProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 8))
        XCTAssertEqual(
            progress.value as? String,
            "0:00 / 3:00",
            "迷你播放器应在进度条两端提供当前播放时间和总时长"
        )
    }

    @MainActor
    func testClosingMiniPlayerDoesNotRestoreFromStalePlaybackState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingDemoTrack", "-uiTestingIOS15Root"]
        app.launch()

        let miniPlayer = app.otherElements["ios15MiniPlayer"]
        let moreMenu = app.buttons["miniPlayerMoreMenu"]
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 8))
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 8))
        moreMenu.tap()

        let close = app.buttons["关闭播放器"]
        XCTAssertTrue(close.waitForExistence(timeout: 4))
        close.tap()
        XCTAssertFalse(miniPlayer.waitForExistence(timeout: 3))

        app.buttons["ios15Tab-2"].tap()
        XCTAssertFalse(
            miniPlayer.exists,
            "进入漫游页不应从延迟播放解析或旧队列恢复已关闭的迷你播放器"
        )
    }

    @MainActor
    func testMiniPlayerPlaybackRateCyclesThroughThreeQuarters() throws {
        let app = XCUIApplication()
        // 通过启动参数注入本地演示曲目，避免测试依赖账户、网络或流媒体解析。
        app.launchArguments = ["-uiTestingDemoTrack", "-uiTestingIOS15Root"]
        app.launch()

        let rateButton = app.buttons["miniPlayerPlaybackRateButton"]
        XCTAssertTrue(
            rateButton.waitForExistence(timeout: 8),
            "迷你播放器的倍速按钮应具有稳定的自动化标识"
        )
        XCTAssertEqual(rateButton.value as? String, "1×")
        XCTAssertGreaterThanOrEqual(rateButton.frame.width, 44)
        XCTAssertLessThanOrEqual(
            rateButton.frame.width,
            46,
            "倍速按钮应较旧版 54pt 视觉宽度更紧凑"
        )

        rateButton.tap()
        XCTAssertEqual(rateButton.value as? String, "1.25×")
        rateButton.tap()
        XCTAssertEqual(rateButton.value as? String, "1.5×")
        rateButton.tap()
        XCTAssertEqual(rateButton.value as? String, "2×")
        rateButton.tap()
        XCTAssertEqual(rateButton.value as? String, "0.75×")
        rateButton.tap()
        XCTAssertEqual(rateButton.value as? String, "1×")
    }

    @MainActor
    func testPosterCloseButtonIsTappable() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingDemoTrack",
            "-uiTestingIOS15Root",
            "-uiTestingNowPlaying",
            "-uiTestingImmersiveNowPlaying"
        ]
        app.launch()

        let closeButton = app.buttons["nowPlayingPosterCloseButton"]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 8),
            "海报播放页右上角应提供稳定的关闭按钮"
        )
        XCTAssertGreaterThanOrEqual(
            closeButton.frame.width,
            64,
            "沉浸模式关闭按钮应提供至少 64pt 的横向触控范围"
        )
        XCTAssertGreaterThanOrEqual(
            closeButton.frame.height,
            64,
            "沉浸模式关闭按钮应提供至少 64pt 的纵向触控范围"
        )
        closeButton.tap()
        XCTAssertFalse(
            closeButton.waitForExistence(timeout: 3),
            "关闭按钮点击后应关闭正在播放页面"
        )
    }

    @MainActor
    func testImmersiveModeRemovesTopLyricsFloatingButton() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingDemoTrack",
            "-uiTestingIOS15Root",
            "-uiTestingNowPlaying",
            "-uiTestingImmersiveNowPlaying"
        ]
        app.launch()

        let favorite = app.buttons["immersiveFavoriteButton"]
        let moreMenu = app.buttons["immersiveMoreMenu"]
        XCTAssertTrue(
            favorite.waitForExistence(timeout: 8),
            "沉浸模式应继续显示收藏心形按钮"
        )
        XCTAssertTrue(
            moreMenu.waitForExistence(timeout: 8),
            "沉浸模式应继续显示三点更多菜单"
        )
        XCTAssertEqual(
            favorite.frame.midY,
            moreMenu.frame.midY,
            accuracy: 1,
            "原版心形与三点菜单应位于同一顶栏基线"
        )
        XCTAssertEqual(
            favorite.frame.maxX,
            moreMenu.frame.minX,
            accuracy: 1,
            "原版心形应紧邻三点菜单左侧"
        )
        XCTAssertFalse(
            app.buttons["immersiveLyricsFloatingButton"].exists,
            "沉浸模式右上角不应再显示浮窗歌词按钮"
        )
    }

    @MainActor
    func testImmersiveMoreMenuAdvancesToNextTrack() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingDemoTrack",
            "-uiTestingIOS15Root",
            "-uiTestingNowPlaying",
            "-uiTestingImmersiveNowPlaying"
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["UI Test Track"].waitForExistence(timeout: 8),
            "测试应从确定的第一首演示曲目开始"
        )
        let moreMenu = app.buttons["immersiveMoreMenu"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 8))
        moreMenu.tap()

        let nextAction = app.buttons["下一曲播放"]
        XCTAssertTrue(
            nextAction.waitForExistence(timeout: 4),
            "三点菜单应显示可点击的下一曲动作"
        )
        nextAction.tap()

        XCTAssertTrue(
            app.staticTexts["UI Test Next Track"].waitForExistence(timeout: 5),
            "点击下一曲动作后应立即切换到队列中的下一首"
        )
        XCTAssertFalse(
            nextAction.exists,
            "完成下一曲动作后系统操作菜单应自动收回"
        )
    }

    @MainActor
    func testSettingsUsesCardGroupsAndChoiceSheet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestingDemoTrack", "-uiTestingIOS15Root"]
        app.launch()

        let library = app.buttons["ios15Tab-4"]
        XCTAssertTrue(library.waitForExistence(timeout: 8))
        library.tap()

        let settings = app.buttons["设置"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["播放"].exists)
        XCTAssertTrue(app.staticTexts["外观"].exists)
        XCTAssertTrue(app.staticTexts["存储"].exists)

        let quality = app.buttons["音质"]
        XCTAssertTrue(quality.waitForExistence(timeout: 5))
        quality.tap()
        XCTAssertTrue(app.navigationBars["音质"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["极高"].exists)
    }

    @MainActor
    func testNowPlayingUsesSystemSwipeDownDismissal() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingDemoTrack",
            "-uiTestingIOS15Root",
            "-uiTestingNowPlaying",
            "-uiTestingImmersiveNowPlaying"
        ]
        app.launch()

        let indicator = app.otherElements["nowPlayingDismissIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 8))
        indicator.swipeDown()
        XCTAssertFalse(
            indicator.waitForExistence(timeout: 4),
            "系统页面转场应响应下滑手势并关闭播放页"
        )
    }

    @MainActor
    func testClassicModeKeepsOriginalCloseControl() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uiTestingDemoTrack",
            "-uiTestingIOS15Root",
            "-uiTestingNowPlaying",
            "-uiTestingClassicNowPlaying"
        ]
        app.launch()

        let closeButton = app.buttons["nowPlayingCloseButton"]
        let lyricsButton = app.buttons["classicLyricsFloatingButton"]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 8),
            "经典模式应继续显示原有左上角关闭控件"
        )
        XCTAssertTrue(
            lyricsButton.waitForExistence(timeout: 8),
            "经典模式右上角应提供歌词浮窗按钮"
        )
        XCTAssertEqual(
            closeButton.frame.midY,
            lyricsButton.frame.midY,
            accuracy: 1,
            "经典模式歌词按钮应与左上关闭按钮处于同一高度"
        )
        XCTAssertEqual(closeButton.frame.size, lyricsButton.frame.size)
        XCTAssertFalse(
            app.buttons["nowPlayingPosterCloseButton"].exists,
            "沉浸模式专用右上角关闭按钮不应出现在经典模式"
        )
    }
}
