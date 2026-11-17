/** Promise reactions run at the host's microtask checkpoint. */
class JsPromise extends JsObject {
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
		if (Std.isOfType(v, JsPromise) && (cast v : JsPromise) == this) {
			reject(Js.construct(Js.global("TypeError"), ["Cyclic promise"]));
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

	function chain(ok:Dynamic, no:Dynamic):JsPromise {
		final next = new JsPromise();
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

	public static function done(v:Dynamic):JsPromise {
		if (Std.isOfType(v, JsPromise)) return cast v;
		final p = new JsPromise();
		p.resolve(v);
		return p;
	}

	public static function install() {
		final ctor = Js.fn((_, a) -> {
			if (Js.type(Js.at(a, 0)) != "function")
				throw Js.construct(Js.global("TypeError"), ["Promise executor is not callable"]);
			final p = new JsPromise();
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
		proto.values.set("then", Js.fn((r, a) -> (cast r : JsPromise).chain(Js.at(a, 0), Js.at(a, 1)), false));
		proto.values.set("catch", Js.fn((r, a) -> (cast r : JsPromise).chain(Js.u, Js.at(a, 0)), false));
		proto.values.set("finally", Js.fn((r, a) -> {
			final callback = Js.at(a, 0), promise:JsPromise = cast r;
			if (Js.type(callback) != "function") return promise.chain(Js.u, Js.u);
			function finish(value:Dynamic, failed:Bool):Dynamic {
				return done(Js.call(callback, Js.u, [])).chain(Js.fn((_, _) -> {
					if (failed) throw value;
					return value;
				}, false), Js.u);
			}
			return promise.chain(Js.fn((_, v) -> finish(Js.at(v, 0), false), false), Js.fn((_, v) -> finish(Js.at(v, 0), true), false));
		}, false));
		for (name in ["all", "race"]) {
			ctor.define(name, Js.fn((_, a) -> {
				final result = new JsPromise();
				try {
					final values = Js.items(Js.at(a, 0)), resolved:Array<Dynamic> = [];
					var pending = values.length;
					if (name == "all" && pending == 0) result.resolve(resolved);
					final no = Js.fn((_, args) -> { result.reject(Js.at(args, 0)); return Js.u; }, false);
					for (i in 0...values.length)
						done(values[i]).chain(Js.fn((_, args) -> {
							final value = Js.at(args, 0);
							if (name == "race") result.resolve(value);
							else {
								resolved[i] = value;
								if (--pending == 0) result.resolve(resolved);
							}
							return Js.u;
						}, false), no);
				} catch (e:Dynamic) result.reject(e);
				return result;
			}, false));
		}
		ctor.define("resolve", Js.fn((_, a) -> done(Js.at(a, 0)), false));
		ctor.define("reject", Js.fn((_, a) -> {
			final p = new JsPromise();
			p.reject(Js.at(a, 0));
			return p;
		}, false));
		Js.realm.define("Promise", ctor);
	}
}
