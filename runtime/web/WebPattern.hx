import haxe.io.Bytes;

/** A CanvasPattern captures its image at creation and tiles it in user space. */
class WebPattern extends JsObject {
	final source:Bytes;
	final width:Int;
	final height:Int;
	final repeatX:Bool;
	final repeatY:Bool;
	final matrix = new WebTransform();

	public static function create(image:Dynamic, repeat:Dynamic):WebPattern {
		var mode = repeat == Js.u || repeat == null ? "" : Js.str(repeat);
		if (mode == "")
			mode = "repeat";
		if (!["repeat", "repeat-x", "repeat-y", "no-repeat"].contains(mode))
			throw "SyntaxError: invalid pattern repetition";
		if (Std.isOfType(image, WebCanvas)) {
			final c:WebCanvas = image;
			if (c.width == 0 || c.height == 0)
				throw "InvalidStateError: empty source canvas";
			return new WebPattern(c.surface(), c.width, c.height, mode);
		}
		if (Std.isOfType(image, WebImage)) {
			final i:WebImage = image;
			return i.pixels == null ? null : new WebPattern(i.pixels, i.width, i.height, mode);
		}
		throw "TypeError: expected a canvas image source";
	}

	function new(pixels:Bytes, width:Int, height:Int, mode:String) {
		super(WebPlatform.patternType);
		this.source = pixels.sub(0, pixels.length);
		this.width = width;
		this.height = height;
		repeatX = mode == "repeat" || mode == "repeat-x";
		repeatY = mode == "repeat" || mode == "repeat-y";
		define("setTransform", Js.fn((_, args) -> {
			final m = Js.at(args, 0);
			final coefficients = [for (k in ["a", "b", "c", "d", "e", "f"]) {
				final v = m == null || m == Js.u ? Js.u : Js.get(m, k);
				v == Js.u ? (k == "a" || k == "d" ? 1. : 0.) : Js.num(v);
			}];
			matrix.set(coefficients[0], coefficients[1], coefficients[2], coefficients[3], coefficients[4], coefficients[5]);
			return Js.u;
		}, false));
	}

	public function painter(canvas:WebCanvas, transform:WebTransform, op:String, opacity:Float):(Int, Float) -> Void {
		final t = transform.copy();
		t.mul(matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f);
		final det = t.a * t.d - t.b * t.c;
		return (offset, coverage) -> {
			final i = Std.int(offset / 4), x = (i % canvas.width) + 0.5 - t.e, y = Std.int(i / canvas.width) + 0.5 - t.f;
			if (!Math.isFinite(det) || det == 0)
				return;
			var u = Math.floor((t.d * x - t.c * y) / det), v = Math.floor((t.a * y - t.b * x) / det);
			if (repeatX) u = (u % width + width) % width;
			if (repeatY) v = (v % height + height) % height;
			if (u < 0 || u >= width || v < 0 || v >= height) {
				WebRaster.blend(canvas.pixels, offset, 0, 0, 0, 0, op);
				return;
			}
			final s = (v * width + u) * 4;
			WebRaster.blend(canvas.pixels, offset, source.get(s), source.get(s + 1), source.get(s + 2),
				WebRaster.byte(source.get(s + 3) * opacity * coverage), op);
		};
	}
}
