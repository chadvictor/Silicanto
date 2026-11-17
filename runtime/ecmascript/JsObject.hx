/** Ordinary JS objects use string keys and a prototype independently of Haxe reflection. */
class JsObject {
	public var prototype:JsObject;
	public final values:Map<String, Dynamic> = [];
	public final descriptors:Map<String, JsObject> = [];
	public final setters:Map<String, Dynamic->Void> = [];
	public final getters:Map<String, Void->Dynamic> = [];
	public final keys:Array<String> = [];
	public var invoke:(Dynamic, Array<Dynamic>) -> Dynamic;
	public var constructible = false;
	public var boundTarget:JsObject;
	public var boundArgs:Array<Dynamic>;

	public function new(?prototype:JsObject) {
		this.prototype = prototype;
	}

	public function toString():String {
		if (values.exists("name") && values.exists("message"))
			return Js.str(values.get("name")) + ": " + Js.str(values.get("message"));
		return "[object Object]";
	}

	public function define(key:String, value:Dynamic):Dynamic {
		if (!values.exists(key) && !getters.exists(key))
			keys.push(key);
		values.set(key, value);
		return value;
	}

	public function read(key:String, ?receiver:JsObject):Dynamic {
		if (receiver == null)
			receiver = this;
		if (descriptors.exists(key)) {
			final d = descriptors.get(key);
			if (d.values.exists("value"))
				return d.values.get("value");
			final get = d.read("get");
			return get == Js.u ? Js.u : Js.call(get, receiver, []);
		}
		if (getters.exists(key))
			return getters.get(key)();
		if (values.exists(key))
			return values.get(key);
		return prototype == null ? Js.u : prototype.read(key, receiver);
	}
}
