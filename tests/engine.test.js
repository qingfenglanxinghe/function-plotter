/**
 * 引擎单元测试
 * 运行：node tests/engine.test.js
 *
 * 直接从 index.html 里载入脚本（不复制代码），保证测的就是发布物。
 */
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const htmlPath = path.join(__dirname, "..", "index.html");
const html = fs.readFileSync(htmlPath, "utf8");

const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) {
	console.error("未能在 index.html 中找到 <script> 块");
	process.exit(1);
}

let code = m[1];
code += "\n;globalThis.__T = { Expr, Viewport, Numeric, samplePath, safeEval, FUNCS, CONSTS, fmtNum };";

const sandbox = {
	window: { addEventListener() {}, matchMedia: null },
	document: {
		readyState: "loading",   /* 阻止 boot() 触碰真实 DOM */
		addEventListener() {},
		getElementById() { return null; },
		createElement() { return { style: {}, appendChild() {}, addEventListener() {} }; },
		body: { appendChild() {} },
		documentElement: { dataset: {}, style: {} }
	},
	requestAnimationFrame() { return 0; },
	setTimeout, clearTimeout,
	console, Math, Number, Date, JSON, URL,
	localStorage: { getItem() { return null; }, setItem() {} },
	getComputedStyle() { return { getPropertyValue() { return "#000"; } }; }
};
sandbox.globalThis = sandbox;
sandbox.window = sandbox;
sandbox.addEventListener = function () {};
sandbox.matchMedia = null;

vm.createContext(sandbox);
vm.runInContext(code, sandbox, { filename: "index.html:script" });

const T = sandbox.__T;
const { Expr, Viewport, Numeric, samplePath, safeEval } = T;

/* ---------------- 断言框架 ---------------- */
let pass = 0, fail = 0;
const failures = [];

function ok(name, cond, detail) {
	if (cond) { pass++; }
	else { fail++; failures.push(name + (detail ? "  → " + detail : "")); }
}
function near(name, actual, expected, tol) {
	const t = tol === undefined ? 1e-9 : tol;
	const good = Number.isFinite(actual) && Math.abs(actual - expected) <= t;
	ok(name, good, "期望 " + expected + "，实得 " + actual);
}
function evalAt(src, x) {
	return Expr.parseToFn(src)(x);
}
function group(title) {
	console.log("\n── " + title + " " + "─".repeat(Math.max(0, 46 - title.length)));
}

/* ============================================================
   1. 表达式引擎：基础求值
   ============================================================ */
group("表达式求值");

near("sin(x) @ π/2", evalAt("sin(x)", Math.PI / 2), 1);
near("cos(x) @ 0", evalAt("cos(x)", 0), 1);
near("x^3/3 - x @ 3", evalAt("x^3/3 - x", 3), 6);
near("隐式乘法 2x @ 3", evalAt("2x", 3), 6);
near("隐式乘法 3sin(x)+1 @ π/2", evalAt("3sin(x)+1", Math.PI / 2), 4);
near("隐式乘法 (x+1)(x-1) @ 3", evalAt("(x+1)(x-1)", 3), 8);
near("一元负号优先于乘方 -x^2 @ 3", evalAt("-x^2", 3), -9);
near("右结合 2^3^2", evalAt("2^3^2", 0), 512);
near("分数幂 x^(1/2) @ 4", evalAt("x^(1/2)", 4), 2);
near("科学计数 1e3", evalAt("1e3", 0), 1000);
near("常量 pi", evalAt("pi", 0), Math.PI);
near("常量连写 2pi*x @ 1", evalAt("2pi*x", 1), Math.PI * 2);
near("常量 e", evalAt("e", 0), Math.E);

group("符号归一化");

near("全角括号 （x+1）*2 @ 3", evalAt("（x+1）*2", 3), 8);
near("上标 x²  @ 4", evalAt("x²", 4), 16);
near("上标 x³  @ 2", evalAt("x³", 2), 8);
near("乘号 × x×3 @ 2", evalAt("x×3", 2), 6);
near("除号 ÷ x÷2 @ 4", evalAt("x÷2", 4), 2);
near("减号 − x−1 @ 5", evalAt("x−1", 5), 4);
near("π 符号 π @ 0", evalAt("π", 0), Math.PI);
near("全角逗号 min（2，3）", evalAt("min（2，3）", 0), 2);

group("函数库");

near("abs", evalAt("abs(-3)", 0), 3);
near("sqrt", evalAt("sqrt(9)", 0), 3);
near("cbrt", evalAt("cbrt(27)", 0), 3);
near("ln(e)", evalAt("ln(e)", 0), 1);
near("log100 (常用对数)", evalAt("log(100)", 0), 2);
near("log2(8)", evalAt("log2(8)", 0), 3);
near("exp(0)", evalAt("exp(0)", 0), 1);
near("floor(2.9)", evalAt("floor(2.9)", 0), 2);
near("ceil(2.1)", evalAt("ceil(2.1)", 0), 3);
near("round(2.5)", evalAt("round(2.5)", 0), 3);
near("min(2,3)", evalAt("min(2,3)", 0), 2);
near("max(2,3)", evalAt("max(2,3)", 0), 3);
near("mod(-1,3) 非负余数", evalAt("mod(-1,3)", 0), 2);
near("step(0)=1", evalAt("step(0)", 0), 1);
near("step(-1)=0", evalAt("step(-1)", 0), 0);
near("sgn(-3,2) = -9", evalAt("sgn(-3,2)", 0), -9);
near("atan2(1,1)", evalAt("atan2(1,1)", 0), Math.PI / 4);
near("tanh(0)", evalAt("tanh(0)", 0), 0);

group("非法输入必须报错（而不是静默返回 NaN）");

function throws(name, src, hint) {
	let threw = false, msg = "";
	try { Expr.parseToFn(src); } catch (e) { threw = true; msg = e.message; }
	ok(name, threw, "应当抛错，实际没有" + (hint ? "（" + hint + "）" : ""));
	if (threw) ok(name + " · 错误信息非空", typeof msg === "string" && msg.length > 0, msg);
}

throws("未知变量 abc", "abc");
throws("缺括号 sin x", "sin x");
throws("截断表达式 x+", "x+");
throws("空表达式", "");
throws("右括号多余 (x))", "(x))");
throws("未闭合 (x+1", "(x+1");
throws("非法字符 x@2", "x@2");

/* ============================================================
   2. 视口
   ============================================================ */
group("视口变换");

const vp = new Viewport();
vp.W = 800; vp.H = 600; vp.cx = 0; vp.cy = 0; vp.kx = 60; vp.ky = 60;

near("原点映射到画布中心 x", vp.toSx(0), 400);
near("原点映射到画布中心 y", vp.toSy(0), 300);
near("x 往返一致", vp.toWx(vp.toSx(2.5)), 2.5, 1e-9);
near("y 往返一致", vp.toWy(vp.toSy(-1.5)), -1.5, 1e-9);

{
	/* 以 (300,200) 为不动点放大，该屏幕点对应的世界坐标必须不变 */
	const wx = vp.toWx(300), wy = vp.toWy(200);
	vp.zoomAt(300, 200, 2.5);
	near("缩放后不动点世界 x 不变", vp.toWx(300), wx, 1e-9);
	near("缩放后不动点世界 y 不变", vp.toWy(200), wy, 1e-9);
	near("缩放后 kx 加倍", vp.kx, 150);
}

{
	const before = vp.toWx(100);
	vp.panBy(50, 0);
	near("平移 50px 对应世界位移", vp.toWx(100), before - 50 / vp.kx, 1e-9);
}

{
	/* 缩放上下限不能破 */
	const v2 = new Viewport();
	for (let i = 0; i < 200; i++) v2.zoomAt(0, 0, 2);
	ok("缩放上限被钳制", Number.isFinite(v2.kx) && v2.kx <= 1e7, "kx=" + v2.kx);
}

/* ============================================================
   3. 采样：渐近线必须断开
   ============================================================ */
group("采样与断点");

{
	const v = new Viewport(); v.W = 800; v.H = 600; v.kx = 60; v.ky = 60;
	const segs = samplePath(Expr.parseToFn("1/x"), v);
	ok("1/x 被切成多段（不画穿渐近线）", segs.length >= 2, "段数=" + segs.length);

	const segs2 = samplePath(Expr.parseToFn("tan(x)"), v);
	ok("tan(x) 被切成多段", segs2.length >= 3, "段数=" + segs2.length);

	const segs3 = samplePath(Expr.parseToFn("sin(x)"), v);
	ok("sin(x) 为单段", segs3.length === 1, "段数=" + segs3.length);

	const segs4 = samplePath(Expr.parseToFn("sqrt(x)"), v);
	ok("sqrt(x) 在 x<0 处不产生点", segs4.length === 1 && segs4[0][0][0] >= v.toSx(0) - 2);
}

/* ============================================================
   4. 数值分析
   ============================================================ */
group("零点");

{
	const rs = Numeric.roots(Expr.parseToFn("x^3/3-x"), -3, 3, 2200);
	ok("三次曲线有 3 个零点", rs.length === 3, "实得 " + rs.length + " 个：" + rs.map(x => x.toFixed(4)).join(", "));
	const sorted = rs.slice().sort((a, b) => a - b);
	if (sorted.length === 3) {
		near("零点1 ≈ -√3", sorted[0], -Math.sqrt(3), 1e-4);
		near("零点2 ≈ 0", sorted[1], 0, 1e-4);
		near("零点3 ≈ √3", sorted[2], Math.sqrt(3), 1e-4);
	}
}

{
	/* 关键回归：1/x 在 0 处符号翻转，但不是零点 */
	const rs = Numeric.roots(Expr.parseToFn("1/x"), -3, 3, 2200);
	ok("1/x 不产生假零点", rs.length === 0, "实得 " + rs.length + " 个：" + rs.join(", "));
}

{
	const rs = Numeric.roots(Expr.parseToFn("tan(x)"), -2, 2, 2200);
	ok("tan(x) 只识别出真零点 0", rs.length === 1 && Math.abs(rs[0]) < 1e-4,
		"实得 " + rs.length + " 个：" + rs.map(x => x.toFixed(4)).join(", "));
}

{
	const rs = Numeric.roots(Expr.parseToFn("sin(x)"), -7, 7, 3000);
	ok("sin(x) 在 [-7,7] 上有 5 个零点", rs.length === 5, "实得 " + rs.length);
}

group("极值");

{
	const es = Numeric.extrema(Expr.parseToFn("x^3/3-x"), -3, 3, 2200);
	ok("三次曲线有 2 个极值", es.length === 2, "实得 " + es.length);
	const byX = es.slice().sort((a, b) => a.x - b.x);
	if (byX.length === 2) {
		near("极大值点 x ≈ -1", byX[0].x, -1, 1e-3);
		near("极大值 y = 2/3", byX[0].y, 2 / 3, 1e-4);
		ok("第一个是极大", byX[0].kind === "max", byX[0].kind);
		near("极小值点 x ≈ 1", byX[1].x, 1, 1e-3);
		near("极小值 y = -2/3", byX[1].y, -2 / 3, 1e-4);
		ok("第二个是极小", byX[1].kind === "min", byX[1].kind);
	}
}

{
	const es = Numeric.extrema(Expr.parseToFn("sin(x)"), -7, 7, 3000);
	ok("sin(x) 在 [-7,7] 上极值点数量合理", es.length >= 4 && es.length <= 6, "实得 " + es.length);
}

group("交点与导数");

{
	const xs = Numeric.intersections(Expr.parseToFn("x"), Expr.parseToFn("x^2"), -2, 2, 2200);
	const s = xs.slice().sort((a, b) => a - b);
	ok("y=x 与 y=x² 有 2 个交点", s.length === 2, "实得 " + s.length);
	if (s.length === 2) {
		near("交点 x=0", s[0], 0, 1e-4);
		near("交点 x=1", s[1], 1, 1e-4);
	}
}

{
	const f = Expr.parseToFn("x^2");
	near("d/dx x² @ 3 = 6", Numeric.derivative(f, 3), 6, 1e-4);
	near("d/dx x² @ -2 = -4", Numeric.derivative(f, -2), -4, 1e-4);

	const g = Expr.parseToFn("sin(x)");
	near("d/dx sin(x) @ 0 = 1", Numeric.derivative(g, 0), 1, 1e-5);

	ok("不可导点返回有限值或 null", (() => {
		const h = Expr.parseToFn("abs(x)");
		const d = Numeric.derivative(h, 0);
		return d === null || Number.isFinite(d);
	})());
}

/* ============================================================
   5. 文档示例
   README 里承诺可用的写法必须真的能解析，避免文档与实现脱节。
   ============================================================ */
group("文档示例均可解析");

[
	"x^3/3 - x",
	"sin(x)",
	"cos(2x)",
	"1/(1+exp(-8x))",
	"sin(1/x)*x",
	"x*sin(1/x)",
	"tan(x)",
	"sqrt(x)",
	"ln(abs(x))",
	"2^x",
	"x^(1/3)",
	"sqrt(x²+1)",
	"min(sin(x),cos(x))",
	"step(x)*x",
	"abs(x)-1"
].forEach(src => {
	let good = false, msg = "";
	try {
		const f = Expr.parseToFn(src);
		const y = f(1.234);
		good = typeof y === "number";
		if (!good) msg = "求值返回 " + y;
	} catch (e) {
		msg = e.message;
	}
	ok("可解析 " + src, good, msg);
});

/* ============================================================
   6. 数值格式化
   ============================================================ */
group("刻度格式化");
{
	const f = T.fmtNum;
	ok("整数不带小数点", f(3, 3) === "3", f(3, 3));
	ok("小数去尾零", f(0.5, 3) === "0.5", f(0.5, 3));
	ok("负数保留符号", f(-2.25, 3) === "-2.25", f(-2.25, 3));
}

/* ---------------- 汇总 ---------------- */
console.log("\n" + "=".repeat(52));
if (fail === 0) {
	console.log("全部通过：" + pass + " 项");
	process.exit(0);
} else {
	console.log("通过 " + pass + " 项，失败 " + fail + " 项：");
	failures.forEach(f => console.log("  ✗ " + f));
	process.exit(1);
}
