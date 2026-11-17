import haxe.io.Bytes;

class WebCanvas extends JsObject {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var pixels(default, null):Bytes;

	final ctx:JsObject;
	var fill = 0;
	var alpha = 255;
	var style = "#000000";
	var op = "source-over";
	var opacity:Float = 1.;
	var transform = new WebTransform();
	var path = new WebPath();
	var clips:Array<WebPath> = [];
	var stroke = 0;
	var strokeAlpha = 255;
	var strokeStyle = "#000000";
	var lineWidth = 1.;

	var stack:Array<{
		matrix:WebTransform,
		opacity:Float,
		op:String,
		style:String,
		fill:Int,
		alpha:Int,
		clips:Array<WebPath>,
		stroke:Int,
		strokeStyle:String,
		strokeAlpha:Int,
		lineWidth:Float
	}> = [];

	static function arg(a:Array<Dynamic>, i:Int):Int {
		final n = Js.num(Js.at(a, i));
		if (!Math.isFinite(n) || n != Math.ffloor(n))
			throw "E-CANVAS: expected integer coordinates";
		return Std.int(n);
	}

	public function new(w:Int, h:Int) {
		super(WebPlatform.canvasType);
		ctx = new JsObject(WebPlatform.contextType);
		resize(w, h);
		getters.set("width", () -> width);
		getters.set("height", () -> height);
		setters.set("width", v -> resize(Std.int(Js.num(v)), height));
		setters.set("height", v -> resize(width, Std.int(Js.num(v))));
		define("getContext", Js.fn((_, a) -> Js.str(Js.at(a, 0)) == "2d" ? ctx : null, false));
		ctx.define("canvas", this);
		ctx.define("imageSmoothingEnabled", true);
		ctx.getters.set("globalAlpha", () -> opacity);
		ctx.setters.set("globalAlpha", v -> {
			final n = Js.num(v);
			if (n >= 0 && n <= 1)
				opacity = n;
		});
		ctx.define("save", Js.fn((_, a) -> {
			stack.push({
				matrix: transform.copy(),
				opacity: opacity,
				op: op,
				style: style,
				fill: fill,
				alpha: alpha,
				clips: clips.copy(),
				stroke: stroke,
				strokeStyle: strokeStyle,
				strokeAlpha: strokeAlpha,
				lineWidth: lineWidth
			});
			return Js.u;
		}, false));
		ctx.define("restore", Js.fn((_, a) -> {
			final s = stack.pop();
			if (s != null) {
				transform = s.matrix;
				opacity = s.opacity;
				op = s.op;
				style = s.style;
				fill = s.fill;
				alpha = s.alpha;
				clips = s.clips;
				stroke = s.stroke;
				strokeStyle = s.strokeStyle;
				strokeAlpha = s.strokeAlpha;
				lineWidth = s.lineWidth;
			}
			return Js.u;
		}, false));
		for (k in ["setTransform", "transform", "resetTransform", "translate", "scale", "rotate"]) {
			ctx.define(k, Js.fn((_, args) -> {
				final v = [for (i in 0...6) Js.num(Js.at(args, i))];
				switch k {
					case "setTransform":
						if (args.length != 6)
							throw "E-CANVAS: six transform coefficients required";
						transform.set(v[0], v[1], v[2], v[3], v[4], v[5]);
					case "transform": transform.mul(v[0], v[1], v[2], v[3], v[4], v[5]);
					case "resetTransform": transform = new WebTransform();
					case "translate": transform.mul(1, 0, 0, 1, v[0], v[1]);
					case "scale": transform.mul(v[0], 0, 0, v[1], 0, 0);
					case "rotate":
						final co = Math.cos(v[0]), si = Math.sin(v[0]);
						transform.mul(co, si, -si, co, 0, 0);
				}
				return Js.u;
			}, false));
		}
		ctx.getters.set("fillStyle", () -> style);
		ctx.setters.set("fillStyle", setStyle);
		ctx.getters.set("globalCompositeOperation", () -> op);
		ctx.setters.set("globalCompositeOperation", v -> {
			final k = Js.str(v);
			if (k != "multiply" && k != "source-over")
				throw "E-CANVAS: unsupported composition " + k;
			op = k;
		});
		ctx.getters.set("strokeStyle", () -> strokeStyle);
		ctx.setters.set("strokeStyle", v -> {
			final a = alpha, f = fill, old = style;
			setStyle(v);
			stroke = fill;
			strokeAlpha = alpha;
			strokeStyle = style;
			alpha = a;
			fill = f;
			style = old;
		});
		ctx.getters.set("lineWidth", () -> lineWidth);
		ctx.setters.set("lineWidth", v -> {
			final n = Js.num(v);
			if (n > 0 && Math.isFinite(n))
				lineWidth = n;
		});
		for (k in [
			"beginPath",
			"moveTo",
			"lineTo",
			"closePath",
			"rect",
			"clip",
			"stroke",
			"fill",
			"strokeRect"
		]) {
			ctx.define(k, Js.fn((_, a) -> {
				final v = [for (i in 0...4) Js.num(Js.at(a, i))];
				switch k {
					case "beginPath": path = new WebPath();
					case "moveTo", "lineTo": path.point(transform, v[0], v[1], k == "moveTo");
					case "closePath": path.close();
					case "rect": path.rect(transform, v[0], v[1], v[2], v[3]);
					case "clip": clips = clips.concat([path.snapshot()]);
					case "strokeRect":
						final p = new WebPath();
						p.rect(transform, v[0], v[1], v[2], v[3]);
						paintPath(p, true);
					default: paintPath(path, k == "stroke");
				}
				return Js.u;
			}, false));
		}
		ctx.define("fillRect", Js.fn((_, a) -> {
			rect(a, false);
			return Js.u;
		}, false));
		ctx.define("clearRect", Js.fn((_, a) -> {
			rect(a, true);
			return Js.u;
		}, false));
		ctx.define("getImageData", Js.fn((_, a) -> imageData(arg(a, 0), arg(a, 1), arg(a, 2), arg(a, 3), true), false));
		ctx.define("createImageData", Js.fn((_, a) -> imageData(0, 0, arg(a, 0), arg(a, 1), false), false));
		ctx.define("putImageData", Js.fn((_, a) -> {
			if (a.length != 3)
				throw "E-CANVAS: dirty rectangles are unsupported";
			final img = Js.at(a, 0), data = Js.get(img, "data"), w = Std.int(Js.num(Js.get(img, "width"))), h = Std.int(Js.num(Js.get(img, "height")));
			final x0 = arg(a, 1), y0 = arg(a, 2);
			for (y in 0...h)
				for (x in 0...w)
					if (inside(x + x0, y + y0))
						for (k in 0...4)
							pixels.set(((y + y0) * width + x + x0) * 4 + k, WebRaster.byte(Js.num(Js.get(data, (y * w + x) * 4 + k))));
			return Js.u;
		}, false));
		ctx.define("drawImage", Js.fn((_, a) -> {
			draw(a);
			return Js.u;
		}, false));
	}

	function setStyle(v:Dynamic) {
		var s = Js.str(v).toLowerCase();
		s = switch s {
			case "red": "#ff0000";
			case "green": "#008000";
			case "blue": "#0000ff";
			case "white": "#ffffff";
			case "black": "#000000";
			case "transparent": "rgba(0,0,0,0)";
			default: s;
		};
		if (~/^#[0-9a-f]{3}$/.match(s))
			s = "#" + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2) + s.charAt(3) + s.charAt(3);
		if (~/^#[0-9a-f]{6}$/.match(s)) {
			style = s;
			fill = Std.parseInt("0x" + s.substr(1));
			alpha = 255;
			return;
		}
		final rgba = ~/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([.\d]+)\s*)?\)$/;
		if (!rgba.match(s))
			throw "E-CANVAS: unsupported fill style " + s;
		fill = (WebRaster.byte(Std.parseFloat(rgba.matched(1))) << 16) | (WebRaster.byte(Std.parseFloat(rgba.matched(2))) << 8) | WebRaster.byte(Std.parseFloat(rgba.matched(3)));
		final part = rgba.matched(4);
		alpha = part == null ? 255 : WebRaster.byte(Std.parseFloat(part) * 255);
		style = s;
	}

	function resize(w:Int, h:Int) {
		pixels = Bytes.alloc(WebRaster.size(w, h));
		width = w;
		height = h;
		style = "#000000";
		fill = 0;
		alpha = 255;
		op = "source-over";
		opacity = 1.;
		transform = new WebTransform();
		stack = [];
		path = new WebPath();
		clips = [];
		stroke = 0;
		strokeAlpha = 255;
		strokeStyle = "#000000";
		lineWidth = 1.;
	}

	inline function inside(x:Int, y:Int)
		return x >= 0 && y >= 0 && x < width && y < height;

	function imageData(x0:Int, y0:Int, w:Int, h:Int, copy:Bool):JsObject {
		if (w < 1 || h < 1)
			throw "E-CANVAS: expected positive image dimensions";
		WebRaster.size(w, h);
		final data:JsTypedArray = Js.construct(Js.global("Uint8ClampedArray"), [w * h * 4]);
		var index = 0;
		for (y in 0...h)
			for (x in 0...w)
				for (k in 0...4)
					data.writeIndex(index++, copy && inside(x + x0, y + y0) ? pixels.get(((y + y0) * width + x + x0) * 4 + k) : 0);
		final o = Js.obj();
		o.define("width", w);
		o.define("height", h);
		o.define("data", data);
		return o;
	}

	function rect(a:Array<Dynamic>, clear:Bool) {
		final x = Js.num(Js.at(a, 0)), y = Js.num(Js.at(a, 1)), w = Js.num(Js.at(a, 2)), h = Js.num(Js.at(a, 3));
		project(x, y, w, h, (i, _, _) -> {
			if (clear)
				pixels.setInt32(i, 0);
			else if (op == "source-over" && alpha == 255 && opacity == 1) {
				pixels.set(i, fill >> 16);
				pixels.set(i + 1, (fill >> 8) & 255);
				pixels.set(i + 2, fill & 255);
				pixels.set(i + 3, 255);
			} else
				WebRaster.blend(pixels, i, fill >> 16, (fill >> 8) & 255, fill & 255, WebRaster.byte(alpha * opacity), op);
		});
	}

	function visible(x:Float, y:Float):Bool {
		for (c in clips)
			if (!c.contains(x, y))
				return false;
		return true;
	}

	function paintPath(p:WebPath, isStroke:Bool) {
		if (p.contours.length == 0)
			return;
		final r = isStroke ? lineWidth * Math.sqrt(transform.a * transform.a + transform.b * transform.b) * 0.5 : 0.;
		final col = isStroke ? stroke : fill, a = WebRaster.byte((isStroke ? strokeAlpha : alpha) * opacity);
		for (y in Math.floor(Math.max(0, p.minY - r))...Math.ceil(Math.min(height, p.maxY + r)))
			for (x in Math.floor(Math.max(0, p.minX - r))...Math.ceil(Math.min(width, p.maxX + r))) {
				final px = x + 0.5, py = y + 0.5;
				if (visible(px, py) && (isStroke ? p.onStroke(px, py, r) : p.contains(px, py)))
					WebRaster.blend(pixels, (y * width + x) * 4, col >> 16, (col >> 8) & 255, col & 255, a, op);
			}
	}

	function project(x:Float, y:Float, w:Float, h:Float, paint:(Int, Float, Float) -> Void) {
		final t = transform, det = t.a * t.d - t.b * t.c;
		if (w == 0 || h == 0 || det == 0 || !Math.isFinite(w + h + x + y + det))
			return;
		final xs = [t.x(x, y), t.x(x + w, y), t.x(x, y + h), t.x(x + w, y + h)], ys = [t.y(x, y), t.y(x + w, y), t.y(x, y + h), t.y(x + w, y + h)];
		function lo(a:Array<Float>)
			return Math.floor(Math.max(0, Math.min(Math.min(a[0], a[1]), Math.min(a[2], a[3]))));
		function hi(a:Array<Float>, n:Int)
			return Math.ceil(Math.min(n, Math.max(Math.max(a[0], a[1]), Math.max(a[2], a[3]))));
		for (py in lo(ys)...hi(ys, height))
			for (px in lo(xs)...hi(xs, width)) {
				final dx = px + 0.5 - t.e, dy = py + 0.5 - t.f, u = ((t.d * dx - t.c * dy) / det - x) / w, v = ((t.a * dy - t.b * dx) / det - y) / h;
				if (u >= 0 && v >= 0 && u < 1 && v < 1 && visible(px + 0.5, py + 0.5))
					paint((py * width + px) * 4, u, v);
			}
	}

	function draw(a:Array<Dynamic>) {
		if (a.length != 3 && a.length != 5 && a.length != 9)
			throw "E-CANVAS: invalid drawImage arguments";
		final img:Dynamic = Js.at(a, 0);
		var w:Int, h:Int, src:Bytes;
		if (Std.isOfType(img, WebImage)) {
			final im:WebImage = img;
			w = im.width;
			h = im.height;
			src = im.pixels;
		} else if (Std.isOfType(img, WebCanvas)) {
			final c:WebCanvas = img;
			w = c.width;
			h = c.height;
			src = c == this ? pixels.sub(0, pixels.length) : c.pixels;
		} else
			throw "E-CANVAS: expected an image or canvas";
		final crop = a.length == 9, i = crop ? 5 : 1;
		final sx = crop ? Js.num(a[1]) : 0., sy = crop ? Js.num(a[2]) : 0., sw = crop ? Js.num(a[3]) : w, sh = crop ? Js.num(a[4]) : h;
		final dw = a.length < 5 ? w : Js.num(a[i + 2]), dh = a.length < 5 ? h : Js.num(a[i + 3]);
		project(Js.num(a[i]), Js.num(a[i + 1]), dw, dh, (offset, u, v) -> {
			final x = Math.floor(sx + u * sw), y = Math.floor(sy + v * sh);
			if (x >= 0 && y >= 0 && x < w && y < h) {
				final p = (y * w + x) * 4;
				WebRaster.blend(pixels, offset, src.get(p), src.get(p + 1), src.get(p + 2), WebRaster.byte(src.get(p + 3) * opacity), op);
			}
		});
	}
}
