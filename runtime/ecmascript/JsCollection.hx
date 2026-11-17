/** Map and Set use SameValueZero keys and retain insertion order when visited. */
class JsCollection extends JsObject {
	final entries:Array<{key:Dynamic, value:Dynamic, live:Bool}> = [];
	final map:Bool;
	var count = 0;

	public function new(p:JsObject, map:Bool, init:Dynamic) {
		super(p);
		this.map = map;
		if (init == null || init == Js.u)
			return;
		for (item in Js.items(init))
			if (map)
				store(Js.get(item, 0), Js.get(item, 1));
			else
				store(item, item);
	}

	function find(k:Dynamic):Int {
		for (i in 0...entries.length)
			if (entries[i].live) {
				final key:Dynamic = entries[i].key;
				if (Js.equal(key, k) || (Js.type(key) == "number" && Js.type(k) == "number" && Math.isNaN(key) && Math.isNaN(k)))
					return i;
			}
		return -1;
	}

	function store(k:Dynamic, v:Dynamic) {
		final i = find(k);
		if (i < 0) {
			entries.push({key: k, value: v, live: true});
			count++;
		} else
			entries[i].value = v;
	}

	public function items():Array<Dynamic> {
		return [for (e in entries) if (e.live) map ? ([e.key, e.value] : Dynamic) : e.key];
	}

	public static function install(realm:JsObject) {
		for (isMap in [false, true]) {
			final c = Js.fn((r, args) -> new JsCollection((cast r : JsObject).prototype, isMap, Js.at(args, 0)), true), p:JsObject = c.read("prototype");
			final size = Js.obj();
			size.define("get", Js.fn((r, _) -> (cast r : JsCollection).count, false));
			JsProperties.define(p, "size", size);
			for (k in ([
				isMap ? "set" : "add",
				"delete",
				"clear",
				"has",
				"values",
				"keys",
				"entries",
				"forEach"
			].concat(isMap ? ["get"] : []))) {
				p.values.set(k, Js.fn(function(r:Dynamic, args:Array<Dynamic>):Dynamic {
					final that:JsCollection = r, key = Js.at(args, 0);
					switch k {
						case "set", "add":
							that.store(key, isMap ? Js.at(args, 1) : key);
							return r;
						case "has":
							return that.find(key) >= 0;
						case "get":
							final i = that.find(key);
							return i < 0 ? Js.u : that.entries[i].value;
						case "delete":
							final i = that.find(key);
							if (i < 0)
								return false;
							that.entries[i].live = false;
							that.count--;
							return true;
						case "clear":
							for (e in that.entries)
								e.live = false;
							that.count = 0;
							return Js.u;
						case "forEach":
							var i = 0;
							while (i < that.entries.length) {
								final e = that.entries[i++];
								if (e.live)
									Js.call(key, Js.at(args, 1), [e.value, e.key, r]);
							}
							return Js.u;
						default:
							return [
								for (e in that.entries)
									if (e.live) k == "entries" ? ([e.key, e.value] : Dynamic) : k == "keys" ? e.key : e.value
							];
					}
				}, false));
			}
			realm.define(isMap ? "Map" : "Set", c);
		}
	}
}
