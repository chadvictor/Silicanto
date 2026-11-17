import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** Ordered query pairs with application/x-www-form-urlencoded serialization. */
class WebSearchParams extends JsObject {
	final pairs:Array<{key:String, value:String}> = [];

	static inline var hex = "0123456789ABCDEF";
	static function decode(s:String):String {
		final bytes = Bytes.ofString(s), out = new BytesBuffer();
		var i = 0;
		function nibble(c:Int):Int
			return c >= 48 && c <= 57 ? c - 48 : (c | 32) >= 97 && (c | 32) <= 102 ? (c | 32) - 87 : -1;
		while (i < bytes.length) {
			final c = bytes.get(i++);
			if (c == 37 && i + 1 < bytes.length) {
				final a = nibble(bytes.get(i)), b = nibble(bytes.get(i + 1));
				if (a >= 0 && b >= 0) { out.addByte(a * 16 + b); i += 2; continue; }
			}
			out.addByte(c == 43 ? 32 : c);
		}
		return out.getBytes().toString();
	}

	static function encode(s:String):String {
		final bytes = Bytes.ofString(s), out = new StringBuf();
		for (i in 0...bytes.length) {
			final c = bytes.get(i);
			if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 42 || c == 45 || c == 46 || c == 95)
				out.addChar(c);
			else if (c == 32) out.add("+");
			else out.add("%" + hex.charAt(c >> 4) + hex.charAt(c & 15));
		}
		return out.toString();
	}

	public function serialize():String
		return [for (p in pairs) encode(p.key) + "=" + encode(p.value)].join("&");

	public override function toString():String return serialize();

	function new(p:JsObject, input:Dynamic) {
		super(p);
		if (Std.isOfType(input, WebSearchParams)) {
			for (pair in (cast input : WebSearchParams).pairs)
				pairs.push({key:pair.key,value:pair.value});
		} else if (Std.isOfType(input, Array)) {
			for (entry in (cast input:Array<Dynamic>)) {
				final values = Js.items(entry);
				if (values.length != 2) throw Js.construct(Js.global("TypeError"), ["Expected name and value"]);
				pairs.push({key:Js.str(values[0]),value:Js.str(values[1])});
			}
		} else if (Std.isOfType(input, JsObject)) {
			for (key in JsStandard.keys(input)) pairs.push({key:key, value:Js.str(Js.get(input,key))});
		} else if (input != Js.u) {
			var data = Js.str(input);
			if (StringTools.startsWith(data,"?")) data = data.substr(1);
			for (part in data.split("&")) {
				if (part == "") continue;
				final split = part.indexOf("=");
				pairs.push({key:decode(split < 0 ? part : part.substr(0, split)), value:split < 0 ? "" : decode(part.substr(split+1))});
			}
		}
		getters.set("size", () -> pairs.length);
	}

	public static function install() {
		var proto:JsObject = null;
		final ctor = Js.fn((_, args) -> new WebSearchParams(proto, Js.at(args,0)),true);
		proto = ctor.read("prototype");
		for (method in ["append","get","getAll","has","delete","set","sort","forEach","toString"])
			proto.values.set(method, Js.fn(function(receiver:Dynamic, args:Array<Dynamic>):Dynamic {
				final s:WebSearchParams = cast receiver, pairs = s.pairs;
				final keyed = ["append","get","getAll","has","delete","set"].contains(method);
				if (keyed && args.length == 0 || (method == "append" || method == "set") && args.length < 2)
					throw Js.construct(Js.global("TypeError"), ["Missing query parameter argument"]);
				final key = keyed ? Js.str(args[0]) : "";
				final value = ["append","has","delete","set"].contains(method) ? Js.str(Js.at(args,1)) : "";
				switch method {
					case "append": pairs.push({key:key,value:value});
					case "get": for (p in pairs) if (p.key == key) return p.value; return null;
					case "getAll": return [for (p in pairs) if (p.key == key) p.value];
					case "has": for (p in pairs) if (p.key == key && (Js.at(args,1) == Js.u || p.value == value)) return true; return false;
					case "set", "delete":
						var i = 0, found = false;
						while (i < pairs.length) {
							final p = pairs[i];
							if (p.key != key || (method == "delete" && Js.at(args,1) != Js.u && p.value != value)) { i++; continue; }
							if (method == "set" && !found) { p.value=value; found=true; i++; } else pairs.splice(i,1);
						}
						if (method == "set" && !found) pairs.push({key:key,value:value});
					case "sort": haxe.ds.ArraySort.sort(pairs,(a,b) -> Reflect.compare(a.key,b.key));
					case "forEach":
						var i = 0;
						while (i < pairs.length) {
							final p = pairs[i++];
							Js.call(Js.at(args,0), Js.at(args,1), [p.value,p.key,s]);
						}
					case "toString": return s.serialize();
				}
				return Js.u;
			},false));
		Js.realm.define("URLSearchParams",ctor);
	}
}
