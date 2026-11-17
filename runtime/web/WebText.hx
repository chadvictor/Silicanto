import haxe.io.Bytes;

#if (java && silicanto_window)
@:native("org.silicanto.canvas.CanvasText") private extern class JavaText {
	static function render(family:String, size:Float, bold:Bool, italic:Bool, text:String, stroke:Float, raster:Bool):haxe.io.BytesData;
}
#end

#if (cpp && silicanto_window)
@:buildXml('<target id="haxe"><flag value="-framework"/><flag value="CoreText"/></target>')
@:cppFileCode('
extern "C" const unsigned char *sil_canvas_text(const char*,float,bool,bool,const char*,float,bool,int*);
static ::Array<unsigned char> silText(::String family,double size,bool bold,bool italic,::String text,double stroke,bool raster){
    int n=0;auto p=sil_canvas_text(family.utf8_str(),size,bold,italic,text.utf8_str(),stroke,raster,&n);
    auto bytes=::Array_obj<unsigned char>::__new(n);if(n)memcpy(bytes->GetBase(),p,n);return bytes;
}')
#end
class WebText {
	public var font(default, null) = "10px sans-serif";
	public var align = "start";
	public var baseline = "alphabetic";

	var family = "Arial";
	var size = 10.;
	var bold = false;
	var italic = false;

	public function new() {}

	public function copy() {
		final other = new WebText();
		other.setFont(font);
		other.align = align;
		other.baseline = baseline;
		return other;
	}

	public function setFont(css:String) {
		final pattern = ~/^(.*?)\b([0-9.]+)(px|pt|em|rem)(?:\/[^\s]+)?\s+(.+)$/i;
		if (!pattern.match(css))
			return;
		final n = Std.parseFloat(pattern.matched(2)), unit = pattern.matched(3);
		if (!Math.isFinite(n) || n <= 0 || n > 4096)
			return;
		size = n * (unit == "pt" ? 4 / 3. : unit == "px" ? 1. : 16.);
		final pre = pattern.matched(1).toLowerCase(), first = StringTools.trim(pattern.matched(4).split(",")[0]);
		family = StringTools.replace(StringTools.replace(first, "\"", ""), "'", "");
		family = switch family.toLowerCase() {
			case "monospace": "Courier New";
			case "sans-serif": "Arial";
			case "serif": "Times New Roman";
			default: family;
		};
		bold = pre.indexOf("bold") >= 0 || ~/[6-9]00/.match(pre);
		italic = pre.indexOf("italic") >= 0 || pre.indexOf("oblique") >= 0;
		font = css;
	}

	public function glyphs(text:String, width:Float, paint:Bool):Bytes {
		text = ~/[\t\r\n\x0c]/g.replace(text, " ");
		#if (java && silicanto_window)
		return Bytes.ofData(JavaText.render(family, size, bold, italic, text, width, paint));
		#elseif (cpp && silicanto_window)
		final data:haxe.io.BytesData = untyped __cpp__("silText({0},{1},{2},{3},{4},{5},{6})", family, size, bold, italic, text, width, paint);
		if (data.length < 36)
			throw "E-CANVAS: text raster too large";
		return Bytes.ofData(data);
		#else
		throw "E-CANVAS: native fonts unavailable on this target";
		#end
	}

	public function dx(b:Bytes):Float
		return switch align {
			case "right", "end": -b.getFloat(0);
			case "center": -b.getFloat(0) / 2;
			default: 0.;
		};

	public function dy(b:Bytes):Float
		return switch baseline {
			case "top", "hanging": b.getFloat(20);
			case "bottom", "ideographic": -b.getFloat(24);
			case "middle": (b.getFloat(20) - b.getFloat(24)) / 2;
			default: 0.;
		};

	public function measure(text:String):JsObject {
		final b = glyphs(text, 0, false), o = Js.obj();
		o.define("width", b.getFloat(0));
		o.define("actualBoundingBoxLeft", -dx(b) - b.getFloat(4));
		o.define("actualBoundingBoxRight", dx(b) + b.getFloat(12));
		o.define("actualBoundingBoxAscent", -dy(b) - b.getFloat(8));
		o.define("actualBoundingBoxDescent", dy(b) + b.getFloat(16));
		o.define("fontBoundingBoxAscent", b.getFloat(20) - dy(b));
		o.define("fontBoundingBoxDescent", b.getFloat(24) + dy(b));
		return o;
	}
}
