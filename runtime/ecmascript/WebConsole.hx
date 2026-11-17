class WebConsole {
	public static function error(value:Dynamic):Void {
		#if js
		js.Browser.console.error(value);
		#else
		Sys.stderr().writeString(Std.string(value) + "\n");
		#end
	}

	public static function log(value:Dynamic):Void {
		#if js
		js.Browser.console.log(value);
		#else
		Sys.println(Std.string(value));
		#end
	}
}
