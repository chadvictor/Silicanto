/** Live lexical bindings inherited by native direct eval. */
class JsEvalScope {
	final bindings:Map<String, Void->Dynamic> = [];
	final outer:(String, Bool)->Dynamic;

	public function new(outer:(String, Bool)->Dynamic) {
		this.outer = outer;
	}

	public function add(name:String, getter:Void->Dynamic):Void
		bindings.set(name, getter);

	public function read(name:String, typeOnly:Bool):Dynamic {
		if (!bindings.exists(name)) return outer(name, typeOnly);
		final value = bindings.get(name)();
		return typeOnly ? Js.type(value) : value;
	}
}
