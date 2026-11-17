class JsProperties {
	public static function own(o:JsObject, k:String):Bool
		return o.values.exists(k) || o.getters.exists(k) || o.descriptors.exists(k);

	public static function lookup(o:JsObject, k:String):JsObject {
		while (o != null) {
			if (own(o, k))
				return o;
			o = o.prototype;
		}
		return null;
	}

	public static function descriptor(o:JsObject, k:String):Dynamic {
		if (!own(o, k))
			return Js.u;
		if (o.descriptors.exists(k)) {
			final result = Js.obj();
			copy(result, o.descriptors.get(k));
			return result;
		}
		final d = Js.obj();
		d.define("enumerable", o.keys.contains(k));
		d.define("configurable", true);
		d.define("writable", true);
		d.define("value", o.read(k));
		return d;
	}

	public static function define(o:JsObject, k:String, input:JsObject):JsObject {
		final original = descriptor(o, k);
		final d = Js.obj();
		for (key in ["enumerable", "configurable", "writable", "get", "set", "value"]) {
			if (Js.has(input, key))
				d.define(key, input.read(key));
			else if (original != Js.u && Js.has(original, key))
				d.define(key, Js.get(original, key));
		}
		if (d.values.exists("get") || d.values.exists("set")) {
			if (Js.has(input, "value") || Js.has(input, "writable"))
				throw "TypeError: invalid accessor descriptor";
			d.values.remove("value");
			d.values.remove("writable");
		} else if (!Js.has(d, "value"))
			d.define("value", Js.u);
		o.descriptors.set(k, d);
		o.values.remove(k);
		if (Js.truth(d.read("enumerable"))) {
			if (!o.keys.contains(k))
				o.keys.push(k);
		} else
			o.keys.remove(k);
		return o;
	}

	public static function accessor(o:JsObject, k:String, which:String, f:JsObject) {
		final d = Js.obj();
		d.define("enumerable", true);
		d.define("configurable", true);
		d.define(which, f);
		define(o, k, d);
	}

	public static function copy(dst:JsObject, src:Dynamic) {
		if (src == null || src == Js.u)
			return;
		if (Std.isOfType(src, String)) {
			final s:String = src;
			for (i in 0...s.length)
				dst.define(Std.string(i), s.charAt(i));
			return;
		}
		final keys = Std.isOfType(src, JsObject) ? (cast src : JsObject).keys.copy() : Js.keys(src);
		for (k in keys)
			dst.define(k, Js.get(src, k));
	}

	public static function install(object:JsObject) {
		object.define("assign", Js.fn((_, a) -> {
			final dst = Js.at(a, 0);
			if (dst == null || dst == Js.u)
				throw "TypeError: cannot assign to null or undefined";
			for (src in a.slice(1)) {
				if (src == null || src == Js.u)
					continue;
				if (Std.isOfType(src, String)) {
					final s:String = src;
					for (i in 0...s.length)
						Js.put(dst, i, s.charAt(i));
				} else {
					final keys = Std.isOfType(src, JsObject) ? (cast src : JsObject).keys.copy() : Js.keys(src);
					for (k in keys)
						Js.put(dst, k, Js.get(src, k));
				}
			}
			return dst;
		}, false));
		object.define("defineProperty", Js.fn((_, a) -> define(a[0], Js.str(a[1]), a[2]), false));
		object.define("defineProperties", Js.fn((_, args) -> {
			final target = Js.at(args, 0), descriptors = Js.at(args, 1);
			if (!Std.isOfType(target, JsObject) || descriptors == null || descriptors == Js.u)
				throw Js.construct(Js.global("TypeError"), ["Expected property descriptors"]);
			final pending:Array<{key:String, descriptor:JsObject}> = [];
			for (key in JsStandard.keys(descriptors)) {
				final input = Js.get(descriptors, key);
				if (!Std.isOfType(input, JsObject))
					throw Js.construct(Js.global("TypeError"), ["Expected a property descriptor"]);
				final d = Js.obj();
				for (field in ["enumerable", "configurable", "value", "writable", "get", "set"])
					if (Js.has(input, field)) {
						final v = Js.get(input, field);
						if ((field == "get" || field == "set") && v != Js.u && Js.type(v) != "function")
							throw Js.construct(Js.global("TypeError"), ["Invalid accessor"]);
						d.define(field, v);
					}
				if ((own(d, "get") || own(d, "set")) && (own(d, "value") || own(d, "writable")))
					throw Js.construct(Js.global("TypeError"), ["Mixed property descriptor"]);
				pending.push({key: key, descriptor: d});
			}
			for (entry in pending) define(cast target, entry.key, entry.descriptor);
			return target;
		}, false));
		object.define("getOwnPropertyDescriptor", Js.fn((_, a) -> descriptor(a[0], Js.str(a[1])), false));
		object.define("getPrototypeOf", Js.fn((_, a) -> (cast a[0] : JsObject).prototype, false));
		object.define("getOwnPropertyNames", Js.fn((_, a) -> {
			final o:JsObject = a[0], names = o.keys.copy();
			for (key in o.values.keys())
				if (!names.contains(key))
					names.push(key);
			for (key in o.descriptors.keys())
				if (!names.contains(key))
					names.push(key);
			return names;
		}, false));
	}
}
