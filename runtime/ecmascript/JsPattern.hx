class JsPattern extends JsObject {
	public final regex:EReg;
	public final globalFlag:Bool;
	public final sticky:Bool;

	public final groupsCount:Int;

	public function new(pattern:String, flags:String) {
		super();
		globalFlag = flags.indexOf("g") >= 0;
		sticky = flags.indexOf("y") >= 0;
		if (!~/^[gimsy]*$/.match(flags))
			throw "Unsupported RegExp flags: " + flags;
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
		define("source", pattern);
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
