private typedef WebTimer = {id:Int, due:Float, interval:Float, repeated:Bool, callback:Dynamic, args:Array<Dynamic>};

class WebTimers {
	static var current = 0.;
	static var next = 0;
	static final timers:Map<Int, WebTimer> = [];

	public static function install() {
		for (name in ["setTimeout", "setInterval"]) {
			final repeated = name == "setInterval";
			Js.realm.define(name, Js.fn((_, a) -> {
				final fn = Js.at(a, 0);
				if (Js.type(fn) != "function")
					throw "E-TIMER: a compiled callback is required";
				final n = Js.num(Js.at(a, 1)), delay = Math.isFinite(n) ? Math.max(0, n) : 0., id = ++next;
				timers.set(id, {
					id: id,
					due: current + delay,
					interval: delay,
					repeated: repeated,
					callback: fn,
					args: a.slice(2)
				});
				return id;
			}, false));
		}
		for (name in ["clearTimeout", "clearInterval"])
			Js.realm.define(name, Js.fn((_, a) -> {
				timers.remove(Std.int(Js.num(Js.at(a, 0))));
				return Js.u;
			}, false));
	}

	public static function advance(time:Float) {
		current = time;
		final pending = [for (t in timers) if (t.due <= current) t];
		pending.sort((a, b) -> a.due == b.due ? a.id - b.id : Reflect.compare(a.due, b.due));
		for (t in pending)
			if (timers.exists(t.id)) {
				if (t.repeated)
					t.due = current + t.interval;
				else
					timers.remove(t.id);
				Js.call(t.callback, Js.realm, t.args);
			}
	}
}
