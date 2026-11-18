import haxe.io.Bytes;

/** Convert straight RGBA8 DOM pixels to the requested GLES upload format. */
class WebGLPixels {
	static inline var ALPHA = 0x1906;
	static inline var RGB = 0x1907;
	static inline var RGBA = 0x1908;
	static inline var LUMINANCE = 0x1909;
	static inline var LUMINANCE_ALPHA = 0x190a;
	static inline var UBYTE = 0x1401;
	static inline var RGBA4444 = 0x8033;
	static inline var RGBA5551 = 0x8034;
	static inline var RGB565 = 0x8363;

	static function pixelSize(format:Int, type:Int):Int
		return switch type {
			case UBYTE: switch format {
				case RGBA: 4;
				case RGB: 3;
				case LUMINANCE_ALPHA: 2;
				case ALPHA, LUMINANCE: 1;
				default: 0;
			}
			case RGBA4444, RGBA5551 if (format == RGBA): 2;
			case RGB565 if (format == RGB): 2;
			default: 0;
		};

	public static function pack(source:Bytes, width:Int, height:Int, format:Int, type:Int, alignment:Int, flip:Bool, premultiply:Bool):Bytes {
		final size = pixelSize(format, type);
		if (size == 0) return null;
		final pitch = Std.int(Math.ceil(width * size / alignment)) * alignment;
		final dest = Bytes.alloc(pitch * height);
		for (y in 0...height) {
			var src = (flip ? height - 1 - y : y) * width * 4, dst = y * pitch;
			for (x in 0...width) {
				var r = source.get(src), g = source.get(src + 1), b = source.get(src + 2);
				final a = source.get(src + 3);
				if (premultiply) {
					r = Math.round(r * a / 255);
					g = Math.round(g * a / 255);
					b = Math.round(b * a / 255);
				}
				switch type {
					case RGBA4444: dest.setUInt16(dst, (r >> 4) << 12 | (g >> 4) << 8 | (b >> 4) << 4 | a >> 4);
					case RGBA5551: dest.setUInt16(dst, (r >> 3) << 11 | (g >> 3) << 6 | (b >> 3) << 1 | a >> 7);
					case RGB565: dest.setUInt16(dst, (r >> 3) << 11 | (g >> 2) << 5 | b >> 3);
					default:
						dest.set(dst, format == ALPHA ? a : r);
						if (format == LUMINANCE_ALPHA) dest.set(dst + 1, a);
						if (format == RGB || format == RGBA) {
							dest.set(dst + 1, g);
							dest.set(dst + 2, b);
							if (format == RGBA) dest.set(dst + 3, a);
						}
				}
				src += 4;
				dst += size;
			}
		}
		return dest;
	}

	/** Transform a private copy of a typed view, retaining its GLES unpack layout. */
	public static function unpackView(data:Bytes, width:Int, height:Int, format:Int, type:Int, alignment:Int,
			rowLength:Int, skipRows:Int, skipPixels:Int, flip:Bool, premultiply:Bool):Bool {
		final size = pixelSize(format, type);
		if (size == 0 || width <= 0 || height <= 0) return true;
		final stride = rowLength == 0 ? width : rowLength;
		if (skipPixels + (width : Float) > stride) return false;
		final pitchFloat = Math.fceil(stride * (size : Float) / alignment) * alignment;
		final first = skipRows * pitchFloat + skipPixels * (size : Float);
		final count = width * (size : Float);
		if (first + (height - 1) * pitchFloat + count > data.length) return false;
		final pitch = Std.int(pitchFloat), start = Std.int(first), rowBytes = Std.int(count);
		if (flip && height > 1) {
			final temp = Bytes.alloc(rowBytes);
			for (y in 0...Std.int(height / 2)) {
				final a = start + y * pitch, b = start + (height - 1 - y) * pitch;
				temp.blit(0, data, a, rowBytes);
				data.blit(a, data, b, rowBytes);
				data.blit(b, temp, 0, rowBytes);
			}
		}
		if (!premultiply || (format != RGBA && format != LUMINANCE_ALPHA)) return true;
		for (y in 0...height) {
			var at = start + y * pitch;
			for (x in 0...width) {
				switch type {
					case UBYTE:
						final alpha = data.get(at + size - 1);
						for (channel in 0...(size - 1))
							data.set(at + channel, Math.round(data.get(at + channel) * alpha / 255));
					case RGBA5551:
						if ((data.getUInt16(at) & 1) == 0) data.setUInt16(at, 0);
					case RGBA4444:
						final pixel = data.getUInt16(at), alpha = pixel & 15;
						var packed = alpha;
						for (shift in [4, 8, 12])
							packed |= Math.round(((pixel >> shift) & 15) * alpha / 15) << shift;
						data.setUInt16(at, packed);
				}
				at += size;
			}
		}
		return true;
	}
}
