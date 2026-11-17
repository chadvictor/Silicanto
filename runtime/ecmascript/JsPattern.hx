class JsPattern extends JsObject {
	static var base:JsObject;
	static function patternPrototype():JsObject {
		if (base == null) base = Js.obj();
		return base;
	}
	public static function install(realm:JsObject) {
		final proto = patternPrototype();
		final constructor = Js.fn((receiver, a) -> {
			final value = Js.at(a, 0), flags = Js.at(a, 1);
			if (Std.isOfType(value, JsPattern)) {
				final original:JsPattern = cast value;
				if (flags == Js.u && (receiver == Js.u || receiver == null))
					return original;
				return new JsPattern(original.pattern, flags == Js.u ? original.flags : Js.str(flags));
			}
			return new JsPattern(value == Js.u ? "" : Js.str(value), flags == Js.u ? "" : Js.str(flags));
		}, true);
		constructor.define("prototype", proto);
		proto.define("constructor", constructor);
		realm.define("RegExp", constructor);
	}
	final pattern:String;
	final flags:String;
	public final regex:EReg;
	public final globalFlag:Bool;
	public final sticky:Bool;

	public final groupsCount:Int;

	public function new(pattern:String, flags:String) {
		super(patternPrototype());
		this.pattern = pattern;
		this.flags = flags;
		globalFlag = flags.indexOf("g") >= 0;
		sticky = flags.indexOf("y") >= 0;
		for (i in 0...flags.length)
			if ("gimsy".indexOf(flags.charAt(i)) < 0 || flags.indexOf(flags.charAt(i)) != i)
				throw Js.construct(Js.global("SyntaxError"), ["Invalid or unsupported RegExp flags: " + flags]);
		var count = 1, inClass = false, escaped = false;
		for (i in 0...pattern.length) {
			final c = pattern.charAt(i);
			if (escaped) {
				escaped = false;
				continue;
			}
			if (c == "\\") {
				escaped = true;
				continue;
			}
			if (c == "[") {
				inClass = true;
				continue;
			}
			if (c == "]") {
				inClass = false;
				continue;
			}
			if (!inClass
				&& c == "("
				&& (pattern.charAt(i + 1) != "?"
					|| (pattern.substr(i + 1, 2) == "?<" && pattern.charAt(i + 3) != "=" && pattern.charAt(i + 3) != "!")))
				count++;
		}
		groupsCount = count;
		regex = new EReg(pattern, StringTools.replace(flags, "y", ""));
		define("lastIndex", 0);
		define("source", pattern == "" ? "(?:)" : pattern);
		define("flags", [for (k in ["g","i","m","s","y"]) if (flags.indexOf(k) != -1) k].join(""));
		define("ignoreCase", flags.indexOf("i") != -1);
		define("multiline", flags.indexOf("m") != -1);
		define("dotAll", flags.indexOf("s") != -1);
		define("sticky", sticky);
		define("global", globalFlag);
		define("test", Js.fn((r, a) -> (cast r : JsPattern).exec(Js.str(Js.at(a, 0))) != null, false));
		define("exec", Js.fn((r, a) -> (cast r : JsPattern).exec(Js.str(Js.at(a, 0))), false));
	}

	public function matchString(s:String):Dynamic {
		if (!globalFlag)
			return exec(s);
		final out:Array<Dynamic> = [];
		define("lastIndex", 0);
		while (true) {
			final result:Array<Dynamic> = exec(s);
			if (result == null)
				break;
			out.push(result[0]);
			if (result[0] == "")
				define("lastIndex", Js.num(read("lastIndex")) + 1);
		}
		return out.length == 0 ? null : out;
	}

	public function exec(s:String):Dynamic {
		final start = globalFlag || sticky ? Std.int(Math.max(0, Js.num(read("lastIndex")))) : 0;
		if (start > s.length || !regex.matchSub(s, start) || (sticky && regex.matchedPos().pos != start)) {
			if (globalFlag || sticky)
				define("lastIndex", 0);
			return null;
		}
		final match = regex.matchedPos();
		if (globalFlag || sticky)
			define("lastIndex", match.pos + match.len);
		final groups:Array<Dynamic> = [];
		for (i in 0...groupsCount) {
			final g = regex.matched(i);
			groups.push(g == null ? Js.u : g);
		}
		return groups;
	}
}
