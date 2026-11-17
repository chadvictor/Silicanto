private typedef Listener = {cb:Dynamic, capture:Bool, once:Bool, passive:Bool};

private class DispatchEvent extends JsObject {
	public final target:WebEvents;

	public function new(t:WebEvents) {
		super(Js.obj().prototype);
		target = t;
		invoke = (_, a) -> t.dispatch(Js.at(a, 0));
	}
}

class WebEvents {
	final owner:JsObject;
	final handlers:Map<String, Array<Listener>> = [];

	static final types:Map<String, JsObject> = [];

	public function new(owner:JsObject) {
		this.owner = owner;
		for (add in [true, false])
			owner.define(add ? "addEventListener" : "removeEventListener", Js.fn((_, a) -> {
				final name = Js.str(Js.at(a, 0)), cb:Dynamic = Js.at(a, 1), opt:Dynamic = Js.at(a, 2);
				final flag = k -> Std.isOfType(opt, JsObject) && opt != Js.u && Js.truth(Js.get(opt, k));
				final capture = Js.equal(opt, true) || flag("capture");
				if (cb == null || cb == Js.u)
					return Js.u;
				var list = handlers.get(name);
				if (list == null) {
					if (!add)
						return Js.u;
					list = [];
					handlers.set(name, list);
				}
				for (v in list)
					if (v.cb == cb && v.capture == capture) {
						if (!add)
							list.remove(v);
						return Js.u;
					}
				if (add)
					list.push({
						cb: cb,
						capture: capture,
						once: flag("once"),
						passive: flag("passive")
					});
				return Js.u;
			}, false));
		owner.define("dispatchEvent", new DispatchEvent(this));
	}

	public static function install() {
		for (kind in [
			"Event",
			"CustomEvent",
			"MouseEvent",
			"PointerEvent",
			"KeyboardEvent",
			"WheelEvent",
			"FocusEvent"
		]) {
			final ctor = Js.fn((_, a) -> {
				final e = make(Js.str(Js.at(a, 0)), kind, false, false), init = Js.at(a, 1);
				if (init != null && init != Js.u)
					for (k in JsStandard.keys(init))
						e.define(k, Js.get(init, k));
				return e;
			}, true);
			final proto:JsObject = ctor.read("prototype");
			if (kind != "Event")
				proto.prototype = types.get(kind == "PointerEvent" || kind == "WheelEvent" ? "MouseEvent" : "Event");
			types.set(kind, proto);
			Js.realm.define(kind, ctor);
		}
	}

	public static function make(name:String, kind = "Event", bubbles = false, cancelable = false):JsObject {
		final e = new JsObject(types.get(kind));
		e.define("type", name);
		e.define("bubbles", bubbles);
		e.define("cancelable", cancelable);
		e.define("defaultPrevented", false);
		e.define("target", null);
		e.define("currentTarget", null);
		e.define("eventPhase", 0);
		return e;
	}

	public function dispatch(e:JsObject):Bool {
		final name = Js.str(e.read("type"));
		if (name == "" || Js.truth(e.read("eventPhase")))
			throw "InvalidStateError";
		final path:Array<WebEvents> = [this];
		var node = owner;
		while (true) {
			var parent:Dynamic = node.read("parentNode");
			if (parent == null || parent == Js.u)
				parent = node.read("defaultView");
			if (!Std.isOfType(parent, JsObject) || parent == Js.u)
				break;
			final f = Js.get(parent, "dispatchEvent");
			if (!Std.isOfType(f, DispatchEvent))
				break;
			final t = (cast f : DispatchEvent).target;
			if (path.contains(t))
				break;
			path.push(t);
			node = cast parent;
		}
		var stopped = false, immediate = false, passive = false;
		e.define("target", owner);
		e.define("cancelBubble", false);
		e.define("preventDefault", Js.fn((_, _) -> {
			if (!passive && Js.truth(e.read("cancelable")))
				e.define("defaultPrevented", true);
			return Js.u;
		}, false));
		e.define("stopPropagation", Js.fn((_, _) -> {
			stopped = true;
			return Js.u;
		}, false));
		e.define("stopImmediatePropagation", Js.fn((_, _) -> {
			stopped = immediate = true;
			return Js.u;
		}, false));
		e.define("composedPath", Js.fn((_, _) -> [for (t in path) t.owner], false));
		function visit(t:WebEvents, capture:Bool, phase:Int) {
			e.define("currentTarget", t.owner);
			e.define("eventPhase", phase);
			final list = t.handlers.get(name);
			if (list != null)
				for (l in list.copy())
					if (!immediate && l.capture == capture && list.contains(l)) {
						if (l.once)
							list.remove(l);
						passive = l.passive;
						if (Js.type(l.cb) == "function")
							Js.call(l.cb, t.owner, [e]);
						else
							Js.call(Js.get(l.cb, "handleEvent"), l.cb, [e]);
						passive = false;
					}
			final fn = t.owner.read("on" + name);
			if (!capture
				&& !immediate
				&& Js.type(fn) == "function"
				&& Js.equal(Js.call(fn, t.owner, [e]), false)
				&& Js.truth(e.read("cancelable")))
				e.define("defaultPrevented", true);
			if (Js.truth(e.read("cancelBubble")))
				stopped = true;
		}
		try {
			var i = path.length;
			while (--i > 0 && !stopped)
				visit(path[i], true, 1);
			if (!stopped) {
				visit(this, true, 2);
				if (!immediate)
					visit(this, false, 2);
			}
			if (Js.truth(e.read("bubbles")))
				for (i in 1...path.length) {
					if (stopped)
						break;
					visit(path[i], false, 3);
				}
		} catch (err:Dynamic) {
			e.define("currentTarget", null);
			e.define("eventPhase", 0);
			throw err;
		}
		e.define("currentTarget", null);
		e.define("eventPhase", 0);
		return !Js.truth(e.read("defaultPrevented"));
	}

	public function fire(name:String)
		dispatch(make(name));
}
