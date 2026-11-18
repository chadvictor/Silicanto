/** A single pass over a built-in iterable. Exhaustion is distinct from yielding undefined. */
class JsIterator {
	static final end:Dynamic = new JsObject(null);
	final read:Void->Dynamic;
	var finished = false;

	public function new(source:Dynamic) {
		var i = 0;
		if (Std.isOfType(source, Array)) {
			final a:Array<Dynamic> = source;
			read = () -> i < a.length ? a[i++] : end;
		} else if (Std.isOfType(source, JsTypedArray)) {
			final a:JsTypedArray = source;
			read = () -> i < a.length ? a.readIndex(i++) : end;
		} else if (Std.isOfType(source, JsCollection)) {
			read = (cast source : JsCollection).iterate(end);
		} else if (Std.isOfType(source, String)) {
			final s:String = source;
			read = function():Dynamic {
				if (i >= s.length) return end;
				final start = i++;
				#if (neko || (cpp && !hxcpp_smart_strings))
				while (i < s.length && (s.charCodeAt(i) & 0xc0) == 0x80) i++;
				#elseif utf16
				final first = s.charCodeAt(start), second = s.charCodeAt(i);
				if (first >= 0xd800 && first <= 0xdbff && second != null && second >= 0xdc00 && second <= 0xdfff) i++;
				#end
				return s.substring(start, i);
			};
		} else
			throw Js.construct(Js.global("TypeError"), ["Value is not iterable"]);
	}

	public function take():Dynamic {
		if (!finished) {
			final value = read();
			if (value != end) return value;
			finished = true;
		}
		return Js.u;
	}

	public function rest():Array<Dynamic> {
		final values:Array<Dynamic> = [];
		while (!finished) {
			final value = take();
			if (!finished) values.push(value);
		}
		return values;
	}
}
