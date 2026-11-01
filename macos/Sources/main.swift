//
//  函数画板 · macOS 壳
//
//  只是一个 WKWebView 容器：把 index.html 装进 .app，双击即可用，
//  不依赖浏览器标签页。所有绘图与分析逻辑仍在网页里，壳不重复实现。
//
//  资源协议见 Scheme.swift。
//

import Cocoa
import WebKit

// MARK: - 窗口

final class BoardWindow: NSWindow {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { true }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {

	private var window: BoardWindow!
	private var webView: WKWebView!

	func applicationDidFinishLaunching(_ notification: Notification) {
		buildMenu()
		buildWindow()
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		return true
	}

	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}

	// MARK: 窗口搭建

	private func buildWindow() {
		let config = WKWebViewConfiguration()

		let prefs = WKWebpagePreferences()
		prefs.allowsContentJavaScript = true
		config.defaultWebpagePreferences = prefs

		if let resources = Bundle.main.resourceURL {
			config.setURLSchemeHandler(
				AppSchemeHandler(root: resources),
				forURLScheme: AppSchemeHandler.scheme
			)
		}

		webView = WKWebView(frame: .zero, configuration: config)
		webView.navigationDelegate = self
		webView.uiDelegate = self
		webView.allowsMagnification = false

		let rect = NSRect(x: 0, y: 0, width: 1180, height: 820)
		window = BoardWindow(
			contentRect: rect,
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = "函数画板"
		window.contentView = webView
		window.minSize = NSSize(width: 640, height: 460)
		window.setFrameAutosaveName("FunctionPlotMainWindow")
		window.center()
		window.makeKeyAndOrderFront(nil)
		window.makeFirstResponder(webView)

		let url = URL(string: "\(AppSchemeHandler.scheme)://\(AppSchemeHandler.host)/index.html")!
		webView.load(URLRequest(url: url))
	}

	// MARK: 菜单

	private func buildMenu() {
		let mainMenu = NSMenu()
		let appName = "函数画板"

		// —— 应用菜单
		let appItem = NSMenuItem()
		let appMenu = NSMenu()
		appMenu.addItem(withTitle: "关于 \(appName)", action: #selector(showAbout), keyEquivalent: "")
		appMenu.addItem(.separator())
		appMenu.addItem(
			withTitle: "隐藏 \(appName)",
			action: #selector(NSApplication.hide(_:)),
			keyEquivalent: "h"
		)
		let hideOthers = appMenu.addItem(
			withTitle: "隐藏其他",
			action: #selector(NSApplication.hideOtherApplications(_:)),
			keyEquivalent: "h"
		)
		hideOthers.keyEquivalentModifierMask = [.command, .option]
		appMenu.addItem(
			withTitle: "显示全部",
			action: #selector(NSApplication.unhideAllApplications(_:)),
			keyEquivalent: ""
		)
		appMenu.addItem(.separator())
		appMenu.addItem(
			withTitle: "退出 \(appName)",
			action: #selector(NSApplication.terminate(_:)),
			keyEquivalent: "q"
		)
		appItem.submenu = appMenu
		mainMenu.addItem(appItem)

		// —— 编辑菜单：没有它，输入框里的 ⌘C / ⌘V 不工作
		let editItem = NSMenuItem()
		let editMenu = NSMenu(title: "编辑")
		editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
		let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
		redo.keyEquivalentModifierMask = [.command, .shift]
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		editItem.submenu = editMenu
		mainMenu.addItem(editItem)

		// —— 显示菜单
		let viewItem = NSMenuItem()
		let viewMenu = NSMenu(title: "显示")
		let full = viewMenu.addItem(
			withTitle: "进入全屏幕",
			action: #selector(NSWindow.toggleFullScreen(_:)),
			keyEquivalent: "f"
		)
		full.keyEquivalentModifierMask = [.command, .control]
		viewItem.submenu = viewMenu
		mainMenu.addItem(viewItem)

		// —— 窗口菜单
		let windowItem = NSMenuItem()
		let windowMenu = NSMenu(title: "窗口")
		windowMenu.addItem(
			withTitle: "最小化",
			action: #selector(NSWindow.performMiniaturize(_:)),
			keyEquivalent: "m"
		)
		windowMenu.addItem(
			withTitle: "缩放",
			action: #selector(NSWindow.performZoom(_:)),
			keyEquivalent: ""
		)
		windowItem.submenu = windowMenu
		mainMenu.addItem(windowItem)

		NSApp.mainMenu = mainMenu
		NSApp.windowsMenu = windowMenu
	}

	@objc private func showAbout() {
		let credits = NSAttributedString(
			string: "一个只做函数图像与图像分析的画板。\n零点、极值、交点、导函数、切线。\n\nMIT License",
			attributes: [
				.font: NSFont.systemFont(ofSize: 11),
				.foregroundColor: NSColor.secondaryLabelColor
			]
		)
		let info = Bundle.main.infoDictionary
		let options: [NSApplication.AboutPanelOptionKey: Any] = [
			.credits: credits,
			.applicationName: "函数画板",
			.applicationVersion: info?["CFBundleShortVersionString"] as? String ?? "",
			.version: "构建 " + (info?["CFBundleVersion"] as? String ?? "")
		]
		NSApp.orderFrontStandardAboutPanel(options: options)
	}

	// MARK: WKNavigationDelegate

	/// 兜底绘制：某些窗口状态下 requestAnimationFrame 会被延迟，
	/// 而「打开就是白板」对画板类应用是致命的。这里在加载完成后主动驱动一帧。
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		webView.evaluateJavaScript(
			"window.FunctionPlot && window.FunctionPlot.redraw && window.FunctionPlot.redraw();",
			completionHandler: nil
		)
	}

	// MARK: WKUIDelegate

	func webView(
		_ webView: WKWebView,
		createWebViewWith configuration: WKWebViewConfiguration,
		for navigationAction: WKNavigationAction,
		windowFeatures: WKWindowFeatures
	) -> WKWebView? {
		// 站外链接交给系统浏览器，不在壳里开新窗
		if let url = navigationAction.request.url {
			NSWorkspace.shared.open(url)
		}
		return nil
	}
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
