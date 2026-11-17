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
		final s = a / 255., d = dst.get(i + 3) / 255.;
		var sf = 1., df = 1. - s;
		switch op {
			case "copy":
				df = 0.;
			case "source-in":
				sf = d;
				df = 0.;
			case "destination-in":
				sf = 0.;
				df = s;
			case "destination-out":
				sf = 0.;
			case "source-out":
				sf = 1. - d;
				df = 0.;
			case "source-atop":
				sf = d;
			case "destination-atop":
				sf = 1. - d;
				df = s;
			case "destination-over":
				sf = 1. - d;
				df = 1.;
			case "lighter":
				df = 1.;
			case "xor":
				sf = 1. - d;
		}
		final alpha = Math.min(1., s * sf + d * df);
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
			final mix = switch op {
				case "multiply": c * old / 255.;
				case "screen": c + old - c * old / 255.;
				case "lighten": Math.max(c, old);
				case "darken": Math.min(c, old);
				default: (c : Float);
			};
			dst.set(i + k, byte((s * sf * ((1. - d) * c + d * mix) + df * d * old) / alpha));
		}
		dst.set(i + 3, byte(alpha * 255));
	}
}
