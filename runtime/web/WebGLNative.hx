#if (java && silicanto_window)
@:native("org.silicanto.canvas.NativeWebGL") private extern class JavaGL {
	static function available():Bool;
	static function call(request:String):String;
}
#end

#if (cpp && silicanto_webgl)
@:buildXml('<target id="haxe"><lib name="../platform/webgl/libsilicanto_webgl.dylib"/><flag value="-Wl,-rpath,@executable_path/webgl"/></target>')
@:cppFileCode('extern "C" const char *sil_webgl(const char*);')
#end
class WebGLNative {
	public static function available():Bool {
		#if (java && silicanto_window)
		return JavaGL.available();
		#elseif (cpp && silicanto_webgl)
		return true;
		#else
		return false;
		#end
	}

	public static function call(handle:Int, name:String, args:Array<Dynamic>):Dynamic {
		#if ((cpp && silicanto_webgl) || (java && silicanto_window))
		final request = haxe.Json.stringify(([handle, name, args] : Array<Dynamic>));
		#if cpp
		final result:String = untyped __cpp__("::String(sil_webgl({0}.utf8_str()))", request);
		#else
		final result = JavaGL.call(request);
		#end
		final reply:Array<Dynamic> = Js.json(result);
		if (reply[0] != true)
			throw "E-WEBGL: " + name + ": " + reply[1] + " (" + request.substr(0, 120) + ")";
		return reply[1];
		#else
		throw "E-WEBGL: no graphics driver on this payload";
		#end
	}
}
