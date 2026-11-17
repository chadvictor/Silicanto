/** ECMAScript methods shared by JavaScript array instances and Array.prototype. */
class JsList {
	static function index(n:Dynamic, len:Int):Int {
		final i = Std.int(Js.num(n));
		return i < 0 ? Std.int(Math.max(0, len + i)) : Std.int(Math.min(len, i));
	}

	public static function method(name:String):Dynamic {
		switch name {
			case "slice", "splice", "shift", "unshift", "indexOf", "lastIndexOf", "includes", "map", "filter", "some", "every", "find", "concat", "reverse",
				"sort", "entries", "fill", "at", "reduce", "reduceRight", "copyWithin", "findIndex":
			default:
				return Js.u;
		}
		return Js.fn(function(r:Dynamic, args:Array<Dynamic>):Dynamic {
			final a:Array<Dynamic> = r;
			final f:Dynamic = Js.at(args, 0), self:Dynamic = Js.at(args, 1);
			final len = a.length;
			switch name {
				case "at":
					var i = Std.int(Js.num(f));
					if (i < 0)
						i += len;
					return i >= 0 && i < len ? a[i] : Js.u;
				case "fill":
					for (i in JsStandard.relative(self, len, 0)...JsStandard.relative(Js.at(args, 2), len, len))
						a[i] = f;
					return a;
				case "copyWithin":
					final dest = JsStandard.relative(f, len, 0), src = JsStandard.relative(self, len, 0), end = JsStandard.relative(Js.at(args, 2), len, len);
					final part = a.slice(src, end);
					for (i in 0...Std.int(Math.min(len - dest, part.length)))
						a[dest + i] = part[i];
					return a;
				case "reduce", "reduceRight":
					final backwards = name == "reduceRight";
					var pos = backwards ? len - 1 : 0,
						delta = backwards ? -1 : 1,
						acc:Dynamic = self;
					if (args.length < 2) {
						if (len == 0)
							throw "TypeError: empty reduce";
						acc = a[pos];
						pos += delta;
					}
					while (pos >= 0 && pos < len) {
						acc = Js.call(f, Js.u, [acc, a[pos], pos, a]);
						pos += delta;
					}
					return acc;
				case "slice":
					return a.slice(index(f, len), self == Js.u ? len : index(self, len));
				case "splice":
					final pos = index(f,
						len), count = args.length == 0 ? 0 : args.length == 1 ? len - pos : Std.int(Math.max(0, Math.min(len - pos, Js.num(self))));
					final removed = a.splice(pos, count);
					for (i in 2...args.length)
						a.insert(pos + i - 2, args[i]);
					return removed;
				case "shift":
					return len == 0 ? Js.u : a.shift();
				case "unshift":
					for (i in 0...args.length)
						a.insert(i, args[i]);
					return a.length;
				case "concat":
					var out = a.copy();
					for (v in args)
						if (Std.isOfType(v, Array))
							out = out.concat(v);
						else
							out.push(v);
					return out;
				case "reverse":
					a.reverse();
					return a;
				case "entries":
					return [for (i in 0...len) ([i, a[i]] : Array<Dynamic>)];
				case "sort":
					haxe.ds.ArraySort.sort(a, (x, y) -> {
						if (x == Js.u)
							return y == Js.u ? 0 : 1;
						if (y == Js.u)
							return -1;
						if (f == Js.u)
							return Reflect.compare(Js.str(x), Js.str(y));
						final d = Js.num(Js.call(f, Js.u, [x, y]));
						return d < 0 ? -1 : d > 0 ? 1 : 0;
					});
					return a;
				case "includes", "indexOf", "lastIndexOf":
					if (name == "lastIndexOf") {
						var i = args.length < 2 ? len - 1 : Std.int(Js.num(self));
						if (i < 0)
							i += len;
						if (i >= len)
							i = len - 1;
						while (i >= 0) {
							if (Js.equal(a[i], f))
								return i;
							i--;
						}
						return -1;
					}
					for (i in index(self, len)...len)
						if (Js.equal(a[i], f)
							|| (name == "includes" && Js.type(a[i]) == "number" && Js.type(f) == "number" && Math.isNaN(f) && Math.isNaN(a[i])))
							return name == "includes" ? (true : Dynamic) : (i : Dynamic);
					return name == "includes" ? (false : Dynamic) : (-1 : Dynamic);
				default:
					final out:Array<Dynamic> = [];
					for (i in 0...len)
						if (i < a.length) {
							final v = a[i], b = Js.call(f, self, [v, i, a]);
							switch name {
								case "map": out.push(b);
								case "filter": if (Js.truth(b)) out.push(v);
								case "some": if (Js.truth(b)) return true;
								case "every": if (!Js.truth(b)) return false;
								case "find": if (Js.truth(b)) return v;
								case "findIndex": if (Js.truth(b)) return i;
							}
						}
					return switch name {
						case "some": false;
						case "every": true;
						case "find": Js.u;
						case "findIndex": -1;
						default: out;
					};
			}
		}, false);
	}
}
