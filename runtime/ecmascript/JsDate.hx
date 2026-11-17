class JsDate extends JsObject {
	public final timestamp:Float;

	public function new(proto:JsObject, t:Float) {
		super(proto);
		timestamp = t;
	}

	public static function install(realm:JsObject) {
		final date = Js.fn((r, a) -> {
			if (r == Js.u)
				return (Date.now().toString() : Dynamic);
			if (a.length > 1 || (a.length == 1 && Js.type(a[0]) != "number"))
				throw "E-DATE: only numeric millisecond timestamps are supported";
			return (new JsDate((cast r : JsObject).prototype, a.length == 0 ? Date.now().getTime() : Js.num(a[0])) : Dynamic);
		}, true);
		date.define("now", Js.fn((_, a) -> Date.now().getTime(), false));
		final p:JsObject = date.read("prototype");
		for (k in ["getTime", "valueOf"])
			p.values.set(k, Js.fn((r, _) -> (cast r : JsDate).timestamp, false));
		realm.define("Date", date);
	}
}
