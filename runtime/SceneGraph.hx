import GeometryData;
import ProcJs.ProcFloats;
import Three;

@:keep class PEuler extends PVector3 {
	public var order = "XYZ";
}

@:keep class PGroup {
	public var name = "";
	public final position = new PVector3();
	public final rotation = new PEuler();
	public final scale = new PVector3(1, 1, 1);
	public final children:Array<PGroup> = [];

	var parent:PGroup;

	public function new() {}

	public function add(child:PGroup) {
		var p:PGroup = this;
		while (p != null) {
			if (p == child)
				throw "Cycle in scene graph";
			p = p.parent;
		}
		if (child.parent != null)
			child.parent.children.remove(child);
		children.push(child);
		child.parent = this;
		return this;
	}

	// World matrices are evaluated from the latest graph at render time.
	public function updateMatrixWorld(force:Bool = false):Void {}
}

@:keep class PMeshBasicMaterial {
	public final color:PColor;
	public final emissive:PColor;
	public var roughness:Float;
	public var metalness:Float;
	public var emissiveIntensity:Float;
	public var side:Int;
	public var vertexColors:Bool;
	public var flatShading:Bool;
	public var fog:Bool;

	public function new(?options:Dynamic) {
		if (options == null)
			options = {};
		for (key in Reflect.fields(options))
			if (![
				"color",
				"emissive",
				"roughness",
				"metalness",
				"emissiveIntensity",
				"side",
				"vertexColors",
				"flatShading",
				"fog"
			].contains(key))
				throw "Unsupported material option " + key;
		color = new PColor(options.color);
		emissive = new PColor(options.emissive ?? 0);
		roughness = -1;
		metalness = 0;
		emissiveIntensity = options.emissiveIntensity ?? 1.;
		side = Std.int(options.side ?? 0);
		vertexColors = options.vertexColors ?? false;
		flatShading = options.flatShading ?? false;
		fog = options.fog ?? true;
	}
}

@:keep class PMeshStandardMaterial extends PMeshBasicMaterial {
	public function new(?options:Dynamic) {
		super(options);
		roughness = options == null ? 1 : options.roughness ?? 1.;
		metalness = options == null ? 0 : options.metalness ?? 0.;
	}
}

@:keep class PMesh extends PGroup {
	public final geometry:PBufferGeometry;
	public final material:PMeshBasicMaterial;

	public function new(g:PBufferGeometry, m:PMeshBasicMaterial) {
		super();
		geometry = g;
		material = m;
	}
}

@:keep class PFogExp2 {
	public final color:PColor;
	public var density:Float;

	public function new(hex:Dynamic, density:Float) {
		this.color = new PColor(hex);
		this.density = density;
	}
}

@:keep class PHemisphereLight extends PGroup {
	public final color:PColor;
	public final groundColor:PColor;
	public var intensity:Float;

	public function new(sky:Dynamic, ground:Dynamic, intensity:Float) {
		super();
		color = new PColor(sky);
		groundColor = new PColor(ground);
		this.intensity = intensity;
		position.y = 1;
	}
}

@:keep class PDirectionalLight extends PGroup {
	public final color:PColor;
	public var intensity:Float;

	public function new(hex:Dynamic, intensity:Float) {
		super();
		color = new PColor(hex);
		this.intensity = intensity;
		position.y = 1;
	}
}

@:keep class PDataTexture {
	public final pixels:ProcFloats;
	public final width:Int;
	public final height:Int;
	public var mapping:Int;
	public var minFilter:Int;
	public var magFilter:Int;
	public var colorSpace:String;
	public var needsUpdate:Bool;

	public function new(data:ProcFloats, w:Float, h:Float, format:Int, type:Int) {
		if (format != 1023 || type != 1015)
			throw "Only float RGBA textures are available";
		pixels = data;
		width = Std.int(w);
		height = Std.int(h);
		if (width * height * 4 != data.data.length)
			throw "Texture size mismatch";
	}
}

@:keep class PScene extends PGroup {
	public final surfaceScene:Scene;
	public var background:PColor;
	public var fog:PFogExp2;
	public var environment:PDataTexture;
	public var environmentIntensity = 1.;

	public function new() {
		super();
		surfaceScene = new Scene();
		surfaceScene.procedural = this;
	}
}

@:keep class PWebGLRenderer {
	final antialias:Bool;

	public function new(?options:Dynamic) {
		if (options != null)
			for (k in Reflect.fields(options))
				if (k != "antialias")
					throw "Unsupported renderer option " + k;
		antialias = options != null && options.antialias == true;
	}

	public function setSize(w:Float, h:Float)
		Host.setSize(Std.int(w), Std.int(h));

	public function setAnimationLoop(cb:Float->Void)
		Host.loop = cb;

	public function render(s:PScene, c:PerspectiveCamera)
		Host.draw(s.surfaceScene, c, antialias);
}
