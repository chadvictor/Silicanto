import haxe.io.Bytes;
import haxe.crypto.Base64;
import WebResources.WebBlob;

class WebNetwork {
	static final pending:Map<Int, Dynamic->Void> = [];

	public static function remote(url:String):Bool
		return ~/^https?:\/\//i.match(url);

	public static function busy():Bool
		return pending.iterator().hasNext();

	public static function poll() {
		for (id in [for (id in pending.keys()) id]) {
			final result = DesktopServices.call("http.poll", [id]), cb = pending.get(id);
			if (result != null && cb != null) {
				pending.remove(id);
				cb(result);
			}
		}
	}

	public static function cancel(id:Int) {
		if (pending.remove(id))
			DesktopServices.call("http.abort", [id]);
	}

	public static function send(method:String, url:String, headers:Dynamic, body:Bytes, timeout:Float, async:Bool, cb:Dynamic->Void):Int {
		if (!DesktopServices.available())
			throw "E-NETWORK: transport unavailable";
		final id:Int = DesktopServices.call("http.start", [method, url, headers, body == null ? null : Base64.encode(body), timeout]);
		if (async) {
			pending.set(id, cb);
			return id;
		}
		#if sys
		var result:Dynamic;
		while ((result = DesktopServices.call("http.poll", [id])) == null)
			Sys.sleep(.001);
		cb(result);
		#end
		return 0;
	}

	public static function blob(r:Dynamic):WebBlob {
		final mime = Reflect.field(r.headers, "content-type");
		return new WebBlob(WebResources.blobPrototype, Base64.decode(r.body), mime == null ? "" : Std.string(mime));
	}

	public static function load(url:String, ok:WebBlob->Void, no:String->Void) {
		if (remote(url)) {
			try
				send("GET", url, {}, null, 0, true, r -> {
					if (r.error != null)
						no(r.error);
					else if (r.status < 200 || r.status >= 300)
						no("HTTP " + r.status);
					else
						ok(blob(r));
				})
			catch (e:Dynamic)
				no(Std.string(e));
		} else
			WebPlatform.enqueue(() -> {
				var b:WebBlob;
				try
					b = WebResources.read(url)
				catch (e:Dynamic) {
					no(Std.string(e));
					return;
				}
				ok(b);
			});
	}

	public static function body(v:Dynamic, ?headers:Dynamic):Bytes {
		if (Std.isOfType(v, WebSearchParams)) {
			if (headers != null && !Reflect.fields(headers).map(k -> k.toLowerCase()).contains("content-type"))
				Reflect.setField(headers, "content-type", "application/x-www-form-urlencoded;charset=UTF-8");
			return Bytes.ofString((cast v : WebSearchParams).serialize());
		}
		if (v == null || v == Js.u)
			return null;
		if (Std.isOfType(v, WebBlob))
			return (cast v : WebBlob).bytes;
		if (Std.isOfType(v, JsTypedArray.JsBuffer))
			return (cast v : JsTypedArray.JsBuffer).bytes;
		if (Std.isOfType(v, JsTypedArray)) {
			final view:JsTypedArray = v;
			return view.buffer.bytes.sub(view.offset, Std.int(Js.num(view.read("byteLength"))));
		}
		return Bytes.ofString(Js.str(v));
	}

	public static function buffer(bytes:Bytes):Dynamic {
		final buf:JsTypedArray.JsBuffer = Js.construct(Js.global("ArrayBuffer"), [bytes.length]);
		buf.bytes.blit(0, bytes, 0, bytes.length);
		return buf;
	}

	public static function install() {
		Js.realm.define("fetch", Js.fn((_, a) -> {
			final promise = new JsPromise(), url = Js.str(Js.at(a, 0)), init = Js.at(a, 1);
			final field = k -> init == Js.u || init == null ? Js.u : Js.get(init, k);
			final method = field("method") == Js.u ? "GET" : Js.str(field("method")).toUpperCase(), headers:Dynamic = {}, h = field("headers");
			function finish(b:WebBlob, status:Int, finalUrl:String, fields:Dynamic) {
				final res = Js.obj(), head = Js.obj();
				var used = false;
				res.define("status", status);
				res.define("ok", status >= 200 && status < 300);
				res.define("url", finalUrl);
				head.define("get", Js.fn((_, a) -> Reflect.field(fields, Js.str(a[0]).toLowerCase()), false));
				res.define("headers", head);
				res.getters.set("bodyUsed", () -> used);
				for (name in ["text", "json", "blob", "arrayBuffer"])
					res.define(name, Js.fn((_, _) -> {
						final p = new JsPromise();
						if (used) {
							p.reject("TypeError: body already consumed");
							return p;
						}
						used = true;
						try {
							final v:Dynamic = switch (name) {
								case "text": WebRequest.textBody(b.bytes);
								case "json": Js.json(WebRequest.textBody(b.bytes));
								case "blob": b;
								default: buffer(b.bytes);
							};
							p.resolve(v);
						} catch (e:Dynamic)
							p.reject(e);
						return p;
					}, false));
				promise.resolve(res);
			}
			try {
				if (h != null && h != Js.u)
					for (k in JsStandard.keys(h))
						Reflect.setField(headers, k, Js.str(Js.get(h, k)));
				final bytes = body(field("body"), headers);
				if ((method == "GET" || method == "HEAD") && bytes != null)
					throw "TypeError: body on GET/HEAD";
				if (remote(url))
					send(method, url, headers, bytes, 0, true, r -> {
						if (r.error != null)
							promise.reject(r.error);
						else
							finish(blob(r), r.status, r.url, r.headers);
					});
				else if (method == "GET")
					load(url, b -> finish(b, 200, url, {}), e -> promise.reject(e));
				else
					throw "Unsupported local method";
			} catch (e:Dynamic)
				promise.reject(e);
			return promise;
		}, false));
	}
}
