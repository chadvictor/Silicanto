import haxe.io.Bytes;
import haxe.crypto.Base64;

class WebEncoding {
	public static function install() {
		Js.realm.define("btoa", Js.fn((_, a) -> {
			final s = Js.str(Js.at(a, 0)), bytes = Bytes.alloc(s.length);
			for (i in 0...s.length) {
				final code = s.charCodeAt(i);
				if (code > 255)
					throw "InvalidCharacterError";
				bytes.set(i, code);
			}
			return Base64.encode(bytes);
		}, false));
		Js.realm.define("atob", Js.fn((_, a) -> {
			var s = ~/[\t\n\r \x0c]/g.replace(Js.str(Js.at(a, 0)), "");
			if (s.length % 4 == 0)
				s = ~/={1,2}$/.replace(s, "");
			if (s.length % 4 == 1 || ~/[^A-Za-z0-9+\/]/.match(s))
				throw "InvalidCharacterError";
			final bytes = Base64.decode(s), out = new StringBuf();
			for (i in 0...bytes.length)
				out.addChar(bytes.get(i));
			return out.toString();
		}, false));
	}
}
