/** XHR over mounted resources and native HTTP(S). */
class WebRequest extends JsObject {
	final events:WebEvents;
	var url:String;
	var mime:String;
	var async = true;
	var token = 0;
	var requestId = 0;
	var sending = false;
	var method:String;
	var headers:Dynamic = {};
	var responseHeaders:Dynamic = {};

	public function new(proto:JsObject) {
		super(proto);
		events = new WebEvents(this);
		define("readyState", 0);
		define("status", 0);
		define("responseType", "");
		define("timeout", 0);
		define("response", null);
		define("responseText", "");
		define("responseXML", null);
		define("open", Js.fn((_, a) -> {
			method = Js.str(Js.at(a, 0)).toUpperCase();
			if (!~/^[A-Z]+$/.match(method) || ["CONNECT", "TRACE", "TRACK"].contains(method))
				throw "Invalid HTTP method";
			WebNetwork.cancel(requestId);
			requestId = 0;
			sending = false;
			headers = {};
			responseHeaders = {};
			token++;
			mime = null;
			define("status", 0);
			define("response", null);
			define("responseText", "");
			define("responseXML", null);
			url = Js.str(Js.at(a, 1));
			async = a.length < 3 || Js.truth(a[2]);
			state(1);
			return Js.u;
		}, false));
		define("overrideMimeType", Js.fn((_, a) -> {
			mime = Js.str(Js.at(a, 0));
			return Js.u;
		}, false));
		define("setRequestHeader", Js.fn((_, a) -> {
			if (read("readyState") != 1 || sending)
				throw "InvalidStateError";
			final key = Js.str(Js.at(a, 0)).toLowerCase(), v = Js.str(Js.at(a, 1)), old = Reflect.field(headers, key);
			Reflect.setField(headers, key, old == null ? v : old + ", " + v);
			return Js.u;
		}, false));
		define("getAllResponseHeaders", Js.fn((_, _) -> {
			final keys = Reflect.fields(responseHeaders);
			keys.sort(Reflect.compare);
			return [
				for (k in keys) k + ": " + Std.string(Reflect.field(responseHeaders, k)) + "\r\n"
			].join("");
		}, false));
		define("getResponseHeader", Js.fn((_, a) -> Reflect.field(responseHeaders, Js.str(Js.at(a, 0)).toLowerCase()), false));
		define("abort", Js.fn((_, a) -> {
			WebNetwork.cancel(requestId);
			requestId = 0;
			sending = false;
			token++;
			define("readyState", 0);
			define("status", 0);
			events.fire("abort");
			return Js.u;
		}, false));
		define("send", Js.fn((_, a) -> {
			if (read("readyState") != 1 || sending)
				throw "InvalidStateError";
			final current = token;
			sending = true;
			function failed(event:String) {
				if (current != token)
					return;
				sending = false;
				requestId = 0;
				define("status", 0);
				state(4);
				events.fire(event);
				events.fire("loadend");
			}
			function receive(b:WebResources.WebBlob, status:Int, actualURL:String, fields:Dynamic) {
				if (current != token)
					return;
				sending = false;
				requestId = 0;
				responseHeaders = fields;
				define("status", status);
				define("responseURL", actualURL);
				if (mime == null)
					mime = Js.str(b.read("type"));
				state(2);
				state(3);
				final kind = Js.str(read("responseType"));
				switch kind {
					case "blob":
						define("response", b);
					case "arraybuffer":
						final v:JsTypedArray.JsBuffer = Js.construct(Js.global("ArrayBuffer"), [b.bytes.length]);
						v.bytes.blit(0, b.bytes, 0, b.bytes.length);
						define("response", v);
					case "document":
						final doc = WebXml.parse(textBody(b.bytes));
						final value = Js.get(Js.get(doc, "documentElement"), "tagName") == "parsererror" ? null : doc;
						define("response", value);
						define("responseXML", value);
					case "json":
						try {
							define("response", Js.json(textBody(b.bytes)));
						} catch (_:Dynamic) {
							define("response", null);
						}
					case "", "text":
						final s = textBody(b.bytes);
						define("response", s);
						define("responseText", s);
						if (kind == "" && (mime != null && mime.toLowerCase().indexOf("xml") >= 0)) {
							final xml = WebXml.parse(s);
							if (Js.get(Js.get(xml, "documentElement"), "tagName") != "parsererror")
								define("responseXML", xml);
						}
					default:
						throw "E-XHR: unsupported response type " + kind;
				}
				final ev = Js.obj();
				ev.define("type", "progress");
				ev.define("lengthComputable", true);
				ev.define("loaded", b.bytes.length);
				ev.define("total", b.bytes.length);
				events.dispatch(ev);
				state(4);
				events.fire("load");
				events.fire("loadend");
			};
			if (WebNetwork.remote(url)) {
				final payload = (method == "GET" || method == "HEAD") ? null : WebNetwork.body(Js.at(a, 0));
				try
					requestId = WebNetwork.send(method, url, headers, payload, Js.num(read("timeout")), async, r -> {
						if (r.error != null)
							failed(r.timeout == true ? "timeout" : "error");
						else
							receive(WebNetwork.blob(r), r.status, r.url, r.headers);
					})
				catch (e:Dynamic) {
					failed("error");
					if (!async)
						throw e;
				}
			} else {
				final local = () -> {
					if (current != token)
						return;
					var b:WebResources.WebBlob;
					try {
						if (method != "GET")
							throw "Local requests require GET";
						b = WebResources.read(url);
					} catch (_:Dynamic) {
						failed("error");
						return;
					}
					final fields:Dynamic = {};
					Reflect.setField(fields, "content-type", b.read("type"));
					receive(b, 200, url, fields);
				};
				if (async)
					WebPlatform.enqueue(local);
				else
					local();
			}
			return Js.u;
		}, false));
	}

	public static function textBody(bytes:haxe.io.Bytes):String {
		final bom = bytes.length >= 3 && bytes.get(0) == 239 && bytes.get(1) == 187 && bytes.get(2) == 191;
		return bytes.getString(bom ? 3 : 0, bytes.length - (bom ? 3 : 0));
	}

	function state(n:Int) {
		define("readyState", n);
		events.fire("readystatechange");
	}
}
