import haxe.io.Float32Array;

/** Numeric typed-array operations shared by all Haxe targets. */
class WebFloat32 {
  final data:Float32Array;
  public var length(get,never):Int;
  inline function get_length():Int return data.length;

  public function new(count:Float) {
    final n = Math.isNaN(count) ? 0.0 : (count < 0 ? Math.fceil(count) : Math.ffloor(count));
    if (!Math.isFinite(n) || n < 0 || n > 536870911) throw "Float32Array length outside supported range";
    data = new Float32Array(Std.int(n));
  }
  public static function fromArray(values:Array<Float>):WebFloat32 {
    final buffer = new WebFloat32(values.length);
    buffer.set(values,0);
    return buffer;
  }
  public function set(values:Array<Float>,offset:Float):Void {
    final start = Math.isNaN(offset) ? 0.0 : (offset < 0 ? Math.fceil(offset) : Math.ffloor(offset));
    if (start < 0 || start + values.length > length) throw "Float32Array.set outside array bounds";
    for (i in 0...values.length) data[Std.int(start)+i] = values[i];
  }
  function inBounds(i:Float):Bool return i >= 0 && i < length && i == Math.ffloor(i);
  public function read(i:Float):Float {
    if (!inBounds(i)) throw "E-JS-UNDEFINED: out-of-bounds typed-array read requires an undefined value";
    return data[Std.int(i)];
  }
  public function write(i:Float,v:Float):Float {
    if (inBounds(i)) data[Std.int(i)] = v;
    return v;
  }
}
