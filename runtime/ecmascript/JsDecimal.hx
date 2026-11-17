/** Number.toFixed rounds the actual IEEE-754 significand before writing decimal digits. */
class JsDecimal {
	public static function fixed(n:Float, count:Dynamic):String {
		final raw = Js.num(count);
		if (raw <= -1 || raw >= 101)
			throw "RangeError: invalid fraction digits";
		final digits = Math.isNaN(raw) || raw < 0 ? 0 : Std.int(raw);
		if (!Math.isFinite(n) || Math.abs(n) >= 1e21)
			return Js.str(n);
		var binary = haxe.io.FPHelper.doubleToI64(Math.abs(n));
		final exponent = (binary.high >>> 20) & 2047, high = (binary.high & 0xfffff) | (exponent == 0 ? 0 : 0x100000);
		final limbs:Array<Int> = [0];
		// Base 10^7 keeps multiply-by-two and carry arithmetic within signed Int.
		function multiply(factor:Int, carry:Int) {
			for (i in 0...limbs.length) {
				final v = limbs[i] * factor + carry;
				limbs[i] = v % 10000000;
				carry = Std.int(v / 10000000);
			}
			if (carry != 0)
				limbs.push(carry);
		}
		for (i in 0...53) {
			final bit = 52 - i;
			multiply(2, bit >= 32 ? (high >>> (bit - 32)) & 1 : (binary.low >>> bit) & 1);
		}
		for (i in 0...digits)
			multiply(5, 0);
		final shift = (exponent == 0 ? -1022 : exponent - 1023) - 52 + digits;
		if (shift >= 0)
			for (i in 0...shift)
				multiply(2, 0);
		else {
			var rounded = 0;
			for (i in 0... - shift) {
				var carry = 0, j = limbs.length;
				while (j > 0) {
					j--;
					final v = carry * 10000000 + limbs[j];
					limbs[j] = Std.int(v / 2);
					carry = v & 1;
				}
				rounded = carry;
				while (limbs.length > 1 && limbs[limbs.length - 1] == 0)
					limbs.pop();
				if (limbs.length == 1 && limbs[0] == 0 && i + 1 < -shift) {
					rounded = 0;
					break;
				}
			}
			if (rounded != 0)
				multiply(1, 1);
		}
		var s = Std.string(limbs.pop());
		while (limbs.length > 0)
			s += StringTools.lpad(Std.string(limbs.pop()), "0", 7);
		if (digits > 0) {
			s = StringTools.lpad(s, "0", digits + 1);
			s = s.substring(0, s.length - digits) + "." + s.substr(s.length - digits);
		}
		return (n < 0 ? "-" : "") + s;
	}
}
