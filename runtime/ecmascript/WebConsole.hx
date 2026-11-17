class WebConsole {
  public static function log(value:Dynamic):Void {
    #if js
    js.Browser.console.log(value);
    #else
    Sys.println(Std.string(value));
    #end
  }
}
