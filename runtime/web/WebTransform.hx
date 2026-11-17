/** Canvas affine transform and inverse mapping from device pixel centers. */
class WebTransform {
	public var a:Float = 1.;
	public var b:Float = 0.;
	public var c:Float = 0.;
	public var d:Float = 1.;
	public var e:Float = 0.;
	public var f:Float = 0.;

	public function new() {}

	public function set(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		this.a = a;
		this.b = b;
		this.c = c;
		this.d = d;
		this.e = e;
		this.f = f;
	}

	public function copy() {
		final t = new WebTransform();
		t.set(a, b, c, d, e, f);
		return t;
	}

	public function mul(aa:Float, bb:Float, cc:Float, dd:Float, ee:Float, ff:Float)
		set(a * aa + c * bb, b * aa + d * bb, a * cc + c * dd, b * cc + d * dd, a * ee + c * ff + e, b * ee + d * ff + f);

	public inline function x(u:Float, v:Float)
		return a * u + c * v + e;

	public inline function y(u:Float, v:Float)
		return b * u + d * v + f;
}
