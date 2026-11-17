private class JsUndefined {
	public function new() {}
}

private class JsUninitialized {
	public function new() {}
}

class Js {
	public static final u:Dynamic = new JsUndefined();
	public static final tdz:Dynamic = new JsUninitialized();
	static final cache:Map<Int, JsObject> = [];
	static final globals:Map<String, Dynamic> = [];
	// Dense elements stay in the target Array. Allocate a property bag only for named writes.
	#if (cpp || java)
	static final arrayProperties = new haxe.ds.WeakMap<Array<Dynamic>, JsObject>();
	#else
	static final arrayProperties = new haxe.ds.ObjectMap<Array<Dynamic>, JsObject>();
	#end
	static final ordinary = new JsObject();
	static var ready = false;

	public static function load(id:Int, factory:(Dynamic, Dynamic) -> Void):Dynamic {
		if (cache.exists(id))
			return cache.get(id).read("exports");
		final module = obj(), exports = obj();
		module.define("exports", exports);
		cache.set(id, module);
		try
			factory(module, exports)
		catch (e:Dynamic) {
			cache.remove(id);
			throw e;
		}
		return module.read("exports");
	}

	public static function constantWrite(value:Dynamic):Dynamic {
		throw construct(global("TypeError"), ["Assignment to constant variable."]);
	}

	public static function obj():JsObject
		return new JsObject(ordinary);

	public static function binding(value:Dynamic, name:String):Dynamic {
		if (value == tdz)
			throw 'ReferenceError: ' + name + ' is not initialized';
		return value;
	}

	public static function expose(obj:JsObject, key:String, getter:Void->Dynamic) {
		obj.keys.push(key);
		obj.getters.set(key, getter);
	}

	public static function fn(body:(Dynamic, Array<Dynamic>) -> Dynamic, constructible:Bool):JsObject {
		final f = obj();
		f.invoke = body;
		f.constructible = constructible;
		if (constructible) {
			final p = obj();
			p.define("constructor", f);
			f.define("prototype", p);
		}
		return f;
	}

	public static function at(args:Array<Dynamic>, i:Int):Dynamic
		return i < args.length ? args[i] : u;

	public static function call(f:Dynamic, receiver:Dynamic, args:Array<Dynamic>, site:String = "runtime"):Dynamic {
		if (!Std.isOfType(f, JsObject) || (cast f : JsObject).invoke == null)
			throw site + " TypeError: value is not callable";
		return (cast f : JsObject).invoke(receiver, args);
	}

	public static function construct(f:Dynamic, args:Array<Dynamic>, site:String = "runtime"):Dynamic {
		if (!Std.isOfType(f, JsObject) || !(cast f : JsObject).constructible)
			throw site + " TypeError: value is not a constructor";
		final callee:JsObject = f;
		if (callee.boundTarget != null)
			return construct(callee.boundTarget, callee.boundArgs.concat(args), site);
		final p = get(f, "prototype"), self = new JsObject(Std.isOfType(p, JsObject) ? p : ordinary);
		final result = call(f, self, args);
		return Std.isOfType(result, JsObject) || Std.isOfType(result, Array) ? result : self;
	}

	public static function type(v:Dynamic):String {
		if (v == u)
			return "undefined";
		if (v == null)
			return "object";
		if (Std.isOfType(v, Bool))
			return "boolean";
		if (Std.isOfType(v, String))
			return "string";
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
			return "number";
		return Std.isOfType(v, JsObject) && (cast v : JsObject).invoke != null ? "function" : "object";
	}

	public static function truth(v:Dynamic):Bool {
		return switch type(v) {
			case "undefined": false;
			case "number": v != 0 && !Math.isNaN(v);
			case "boolean": v;
			case "string": (cast v : String).length > 0;
			default: v != null;
		}
	}

	public static function str(v:Dynamic):String {
		if (v == u)
			return "undefined";
		if (v == null)
			return "null";
		if (Std.isOfType(v, Array))
			return [for (x in (cast v : Array<Dynamic>)) (x == null || x == u) ?"":str(x)].join(",");
		if (Std.isOfType(v, JsObject))
			return "[object Object]";
		if (type(v) == "number") {
			final n:Float = v;
			if (Math.isNaN(n))
				return "NaN";
			if (!Math.isFinite(n))
				return n < 0 ? "-Infinity" : "Infinity";
			if (n == 0)
				return "0";
			if (n >= -2147483648.0 && n <= 2147483647 && Math.floor(n) == n)
				return Std.string(Std.int(n));
		}
		return Std.string(v);
	}

	public static function num(v:Dynamic):Float {
		if (Std.isOfType(v, JsDate))
			return (cast v : JsDate).timestamp;
		return switch type(v) {
			case "number": v;
			case "boolean": v ? 1 : 0;
			case "undefined": Math.NaN;
			default:
				if (v == null) 0.
				else {
					final s = StringTools.trim(str(v));
					if (s == "")
						0.
						else if (s == "Infinity" || s == "+Infinity")
							Math.POSITIVE_INFINITY
						else if (s == "-Infinity")
							Math.NEGATIVE_INFINITY
						else if (!~/^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$/.match(s))
							Math.NaN
						else
							Std.parseFloat(s);
				}
		}
	}

	public static function add(a:Dynamic, b:Dynamic):Dynamic {
		return type(a) == "string"
			|| type(b) == "string"
			|| (a != null && type(a) == "object")
			|| (b != null && type(b) == "object") ? (str(a) + str(b) : Dynamic) : (num(a) + num(b) : Dynamic);
	}

	public static function equal(a:Dynamic, b:Dynamic):Bool
		return type(a) == type(b) && a == b;

	public static function loose(a:Dynamic, b:Dynamic):Bool {
		if (type(a) == type(b))
			return equal(a, b);
		if (a == null || a == u || b == null || b == u)
			return (a == null || a == u) && (b == null || b == u);
		if (type(a) == "boolean" || type(b) == "boolean" || type(a) == "number" || type(b) == "number")
			return num(a) == num(b);
		return str(a) == str(b);
	}

	public static function less(a:Dynamic, b:Dynamic):Bool
		return type(a) == "string" && type(b) == "string" ? (cast a : String) < (cast b : String) : num(a) < num(b);

	public static function lessEqual(a:Dynamic, b:Dynamic):Bool
		return type(a) == "string" && type(b) == "string" ? (cast a : String) <= (cast b : String) : num(a) <= num(b);

	static function index(k:String):Int {
		final i = Std.parseInt(k);
		return i != null && i >= 0 && Std.string(i) == k ? i : -1;
	}

	public static function get(receiver:Dynamic, key:Dynamic):Dynamic {
		final k = str(key);
		if (receiver == null || receiver == u)
			throw 'TypeError: cannot read ' + k;
		if (Std.isOfType(receiver, JsObject)) {
			final ob:JsObject = receiver;
			if (Std.isOfType(ob, JsTypedArray) && index(k) >= 0)
				return (cast ob : JsTypedArray).readIndex(index(k));
			if (ob.invoke != null && k == "call")
				return fn((_, a) -> call(ob, at(a, 0), a.slice(1)), false);
			if (ob.invoke != null && k == "bind")
				return fn((_, a) -> {
					final bound = at(a, 0), head = a.slice(1), f = fn((r, args) -> call(ob, bound, head.concat(args)), false);
					f.boundTarget = ob;
					f.boundArgs = head;
					f.constructible = ob.constructible;
					return f;
				}, false);
			if (ob.invoke != null && k == "apply")
				return fn((_, a) -> call(ob, at(a, 0), a.length < 2 || a[1] == null || a[1] == u ? [] : a[1]), false);
			return ob.read(k);
		}
		if (Std.isOfType(receiver, Array)) {
			final a:Array<Dynamic> = receiver, i = index(k);
			if (i >= 0)
				return at(a, i);
			if (k != "length") {
				final props = arrayProperties.get(a);
				if (props != null && JsProperties.own(props, k))
					return props.read(k);
			}
			return switch k {
				case "length": a.length;
				case "push": fn((r, vs) -> {
						final arr:Array<Dynamic> = r;
						for (v in vs)
							arr.push(v);
						return arr.length;
					}, false);
				case "forEach": fn((r, args) -> {
						final arr:Array<Dynamic> = r;
						final length = arr.length;
						for (i in 0...length)
							if (i < arr.length)
								call(at(args, 0), at(args, 1), [arr[i], i, arr]);
						return u;
					}, false);
				case "pop": fn((r, _) -> {
						final arr:Array<Dynamic> = r;
						return arr.length == 0 ? u : arr.pop();
					}, false);
				case "toString": fn((r, _) -> str(r), false);
				case "join": fn((r, v) -> {
						final arr:Array<Dynamic> = r;
						return [for (x in arr) x == u || x == null ? "" : str(x)].join(v.length == 0 ? "," : str(v[0]));
					}, false);
				default:
					final method = JsList.method(k);
					method == u ? ordinary.read(k) : method;
			}
		}
		if (Std.isOfType(receiver, String)) {
			final s:String = receiver, i = index(k);
			if (k == "length")
				return s.length;
			if (i >= 0 && i < s.length)
				return s.charAt(i);
			final member = JsString.member(k);
			return member == u ? ordinary.read(k) : member;
		}
		if (type(receiver) == "number" && k == "toFixed")
			return fn((r, a) -> JsDecimal.fixed(num(r), at(a, 0)), false);
		if (type(receiver) == "number" && k == "toString")
			return fn((r, args) -> {
				if (args.length > 0 && args[0] != u && num(args[0]) != 10) {
					final radix = Std.int(num(args[0])), n = num(r);
					if (radix < 2 || radix > 36)
						throw "RangeError: invalid radix";
					if (!Math.isFinite(n) || n == 0)
						return str(r);
					return JsStandard.radix(n, radix);
				}
				return str(r);
			}, false);
		return ordinary.read(k);
	}

	public static function put(receiver:Dynamic, key:Dynamic, value:Dynamic):Dynamic {
		final k = str(key);
		if (Std.isOfType(receiver, JsObject)) {
			final ob:JsObject = receiver;
			if (Std.isOfType(ob, JsTypedArray) && index(k) >= 0) {
				(cast ob : JsTypedArray).writeIndex(index(k), value);
				return value;
			}
			final owner = JsProperties.lookup(ob, k);
			if (owner != null && owner.descriptors.exists(k)) {
				final d = owner.descriptors.get(k), setter = d.read("set");
				if (setter != u) {
					call(setter, ob, [value]);
					return value;
				}
				if (!truth(d.read("writable")))
					throw "TypeError: read-only property " + k;
				if (owner == ob) {
					d.define("value", value);
					return value;
				}
			}
			if (ob.setters.exists(k)) {
				ob.setters.get(k)(value);
				return value;
			}
			if (ob.getters.exists(k))
				throw "TypeError: read-only property " + k;
			return ob.define(k, value);
		}
		if (Std.isOfType(receiver, Array)) {
			final a:Array<Dynamic> = receiver, i = index(k);
			if (i >= 0) {
				while (a.length < i)
					a.push(u);
				a[i] = value;
				return value;
			}
			if (k == "length") {
				final n = num(value);
				if (n < 0 || n != Std.int(n))
					throw "RangeError: invalid array length";
				if (a.length > n)
					a.resize(Std.int(n));
				else
					while (a.length < n)
						a.push(u);
				return value;
			}
			var props = arrayProperties.get(a);
			if (props == null) {
				props = new JsObject();
				arrayProperties.set(a, props);
			}
			return props.define(k, value);
		}
		throw 'TypeError: cannot write ' + k;
	}

	static function mathObject():JsObject {
		final o = obj();
		o.define("PI", Math.PI);
		for (k => v in [
			"E" => Math.exp(1),
			"LN2" => Math.log(2),
			"LN10" => Math.log(10),
			"LOG2E" => 1 / Math.log(2),
			"LOG10E" => 1 / Math.log(10),
			"SQRT2" => Math.sqrt(2),
			"SQRT1_2" => Math.sqrt(0.5)
		])
			o.define(k, v);
		for (name in [
			"abs", "floor", "ceil", "round", "sqrt", "sin", "cos", "tan", "atan2", "pow", "min", "max", "random", "asin", "acos", "atan", "exp", "log",
			"log2", "log10", "trunc", "sign", "cbrt", "hypot", "imul", "fround"
		]) {
			o.define(name, fn((_, a) -> {
				final x = num(at(a, 0)), y = num(at(a, 1));
				return switch name {
					case "abs": Math.abs(x);
					case "floor": Math.ffloor(x);
					case "ceil": Math.fceil(x);
					case "round": Math.ffloor(x + 0.5);
					case "sqrt": Math.sqrt(x);
					case "sin": Math.sin(x);
					case "cos": Math.cos(x);
					case "tan": Math.tan(x);
					case "atan2": Math.atan2(x, y);
					case "asin": Math.asin(x);
					case "acos": Math.acos(x);
					case "atan": Math.atan(x);
					case "exp": Math.exp(x);
					case "log": Math.log(x);
					case "log2": Math.log(x) / Math.log(2);
					case "log10": Math.log(x) / Math.log(10);
					case "trunc": x < 0 ? Math.fceil(x) : Math.ffloor(x);
					case "sign": Math.isNaN(x) || x == 0 ? x : x < 0 ? -1. : 1.;
					case "cbrt": x < 0 ? -Math.pow(-x, 1 / 3.) : Math.pow(x, 1 / 3.);
					case "fround": haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(x));
					case "imul": WebBits.signed(x) * WebBits.signed(y);
					case "hypot":
						var max = 0.;
						for (v in a)
							max = Math.max(max, Math.abs(num(v)));
						if (max == 0 || !Math.isFinite(max)) max; else {
							var s = 0.;
							for (v in a) {
								final c = num(v) / max;
								s += c * c;
							}
							Math.sqrt(s) * max;
						}
					case "pow": Math.pow(x, y);
					case "random": Math.random();
					default:
						var n = name == "max" ? Math.NEGATIVE_INFINITY : Math.POSITIVE_INFINITY;
						for (v in a)
							n = name == "max" ? Math.max(n, num(v)) : Math.min(n, num(v));
						n;
				};
			}, false));
		}
		return o;
	}

	public static final realm = new JsObject(ordinary);
	static final lexicalSet:Map<String, Dynamic->Void> = [];
	static final lexicals:Map<String, Void->Dynamic> = [];

	public static function linkGlobal(key:String, get:Void->Dynamic, set:Dynamic->Void) {
		boot();
		expose(realm, key, get);
		realm.setters.set(key, set);
	}

	public static function lexical(key:String, get:Void->Dynamic, ?set:Dynamic->Void) {
		lexicals.set(key, get);
		if (set != null)
			lexicalSet.set(key, set);
	}

	public static function assignGlobal(key:String, value:Dynamic, sloppy:Bool):Dynamic {
		boot();
		if (lexicals.exists(key)) {
			if (!lexicalSet.exists(key))
				throw "TypeError: assignment to constant " + key;
			lexicalSet.get(key)(value);
			return value;
		}
		if (!sloppy && !has(realm, key))
			throw "ReferenceError: " + key + " is not defined";
		return put(realm, key, value);
	}

	public static function globalType(key:String):String {
		boot();
		if (lexicals.exists(key))
			return type(lexicals.get(key)());
		return type(realm.read(key));
	}

	public static function global(name:String):Dynamic {
		boot();
		if (lexicals.exists(name))
			return lexicals.get(name)();
		if (has(realm, name))
			return realm.read(name);
		throw 'ReferenceError: ' + name + ' is not defined';
	}

	public static function keys(value:Dynamic):Array<String> {
		if (Std.isOfType(value, Array)) {
			final a:Array<Dynamic> = value, names = [for (i in 0...a.length) Std.string(i)], props = arrayProperties.get(a);
			return props == null ? names : names.concat(props.keys);
		}
		final found:Array<String> = [];
		if (Std.isOfType(value, JsObject)) {
			var ob:JsObject = value;
			while (ob != null) {
				for (k in ob.keys)
					if (!found.contains(k))
						found.push(k);
				ob = ob.prototype;
			}
		}
		return found;
	}

	public static function items(value:Dynamic):Array<Dynamic> {
		if (Std.isOfType(value, JsCollection))
			return (cast value : JsCollection).items();
		if (Std.isOfType(value, JsTypedArray)) {
			final a:JsTypedArray = value;
			return [for (i in 0...a.length) a.readIndex(i)];
		}
		if (Std.isOfType(value, Array))
			return value;
		if (Std.isOfType(value, String))
			return [for (i in 0...(cast value : String).length) (cast value : String).charAt(i)];
		throw "TypeError: value is not iterable";
	}

	public static function has(value:Dynamic, key:Dynamic):Bool {
		final k = str(key);
		if (Std.isOfType(value, JsObject)) {
			var ob:JsObject = value;
			while (ob != null) {
				if (JsProperties.own(ob, k))
					return true;
				ob = ob.prototype;
			}
			return false;
		}
		if (Std.isOfType(value, Array)) {
			final i = index(k);
			final props = arrayProperties.get(cast value);
			return k == "length" || (i >= 0 && i < (cast value:Array<Dynamic>).length) || (props != null && JsProperties.own(props, k));
		}
		throw "TypeError: cannot test " + k + " in " + str(value);
	}

	public static function remove(value:Dynamic, key:Dynamic):Bool {
		if (Std.isOfType(value, Array)) {
			final k = str(key);
			if (k == "length")
				return false;
			if (index(k) < 0) {
				final a:Array<Dynamic> = value, props = arrayProperties.get(a);
				if (props == null)
					return true;
				final removed = remove(props, k);
				if (props.keys.length == 0)
					arrayProperties.remove(a);
				return removed;
			}
		}
		if (!Std.isOfType(value, JsObject))
			throw "TypeError: delete requires an ordinary object";
		final ob:JsObject = value, k = str(key);
		if (ob.descriptors.exists(k) && !truth(ob.descriptors.get(k).read("configurable")))
			return false;
		ob.descriptors.remove(k);
		ob.values.remove(k);
		ob.getters.remove(k);
		ob.keys.remove(k);
		return true;
	}

	public static function instance(value:Dynamic, ctor:Dynamic):Bool {
		if (Std.isOfType(ctor, JsObject) && (cast ctor : JsObject).boundTarget != null)
			return instance(value, (cast ctor : JsObject).boundTarget);
		final p = get(ctor, "prototype");
		if (Std.isOfType(value, Array))
			return p == ordinary || ctor == globals.get("Array");
		if (!Std.isOfType(value, JsObject))
			return false;
		var ob = (cast value : JsObject).prototype;
		while (ob != null) {
			if (ob == p)
				return true;
			ob = ob.prototype;
		}
		return false;
	}

	static function boot():Void {
		if (!ready) {
			ready = true;
			final console = obj();
			for (level in ["log", "info", "debug", "warn", "error"])
				console.define(level, fn((_, a) -> {
					final line = [for (v in a) str(v)].join(" ");
					if (level == "warn" || level == "error")
						WebConsole.error(line);
					else
						WebConsole.log(line);
					return u;
				}, false));
			globals.set("console", console);
			globals.set("Math", mathObject());
			final number = fn((_, a) -> a.length == 0 ? 0. : num(a[0]), false);
			number.define("MAX_VALUE", 1.7976931348623157e308);
			number.define("MIN_VALUE", 4.9406564584124654e-324);
			number.define("MAX_SAFE_INTEGER", 9007199254740991.0);
			number.define("MIN_SAFE_INTEGER", -9007199254740991.0);
			number.define("POSITIVE_INFINITY", Math.POSITIVE_INFINITY);
			number.define("NEGATIVE_INFINITY", Math.NEGATIVE_INFINITY);
			number.define("EPSILON", 2.220446049250313e-16);
			number.define("NaN", Math.NaN);
			number.define("isNaN", fn((_, a) -> type(at(a, 0)) == "number" && Math.isNaN(at(a, 0)), false));
			number.define("isFinite", fn((_, a) -> type(at(a, 0)) == "number" && Math.isFinite(at(a, 0)), false));
			globals.set("Number", number);
			globals.set("String", fn((_, a) -> a.length == 0 ? "" : str(a[0]), false));
			globals.set("parseFloat", fn((_, a) -> Std.parseFloat(str(at(a, 0))), false));
			globals.set("parseInt", fn((_, a) -> {
				final s = StringTools.ltrim(str(at(a, 0))).toLowerCase();
				var base = a.length > 1 ? Std.int(num(a[1])) : 0;
				var i = 0, sign = 1;
				if (s.charAt(0) == "-") {
					sign = -1;
					i++;
				} else if (s.charAt(0) == "+")
					i++;
				if ((base == 0 || base == 16) && s.substr(i, 2) == "0x") {
					i += 2;
					base = 16;
				}
				if (base == 0)
					base = 10;
				if (base < 2 || base > 36)
					return Math.NaN;
				final start = i;
				var value = 0.;
				while (i < s.length) {
					final d = "0123456789abcdefghijklmnopqrstuvwxyz".indexOf(s.charAt(i));
					if (d < 0 || d >= base)
						break;
					value = value * base + d;
					i++;
				}
				return i == start ? Math.NaN : sign * value;
			}, false));
			globals.set("Boolean", fn((_, a) -> truth(at(a, 0)), false));
			final object = fn((_, a) -> a.length > 0 && a[0] != u && a[0] != null ? a[0] : obj(), true);
			object.define("prototype", ordinary);
			// Built-in methods are non-enumerable.
			ordinary.values.set("toString", fn((r, _) -> str(r), false));
			ordinary.values.set("hasOwnProperty", fn((r, a) -> JsStandard.own(r, at(a, 0)), false));
			object.define("create", fn((_, a) -> {
				final p = at(a, 0);
				if (p != null && !Std.isOfType(p, JsObject))
					throw "TypeError: invalid prototype";
				return new JsObject(p);
			}, false));
			object.define("keys", fn((_, a) -> {
				final o:JsObject = a[0];
				return o.keys.copy();
			}, false));
			JsProperties.install(object);
			globals.set("Object", object);
			final array = fn((_, a) -> {
				if (a.length == 1 && type(a[0]) == "number") {
					final xs:Array<Dynamic> = [];
					put(xs, "length", a[0]);
					return xs;
				}
				return a.copy();
			}, true);
			final ap:JsObject = array.read("prototype");
			for (k in [
				"slice",
				"splice",
				"sort",
				"concat",
				"indexOf",
				"map",
				"filter",
				"includes",
				"forEach",
				"push",
				"pop",
				"join",
				"shift",
				"unshift",
				"reverse"
			])
				ap.values.set(k, get(([] : Array<Dynamic>), k));
			array.define("isArray", fn((_, a) -> Std.isOfType(at(a, 0), Array), false));
			globals.set("Array", array);
			for (k in ["Error", "TypeError", "RangeError", "ReferenceError"])
				globals.set(k, fn((r, a) -> {
					final e = obj();
					e.define("name", k);
					e.define("message", a.length == 0 ? "" : str(a[0]));
					return e;
				}, true));
			globals.set("globalThis", realm);
			globals.set("undefined", u);
			globals.set("NaN", Math.NaN);
			globals.set("Infinity", Math.POSITIVE_INFINITY);
			JsTypedArray.install(realm);
			JsDate.install(realm);
			JsCollection.install(realm);
			for (k in globals.keys())
				realm.define(k, globals.get(k));
			JsStandard.install(realm, object, array, number, globals.get("String"));
		}
	}

	public static function json(s:String):Dynamic
		return fromJson(haxe.Json.parse(s));

	static function fromJson(v:Dynamic):Dynamic {
		if (v == null || Std.isOfType(v, String) || Std.isOfType(v, Bool) || Std.isOfType(v, Float))
			return v;
		if (Std.isOfType(v, Array))
			return [for (x in (cast v : Array<Dynamic>)) fromJson(x)];
		final o = obj();
		for (k in Reflect.fields(v))
			o.define(k, fromJson(Reflect.field(v, k)));
		return o;
	}
}
