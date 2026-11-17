/** Promise reactions run at the host's microtask checkpoint. */
class WebPromise extends JsObject {
	static var proto:JsObject;
	static var tasks:Array<Void->Void> = [];

	var state = 0;
	var value:Dynamic;
	var reactions:Array<Void->Void> = [];

	public function new() {
		super(proto);
	}

	public static function checkpoint() {
		while (tasks.length > 0) {
			final batch = tasks;
			tasks = [];
			for (f in batch)
				f();
		}
	}

	public function resolve(v:Dynamic) {
		if (state != 0)
			return;
		if (v == this) {
			reject("TypeError: cyclic promise");
			return;
		}
		if (Std.isOfType(v, JsObject)) {
			var then:Dynamic;
			try {
				then = Js.get(v, "then");
			} catch (e:Dynamic) {
				reject(e);
				return;
			}
			if (Js.type(then) == "function") {
				tasks.push(() -> {
					var called = false;
					try {
						Js.call(then, v, [
							Js.fn((_, a) -> {
								if (!called) {
									called = true;
									resolve(Js.at(a, 0));
								}
								return Js.u;
							}, false),
							Js.fn((_, a) -> {
								if (!called) {
									called = true;
									reject(Js.at(a, 0));
								}
								return Js.u;
							}, false)
						]);
					} catch (e:Dynamic) {
						if (!called)
							reject(e);
					}
				});
				return;
			}
		}
		settle(1, v);
	}

	public function reject(e:Dynamic) {
		if (state == 0)
			settle(2, e);
	}

	function settle(s:Int, v:Dynamic) {
		state = s;
		value = v;
		for (f in reactions)
			tasks.push(f);
		reactions = [];
	}

	function chain(ok:Dynamic, no:Dynamic):WebPromise {
		final next = new WebPromise();
		final react = () -> {
			final f = state == 1 ? ok : no;
			try {
				if (Js.type(f) == "function")
					next.resolve(Js.call(f, Js.u, [value]));
				else if (state == 1)
					next.resolve(value);
				else
					next.reject(value);
			} catch (e:Dynamic) {
				next.reject(e);
			}
		};
		if (state == 0)
			reactions.push(react);
		else
			tasks.push(react);
		return next;
	}

	public static function done(v:Dynamic):WebPromise {
		final p = new WebPromise();
		p.resolve(v);
		return p;
	}

	public static function install() {
		final ctor = Js.fn((_, a) -> {
			final p = new WebPromise();
			var used = false;
			final yes = Js.fn((_, v) -> {
				if (!used) {
					used = true;
					p.resolve(Js.at(v, 0));
				}
				return Js.u;
			}, false), no = Js.fn((_, v) -> {
				if (!used) {
					used = true;
					p.reject(Js.at(v, 0));
				}
				return Js.u;
			}, false);
			try
				Js.call(Js.at(a, 0), Js.u, [yes, no])
			catch (e:Dynamic) {
				if (!used)
					p.reject(e);
			}
			return p;
		}, true);
		proto = ctor.read("prototype");
		proto.values.set("then", Js.fn((r, a) -> (cast r : WebPromise).chain(Js.at(a, 0), Js.at(a, 1)), false));
		proto.values.set("catch", Js.fn((r, a) -> (cast r : WebPromise).chain(Js.u, Js.at(a, 0)), false));
		ctor.define("resolve", Js.fn((_, a) -> done(Js.at(a, 0)), false));
		ctor.define("reject", Js.fn((_, a) -> {
			final p = new WebPromise();
			p.reject(Js.at(a, 0));
			return p;
		}, false));
		Js.realm.define("Promise", ctor);
	}
}
