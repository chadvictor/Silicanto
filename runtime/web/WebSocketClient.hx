import haxe.io.Bytes;
import haxe.crypto.Base64;
import WebResources.WebBlob;

class WebSocketClient extends JsObject {
	static var proto:JsObject;
	static final sockets:Array<WebSocketClient> = [];

	final id:Int;
	final events:WebEvents;
	var state = 0;
	var binaryType = "blob";

	public static function install() {
		if (!DesktopServices.available())
			return;
		final ctor = Js.fn((_, a) -> new WebSocketClient(Js.str(Js.at(a, 0)), Js.at(a, 1)), true);
		proto = ctor.read("prototype");
		final names = ["CONNECTING", "OPEN", "CLOSING", "CLOSED"];
		for (i in 0...4) {
			ctor.define(names[i], i);
			proto.define(names[i], i);
		}
		Js.realm.define("WebSocket", ctor);
	}

	function new(url:String, requested:Dynamic) {
		super(proto);
		final protocols:Array<String> = [];
		if (requested != Js.u) {
			final list:Array<Dynamic> = Std.isOfType(requested, Array) ? cast requested : [requested];
			for (v in list) {
				final p = Js.str(v);
				if (!~/^[!#$%&'*+.^_\x60|~A-Za-z0-9-]+$/.match(p) || protocols.contains(p))
					throw "SyntaxError: invalid WebSocket subprotocol";
				protocols.push(p);
			}
		}
		id = DesktopServices.call("socket.open", [url, protocols]);
		events = new WebEvents(this);
		sockets.push(this);
		define("url", url);
		define("protocol", "");
		define("extensions", "");
		getters.set("readyState", () -> state);
		getters.set("binaryType", () -> binaryType);
		setters.set("binaryType", v -> {
			final s = Js.str(v);
			if (s == "blob" || s == "arraybuffer")
				binaryType = s;
		});
		define("send", Js.fn((_, a) -> {
			if (state == 0)
				throw "InvalidStateError";
			if (state != 1)
				return Js.u;
			final v:Dynamic = Js.at(a, 0), binary = Std.isOfType(v, WebBlob) || Std.isOfType(v, JsTypedArray) || Std.isOfType(v, JsTypedArray.JsBuffer);
			DesktopServices.call("socket.send", [id, binary, binary ? Base64.encode(WebNetwork.body(v)) : Js.str(v)]);
			return Js.u;
		}, false));
		define("close", Js.fn((_, a) -> {
			final code = a.length == 0 ? 1000 : Std.int(Js.num(a[0])), reason = a.length < 2 ? "" : Js.str(a[1]);
			if (code != 1000 && (code < 3000 || code > 4999))
				throw "InvalidAccessError";
			if (Bytes.ofString(reason).length > 123)
				throw "SyntaxError: close reason exceeds 123 bytes";
			if (state < 2) {
				state = 2;
				DesktopServices.call("socket.close", [id, code, reason]);
			}
			return Js.u;
		}, false));
	}

	public static function poll() {
		for (s in sockets.copy()) {
			final messages:Array<Dynamic> = DesktopServices.call("socket.poll", [s.id]);
			if (messages == null)
				continue;
			for (m in messages) {
				final e = WebEvents.make(m.type);
				switch (m.type) {
					case "open":
						if (s.state == 2)
							continue;
						s.state = 1;
						s.define("protocol", m.protocol);
					case "close":
						s.state = 3;
						sockets.remove(s);
						e.define("code", m.code);
						e.define("reason", m.reason);
						e.define("wasClean", m.wasClean);
					case "message":
						if (m.text != null)
							e.define("data", m.text);
						else {
							final bytes = Base64.decode(m.binary);
							e.define("data", s.binaryType == "arraybuffer" ? WebNetwork.buffer(bytes) : new WebBlob(WebResources.blobPrototype, bytes, ""));
						}
					case "error":
						e.define("message", m.message);
				}
				s.events.dispatch(e);
			}
		}
	}
}
