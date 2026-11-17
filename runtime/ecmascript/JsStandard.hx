/** Built-ins shared by arrays, typed views, strings, and ordinary JS objects. */
class JsStandard {
	public static function radix(value:Float, base:Int):String {
		final alphabet = "0123456789abcdefghijklmnopqrstuvwxyz", n = Math.abs(value);
		var integer = Math.ffloor(n), fraction = n - integer, s = "";
		do {
			s = alphabet.charAt(Std.int(integer % base)) + s;
			integer = Math.ffloor(integer / base);
		} while (integer >= 1);
		if (fraction > 0) {
			s += ".";
			var steps = 0;
			while (fraction > 0 && steps++ < 64) {
				fraction *= base;
				final digit = Math.floor(fraction);
				s += alphabet.charAt(digit);
				fraction -= digit;
			}
		}
		return (value < 0 ? "-" : "") + s;
	}

	public static function relative(value:Dynamic, length:Int, fallback:Int):Int {
		if (value == Js.u)
			return fallback;
		final n = Js.num(value);
		if (Math.isNaN(n))
			return 0;
		if (n >= length)
			return length;
		if (n <= -length)
			return 0;
		final i = Std.int(n);
		return i < 0 ? length + i : i;
	}

	public static function own(value:Dynamic, key:Dynamic):Bool {
		final k = Js.str(key);
		if (value == null || value == Js.u)
			throw "TypeError: null receiver";
		final array = Std.isOfType(value, Array), string = Std.isOfType(value, String), typed = Std.isOfType(value, JsTypedArray);
		if (array || string || typed) {
			if (k == "length" && !typed)
				return true;
			final i = Std.parseInt(k);
			if (i != null && i >= 0 && Std.string(i) == k)
				return i < Js.num(Js.get(value, "length"));
		}
		return Std.isOfType(value, JsObject) && JsProperties.own(value, k);
	}

	public static function keys(value:Dynamic):Array<String> {
		if (value == null || value == Js.u)
			throw "TypeError: null receiver";
		if (Std.isOfType(value, Array) || Std.isOfType(value, String) || Std.isOfType(value, JsTypedArray))
			return [for (i in 0...Std.int(Js.num(Js.get(value, "length")))) Std.string(i)];
		if (!Std.isOfType(value, JsObject))
			return [];
		final obj:JsObject = value;
		final indices:Array<String> = [], names:Array<String> = [];
		for (k in obj.keys) {
			final n = Std.parseFloat(k);
			if (n >= 0 && n < 4294967295. && Math.ffloor(n) == n && Js.str(n) == k)
				indices.push(k);
			else
				names.push(k);
		}
		indices.sort((x, y) -> Reflect.compare(Std.parseFloat(x), Std.parseFloat(y)));
		return indices.concat(names);
	}

	public static function install(realm:JsObject, object:JsObject, array:JsObject, number:JsObject, string:JsObject) {
		for (name in ["isInteger", "isSafeInteger"])
			number.define(name, Js.fn((_, a) -> {
				final v = Js.at(a, 0), n = Js.num(v);
				return Js.type(v) == "number"
					&& Math.isFinite(n)
					&& Math.ffloor(n) == n
					&& (name != "isSafeInteger" || Math.abs(n) <= 9007199254740991.);
			}, false));
		realm.define("isNaN", Js.fn((_, a) -> Math.isNaN(Js.num(Js.at(a, 0))), false));
		realm.define("isFinite", Js.fn((_, a) -> Math.isFinite(Js.num(Js.at(a, 0))), false));
		for (k in ["parseFloat", "parseInt"])
			number.define(k, Js.global(k));
		string.define("fromCharCode", Js.fn((_, a) -> [for (v in a) String.fromCharCode(WebBits.signed(Js.num(v)) & 65535)].join(""), false));
		for (name in ["keys", "values", "entries"])
			object.define(name, Js.fn((_, a) -> {
				final value = Js.at(a, 0), names = keys(value);
				return switch name {
					case "keys": (names : Dynamic);
					case "values": [for (k in names) Js.get(value, k)];
					default: [for (k in names) ([k, Js.get(value, k)] : Array<Dynamic>)];
				};
			}, false));
		object.define("hasOwn", Js.fn((_, a) -> own(Js.at(a, 0), Js.at(a, 1)), false));
		object.define("fromEntries", Js.fn((_, a) -> {
			final out = Js.obj();
			for (entry in Js.items(Js.at(a, 0)))
				out.define(Js.str(Js.get(entry, 0)), Js.get(entry, 1));
			return out;
		}, false));
		array.define("of", Js.fn((_, a) -> a.copy(), false));
		array.define("from", Js.fn((_, a) -> {
			final source = Js.at(a, 0), mapper = Js.at(a, 1), self = Js.at(a, 2);
			if (source == null || source == Js.u)
				throw "TypeError: null array source";
			if (mapper != Js.u && Js.type(mapper) != "function")
				throw "TypeError: map function required";
			final values:Array<Dynamic> = if (Std.isOfType(source, JsCollection) || Std.isOfType(source, JsTypedArray) || Std.isOfType(source, String)
				|| Std.isOfType(source, Array)) Js.items(source).copy(); else {
				final n = Js.num(Js.get(source, "length"));
				if (n > 2147483647.)
					throw "RangeError: invalid array length";
				[for (i in 0...(n > 0 ? Std.int(n) : 0)) Js.get(source, i)];
			}
			if (mapper != Js.u)
				for (i in 0...values.length)
					values[i] = Js.call(mapper, self, [values[i], i]);
			return values;
		}, false));
		JsJson.install(realm);
	}
}
