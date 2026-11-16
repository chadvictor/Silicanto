import haxe.macro.Expr;
#if macro
import haxe.macro.Context;
#end

class ProcApi {
	// On the web use the installed Three.js implementation. Native constructors
	// allocate Haxe objects whose geometry is uploaded to Metal on demand.
	public static macro function make(name:String, args:Array<Expr>):Expr {
		if (Context.defined("js")) {
			final lib = macro js.Syntax.code("ThreecBrowserLibrary");
			final ctor = {expr: EField(lib, name), pos: Context.currentPos()};
			if (name == "DataTexture")
				args[0] = macro ${args[0]}.data.getData();
			if (name == "WebGLRenderer")
				args = [macro ProcApi.canvasOptions(${args.length == 0 ? macro null : args[0]})];
			final construct = {expr: ECall(macro js.Syntax.construct, [ctor].concat(args)), pos: Context.currentPos()};
			return macro($construct : Dynamic);
		}
		final modules = [
			"Vector3" => "GeometryData",
			"Color" => "GeometryData",
			"BufferGeometry" => "GeometryData",
			"SphereGeometry" => "GeometryData",
			"TorusGeometry" => "GeometryData",
			"OctahedronGeometry" => "GeometryData",
			"Float32BufferAttribute" => "GeometryData",
			"Scene" => "SceneGraph",
			"FogExp2" => "SceneGraph",
			"Group" => "SceneGraph",
			"Mesh" => "SceneGraph",
			"MeshBasicMaterial" => "SceneGraph",
			"MeshStandardMaterial" => "SceneGraph",
			"DataTexture" => "SceneGraph",
			"HemisphereLight" => "SceneGraph",
			"DirectionalLight" => "SceneGraph",
			"WebGLRenderer" => "SceneGraph",
			"PerspectiveCamera" => "Three"
		];
		return {expr: ENew({pack: [], name: modules[name], sub: name == "PerspectiveCamera" ? name : "P" + name}, args), pos: Context.currentPos()};
	}

	#if js
	public static function canvasOptions(options:Dynamic):Dynamic {
		final copy:Dynamic = {};
		ProcJs.assign(copy, options);
		final canvas = js.Browser.document.querySelector("canvas");
		if (canvas != null && !Reflect.hasField(copy, "canvas"))
			Reflect.setField(copy, "canvas", canvas);
		return copy;
	}
	#end

	#if !macro
	public static function mount(renderer:Dynamic):Void {
		#if js js.Browser.document.body.appendChild(renderer.domElement); #else Host.mount(); #end
	}
	#end
}
