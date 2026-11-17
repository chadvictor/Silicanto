import haxe.io.Bytes;

/** Straight-alpha RGBA backing store. Color arithmetic is done in sRGB. */
class WebRaster {
	public static function size(w:Int, h:Int):Int {
		if (w < 0 || h < 0 || 1.0 * w * h > 16777216)
			throw "E-CANVAS: unsupported bitmap dimensions";
		return w * h * 4;
	}

	public static function byte(n:Float):Int
		return Std.int(Math.max(0, Math.min(255, Math.fround(n))));

	public static function blend(dst:Bytes, i:Int, r:Int, g:Int, b:Int, a:Int, op:String) {
		final s = a / 255., d = dst.get(i + 3) / 255., alpha = s + d * (1 - s);
		if (alpha == 0) {
			dst.setInt32(i, 0);
			return;
		}
		for (k in 0...3) {
			final c = switch k {
				case 0: r;
				case 1: g;
				default: b;
			}, old = dst.get(i + k);
			final mix = op == "multiply" ? c * old / 255. : c;
			dst.set(i + k, byte((s * (1 - d) * c + s * d * mix + (1 - s) * d * old) / alpha));
		}
		dst.set(i + 3, byte(alpha * 255));
	}
}
