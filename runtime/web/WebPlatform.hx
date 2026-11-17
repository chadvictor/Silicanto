import haxe.io.Bytes;

class WebPlatform {
	static final ids:Map<String, JsObject> = [];
	static var canvas:WebCanvas;
	static var document:JsObject;

	public static function now():Float
		return clock;

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
		final o:JsObject = tag == "canvas" ? new WebCanvas(300,
			150) : tag == "audio"
			&& DesktopServices.available() ? new WebAudio() : tag == "img" ? new WebImage(Js.get(Js.global("Image"), "prototype")) : Js.obj();
		if (!Std.isOfType(o, WebAudio))
			new WebEvents(o);
		WebLayout.attach(o, tag);
		WebInput.attach(o);
		o.define("parentNode", null);
		o.define("parentElement", null);
		o.define("nodeName", tag.toUpperCase());
		o.define("nodeType", 1);
		o.define("tagName", tag.toUpperCase());
		final children:Array<Dynamic> = [];
		o.define("children", children);
		o.define("childNodes", children);
		o.getters.set("firstChild", () -> children.length == 0 ? null : children[0]);
		o.getters.set("lastChild", () -> children.length == 0 ? null : children[children.length - 1]);
		o.define("setAttribute", Js.fn((_, a) -> {
			final k = Js.str(a[0]), v = Js.str(a[1]);
			(cast o.read("style") : WebStyle).attributes.set(k, v);
			Js.put(o, k == "class" ? "className" : k, v);
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
		WebEvents.install();
		WebResources.install();
		WebNetwork.install();
		WebSocketClient.install();
		WebAudio.install();
		WebGL.install();
		WebTimers.install();
		WebXml.install();
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
		WebLayout.root = html;
		document = dom;
		WebInput.setup(dom, body);
		html.define("parentNode", dom);
		dom.define("defaultView", Js.realm);
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
			WebLayout.initial(e, n);
			if (n.attrs != null && Reflect.hasField(n.attrs, "src") && (Std.isOfType(e, WebImage) || Std.isOfType(e, WebAudio)))
				Js.put(e, "src", n.attrs.src);
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
		if (DesktopServices.available()) {
			WebLayout.selectors(dom);
			Js.realm.define("getComputedStyle", Js.fn((_, a) -> WebLayout.computed(Js.at(a, 0)), false));
		}
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
		var inputs:Array<Dynamic> = [];
		var timelinePath:String = null;
		var marks:Array<Int> = [];
		final trace:Array<Dynamic> = [];
		var frames = 1, path:String = null, pagePath:String = null, window = false, realtime = false;
		final finite = args.indexOf("--frames") >= 0;
		while (args.length > 0)
			switch args.shift() {
				case "--input":
					inputs = haxe.Json.parse(sys.io.File.getContent(args.shift()));
				case "--timeline":
					timelinePath = args.shift();
					marks = [];
					for (s in args.shift().split(",")) {
						final n = Std.parseInt(s);
						if (n == null || n < 1)
							throw "Invalid timeline frame";
						marks.push(n);
					}
					if (timelinePath == null || marks.length == 0)
						throw "Expected timeline file and positive frame numbers";
				case "--realtime":
					realtime = true;
				case "--window":
					window = true;
				case "--asset-root":
					args.shift();
				case "--frames":
					final count = Std.parseInt(args.shift());
					if (count == null || count < 1)
						throw "Expected a positive frame count";
					frames = count;
				case "--capture-page":
					pagePath = args.shift();
					if (pagePath == null)
						throw "Expected a page capture path";
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
			clock = realtime || (window && !finite) ? (haxe.Timer.stamp() - start) * 1000 : i * 1000. / 60.;
			WebTimers.advance(clock);
			for (event in inputs)
				if (event.frame == i + 1)
					WebInput.dispatch(event, canvas, document);
			if (window)
				for (event in WebWindow.events())
					WebInput.dispatch(event, canvas, document);
			WebNetwork.poll();
			WebSocketClient.poll();
			WebAudio.poll();
			WebPromise.checkpoint();
			var count = 0;
			while (tasks.length > 0) {
				if (++count > 100000)
					throw "E-EVENT: task queue did not settle";
				tasks.shift()();
				WebPromise.checkpoint();
				if (i == frames - 1 && (!window || finite))
					while (WebNetwork.busy()) {
						WebNetwork.poll();
						WebPromise.checkpoint();
						if (WebNetwork.busy())
							Sys.sleep(.001);
					}
			}
			if (i == frames - 1 && (!window || finite))
				while (WebNetwork.busy()) {
					WebNetwork.poll();
					WebPromise.checkpoint();
					if (WebNetwork.busy())
						Sys.sleep(.001);
				}
			final frame = callbacks;
			callbacks = [];
			for (cb in frame) {
				Js.call(cb.fn, Js.realm, [clock]);
				WebPromise.checkpoint();
			}
			if (timelinePath != null && marks.contains(i + 1)) {
				if (canvas == null)
					throw "E-CANVAS: no timeline canvas";
				final b = canvas.surface(), w = canvas.width, h = canvas.height;
				var changed = false;
				if (w * h > 0)
					for (pixel in 1...w * h)
						if (b.getInt32(pixel * 4) != b.getInt32(0)) {
							changed = true;
							break;
						}
				trace.push({
					frame: i + 1,
					width: w,
					height: h,
					sha256: haxe.crypto.Sha256.make(b).toHex(),
					uniform: !changed
				});
			}
			if (window) {
				final page = DesktopServices.available() && (WebLayout.styled || canvas == null);
				if (!page && canvas == null)
					throw "E-CANVAS: no display canvas";
				if (!(page ? WebWindow.present(WebLayout.width, WebLayout.height,
					WebLayout.pixels()) : WebWindow.present(canvas.width, canvas.height, canvas.surface())))
					break;
			}
			if (window || realtime)
				Sys.sleep(Math.max(0, (i + 1) / 60. - (haxe.Timer.stamp() - start)));
			i++;
		}
		if (window)
			WebWindow.close();
		if (timelinePath != null)
			sys.io.File.saveContent(timelinePath, haxe.Json.stringify(trace));
		if (pagePath != null) {
			final b = WebLayout.pixels(), f = sys.io.File.write(pagePath, true), rgb = Bytes.alloc(WebLayout.width * WebLayout.height * 3);
			for (i in 0...WebLayout.width * WebLayout.height)
				rgb.blit(i * 3, b, i * 4, 3);
			f.writeString("P6\n" + WebLayout.width + " " + WebLayout.height + "\n255\n");
			f.write(rgb);
			f.close();
		}
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
