import haxe.io.Float32Array;

// Geometry topology and color-space conventions follow Three.js r180 (MIT).
@:keep class PVector3 {
	public var x:Float;
	public var y:Float;
	public var z:Float;

	public function new(x = 0., y = 0., z = 0.)
		set(x, y, z);

	public function set(x:Float, y:Float, z:Float):PVector3 {
		this.x = x;
		this.y = y;
		this.z = z;
		return this;
	}

	public function copy(v:PVector3)
		return set(v.x, v.y, v.z);

	public function clone()
		return new PVector3(x, y, z);

	public function dot(v:PVector3)
		return x * v.x + y * v.y + z * v.z;

	public function multiplyScalar(k:Float)
		return set(x * k, y * k, z * k);

	public function normalize() {
		final n = Math.sqrt(x * x + y * y + z * z);
		return multiplyScalar(n == 0 ? 1 : 1 / n);
	}

	public function add(v:PVector3)
		return set(x + v.x, y + v.y, z + v.z);

	public function sub(v:PVector3)
		return set(x - v.x, y - v.y, z - v.z);

	public function lerp(v:PVector3, t:Float)
		return set(x + (v.x - x) * t, y + (v.y - y) * t, z + (v.z - z) * t);

	public function addScaledVector(v:PVector3, t:Float)
		return set(x + v.x * t, y + v.y * t, z + v.z * t);

	public function crossVectors(a:PVector3, b:PVector3)
		return set(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	public function fromBufferAttribute(a:PFloat32BufferAttribute, i:Float)
		return set(a.getX(i), a.getY(i), a.getZ(i));
}

@:keep class PColor {
	public var r:Float;
	public var g:Float;
	public var b:Float;

	public function new(?hex:Dynamic) {
		if (hex == null) {
			r = g = b = 1.;
			return;
		}
		if (Std.isOfType(hex, PColor)) {
			final c:PColor = hex;
			r = c.r;
			g = c.g;
			b = c.b;
			return;
		}
		var k:Int;
		if (Std.isOfType(hex, String)) {
			final s:String = hex;
			if (!~/^#[a-fA-F0-9]{6}$/.match(s))
				throw "Expected a #rrggbb color";
			k = Std.parseInt("0x" + s.substr(1));
		} else
			k = Std.int(hex);
		r = linear(((k >> 16) & 255) / 255.);
		g = linear(((k >> 8) & 255) / 255.);
		b = linear((k & 255) / 255.);
	}

	static inline function linear(x:Float)
		return x < 0.04045 ? x * 0.0773993808 : Math.pow(x * 0.9478672986 + 0.0521327014, 2.4);

	public static inline function srgb(x:Float)
		return x < 0.0031308 ? 12.92 * x : 1.055 * Math.pow(x, 1 / 2.4) - 0.055;

	public function clone() {
		final c = new PColor();
		c.r = r;
		c.g = g;
		c.b = b;
		return c;
	}

	public function multiplyScalar(k:Float) {
		r *= k;
		g *= k;
		b *= k;
		return this;
	}

	public function lerp(c:PColor, t:Float) {
		r += (c.r - r) * t;
		g += (c.g - g) * t;
		b += (c.b - b) * t;
		return this;
	}
}

@:keep class PFloat32BufferAttribute {
	public final data:Float32Array;
	public final itemSize:Int;
	public final count:Int;
	public var version = 0;

	public function new(values:Array<Dynamic>, size:Float) {
		itemSize = Std.int(size);
		if (itemSize < 1 || values.length % itemSize != 0)
			throw "Invalid buffer attribute";
		data = new Float32Array(values.length);
		count = Std.int(values.length / itemSize);
		for (i in 0...values.length)
			data[i] = values[i];
	}

	public function getX(i:Float):Float
		return data[Std.int(i) * itemSize];

	public function getY(i:Float):Float
		return data[Std.int(i) * itemSize + 1];

	public function getZ(i:Float):Float
		return data[Std.int(i) * itemSize + 2];

	public function setXYZ(i:Float, x:Float, y:Float, z:Float) {
		final k = Std.int(i) * itemSize;
		data[k] = x;
		data[k + 1] = y;
		data[k + 2] = z;
		version++;
		return this;
	}
}

@:keep class PBufferGeometry {
	public var attributes:{?position:PFloat32BufferAttribute, ?normal:PFloat32BufferAttribute, ?color:PFloat32BufferAttribute} = {};
	public var indices:Array<Int>;
	public var version = 0;

	public function new() {}

	public function setAttribute(key:String, a:PFloat32BufferAttribute) {
		switch (key) {
			case "position":
				attributes.position = a;
			case "normal":
				attributes.normal = a;
			case "color":
				attributes.color = a;
			default:
				throw "Unsupported attribute " + key;
		}
		version++;
		return this;
	}

	public function getAttribute(key:String):PFloat32BufferAttribute
		return switch (key) {
			case "position": attributes.position;
			case "normal": attributes.normal;
			case "color": attributes.color;
			default: null;
		}

	public function setIndex(list:Array<Dynamic>) {
		indices = [for (i in list) Std.int(i)];
		version++;
		return this;
	}

	public function copy(src:PBufferGeometry) {
		for (k in ["position", "normal", "color"]) {
			final a = src.getAttribute(k);
			if (a != null)
				setAttribute(k, new PFloat32BufferAttribute([for (i in 0...a.data.length) a.data[i]], a.itemSize));
		}
		indices = src.indices == null ? null : src.indices.copy();
		version++;
		return this;
	}

	public function computeVertexNormals() {
		final p = attributes.position, raw = new Float32Array(p.count * 3);
		final count = indices == null ? p.count : indices.length;
		var k = 0;
		while (k < count) {
			final a = indices == null ? k : indices[k], b = indices == null ? k + 1 : indices[k + 1], c = indices == null ? k + 2 : indices[k + 2];
			final ux = p.getX(c) - p.getX(b), uy = p.getY(c) - p.getY(b), uz = p.getZ(c) - p.getZ(b);
			final vx = p.getX(a) - p.getX(b), vy = p.getY(a) - p.getY(b), vz = p.getZ(a) - p.getZ(b);
			final x = uy * vz - uz * vy, y = uz * vx - ux * vz, z = ux * vy - uy * vx;
			for (ix in [a, b, c]) {
				final j = ix * 3;
				raw[j] += x;
				raw[j + 1] += y;
				raw[j + 2] += z;
			}
			k += 3;
		}
		final n = new PFloat32BufferAttribute([for (i in 0...raw.length) raw[i]], 3);
		for (i in 0...p.count) {
			final v = new PVector3().fromBufferAttribute(n, i).normalize();
			n.setXYZ(i, v.x, v.y, v.z);
		}
		setAttribute("normal", n);
	}
}

@:keep class PSphereGeometry extends PBufferGeometry {
	public function new(radius:Float, width:Float = 32, height:Float = 16) {
		super();
		final w = Std.int(Math.max(3, Math.floor(width))), h = Std.int(Math.max(2, Math.floor(height)));
		final pts:Array<Dynamic> = [], normals:Array<Dynamic> = [];
		indices = [];
		for (y in 0...h + 1)
			for (x in 0...w + 1) {
				final phi = x / w * Math.PI * 2, theta = y / h * Math.PI, v = new PVector3(-radius * Math.cos(phi) * Math.sin(theta),
					radius * Math.cos(theta), radius * Math.sin(phi) * Math.sin(theta));
				pts.push(v.x);
				pts.push(v.y);
				pts.push(v.z);
				v.normalize();
				normals.push(v.x);
				normals.push(v.y);
				normals.push(v.z);
			}
		for (y in 0...h)
			for (x in 0...w) {
				final b = y * (w + 1) + x, a = b + 1, c = b + w + 1, d = c + 1;
				if (y != 0)
					for (i in [a, b, d])
						indices.push(i);
				if (y != h - 1)
					for (i in [b, c, d])
						indices.push(i);
			}
		setAttribute("position", new PFloat32BufferAttribute(pts, 3));
		setAttribute("normal", new PFloat32BufferAttribute(normals, 3));
	}
}

@:keep class PTorusGeometry extends PBufferGeometry {
	public function new(radius:Float, tube:Float = 0.4, radial:Float = 12, tubular:Float = 48, ?arc:Float) {
		super();
		final r = Std.int(radial), t = Std.int(tubular), sweep = arc == null ? 2 * Math.PI : arc;
		final pts:Array<Dynamic> = [], normals:Array<Dynamic> = [];
		indices = [];
		for (j in 0...r + 1)
			for (i in 0...t + 1) {
				final u = i / t * sweep, v = j / r * Math.PI * 2, cv = Math.cos(v), cu = Math.cos(u), su = Math.sin(u);
				pts.push((radius + tube * cv) * cu);
				pts.push((radius + tube * cv) * su);
				pts.push(tube * Math.sin(v));
				normals.push(cv * cu);
				normals.push(cv * su);
				normals.push(Math.sin(v));
			}
		for (j in 1...r + 1)
			for (i in 1...t + 1) {
				final a = (t + 1) * j + i - 1, b = (t + 1) * (j - 1) + i - 1, c = b + 1, d = a + 1;
				for (k in [a, b, d, b, c, d])
					indices.push(k);
			}
		setAttribute("position", new PFloat32BufferAttribute(pts, 3));
		setAttribute("normal", new PFloat32BufferAttribute(normals, 3));
	}
}

@:keep class POctahedronGeometry extends PBufferGeometry {
	public function new(radius:Float) {
		super();
		final corners = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
		final faces = [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2], pts:Array<Dynamic> = [];
		for (f in 0...8)
			for (j in [1, 2, 0])
				for (v in corners[faces[3 * f + j]])
					pts.push(radius * v);
		setAttribute("position", new PFloat32BufferAttribute(pts, 3));
		computeVertexNormals();
	}
}
