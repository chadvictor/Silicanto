class JsJson {
	static function stringify(args:Array<Dynamic>):Dynamic {
		final replacer = Js.at(args, 1), space = Js.at(args, 2), seen:Array<Dynamic> = [];
		final gap = Js.type(space) == "number" ? StringTools.lpad("", " ",
			Std.int(Math.max(0, Math.min(10, Js.num(space))))) : Js.type(space) == "string" ? Js.str(space).substr(0, 10) : "";
		var selected:Array<String> = null;
		if (Std.isOfType(replacer, Array)) {
			selected = [];
			for (item in (cast replacer : Array<Dynamic>))
				if (["string", "number"].contains(Js.type(item)) && !selected.contains(Js.str(item)))
					selected.push(Js.str(item));
		}
		function encode(holder:Dynamic, key:String, indent:String):Null<String> {
			var value:Dynamic = Js.get(holder, key);
			if (Std.isOfType(value, JsObject)) {
				final hook = Js.get(value, "toJSON");
				if (Js.type(hook) == "function")
					value = Js.call(hook, value, [key]);
			}
			if (Js.type(replacer) == "function")
				value = Js.call(replacer, holder, [key, value]);
			if (value == null)
				return "null";
			switch Js.type(value) {
				case "undefined", "function":
					return null;
				case "boolean":
					return Js.truth(value) ? "true" : "false";
				case "string":
					return haxe.Json.stringify(Js.str(value));
				case "number":
					return Math.isFinite(Js.num(value)) ? Js.str(value) : "null";
			}
			if (seen.indexOf(value) != -1)
				throw "TypeError: circular JSON structure";
			seen.push(value);
			final array = Std.isOfType(value, Array), out:Array<String> = [], next = indent + gap;
			if (array) {
				final a:Array<Dynamic> = value;
				for (i in 0...a.length) {
					final item = encode(value, Std.string(i), next);
					out.push(item == null ? "null" : item);
				}
			} else {
				for (k in (selected == null ? JsStandard.keys(value) : selected)) {
					final item = encode(value, k, next);
					if (item != null)
						out.push(haxe.Json.stringify(k) + (gap == "" ? ":" : ": ") + item);
				}
			}
			seen.pop();
			final body = out.length == 0 ? "" : gap == "" ? out.join(",") : "\n" + next + out.join(",\n" + next) + "\n" + indent;
			return (array ? "[" : "{") + body + (array ? "]" : "}");
		}
		final holder = Js.obj();
		holder.define("", Js.at(args, 0));
		final result = encode(holder, "", "");
		return result == null ? Js.u : (result : Dynamic);
	}

	public static function install(realm:JsObject) {
		final json = Js.obj();
		json.values.set("stringify", Js.fn((_, args) -> stringify(args), false));
		json.values.set("parse", Js.fn((_, args) -> {
			final value = Js.json(Js.str(Js.at(args, 0))), fn = Js.at(args, 1);
			if (Js.type(fn) != "function")
				return value;
			final holder = Js.obj();
			holder.define("", value);
			function visit(parent:Dynamic, key:String):Dynamic {
				final item = Js.get(parent, key);
				if (item != null && Js.type(item) == "object")
					for (k in JsStandard.keys(item)) {
						final child = visit(item, k);
						if (child == Js.u && Std.isOfType(item, JsObject))
							Js.remove(item, k);
						else
							Js.put(item, k, child);
					}
				return Js.call(fn, parent, [key, item]);
			}
			return visit(holder, "");
		}, false));
		realm.define("JSON", json);
	}
}
