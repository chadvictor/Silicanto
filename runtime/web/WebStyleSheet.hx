/** CSSOM rule lists retain object identity while their owning stylesheet changes. */
private class WebRuleList extends JsObject {
	public final rules:Array<WebRule> = [];

	public function new() {
		super(Js.obj().prototype);
		getters.set("length", () -> rules.length);
		define("item", Js.fn((_, a) -> {
			final index = Std.int(Js.num(Js.at(a, 0)));
			return index >= 0 && index < rules.length ? rules[index] : null;
		}, false));
	}

	public override function read(key:String, ?receiver:JsObject):Dynamic {
		final index = Std.parseInt(key);
		if (index != null && index >= 0 && Std.string(index) == key)
			return index < rules.length ? cast rules[index] : Js.u;
		return super.read(key, receiver);
	}
}

private class WebRule extends JsObject {
	final name:String;
	var prelude:String;
	final body:Null<String>;
	final declarations:WebStyle;
	final initial:String;

	public function new(parts:Array<Dynamic>, sheet:WebStyleSheet) {
		super(Js.obj().prototype);
		name = parts[0];
		prelude = parts[1];
		body = parts[2];
		define("parentStyleSheet", sheet);
		define("type", switch name.toLowerCase() {
			case "": 1;
			case "import": 3;
			case "media": 4;
			case "font-face": 5;
			case "page": 6;
			case "keyframes": 7;
			case "supports": 12;
			default: 0;
		});
		if (name == "") {
			getters.set("selectorText", () -> prelude);
			setters.set("selectorText", value -> prelude = Js.str(value));
		}
		if (name == "" || name == "font-face" || name == "page") {
			declarations = new WebStyle("");
			declarations.parse(body == null ? "" : body);
			initial = declarations.serialize();
			define("style", declarations);
		} else {
			declarations = null;
			initial = null;
		}
		getters.set("cssText", serialize);
	}

	public function serialize():String {
		final head = name == "" ? prelude : "@" + name + (prelude == "" ? "" : " " + prelude);
		if (body == null)
			return head + ";";
		final current = declarations == null ? null : declarations.serialize();
		return head + " {" + (current != null && current != initial ? current : body) + "}";
	}
}

class WebStyleSheet extends JsObject {
	final list = new WebRuleList();
	var disabled = false;

	static function parse(source:String):Array<Array<Dynamic>>
		return cast DesktopServices.call("layout.rules", [source]);

	public function new(owner:JsObject, source:String) {
		super(Js.obj().prototype);
		for (parts in parse(source))
			list.rules.push(new WebRule(parts, this));
		define("ownerNode", owner);
		define("cssRules", list);
		getters.set("disabled", () -> disabled);
		setters.set("disabled", v -> disabled = Js.truth(v));
		define("insertRule", Js.fn((_, a) -> {
			final i = a.length > 1 ? Std.int(Js.num(a[1])) : 0;
			if (i < 0 || i > list.rules.length)
				throw "IndexSizeError";
			final parsed = parse(Js.str(Js.at(a, 0)));
			if (parsed.length != 1)
				throw "SyntaxError";
			list.rules.insert(i, new WebRule(parsed[0], this));
			WebLayout.styled = true;
			return i;
		}, false));
		define("deleteRule", Js.fn((_, a) -> {
			final i = Std.int(Js.num(Js.at(a, 0)));
			if (i < 0 || i >= list.rules.length)
				throw "IndexSizeError";
			list.rules.splice(i, 1)[0].define("parentStyleSheet", null);
			return Js.u;
		}, false));
	}

	public function serialize():String
		return disabled ? "" : [for (rule in list.rules) rule.serialize()].join("\n");
}
