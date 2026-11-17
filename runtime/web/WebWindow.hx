import haxe.io.Bytes;

#if (silicanto_window && java)
@:native("org.silicanto.canvas.CanvasWindow") private extern class JavaCanvasWindow {
	static function present(w:Int, h:Int, rgba:haxe.io.BytesData):Bool;
	static function events():String;
	static function close():Void;
}
#end

#if (silicanto_window && cpp)
@:buildXml('<target id="haxe"><lib name="../platform/libcanvas.a"/><flag value="-framework"/><flag value="AppKit"/><flag value="-framework"/><flag value="QuartzCore"/></target>')
@:cppFileCode('extern "C" const char* sil_canvas_events(); extern "C" bool sil_canvas_present(int,int,const unsigned char*); extern "C" void sil_canvas_close();')
#end
class WebWindow {
	public static function present(w:Int, h:Int, rgba:Bytes):Bool {
		#if (silicanto_window && java)
		return JavaCanvasWindow.present(w, h, rgba.getData());
		#elseif (silicanto_window && cpp)
		return untyped __cpp__("sil_canvas_present({0},{1},reinterpret_cast<const unsigned char*>({2}->GetBase()))", w, h, rgba.getData());
		#else
		throw "E-WINDOW: no desktop surface on this payload";
		#end
	}

	public static function events():Array<Dynamic> {
		#if (silicanto_window && java)
		return haxe.Json.parse(JavaCanvasWindow.events());
		#elseif (silicanto_window && cpp)
		final s:String = untyped __cpp__("::String(sil_canvas_events())");
		return haxe.Json.parse(s);
		#else
		return [];
		#end
	}

	public static function close() {
		#if (silicanto_window && java)
		JavaCanvasWindow.close();
		#elseif (silicanto_window && cpp)
		untyped __cpp__("sil_canvas_close()");
		#end
	}
}
