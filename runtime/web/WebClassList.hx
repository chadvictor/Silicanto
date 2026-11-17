/** The element's class attribute and DOMTokenList share a live token set. */
class WebClassList extends JsObject {
	final element:JsObject;
	final whitespace = ~/[ \t\n\x0c\r]+/g;

	function value():String {
		final raw = element.read("className");
		return raw == Js.u ? "" : Js.str(raw);
	}

	function tokens():Array<String> {
		final unique = [];
		for (token in whitespace.split(value()))
			if (token != "" && !unique.contains(token)) unique.push(token);
		return unique;
	}

	function store(tokens:Array<String>):Void {
		final text = tokens.join(" ");
		element.define("className", text);
		(cast element.read("style"):WebStyle).attributes.set("class", text);
	}

	function validate(name:String):Void {
		if (name == "" || whitespace.match(name))
			throw Js.construct(Js.global("Error"), ["Invalid class token"]);
	}

	public function new(element:JsObject) {
		super();
		this.element = element;
		getters.set("length", () -> tokens().length);
		getters.set("value", value);
		setters.set("value", v -> {
			element.define("className", Js.str(v));
			(cast element.read("style"):WebStyle).attributes.set("class", Js.str(v));
		});
		define("toString", Js.fn((_, _) -> value(), false));
		for (op in ["add", "remove", "contains", "toggle", "replace", "item"])
			define(op, Js.fn(function(_, args):Dynamic {
				final list = tokens();
				if (op == "item") {
					final i = Std.int(Js.num(Js.at(args, 0)));
					return i >= 0 && i < list.length ? list[i] : null;
				}
				final name = Js.str(Js.at(args, 0));
				if (op == "contains") return list.contains(name);
				if (op == "toggle") {
					validate(name);
					final present = list.contains(name);
					final keep = args.length < 2 || args[1] == Js.u ? !present : Js.truth(args[1]);
					if (keep != present) {
						if (keep) list.push(name); else list.remove(name);
						store(list);
					}
					return keep;
				}
				if (op == "replace") {
					final replacement = Js.str(Js.at(args, 1));
					validate(name);
					validate(replacement);
					final i = list.indexOf(name);
					if (i < 0) return false;
					if (name != replacement) {
						if (list.contains(replacement)) {
							final first = Std.int(Math.min(i, list.indexOf(replacement)));
							list.remove(name);
							list.remove(replacement);
							list.insert(first, replacement);
						} else list[i] = replacement;
						store(list);
					}
					return true;
				}
				final names = [for (arg in args) Js.str(arg)];
				for (name in names) validate(name);
				for (name in names)
					if (op == "remove") list.remove(name); else if (!list.contains(name)) list.push(name);
				if (names.length != 0) store(list);
				return Js.u;
			}, false));
	}
}
