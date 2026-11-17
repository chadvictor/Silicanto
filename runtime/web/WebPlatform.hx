import haxe.io.Bytes;

class WebPlatform {
	static final ids:Map<String, JsObject> = [];
	static var canvas:WebCanvas;
	static var callbacks:Array<{id:Int, fn:Dynamic}> = [];
	static var next = 0;
	static var clock:Float = 0.;
	static final tasks:Array<Void->Void> = [];

	public static function enqueue(job:Void->Void)
		tasks.push(job);

	public static var canvasType:JsObject;
	public static var contextType:JsObject;

	static function interfaceType(name:String):JsObject {
		final c = Js.fn((_, _) -> {
			throw "TypeError: Illegal constructor " + name;
		}, true);
		Js.realm.define(name, c);
		return Js.get(c, "prototype");
	}

	static function element(tag:String):JsObject {
		final o:JsObject = tag == "canvas" ? new WebCanvas(300, 150) : Js.obj();
		new WebEvents(o);
		final style = Js.obj();
		style.values.set("setProperty", Js.fn((_, a) -> {
			style.define(Js.str(a[0]), Js.str(a[1]));
			return Js.u;
		}, false));
		style.values.set("getPropertyValue", Js.fn((_, a) -> {
			final v = style.read(Js.str(a[0]));
			return v == Js.u ? "" : Js.str(v);
		}, false));
		o.define("style", style);
		o.define("parentNode", null);
		o.define("parentElement", null);
		o.define("nodeName", tag.toUpperCase());
		o.define("nodeType", 1);
		o.define("tagName", tag.toUpperCase());
		o.define("getBoundingClientRect", Js.fn((_, a) -> {
			final box = Js.obj(), w = Std.isOfType(o,
				WebCanvas) ? (cast o : WebCanvas).width : 800, h = Std.isOfType(o, WebCanvas) ? (cast o : WebCanvas).height : 600;
			for (k in ["x", "y", "top", "left"])
				box.define(k, 0);
			for (k in ["width", "right"])
				box.define(k, w);
			for (k in ["height", "bottom"])
				box.define(k, h);
			return box;
		}, false));
		final children:Array<Dynamic> = [];
		o.define("children", children);
		o.define("childNodes", children);
		o.getters.set("firstChild", () -> children.length == 0 ? null : children[0]);
		o.getters.set("lastChild", () -> children.length == 0 ? null : children[children.length - 1]);
		o.define("setAttribute", Js.fn((_, a) -> {
			Js.put(o, Js.str(a[0]), Js.str(a[1]));
			return Js.u;
		}, false));
		o.define("getAttribute", Js.fn((_, a) -> {
			final x = o.read(Js.str(a[0]));
			return x == Js.u ? null : Js.str(x);
		}, false));
		o.define("removeChild", Js.fn((_, a) -> {
			final n = Js.at(a, 0);
			if (!children.remove(n))
				throw "NotFoundError";
			Js.put(n, "parentElement", null);
			Js.put(n, "parentNode", null);
			return n;
		}, false));
		o.define("appendChild", Js.fn((_, args) -> {
			final n:Dynamic = Js.at(args, 0);
			if (Std.isOfType(n, WebCanvas))
				canvas = cast n;
			final old = Js.get(n, "parentNode");
			if (old != null && old != Js.u)
				Js.call(Js.get(old, "removeChild"), old, [n]);
			children.push(n);
			Js.put(n, "parentElement", o);
			Js.put(n, "parentNode", o);
			return n;
		}, false));
		return o;
	}

	public static function init(markup:String) {
		WebResources.install();
		WebGL.install();
		WebTimers.install();
		WebEncoding.install();
		#if sys
		final args = Sys.args();
		final rootArg = args.indexOf("--asset-root");
		if (rootArg >= 0)
			WebResources.mount(args[rootArg + 1]);
		#end
		canvasType = interfaceType("HTMLCanvasElement");
		contextType = interfaceType("CanvasRenderingContext2D");
		final image = Js.fn((self, _) -> new WebImage((cast self : JsObject).prototype), true);
		Js.realm.define("Image", image);
		Js.realm.define("HTMLImageElement", image);
		final dom = Js.obj(), body = element("body");
		dom.define("body", body);
		final html = element("html"), head = element("head");
		dom.define("documentElement", html);
		dom.define("head", head);
		for (child in [head, body])
			Js.call(html.read("appendChild"), html, [child]);
		dom.define("createElementNS", Js.fn((_, a) -> element(Js.str(Js.at(a, 1)).toLowerCase()), false));
		dom.define("getElementsByTagName", Js.fn((_, a) -> {
			final tag = Js.str(Js.at(a, 0)).toUpperCase(), found:Array<Dynamic> = [];
			function visit(o:JsObject) {
				if (tag == "*" || o.read("tagName") == tag)
					found.push(o);
				for (child in (cast o.read("children") : Array<Dynamic>))
					visit(child);
			}
			visit(html);
			return found;
		}, false));
		final domEvents = new WebEvents(dom), winEvents = new WebEvents(Js.realm);
		dom.define("readyState", "loading");
		enqueue(() -> {
			dom.define("readyState", "interactive");
			domEvents.fire("DOMContentLoaded");
			dom.define("readyState", "complete");
			winEvents.fire("load");
		});
		final performance = Js.obj();
		performance.define("now", Js.fn((_, a) -> clock, false));
		Js.realm.define("performance", performance);
		final screen = Js.obj();
		screen.define("width", 800);
		screen.define("height", 600);
		screen.define("availWidth", 800);
		screen.define("availHeight", 600);
		Js.realm.define("screen", screen);
		Js.realm.define("innerWidth", 800);
		Js.realm.define("innerHeight", 600);
		final nodes:Array<Dynamic> = haxe.Json.parse(markup);
		final built:Array<JsObject> = [];
		for (n in nodes) {
			final e = switch Std.string(n.tag) {
				case "head": head;
				case "body": body;
				case "html": html;
				default: element(n.tag);
			};
			if (e != head && e != body && e != html) {
				final parent:JsObject = n.parent != null && n.parent >= 0 && n.parent < built.length ? built[n.parent] : body;
				Js.call(parent.read("appendChild"), parent, [e]);
			}
			built.push(e);
			e.define("id", n.id);
			if (n.id != "")
				ids.set(n.id, e);
			if (Std.isOfType(e, WebCanvas)) {
				canvas = cast e;
				if (n.width != null)
					Js.put(e, "width", n.width);
				if (n.height != null)
					Js.put(e, "height", n.height);
			}
		}
		dom.define("createElement", Js.fn((_, args) -> element(Js.str(Js.at(args, 0))), false));
		dom.define("getElementById", Js.fn((_, args) -> ids.get(Js.str(Js.at(args, 0))), false));
		dom.define("querySelector", Js.fn((_, args) -> {
			final query = Js.str(Js.at(args, 0));
			if (query == "canvas")
				return (canvas : JsObject);
			if (query == "body")
				return body;
			if (StringTools.startsWith(query, "#"))
				return ids.get(query.substr(1));
			throw "E-DOM: unsupported selector " + query;
		}, false));
		final nav = Js.obj();
		nav.define("userAgent", "Silicanto");
		nav.define("platform", #if sys Sys.systemName() #else "Web" #end);
		nav.define("maxTouchPoints", 0);
		Js.realm.define("navigator", nav);
		Js.realm.define("devicePixelRatio", 1);
		Js.realm.define("document", dom);
		Js.realm.define("window", Js.realm);
		Js.realm.define("self", Js.realm);
		Js.realm.define("requestAnimationFrame", Js.fn((_, a) -> {
			callbacks.push({id: ++next, fn: Js.at(a, 0)});
			return next;
		}, false));
		Js.realm.define("cancelAnimationFrame", Js.fn((_, a) -> {
			final id = Std.int(Js.num(Js.at(a, 0)));
			callbacks = callbacks.filter(c -> c.id != id);
			return Js.u;
		}, false));
	}

	public static function run() {
		#if sys
		final args = Sys.args();
		var frames = 1, path:String = null, window = false;
		final finite = args.indexOf("--frames") >= 0;
		while (args.length > 0)
			switch args.shift() {
				case "--window":
					window = true;
				case "--asset-root":
					args.shift();
				case "--frames":
					final count = Std.parseInt(args.shift());
					if (count == null || count < 1)
						throw "Expected a positive frame count";
					frames = count;
				case "--capture":
					path = args.shift();
					if (path == null)
						throw "Expected capture path";
				default:
					throw "Expected --frames, --capture, --asset-root or --window";
			}
		var i = 0;
		final start = haxe.Timer.stamp();
		while (window && !finite || i < frames) {
			clock = window && !finite ? (haxe.Timer.stamp() - start) * 1000 : i * 1000. / 60.;
			WebTimers.advance(clock);
			var count = 0;
			while (tasks.length > 0) {
				if (++count > 100000)
					throw "E-EVENT: task queue did not settle";
				tasks.shift()();
			}
			final frame = callbacks;
			callbacks = [];
			for (cb in frame)
				Js.call(cb.fn, Js.realm, [clock]);
			if (window) {
				if (canvas == null || canvas.width == 0 || canvas.height == 0)
					throw "E-CANVAS: no display canvas";
				if (!WebWindow.present(canvas.width, canvas.height, canvas.surface()))
					break;
				Sys.sleep(Math.max(0, (i + 1) / 60. - (haxe.Timer.stamp() - start)));
			}
			i++;
		}
		if (window)
			WebWindow.close();
		if (path != null) {
			if (canvas == null || canvas.width == 0 || canvas.height == 0)
				throw "E-CANVAS: nothing to capture";
			final f = sys.io.File.write(path, true);
			f.writeString("P6\n" + canvas.width + " " + canvas.height + "\n255\n");
			final rgba = canvas.surface();
			final rgb = Bytes.alloc(canvas.width * canvas.height * 3);
			for (i in 0...(canvas.width * canvas.height))
				for (k in 0...3)
					rgb.set(i * 3 + k, WebRaster.byte(rgba.get(i * 4 + k) * rgba.get(i * 4 + 3) / 255.));
			f.write(rgb);
			f.close();
		}
		#else
		throw "E-TARGET: this Canvas host requires a sys target";
		#end
	}
}
