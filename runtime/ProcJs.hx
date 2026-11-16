import haxe.io.Float32Array;

class ProcJs {
	public static function truth(v:Dynamic):Bool {
		if (v == null)
			return false;
		if (Std.isOfType(v, Bool))
			return (v : Bool);
		if (Std.isOfType(v, Float))
			return v != 0 && !Math.isNaN(v);
		if (Std.isOfType(v, String))
			return (v : String).length != 0;
		return true;
	}

	public static function assign(to:Dynamic, from:Dynamic):Void {
		if (from != null)
			for (key in Reflect.fields(from))
				Reflect.setField(to, key, Reflect.field(from, key));
	}

	public static function setVector(v:Dynamic, args:Array<Dynamic>):Dynamic {
		if (args.length != 3)
			throw "Expected three vector components";
		return v.set(args[0], args[1], args[2]);
	}

	public static inline function hypot(x:Float, y:Float):Float {
		final a = Math.max(Math.abs(x), Math.abs(y));
		return a == 0 || !Math.isFinite(a) ? a : a * Math.sqrt((x / a) * (x / a) + (y / a) * (y / a));
	}
}

class ProcFloats {
	public final data:Float32Array;
	public var version(default, null) = 0;

	public function new(length:Float) {
		if (length < 0 || !Math.isFinite(length))
			throw "Invalid Float32Array length";
		data = new Float32Array(Std.int(length));
	}

	public function set(values:Array<Dynamic>, offset:Float = 0):Void {
		final start = Std.int(offset);
		if (start < 0 || start + values.length > data.length)
			throw "Float32Array.set outside array bounds";
		for (i in 0...values.length)
			data[start + i] = values[i];
		version++;
	}
}
