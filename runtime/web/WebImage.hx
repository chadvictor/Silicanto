import haxe.io.Bytes;
import haxe.crypto.Base64;
import format.png.Reader;
import format.png.Tools;

/** PNG image decoding is asynchronous with respect to the assigning script. */
class WebImage extends JsObject {
	public var pixels:Bytes;
	public var width = 0;
	public var height = 0;

	var generation = 0;
	var url = "";

	public function new(proto:JsObject) {
		super(proto);
		getters.set("width", () -> width);
		getters.set("naturalWidth", () -> width);
		getters.set("height", () -> height);
		getters.set("naturalHeight", () -> height);
		getters.set("src", () -> url);
		setters.set("src", assign);
	}

	function assign(value:Dynamic) {
		url = Js.str(value);
		final src = url, current = ++generation;
		WebPlatform.enqueue(() -> {
			if (current != generation)
				return;
			var event = "load", failure = "";
			try {
				final data = WebResources.read(src).bytes;
				if (data.length >= 2 && data.get(0) == 255 && data.get(1) == 216) {
					final decoded = WebImageCodec.jpeg(data);
					if (decoded == null)
						throw "JPEG decoding unavailable on this target";
					width = decoded.getInt32(0);
					height = decoded.getInt32(4);
					pixels = decoded.sub(8, decoded.length - 8);
				} else {
					final png = new Reader(new haxe.io.BytesInput(data)).read();
					final h = Tools.getHeader(png);
					if (h.interlaced || h.width < 1 || h.height < 1 || 1.0 * h.width * h.height > 16777216)
						throw "unsupported image dimensions or interlacing";
					final bgra = Tools.extract32(png);
					for (i in 0...(h.width * h.height)) {
						final p = i * 4, b = bgra.get(p);
						bgra.set(p, bgra.get(p + 2));
						bgra.set(p + 2, b);
					}
					width = h.width;
					height = h.height;
					pixels = bgra;
				}
			} catch (err:Dynamic) {
				pixels = null;
				width = height = 0;
				event = "error";
				failure = Std.string(err);
			}
			final cb = read("on" + event);
			if (cb != Js.u && cb != null) {
				final e = Js.obj();
				e.define("type", event);
				e.define("target", this);
				Js.call(cb, this, [e]);
			} else if (event == "error")
				throw "E-IMAGE: " + failure;
		});
	}
}
