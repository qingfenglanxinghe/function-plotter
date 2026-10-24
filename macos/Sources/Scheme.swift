//
//  资源协议处理器
//
//  main.swift（正式壳）与 verify.swift（冒烟测试）共用这一份实现，
//  避免两处各写一遍导致行为分叉。
//
//  用自定义 scheme `fp://app/...` 而不是 file://，
//  页面因此拥有正常 origin，localStorage 等 Web 存储可用。
//

import Foundation
import WebKit

final class AppSchemeHandler: NSObject, WKURLSchemeHandler {

	static let scheme = "fp"
	static let host = "app"
	static let bundleID = "cn.geoboard.functionplotter"

	private let root: URL

	init(root: URL) {
		self.root = root.standardizedFileURL
		super.init()
	}

	func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
		guard let url = task.request.url else {
			fail(task, "缺少 URL")
			return
		}

		var rel = url.path
		while rel.hasPrefix("/") { rel.removeFirst() }
		if rel.isEmpty { rel = "index.html" }

		let target = root.appendingPathComponent(rel).standardizedFileURL

		// 目录穿越防护：解析后必须仍在资源根目录之内
		guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
			fail(task, "越界访问：\(rel)")
			return
		}

		guard let data = try? Data(contentsOf: target) else {
			fail(task, "找不到资源：\(rel)")
			return
		}

		let mime: String
		switch (rel as NSString).pathExtension.lowercased() {
		case "html", "htm": mime = "text/html"
		case "js":          mime = "text/javascript"
		case "css":         mime = "text/css"
		case "json":        mime = "application/json"
		case "png":         mime = "image/png"
		case "svg":         mime = "image/svg+xml"
		default:            mime = "application/octet-stream"
		}

		let response = URLResponse(
			url: url,
			mimeType: mime,
			expectedContentLength: data.count,
			textEncodingName: "utf-8"
		)
		task.didReceive(response)
		task.didReceive(data)
		task.didFinish()
	}

	func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
		// 资源一次读完，无需中断
	}

	private func fail(_ task: WKURLSchemeTask, _ message: String) {
		let err = NSError(
			domain: AppSchemeHandler.bundleID,
			code: 404,
			userInfo: [NSLocalizedDescriptionKey: message]
		)
		task.didFailWithError(err)
	}
}
