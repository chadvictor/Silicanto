/** Selects a translated classic script by its document URL. */
class WebScriptElement extends JsObject {
	static final modules:Map<String, {id:Int, load:Void->Dynamic}> = [];
	var source = "";
	var started = false;

	public static function register(url:String, id:Int, load:Void->Dynamic):Void
		modules.set(url, {id:id, load:load});

	public function new() {
		super(Js.obj().prototype);
		define("type", "");
		getters.set("src", () -> source);
		setters.set("src", v -> {
			source = Js.str(v);
			schedule();
		});
		getters.set("text", () -> read("textContent"));
		setters.set("text", v -> Js.put(this, "textContent", Js.str(v)));
	}

	public function parserInserted(attrs:Dynamic):Void {
		started = true;
		if (attrs == null) return;
		if (Reflect.hasField(attrs, "src")) source = Reflect.field(attrs, "src");
		if (Reflect.hasField(attrs, "type")) define("type", Reflect.field(attrs, "type"));
	}

	public static function attached(node:Dynamic):Void {
		if (!Std.isOfType(node, JsObject)) return;
		final element:JsObject = node;
		if (Std.isOfType(element, WebScriptElement)) (cast element:WebScriptElement).schedule();
		final children = element.read("children");
		if (Std.isOfType(children, Array))
			for (child in (cast children:Array<Dynamic>)) attached(child);
	}

	function schedule():Void {
		if (started || source == "" || WebLayout.root == null) return;
		var parent:Dynamic = read("parentNode");
		while (Std.isOfType(parent, JsObject) && parent != WebLayout.root)
			parent = Js.get(parent, "parentNode");
		if (parent != WebLayout.root) return;
		final type = StringTools.trim(Js.str(read("type"))).toLowerCase();
		if (type != "" && type != "module" && !~/^(?:(?:application|text)\/(?:x-)?(?:java|ecma)script|text\/(?:javascript1\.[0-5]|jscript|livescript))$/.match(type)) return;
		started = true;
		final path = source.split("#")[0].split("?")[0];
		var decoded = path;
		try decoded = StringTools.urlDecode(StringTools.replace(path, "+", "%2B")) catch (_:Dynamic) {}
		final module = modules.get(haxe.io.Path.normalize(decoded));
		WebPlatform.enqueue(() -> {
			if (module == null || type == "module") {
				fire("error");
				return;
			}
			Js.runClassic(module.id, module.load);
			fire("load");
		});
	}

	function fire(name:String):Void
		Js.call(read("dispatchEvent"), this, [WebEvents.make(name, "Event", false, false)]);
}
