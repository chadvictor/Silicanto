import haxe.io.Bytes;

/** ECMA-262 URI handling. The reserved set is preserved only for full URIs. */
class JsUri {
	static inline var unescaped = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()";
	static inline var reserved = ";/?:@&=+$,#";
	static inline var digits = "0123456789ABCDEF";

	static function malformed():Dynamic
		throw Js.construct(Js.global("URIError"), ["Malformed URI sequence"]);

	public static function encode(s:String, whole:Bool):String {
		final result = new StringBuf();
		#if utf16
		var i = 0;
		while (i < s.length) {
			final unit = s.charCodeAt(i++);
			if (unit >= 0xD800 && unit <= 0xDBFF) {
				if (i >= s.length) return malformed();
				final low = s.charCodeAt(i++);
				if (low < 0xDC00 || low > 0xDFFF) return malformed();
			} else if (unit >= 0xDC00 && unit <= 0xDFFF) return malformed();
		}
		#end
		final bytes = Bytes.ofString(s);
		for (i in 0...bytes.length) {
			final b = bytes.get(i);
			final ch = b < 128 ? String.fromCharCode(b) : "";
			if (b < 128 && (unescaped.indexOf(ch) >= 0 || whole && reserved.indexOf(ch) >= 0))
				result.add(ch);
			else
				result.add("%" + digits.charAt(b >> 4) + digits.charAt(b & 15));
		}
		return result.toString();
	}

	public static function decode(s:String, whole:Bool):String {
		final result = new StringBuf();
		var i = 0;
		function byte(at:Int):Int {
			if (s.charAt(at) != "%" || at + 2 >= s.length) return malformed();
			final a = digits.indexOf(s.charAt(at + 1).toUpperCase()), b = digits.indexOf(s.charAt(at + 2).toUpperCase());
			if (a < 0 || b < 0) return malformed();
			return (a << 4) | b;
		}
		while (i < s.length) {
			final mark = s.indexOf("%", i);
			if (mark == -1) { result.add(s.substr(i)); break; }
			result.add(s.substring(i, mark));
			final first = byte(mark);
			final count = first < 128 ? 1 : first >= 0xC2 && first <= 0xDF ? 2 : first >= 0xE0 && first <= 0xEF ? 3 : first >= 0xF0 && first <= 0xF4 ? 4 : 0;
			if (count == 0) return malformed();
			var code = count == 1 ? first : first & (127 >> count);
			for (k in 1...count) {
				final b = byte(mark + 3 * k);
				if ((b & 0xC0) != 0x80) return malformed();
				code = (code << 6) | (b & 63);
			}
			if ((count == 3 && code < 0x800) || (count == 4 && code < 0x10000) ||
			    (code >= 0xD800 && code <= 0xDFFF) || code > 0x10FFFF) return malformed();
			i = mark + 3 * count;
			if (count == 1 && whole && reserved.indexOf(String.fromCharCode(code)) >= 0)
				result.add(s.substring(mark, i));
			else {
				final bytes = Bytes.alloc(count);
				for (k in 0...count) bytes.set(k, k == 0 ? first : byte(mark + 3*k));
				result.add(bytes.toString());
			}
		}
		return result.toString();
	}
}
