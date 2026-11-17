import haxe.io.Bytes;
import haxe.crypto.Base64;

class WebLayout {
	public static var root:JsObject;
	public static var width = 800;
	public static var height = 600;
	public static var styled = false;
	static var nodes:Array<JsObject> = [];
	static var boxes:Dynamic;

	static function style(o:JsObject):WebStyle
		return cast o.read("style");

	public static function attach(o:JsObject, tag:String) {
		final css = new WebStyle(tag);
		if (DesktopServices.available())
			selectors(o, o);
		o.getters.set("style", () -> css);
		o.setters.set("style", v -> {
			css.parse(Js.str(v));
			styled = true;
		});
		o.getters.set("textContent", () -> css.text != null ? css.text : plain(o));
		o.setters.set("textContent", v -> {
			clear(o);
			css.text = v == null ? "" : Js.str(v);
			css.html = null;
			styled = true;
		});
		o.getters.set("innerHTML", () -> css.html != null ? css.html : StringTools.htmlEscape(css.text == null ? "" : css.text));
		o.setters.set("innerHTML", v -> {
			clear(o);
			css.html = Js.str(v);
			css.text = null;
			styled = true;
		});
		o.define("getBoundingClientRect", Js.fn((_, _) -> bounds(o), false));
		for (k in ["clientWidth", "offsetWidth", "clientHeight", "offsetHeight"])
			o.getters.set(k, () -> bounds(o).read(StringTools.endsWith(k, "Width") ? "width" : "height"));
	}

	static function clear(o:JsObject) {
		final list:Dynamic = o.read("children");
		if (Std.isOfType(list, Array))
			for (n in (cast list : Array<Dynamic>).copy())
				Js.call(o.read("removeChild"), o, [n]);
		style(o).fragments = [];
	}

	static function plain(o:JsObject):String {
		final css = style(o), out = new StringBuf(), children:Array<Dynamic> = o.read("children");
		for (i in 0...children.length + 1) {
			for (f in css.fragments)
				if (f.at == i)
					out.add(f.text);
			if (i < children.length) {
				final child:JsObject = children[i];
				out.add(Js.str(child.read("textContent")));
			}
		}
		return out.toString();
	}

	public static function initial(o:JsObject, n:Dynamic) {
		final css = style(o);
		if (n.attrs != null)
			for (k in Reflect.fields(n.attrs)) {
				final v = Std.string(Reflect.field(n.attrs, k));
				css.attributes.set(k, v);
				if (k == "style") {
					css.parse(v);
					styled = true;
				} else if (k == "class")
					o.define("className", v);
			}
		if (n.fragments != null)
			css.fragments = cast n.fragments;
		if (n.sheet != null)
			css.sheet = n.sheet;
		else if (css.tag == "link"
			&& css.attributes.exists("href")
			&& css.attributes.exists("rel")
			&& css.attributes.get("rel").toLowerCase().split(" ").contains("stylesheet")
			&& WebNetwork.remote(css.attributes.get("href"))) {
			WebNetwork.load(css.attributes.get("href"), b -> {
				css.sheet = WebRequest.textBody(b.bytes);
				styled = true;
				Js.call(o.read("dispatchEvent"), o, [WebEvents.make("load")]);
			}, _ -> Js.call(o.read("dispatchEvent"), o, [WebEvents.make("error")]));
		}
		if (css.tag == "style" || css.sheet != null || css.fragments.filter(f -> StringTools.trim(f.text) != "").length > 0)
			styled = true;
	}

	static function render(op:String, ?scope:JsObject, ?selector:String, ?point:Array<Float>):Dynamic {
		if (root == null)
			return null;
		nodes = [];
		final out = new StringBuf(), images:Dynamic = {};
		function visit(o:JsObject) {
			if (!Std.isOfType(o.read("style"), WebStyle))
				return;
			final css = style(o), id = nodes.length;
			nodes.push(o);
			final tag = css.sheet != null ? "style" : css.tag;
			out.add("<" + tag + ' data-silicanto-node="' + id + '"');
			function attr(k:String, v:String)
				out.add(" " + k + '="' + StringTools.htmlEscape(v, true) + '"');
			for (k => v in css.attributes)
				if (!["style", "class", "id", "data-silicanto-node", "width", "height", "src"].contains(k)
					&& ~/^[A-Za-z_:][A-Za-z0-9_.:-]*$/.match(k))
					attr(k, v);
			for (k in ["id", "className", "width", "height", "src"]) {
				final v = o.read(k);
				if (v != null && v != Js.u && !(k == "src" && Std.isOfType(o, WebCanvas)))
					attr(k == "className" ? "class" : k, Js.str(v));
			}
			final inlineCss = css.serialize();
			if (inlineCss != "")
				attr("style", inlineCss);
			if (Std.isOfType(o, WebCanvas)) {
				final c:WebCanvas = cast o, key = "silicanto-canvas-" + id;
				attr("src", key);
				final img:Array<Dynamic> = [c.width, c.height];
				if (op == "paint")
					img.push(Base64.encode(c.surface()));
				Reflect.setField(images, key, img);
			} else if (Std.isOfType(o, WebImage)) {
				final img:WebImage = cast o, key = Js.str(o.read("src")), data:Array<Dynamic> = [img.width, img.height];
				if (op == "paint" && img.pixels != null)
					data.push(Base64.encode(img.pixels));
				Reflect.setField(images, key, data);
			}
			out.add(">");
			if (css.sheet != null)
				out.add(css.sheet);
			else if (css.html != null)
				out.add(css.html);
			else {
				final raw = tag == "style", children:Array<Dynamic> = o.read("children");
				if (css.text != null)
					out.add(raw ? css.text : StringTools.htmlEscape(css.text));
				for (i in 0...children.length + 1) {
					for (f in css.fragments)
						if (f.at == i)
							out.add(raw ? f.text : StringTools.htmlEscape(f.text));
					if (i < children.length)
						visit(children[i]);
				}
			}
			if (![
				"img", "link", "meta", "input", "br", "hr", "source", "area", "base", "embed", "param", "track", "wbr", "col"
			].contains(tag))
				out.add("</" + tag + ">");
		}
		visit(root);
		return DesktopServices.call("layout." + op, [
			out.toString(),
			width,
			height,
			images,
			scope == null ? -1 : (nodes.contains(scope) ? nodes.indexOf(scope) : -2),
			selector,
			point
		]);
	}

	public static function selectors(o:JsObject, ?scope:JsObject) {
		for (all in [false, true])
			o.define(all ? "querySelectorAll" : "querySelector", Js.fn((_, a) -> {
				final ids:Array<Int> = render("query", scope, Js.str(Js.at(a, 0)));
				final found:Array<Dynamic> = [for (i in ids) nodes[i]];
				return all ? cast found : found.length > 0 ? found[0] : null;
			}, false));
	}

	public static function computed(o:JsObject):Dynamic {
		final result = Js.obj(), fields = render("computed", o);
		for (k in Reflect.fields(fields))
			result.define(k, Reflect.field(fields, k));
		result.define("getPropertyValue", Js.fn((_, a) -> {
			final name = WebStyle.key(Js.str(Js.at(a, 0))), v = result.read(name);
			return v == Js.u ? "" : v;
		}, false));
		return result;
	}

	public static function bounds(o:JsObject):JsObject {
		var p:Array<Dynamic> = null;
		if (root != null && DesktopServices.available()) {
			boxes = render("boxes");
			p = Reflect.field(boxes, Std.string(nodes.indexOf(o)));
		} else {
			final c:WebCanvas = Std.isOfType(o, WebCanvas) ? cast o : null;
			p = [0, 0, c == null ? width : c.width, c == null ? height : c.height];
		}
		if (p == null)
			p = [0, 0, 0, 0];
		final x:Float = p[0], y:Float = p[1], w:Float = p[2], h:Float = p[3], r = Js.obj();
		for (k in ["left", "x"])
			r.define(k, x);
		for (k in ["top", "y"])
			r.define(k, y);
		r.define("width", w);
		r.define("height", h);
		r.define("right", x + w);
		r.define("bottom", y + h);
		return r;
	}

	public static function hit(x:Float, y:Float):JsObject {
		if (!DesktopServices.available())
			return null;
		final index:Int = render("hit", null, null, [x, y]);
		return index < 0 ? null : nodes[index];
	}

	public static function pixels():Bytes
		return Base64.decode(render("paint"));
}
