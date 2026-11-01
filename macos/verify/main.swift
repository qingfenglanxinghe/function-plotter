//
//  离屏冒烟测试
//
//  用法：
//    swiftc -swift-version 5 -O -o build/verify \
//        verify/main.swift Sources/Scheme.swift
//    ./build/verify "build/函数画板.app/Contents/Resources" build/verify-shot.png
//
//  不开窗口、不占 Dock：只验证「fp:// 协议能加载页面、页面能跑起来、能画出东西」。
//  判定依据是页面内自检返回值 + 一张实际渲染快照，避免只凭进程存活就宣布成功。
//

import Cocoa
import WebKit

// MARK: - 参数

let rootPath = CommandLine.arguments.count > 1
	? CommandLine.arguments[1]
	: "build/函数画板.app/Contents/Resources"
let shotPath = CommandLine.arguments.count > 2
	? CommandLine.arguments[2]
	: "build/verify-shot.png"

let rootURL = URL(fileURLWithPath: rootPath)
var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: String = "") {
	if ok {
		print("  ✓ \(name)")
	} else {
		print("  ✗ \(name)\(detail.isEmpty ? "" : " — \(detail)")")
		failures.append(name + (detail.isEmpty ? "" : " — " + detail))
	}
}

// MARK: - 环境

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let config = WKWebViewConfiguration()
let prefs = WKWebpagePreferences()
prefs.allowsContentJavaScript = true
config.defaultWebpagePreferences = prefs
config.setURLSchemeHandler(AppSchemeHandler(root: rootURL), forURLScheme: AppSchemeHandler.scheme)

let size = NSRect(x: 0, y: 0, width: 1180, height: 820)
let webView = WKWebView(frame: size, configuration: config)

// 需要一个宿主窗口参与布局。放到屏幕外再 orderFront：
// - 用户看不到任何东西，也不占 Dock（accessory 策略）
// - 但系统仍把它当作可见窗口，requestAnimationFrame 才会正常跑
//   （纯离屏、未 orderFront 的窗口 rAF 会被暂停，draw() 根本不会执行）
let host = NSWindow(contentRect: size, styleMask: [.borderless], backing: .buffered, defer: false)
host.contentView = webView
host.setFrame(size, display: false)
host.setFrameOrigin(NSPoint(x: -30000, y: -30000))
host.orderFront(nil)
webView.frame = size

var finished = false

func finish() {
	if finished { return }
	finished = true
	if failures.isEmpty {
		print("\n全部通过")
		NSApp.terminate(nil)
	} else {
		print("\n失败 \(failures.count) 项")
		exit(1)
	}
}

// MARK: - 加载

let url = URL(string: "\(AppSchemeHandler.scheme)://\(AppSchemeHandler.host)/index.html")!
webView.load(URLRequest(url: url))

DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
	webView.layoutSubtreeIfNeeded()

	let js = """
	(() => {
		const board = document.getElementById('board');
		const fatal = document.getElementById('fpFatal');
		const readout = document.getElementById('readout');
		let ls = 'ok';
		try { localStorage.setItem('__probe', '1'); localStorage.removeItem('__probe'); }
		catch (e) { ls = 'blocked:' + e.name; }

		const countLines = () => readout ? readout.querySelectorAll('div').length : 0;
		let lines = countLines();
		let forced = false;

		// 离屏窗口里 rAF 可能被节流。若一帧都没画过，就手动驱动一次，
		// 这样测的是「绘制逻辑本身」，而不是宿主是否愿意唤醒渲染。
		if (lines === 0 && typeof window.FunctionPlot === 'object'
			&& typeof window.FunctionPlot.redraw === 'function') {
			window.FunctionPlot.redraw();
			forced = true;
			lines = countLines();
		}

		return JSON.stringify({
			title: document.title,
			ready: document.readyState,
			hasBoard: !!board,
			boardPx: board ? [board.width, board.height] : null,
			curves: document.querySelectorAll('#curveList .curve').length,
			readoutLines: lines,
			forcedDraw: forced,
			rootsChecked: document.getElementById('anRoots') ? document.getElementById('anRoots').checked : null,
			rootsClass: document.getElementById('anRoots') ? document.getElementById('anRoots').className : null,
			rootsMatches: (() => {
				const el = document.getElementById('anRoots');
				if (!el) return null;
				try { return el.matches(':checked'); } catch (e) { return 'err:' + e.name; }
			})(),
			rootsBg: (() => {
				const el = document.getElementById('anRoots');
				if (!el) return null;
				return getComputedStyle(el).backgroundColor;
			})(),
			rootsBgNoTransition: (() => {
				const el = document.getElementById('anRoots');
				if (!el) return null;
				el.style.transition = 'none';
				void el.offsetWidth;
				const v = getComputedStyle(el).backgroundColor;
				el.style.transition = '';
				return v;
			})(),
			fatal: fatal ? fatal.textContent.slice(0, 200) : null,
			storage: ls,
			url: location.href
		});
	})()
	"""

	webView.evaluateJavaScript(js) { result, error in
		print("== 页面自检 ==")

		if let error = error {
			check("JS 可执行", false, "\(error)")
			finish()
			return
		}

		guard let json = result as? String,
			  let data = json.data(using: .utf8),
			  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			check("返回可解析的 JSON", false, "\(result ?? "nil")")
			finish()
			return
		}

		// JSONSerialization 会把 null 转成 NSNull，不能用 == nil 判断
		let fatalValue = obj["fatal"]
		let hasFatal = !(fatalValue == nil || fatalValue is NSNull)

		check("页面地址为 fp:// 协议", (obj["url"] as? String ?? "").hasPrefix("fp://app/"),
			  obj["url"] as? String ?? "")
		check("标题已加载", (obj["title"] as? String ?? "").contains("函数画板"),
			  obj["title"] as? String ?? "")
		check("无致命错误横幅", !hasFatal,
			  hasFatal ? (fatalValue as? String ?? "存在 #fpFatal") : "")
		check("canvas 存在且已分配像素",
			  obj["hasBoard"] as? Bool == true && {
				let px = obj["boardPx"] as? [Int] ?? []
				return px.count == 2 && px[0] > 0 && px[1] > 0
			  }(),
			  "\(obj["boardPx"] ?? "nil")")
		check("默认曲线已创建", (obj["curves"] as? Int ?? 0) >= 1, "\(obj["curves"] ?? 0)")
		check("分析读数已产出", (obj["readoutLines"] as? Int ?? 0) >= 3, "\(obj["readoutLines"] ?? 0) 行")
		check("localStorage 可用", (obj["storage"] as? String) == "ok", obj["storage"] as? String ?? "")

		// 注意：离屏窗口不推进 CSS 过渡，带 transition 的 background 会停在起始值。
		// 所以这里读「禁用过渡后的终值」，它才代表真实可见环境下的样子。
		let bg = (obj["rootsBgNoTransition"] as? String ?? "").replacingOccurrences(of: " ", with: "")
		check("开关选中态配色正确", bg == "rgb(37,99,235)", "实得 \(bg.isEmpty ? "nil" : bg)")

		if obj["forcedDraw"] as? Bool == true {
			print("  · 注：rAF 未自动触发，已手动调用 FunctionPlot.redraw() 验证绘制逻辑")
		}

		// 截图前把过渡固定为终态：离屏窗口不推进过渡，否则快照会拍到动画起始帧
		let freeze = """
		(() => {
			document.querySelectorAll('.check input, button, .curve input').forEach(el => {
				el.style.transition = 'none';
			});
			void document.body.offsetWidth;
			return 'ok';
		})()
		"""

		webView.evaluateJavaScript(freeze) { _, _ in
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
				let cfg = WKSnapshotConfiguration()
				cfg.rect = webView.bounds
				webView.takeSnapshot(with: cfg) { image, err in
					print("\n== 渲染快照 ==")
					if let image = image,
					   let tiff = image.tiffRepresentation,
					   let rep = NSBitmapImageRep(data: tiff),
					   let png = rep.representation(using: .png, properties: [:]) {
						try? png.write(to: URL(fileURLWithPath: shotPath))
						check("快照已保存", true)
						print("  → \(shotPath)")
						print("  → 尺寸 \(rep.pixelsWide)×\(rep.pixelsHigh)")
					} else {
						check("快照已保存", false, err?.localizedDescription ?? "unknown")
					}
					finish()
				}
			}
		}
	}
}

// 兜底：无论如何 15 秒后退出，避免挂住
DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
	if !finished {
		print("\n超时：页面未在 15 秒内完成自检")
		exit(1)
	}
}

app.run()
