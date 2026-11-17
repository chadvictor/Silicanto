/** Inline CSS declaration and HTML attributes of a native layout element. */
class WebStyle extends JsObject {
	public final tag:String;
	public final attributes:Map<String, String> = [];
	public var fragments:Array<Dynamic> = [];
	public var text:Null<String>;
	public var html:Null<String>;
	public var sheet:Null<String>;
	public var rules:WebStyleSheet;

	public function new(tag:String) {
		super(Js.obj().prototype);
		this.tag = tag;
		getters.set("cssText", serialize);
		setters.set("cssText", v -> parse(Js.str(v)));
		values.set("getPropertyValue", Js.fn((_, a) -> {
			final v = read(key(Js.str(a[0])));
			return v == Js.u ? "" : Js.str(v);
		}, false));
		values.set("setProperty", Js.fn((_, a) -> {
			set(key(Js.str(a[0])), Js.str(Js.at(a, 1)));
			return Js.u;
		}, false));
		values.set("removeProperty", Js.fn((_, a) -> {
			final k = key(Js.str(a[0])), old = values.get(k);
			set(k, "");
			return old == null ? "" : old;
		}, false));
	}

	public override function define(key:String, value:Dynamic):Dynamic {
		WebLayout.styled = true;
		return super.define(key, value);
	}

	public static function key(name:String):String {
		if (StringTools.startsWith(name, "--"))
			return name;
		final parts = name.toLowerCase().split("-");
		var s = parts.shift();
		for (p in parts)
			s += p.charAt(0).toUpperCase() + p.substr(1);
		return s;
	}

	function set(k:String, v:String) {
		if (k == "" || ["cssText", "setProperty", "getPropertyValue", "removeProperty"].contains(k))
			return;
		if (v == "") {
			keys.remove(k);
			values.remove(k);
		} else
			define(k, v);
	}

	public function parse(value:String) {
		for (k in keys.copy())
			set(k, "");
		var quote = "", depth = 0, start = 0, escaped = false;
		for (i in 0...value.length + 1) {
			final c = value.charAt(i);
			if (escaped) {
				escaped = false;
				continue;
			}
			if (c == "\\") {
				escaped = true;
				continue;
			}
			if (quote != "") {
				if (c == quote)
					quote = "";
				continue;
			}
			if (c == "\"" || c == "'") {
				quote = c;
				continue;
			}
			if (c == "(")
				depth++;
			else if (c == ")" && depth > 0)
				depth--;
			if ((c == ";" && depth == 0) || i == value.length) {
				final declaration = value.substring(start, i), cut = declaration.indexOf(":");
				start = i + 1;
				if (cut > 0)
					set(key(StringTools.trim(declaration.substr(0, cut))), StringTools.trim(declaration.substr(cut + 1)));
			}
		}
	}

	public function serialize():String {
		final out = [];
		for (k in keys) {
			final prop = StringTools.startsWith(k, "--") ? k : ~/[A-Z]/g.map(k, r -> "-" + r.matched(0).toLowerCase());
			final v = values.get(k);
			if (v != null && v != Js.u && Js.str(v) != "")
				out.push(prop + ": " + Js.str(v) + ";");
		}
		return out.join(" ");
	}
}
