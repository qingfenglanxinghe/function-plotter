//
//  生成 App 图标（1024×1024 PNG）
//
//  用法：swift make-icon.swift <输出路径>
//
//  纯程序绘制，不引入任何图片素材，改配色/曲线重跑即可。
//  形态按 macOS Big Sur 之后的规范：1024 画布内 824 圆角方，圆角半径 185。
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments.count > 1
	? CommandLine.arguments[1]
	: "AppIcon-1024.png"

let S: CGFloat = 1024
let inset: CGFloat = 100
let box = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius: CGFloat = 185

guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
	  let ctx = CGContext(
		data: nil,
		width: Int(S),
		height: Int(S),
		bitsPerComponent: 8,
		bytesPerRow: 0,
		space: cs,
		bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
	  )
else {
	FileHandle.standardError.write("无法创建绘图上下文\n".data(using: .utf8)!)
	exit(1)
}

// MARK: - 底板

ctx.saveGState()
ctx.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

let c1 = CGColor(srgbRed: 0.24, green: 0.52, blue: 0.96, alpha: 1)   // #3b85f5 偏蓝
let c2 = CGColor(srgbRed: 0.49, green: 0.23, blue: 0.93, alpha: 1)   // #7c3aed 紫
if let grad = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray, locations: [0, 1]) {
	ctx.drawLinearGradient(
		grad,
		start: CGPoint(x: box.minX, y: box.maxY),
		end: CGPoint(x: box.maxX, y: box.minY),
		options: []
	)
}

// 顶部一层极淡高光，避免纯渐变的塑料感
if let gloss = CGGradient(
	colorsSpace: cs,
	colors: [
		CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16),
		CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0)
	] as CFArray,
	locations: [0, 1]
) {
	ctx.drawLinearGradient(
		gloss,
		start: CGPoint(x: box.midX, y: box.maxY),
		end: CGPoint(x: box.midX, y: box.midY * 1.05),
		options: []
	)
}

// MARK: - 坐标轴

ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30))
ctx.setLineWidth(7)
ctx.setLineCap(.round)

let pad: CGFloat = 118
ctx.move(to: CGPoint(x: box.minX + pad, y: box.midY))
ctx.addLine(to: CGPoint(x: box.maxX - pad, y: box.midY))
ctx.strokePath()

ctx.move(to: CGPoint(x: box.midX, y: box.minY + pad))
ctx.addLine(to: CGPoint(x: box.midX, y: box.maxY - pad))
ctx.strokePath()

// MARK: - 函数曲线（两个周期正弦）

let x0 = box.minX + 96
let x1 = box.maxX - 96
let amp = box.height * 0.21

var path = CGMutablePath()
let steps = 720
for i in 0...steps {
	let t = CGFloat(i) / CGFloat(steps)
	let wx = -2 * CGFloat.pi + t * (4 * CGFloat.pi)
	let px = x0 + t * (x1 - x0)
	let py = box.midY + sin(wx) * amp
	if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
	else { path.addLine(to: CGPoint(x: px, y: py)) }
}

// 曲线下方一层柔光，让线在渐变上有厚度
ctx.saveGState()
ctx.setShadow(
	offset: .zero,
	blur: 24,
	color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(36)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(path)
ctx.strokePath()
ctx.restoreGState()

// 主线
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(36)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(path)
ctx.strokePath()

ctx.restoreGState()

// MARK: - 输出

guard let image = ctx.makeImage() else {
	FileHandle.standardError.write("生成位图失败\n".data(using: .utf8)!)
	exit(1)
}

let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(
	url as CFURL,
	UTType.png.identifier as CFString,
	1,
	nil
) else {
	FileHandle.standardError.write("无法写入 \(outPath)\n".data(using: .utf8)!)
	exit(1)
}

CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) {
	FileHandle.standardError.write("PNG 编码失败\n".data(using: .utf8)!)
	exit(1)
}

print("已生成 \(outPath)")
