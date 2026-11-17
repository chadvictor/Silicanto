// ECMAScript Number operands can exceed a signed Haxe Int, including the
// result of >>> 0. Narrow only inside a bitwise operation.
class WebBits {
  static inline var MOD = 4294967296.0;
  static function unsigned(x:Float):Float {
    if (!Math.isFinite(x)) return 0.0;
    final n = (x < 0 ? Math.fceil(x) : Math.ffloor(x)) % MOD;
    return n < 0 ? n + MOD : n;
  }
  public static function signed(x:Float):Int {
    final n = unsigned(x);
    return Std.int(n >= 2147483648.0 ? n - MOD : n);
  }
  public static function imul(x:Float,y:Float):Float {
    final a = signed(x), b = signed(y);
    final lowA = a & 65535, lowB = b & 65535;
    final highA = (a >>> 16) & 65535, highB = (b >>> 16) & 65535;
    // Each partial product fits exactly in a binary64 mantissa.
    final cross = (1.0 * lowA * highB + 1.0 * highA * lowB) % 65536.0;
    return signed(1.0 * lowA * lowB + cross * 65536.0);
  }
  public static function shiftUnsigned(x:Float,count:Float):Float {
    return Math.ffloor(unsigned(x) / Math.pow(2, signed(count) & 31));
  }
}
