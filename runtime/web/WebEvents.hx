/** DOM event targets without capture through a parent tree. */
class WebEvents {
	final owner:JsObject;
	final handlers:Map<String, Array<Dynamic>> = [];

	public function new(owner:JsObject) {
		this.owner = owner;
		owner.define("addEventListener", Js.fn((_, a) -> {
			final name = Js.str(Js.at(a, 0)), cb = Js.at(a, 1);
			if (!handlers.exists(name))
				handlers.set(name, []);
			if (cb != null && cb != Js.u && !handlers.get(name).contains(cb))
				handlers.get(name).push(cb);
			return Js.u;
		}, false));
		owner.define("removeEventListener", Js.fn((_, a) -> {
			final list = handlers.get(Js.str(Js.at(a, 0)));
			if (list != null)
				list.remove(Js.at(a, 1));
			return Js.u;
		}, false));
		owner.define("dispatchEvent", Js.fn((_, a) -> dispatch(Js.at(a, 0)), false));
	}

	public function dispatch(event:JsObject):Bool {
		final name = Js.str(event.read("type")), list = handlers.get(name);
		event.define("target", owner);
		event.define("currentTarget", owner);
		if (list != null)
			for (cb in list.copy())
				if (list.contains(cb)) {
					if (Js.type(cb) == "function")
						Js.call(cb, owner, [event]);
					else
						Js.call(Js.get(cb, "handleEvent"), cb, [event]);
				}
		final attr = owner.read("on" + name);
		if (attr != Js.u && attr != null)
			Js.call(attr, owner, [event]);
		return !Js.truth(event.read("defaultPrevented"));
	}

	public function fire(name:String) {
		final ev = Js.obj();
		ev.define("type", name);
		dispatch(ev);
	}
}
