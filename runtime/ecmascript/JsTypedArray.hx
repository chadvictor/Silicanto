import haxe.io.Bytes;

class JsBuffer extends JsObject {
	public final bytes:Bytes;

	public function new(proto:JsObject, n:Int) {
		super(proto);
		if (n < 0 || n > 268435456)
			throw "RangeError: invalid ArrayBuffer length";
		bytes = Bytes.alloc(n);
		getters.set("byteLength", () -> n);
	}
}

class JsTypedArray extends JsObject {
	public final buffer:JsBuffer;
	public final offset:Int;
	public final length:Int;

	final kind:String;
	final stride:Int;

	static function integer(v:Dynamic):Int {
		final n = Js.num(v);
		if (Math.isNaN(n))
			return 0;
		if (!Math.isFinite(n) || n < 0 || n > 268435456)
			throw "RangeError: invalid length or offset";
		return Std.int(n);
	}

	public function new(proto:JsObject, kind:String, stride:Int, args:Array<Dynamic>) {
		super(proto);
		this.kind = kind;
		this.stride = stride;
		final src:Dynamic = Js.at(args, 0);
		if (Std.isOfType(src, JsBuffer)) {
			buffer = cast src;
			offset = args.length > 1 ? integer(args[1]) : 0;
			final available = buffer.bytes.length - offset;
			if (available < 0 || offset % stride != 0 || ((args.length < 3 || args[2] == Js.u) && available % stride != 0))
				throw "RangeError: misaligned buffer view";
			length = args.length > 2 && args[2] != Js.u ? integer(args[2]) : Std.int(available / stride);
			if (1.0 * length * stride > available)
				throw "RangeError: view exceeds buffer";
		} else {
			final copy = Std.isOfType(src, Array) || Std.isOfType(src, JsObject);
			length = copy ? integer(Js.get(src, "length")) : integer(src);
			offset = 0;
			if (1.0 * length * stride > 268435456)
				throw "RangeError: typed array too large";
			buffer = new JsBuffer(bufferPrototype, length * stride);
			if (copy)
				for (i in 0...length)
					writeIndex(i, Js.get(src, i));
		}
		getters.set("length", () -> length);
		getters.set("byteLength", () -> length * stride);
		getters.set("byteOffset", () -> offset);
		getters.set("buffer", () -> buffer);
	}

	public function readIndex(i:Int):Dynamic {
		if (i < 0 || i >= length)
			return Js.u;
		final p = offset + i * stride, b = buffer.bytes;
		return switch kind {
			case "Float32Array": b.getFloat(p);
			case "Float64Array": b.getDouble(p);
			case "Uint32Array": WebBits.shiftUnsigned(b.getInt32(p), 0);
			case "Int32Array": b.getInt32(p);
			case "Uint16Array": b.getUInt16(p);
			case "Int16Array": (b.getUInt16(p) << 16) >> 16;
			case "Int8Array": (b.get(p) << 24) >> 24;
			default: b.get(p);
		}
	}

	public function writeIndex(i:Int, value:Dynamic):Void {
		if (i < 0 || i >= length)
			return;
		final p = offset + i * stride, b = buffer.bytes, n = Js.num(value);
		switch kind {
			case "Float32Array":
				b.setFloat(p, n);
			case "Float64Array":
				b.setDouble(p, n);
			case "Uint8ClampedArray":
				final floor = Math.floor(n);
				b.set(p, Math.isNaN(n)
					|| n <= 0 ? 0 : n >= 255 ? 255 : n - floor == 0.5 ? (floor % 2 == 0 ? floor : floor + 1) : Math.round(n));
			default:
				final v = WebBits.signed(n);
				switch stride {
					case 1: b.set(p, v);
					case 2: b.setUInt16(p, v);
					default: b.setInt32(p, v);
				}
		}
	}

	static var bufferPrototype:JsObject;

	public static function install(realm:JsObject) {
		final ctor = Js.fn((self, args) -> new JsBuffer((cast self : JsObject).prototype, integer(Js.at(args, 0))), true);
		bufferPrototype = ctor.read("prototype");
		realm.define("ArrayBuffer", ctor);
		for (kind in [
			"Uint8Array",
			"Uint8ClampedArray",
			"Int8Array",
			"Uint16Array",
			"Int16Array",
			"Uint32Array",
			"Int32Array",
			"Float32Array",
			"Float64Array"
		]) {
			final stride = kind.indexOf("64") >= 0 ? 8 : kind.indexOf("32") >= 0 ? 4 : kind.indexOf("16") >= 0 ? 2 : 1;
			final c = Js.fn((self, args) -> new JsTypedArray((cast self : JsObject).prototype, kind, stride, args), true);
			final proto:JsObject = c.read("prototype");
			proto.define("BYTES_PER_ELEMENT", stride);
			c.define("BYTES_PER_ELEMENT", stride);
			proto.define("set", Js.fn((self, a) -> {
				final dst:JsTypedArray = self, src:Dynamic = Js.at(a, 0), pos = integer(Js.at(a, 1)), n = integer(Js.get(src, "length"));
				if (pos + n > dst.length)
					throw "RangeError: typed array set exceeds its view";
				final snapshot = [for (i in 0...n) Js.get(src, i)];
				for (i in 0...n)
					dst.writeIndex(pos + i, snapshot[i]);
				return Js.u;
			}, false));
			realm.define(kind, c);
		}
	}
}
