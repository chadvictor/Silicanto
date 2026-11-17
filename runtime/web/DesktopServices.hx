#if (java && silicanto_window)
@:native("org.silicanto.canvas.DesktopServices") private extern class JavaServices {
	static function call(input:String):String;
}
#end

#if (cpp && silicanto_webgl)
@:cppFileCode('extern "C" const char *sil_desktop(const char*);')
#end

/** ABI shared by the native macOS library and its JVM bindings. */
class DesktopServices {
	public static function available():Bool
		return WebGLNative.available();

	public static function call(operation:String, args:Array<Dynamic>):Dynamic {
		#if ((cpp && silicanto_webgl) || (java && silicanto_window))
		final request = haxe.Json.stringify([operation, args]);
		#if cpp
		final raw:String = untyped __cpp__("::String(sil_desktop({0}.utf8_str()))", request);
		#else
		final raw = JavaServices.call(request);
		#end
		final reply:Array<Dynamic> = haxe.Json.parse(raw);
		if (reply[0] != true)
			throw "E-DESKTOP: " + operation + ": " + Std.string(reply[1]);
		return reply[1];
		#else
		throw "E-DESKTOP: native service unavailable on this target";
		#end
	}
}
