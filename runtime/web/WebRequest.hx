/** Read-only XHR over an explicitly mounted local origin or a data/blob URL. */
class WebRequest extends JsObject {
	final events:WebEvents;
	var url:String;
	var mime:String;
	var async = true;
	var token = 0;

	public function new(proto:JsObject) {
		super(proto);
		events = new WebEvents(this);
		define("readyState", 0);
		define("status", 0);
		define("responseType", "");
		define("response", null);
		define("responseText", "");
		define("open", Js.fn((_, a) -> {
			if (Js.str(Js.at(a, 0)).toUpperCase() != "GET")
				throw "E-XHR: only GET is available for local resources";
			token++;
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
			if (read("readyState") != 1)
				throw "InvalidStateError";
			return Js.u;
		}, false));
		define("getResponseHeader", Js.fn((_, a) -> Js.str(Js.at(a, 0)).toLowerCase() == "content-type" ? mime : null, false));
		define("abort", Js.fn((_, a) -> {
			token++;
			define("readyState", 0);
			define("status", 0);
			events.fire("abort");
			return Js.u;
		}, false));
		define("send", Js.fn((_, a) -> {
			if (read("readyState") != 1)
				throw "InvalidStateError";
			final current = token;
			final fetch = () -> {
				if (current != token)
					return;
				var b:WebResources.WebBlob;
				try {
					b = WebResources.read(url);
				} catch (e:Dynamic) {
					define("status", 0);
					state(4);
					events.fire("error");
					events.fire("loadend");
					return;
				}
				define("status", 200);
				if (mime == null)
					mime = Js.str(b.read("type"));
				state(2);
				state(3);
				final kind = Js.str(read("responseType"));
				switch kind {
					case "blob": define("response", b);
					case "arraybuffer":
						final v:JsTypedArray.JsBuffer = Js.construct(Js.global("ArrayBuffer"), [b.bytes.length]);
						v.bytes.blit(0, b.bytes, 0, b.bytes.length);
						define("response", v);
					case "json": try {
							define("response", Js.json(b.bytes.toString()));
						} catch (_:Dynamic) {
							define("response", null);
						}
					case "", "text":
						final s = b.bytes.toString();
						define("response", s);
						define("responseText", s);
					default: throw "E-XHR: unsupported response type " + kind;
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
			if (async)
				WebPlatform.enqueue(fetch);
			else
				fetch();
			return Js.u;
		}, false));
	}

	function state(n:Int) {
		define("readyState", n);
		events.fire("readystatechange");
	}
}
