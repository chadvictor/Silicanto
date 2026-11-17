/** XML documents returned by DOMParser and local XMLHttpRequest. */
class WebXml extends JsObject {
	final source:Xml;
	final nodes:Array<WebXml> = [];
	final elements:Array<WebXml> = [];

	public function new(source:Xml, parent:WebXml, document:WebXml) {
		super(Js.obj().prototype);
		this.source = source;
		final kind = source.nodeType;
		final name = switch (kind) {
			case Xml.Element: source.nodeName;
			case Xml.Document: "#document";
			case Xml.CData: "#cdata-section";
			case Xml.Comment: "#comment";
			case Xml.ProcessingInstruction, Xml.DocType: source.nodeValue.split(" ")[0];
			default: "#text";
		};
		define("nodeName", name);
		define("nodeType",
			kind == Xml.Element ? 1 : kind == Xml.Document ? 9 : kind == Xml.CData ? 4 : kind == Xml.Comment ? 8 : kind == Xml.ProcessingInstruction ? 7 : kind == Xml.DocType ? 10 : 3);
		define("parentNode", parent);
		define("ownerDocument", document);
		define("nodeValue", kind == Xml.Element || kind == Xml.Document ? null : source.nodeValue);
		if (kind == Xml.Element) {
			define("tagName", name);
			define("localName", name.split(":").pop());
			define("getAttribute", Js.fn((_, args) -> source.get(Js.str(Js.at(args, 0))), false));
			define("hasAttribute", Js.fn((_, args) -> source.exists(Js.str(Js.at(args, 0))), false));
			define("getAttributeNames", Js.fn((_, _) -> [for (k in source.attributes()) k], false));
		}
		if (kind == Xml.Element || kind == Xml.Document) {
			for (child in source) {
				if (child.nodeType == Xml.ProcessingInstruction && child.nodeValue.split(" ")[0] == "xml")
					continue;
				final n = new WebXml(child, this, kind == Xml.Document ? this : document);
				nodes.push(n);
				if (child.nodeType == Xml.Element)
					elements.push(n);
			}
			define("getElementsByTagName", Js.fn((_, args) -> {
				final found:Array<Dynamic> = [];
				descend(Js.str(Js.at(args, 0)), found);
				return found;
			}, false));
		}
		define("childNodes", nodes);
		define("children", elements);
		define("firstChild", nodes.length == 0 ? null : nodes[0]);
		define("lastChild", nodes.length == 0 ? null : nodes[nodes.length - 1]);
		define("firstElementChild", elements.length == 0 ? null : elements[0]);
		define("childElementCount", elements.length);
		if (kind == Xml.Document)
			define("documentElement", elements.length == 0 ? null : elements[0]);
		getters.set("textContent", () -> kind == Xml.Document ? null : text());
	}

	function text():String {
		if (source.nodeType != Xml.Element && source.nodeType != Xml.Document)
			return source.nodeValue;
		final out = new StringBuf();
		for (n in nodes)
			if (n.source.nodeType == Xml.Element || n.source.nodeType == Xml.PCData || n.source.nodeType == Xml.CData)
				out.add(n.text());
		return out.toString();
	}

	function descend(name:String, found:Array<Dynamic>) {
		for (child in elements) {
			if (name == "*" || child.source.nodeName == name)
				found.push(child);
			child.descend(name, found);
		}
	}

	public static function parse(text:String):WebXml {
		try {
			final xml = haxe.xml.Parser.parse(text, true), roots = [for (e in xml.elements()) e];
			if (roots.length != 1)
				throw "XML document needs one root element";
			for (n in xml)
				if (n.nodeType == Xml.PCData && StringTools.trim(n.nodeValue) != "")
					throw "Text outside root element";
			return new WebXml(xml, null, null);
		} catch (error:Dynamic) {
			final doc = Xml.createDocument(), element = Xml.createElement("parsererror");
			element.addChild(Xml.createPCData(Std.string(error)));
			doc.addChild(element);
			return new WebXml(doc, null, null);
		}
	}

	public static function install() {
		final ctor = Js.fn((_, _) -> Js.u, true), p:JsObject = ctor.read("prototype");
		p.values.set("parseFromString", Js.fn((_, args) -> {
			final mime = Js.str(Js.at(args, 1));
			if (!["text/xml", "application/xml", "application/xhtml+xml", "image/svg+xml"].contains(mime))
				throw "E-DOM: unsupported document type " + mime;
			return parse(Js.str(Js.at(args, 0)));
		}, false));
		Js.realm.define("DOMParser", ctor);
	}
}
