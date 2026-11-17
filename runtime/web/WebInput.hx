class WebInput {
	static var focus:JsObject;
	static var pressed:JsObject;
	static var previous:JsObject;
	static var capture:JsObject;

	public static function attach(o:JsObject) {
		o.define("focus", Js.fn((_, _) -> {
			select(o);
			return Js.u;
		}, false));
		o.define("blur", Js.fn((_, _) -> {
			if (focus == o)
				select(null);
			return Js.u;
		}, false));
		o.define("setPointerCapture", Js.fn((_, a) -> {
			if (pressed != null && Js.num(Js.at(a, 0)) == 1)
				capture = o;
			return Js.u;
		}, false));
		o.define("releasePointerCapture", Js.fn((_, _) -> {
			if (capture == o)
				capture = null;
			return Js.u;
		}, false));
		o.define("hasPointerCapture", Js.fn((_, _) -> capture == o, false));
	}

	static function send(o:JsObject, e:JsObject):Bool
		return Js.truth(Js.call(o.read("dispatchEvent"), o, [e]));

	static function select(o:JsObject) {
		if (o == focus)
			return;
		final old = focus;
		focus = o;
		if (old != null) {
			send(old, WebEvents.make("blur", "FocusEvent"));
			send(old, WebEvents.make("focusout", "FocusEvent", true));
		}
		if (o != null) {
			send(o, WebEvents.make("focus", "FocusEvent"));
			send(o, WebEvents.make("focusin", "FocusEvent", true));
		}
	}

	public static function setup(dom:JsObject, body:JsObject)
		dom.getters.set("activeElement", () -> focus == null ? body : focus);

	public static function dispatch(data:Dynamic, canvas:WebCanvas, dom:JsObject) {
		final type:String = data.type;
		if (type == "resize") {
			WebLayout.width = Std.int(Math.max(1, data.width));
			WebLayout.height = Std.int(Math.max(1, data.height));
			Js.realm.define("innerWidth", WebLayout.width);
			Js.realm.define("innerHeight", WebLayout.height);
			send(Js.realm, WebEvents.make("resize"));
			return;
		}
		final keyboard = type == "keydown" || type == "keyup", wheel = type == "wheel";
		final body:JsObject = dom.read("body");
		var target:JsObject = keyboard ? (focus == null ? body : focus) : (capture != null ? capture : WebLayout.styled ? WebLayout.hit(data.x,
			data.y) : cast canvas);
		if (target == null)
			target = body;
		function event(name:String, kind:String, bubbles = true) {
			final e = WebEvents.make(name, kind, bubbles, true);
			for (k in Reflect.fields(data))
				if (k != "type")
					e.define(k, Reflect.field(data, k));
			if (!keyboard) {
				for (k in ["clientX", "pageX"])
					e.define(k, data.x);
				for (k in ["clientY", "pageY"])
					e.define(k, data.y);
				e.define("pointerType", "mouse");
				e.define("pointerId", 1);
				e.define("isPrimary", true);
				final b = WebLayout.styled ? WebLayout.bounds(target) : null;
				e.define("offsetX", data.x - (b == null ? 0. : Js.num(b.read("x"))));
				e.define("offsetY", data.y - (b == null ? 0. : Js.num(b.read("y"))));
			} else {
				e.define("which", data.keyCode);
				e.define("charCode", 0);
			}
			e.define("timeStamp", WebPlatform.now());
			return e;
		}
		if (keyboard || wheel) {
			send(target, event(type, keyboard ? "KeyboardEvent" : "WheelEvent"));
			return;
		}
		if (previous != target) {
			if (previous != null) {
				send(previous, event("pointerout", "PointerEvent"));
				send(previous, event("mouseout", "MouseEvent"));
			}
			send(target, event("pointerover", "PointerEvent"));
			send(target, event("mouseover", "MouseEvent"));
			previous = target;
		}
		if (type == "pointerdown")
			pressed = target;
		final ok = send(target, event(type, "PointerEvent"));
		if (ok) {
			send(target, event(StringTools.replace(type, "pointer", "mouse"), "MouseEvent"));
			if (type == "pointerdown")
				select(target);
		}
		if (type == "pointerup") {
			if (pressed == target && data.button == 0)
				send(target, event("click", "MouseEvent"));
			pressed = null;
			capture = null;
		}
	}
}
