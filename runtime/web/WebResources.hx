import haxe.io.Bytes;
import haxe.crypto.Base64;

class WebBlob extends JsObject {
	public final bytes:Bytes;

	public function new(p:JsObject, bytes:Bytes, mime:String) {
		super(p);
		this.bytes = bytes;
		define("size", bytes.length);
		define("type", mime);
	}
}

/** Local assets have an explicit origin. Network access is never implicit. */
class WebResources {
	static var root:String;
	static var next = 0;
	static final blobs:Map<String, WebBlob> = [];
	static var blobPrototype:JsObject;

	public static function mount(path:String) {
		#if sys
		if (path == null || !sys.FileSystem.isDirectory(path))
			throw "E-ASSET: expected a web root directory";
		root = sys.FileSystem.fullPath(path);
		#end
	}

	public static function read(url:String):WebBlob {
		if (blobs.exists(url))
			return blobs.get(url);
		if (StringTools.startsWith(url, "data:")) {
			final comma = url.indexOf(",");
			if (comma < 0)
				throw "E-ASSET: invalid data URL";
			final metadata = url.substring(5, comma).split(";"), text = url.substr(comma + 1);
			final b = metadata.contains("base64") ? Base64.decode(text) : Bytes.ofString(StringTools.urlDecode(StringTools.replace(text, "+", "%2B")));
			return new WebBlob(blobPrototype, b, metadata[0]);
		}
		#if sys
		if (root == null || ~/^[a-z][a-z0-9+.-]*:/i.match(url) || StringTools.startsWith(url, "//"))
			throw "E-ASSET: URL is outside the mounted origin: " + url;
		final name = StringTools.urlDecode(StringTools.replace(url.split("#")[0].split("?")[0], "+", "%2B")), parts = [];
		if (name.indexOf("\\") >= 0 || name.indexOf(String.fromCharCode(0)) >= 0)
			throw "E-ASSET: invalid URL path";
		for (part in name.split("/")) {
			if (part == "." || part == "")
				continue;
			if (part == "..") {
				parts.pop();
				continue;
			}
			parts.push(part);
		}
		final path = sys.FileSystem.fullPath(haxe.io.Path.join([root, parts.join("/")]));
		if (!StringTools.startsWith(path, root + "/") || !sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path))
			throw "E-ASSET: missing " + url;
		final ext = haxe.io.Path.extension(path).toLowerCase(), mime = switch ext {
			case "png": "image/png";
			case "jpg", "jpeg": "image/jpeg";
			case "json": "application/json";
			case "txt", "csv": "text/plain";
			default: "application/octet-stream";
		};
		return new WebBlob(blobPrototype, sys.io.File.getBytes(path), mime);
		#else
		throw "E-ASSET: local assets require a sys target";
		#end
	}

	public static function install() {
		final blob = Js.fn((self, a) -> {
			final buf = new haxe.io.BytesBuffer();
			if (a.length > 0)
				for (v in Js.items(a[0])) {
					if (Std.isOfType(v, WebBlob))
						buf.add((cast v : WebBlob).bytes);
					else if (Std.isOfType(v, JsTypedArray.JsBuffer))
						buf.add((cast v : JsTypedArray.JsBuffer).bytes);
					else if (Std.isOfType(v, JsTypedArray)) {
						final view:JsTypedArray = v;
						buf.addBytes(view.buffer.bytes, view.offset, Std.int(Js.num(view.read("byteLength"))));
					} else
						buf.addString(Js.str(v));
				}
			final mime = a.length > 1 && Js.get(a[1], "type") != Js.u ? Js.str(Js.get(a[1], "type")).toLowerCase() : "";
			return new WebBlob(blobPrototype, buf.getBytes(), mime);
		}, true);
		blobPrototype = blob.read("prototype");
		Js.realm.define("Blob", blob);
		final url = Js.fn((_, a) -> {
			throw "E-URL: URL parsing is unsupported";
		}, true);
		url.define("createObjectURL", Js.fn((_, a) -> {
			final b = Js.at(a, 0);
			if (!Std.isOfType(b, WebBlob))
				throw "TypeError: expected a Blob";
			final id = "blob:silicanto/" + (++next);
			blobs.set(id, b);
			return id;
		}, false));
		url.define("revokeObjectURL", Js.fn((_, a) -> {
			blobs.remove(Js.str(Js.at(a, 0)));
			return Js.u;
		}, false));
		Js.realm.define("URL", url);
		Js.realm.define("XMLHttpRequest", Js.fn((self, a) -> new WebRequest((cast self : JsObject).prototype), true));
	}
}
