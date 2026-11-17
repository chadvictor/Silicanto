class JsString {
	static function offset(a:Array<Dynamic>, index:Int, otherwise:Int):Int
		return a.length > index ? Std.int(Js.num(a[index])) : otherwise;

	public static function member(k:String):Dynamic {
		return switch k {
			case "concat", "valueOf", "toString", "toLowerCase", "toUpperCase", "indexOf", "lastIndexOf", "charAt", "charCodeAt", "substring", "substr",
				"slice", "split", "trim", "replace", "includes", "startsWith", "endsWith", "match":
				Js.fn(function(r:Dynamic, a:Array<Dynamic>):Dynamic {
					final s:String = r, x:Dynamic = Js.at(a, 0), i = offset(a, 0, 0), j = offset(a, 1, s.length);
					return switch k {
						case "match":
							final pattern:JsPattern = Std.isOfType(x, JsPattern) ? cast x : new JsPattern(x == Js.u ? "" : Js.str(x), "");
							pattern.matchString(s);
						case "toString", "valueOf": s;
						case "concat": s + [for (x in a) Js.str(x)].join("");
						case "toLowerCase": s.toLowerCase();
						case "toUpperCase": s.toUpperCase();
						case "charAt": s.charAt(i);
						case "charCodeAt": i < 0 || i >= s.length ? Math.NaN : s.charCodeAt(i);
						case "indexOf": s.indexOf(Js.str(x), offset(a, 1, 0));
						case "lastIndexOf": s.lastIndexOf(Js.str(x), j);
						case "trim": StringTools.trim(s);
						case "startsWith", "endsWith":
							if (Std.isOfType(x, JsPattern))
								throw Js.construct(Js.global("TypeError"), ["Expected a string search value"]);
							final search = Js.str(x);
							final position = a.length <= 1 || a[1] == Js.u ? (k == "endsWith" ? s.length : 0) : Js.num(a[1]);
							final bounded = Math.isNaN(position) ? 0 : Std.int(Math.max(0, Math.min(s.length, position)));
							final start = k == "endsWith" ? bounded - search.length : bounded;
							start >= 0 && s.substr(start, search.length) == search;
						case "includes": s.indexOf(Js.str(x), offset(a, 1, 0)) >= 0;
						case "substring": s.substring(Std.int(Math.max(0, Math.min(i, j))), Std.int(Math.max(i, j)));
						case "substr": s.substr(i, j);
						case "slice":
							final start = i < 0 ? Std.int(Math.max(0, s.length + i)) : i, end = j < 0 ? s.length + j : j;
							end <= start ? "" : s.substring(start, end);
						case "split":
							if (Std.isOfType(x, JsPattern)) (cast x : JsPattern).regex.split(s); else if (x == Js.u) [s]; else s.split(Js.str(x));
						default:
							final repl = Js.at(a, 1);
							if (Js.type(repl) == "function") {
								if (Std.isOfType(x, JsPattern)) {
									final pattern:JsPattern = x;
									return pattern.regex.map(s, r -> {
										final args:Array<Dynamic> = [];
										for (i in 0...pattern.groupsCount) {
											final v = r.matched(i);
											args.push(v == null ? Js.u : v);
										}
										args.push(r.matchedPos().pos);
										args.push(s);
										return Js.str(Js.call(repl, Js.u, args));
									});
								}
								final find = Js.str(x), p = s.indexOf(find);
								return p < 0 ? s : s.substr(0, p) + Js.str(Js.call(repl, Js.u, [find, p, s])) + s.substr(p + find.length);
							}
							final replacement = Js.str(repl);
							if (Std.isOfType(x, JsPattern)) (cast x : JsPattern).regex.replace(s, replacement); else {
								final find = Js.str(x), p = s.indexOf(find);
								p < 0 ? s : s.substr(0, p) + replacement + s.substr(p + find.length);
							}
					}
				}, false);
			default: Js.u;
		}
	}
}
