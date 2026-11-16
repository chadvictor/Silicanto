import GeometryData;
import SceneGraph;
import haxe.io.Bytes;

// The affine basis is column-major, like Object3D.matrixWorld. Transform normals
// with the inverse transpose, and reverse winding under a negative determinant.
private class Basis {
	public final x:PVector3;
	public final y:PVector3;
	public final z:PVector3;
	public final t:PVector3;

	public function new(x:PVector3, y:PVector3, z:PVector3, t:PVector3) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.t = t;
	}

	public static function identity()
		return new Basis(new PVector3(1, 0, 0), new PVector3(0, 1, 0), new PVector3(0, 0, 1), new PVector3());

	public inline function apply(v:PVector3, w:Float, out:PVector3):PVector3
		return out.set(x.x * v.x
			+ y.x * v.y
			+ z.x * v.z
			+ t.x * w, x.y * v.x
			+ y.y * v.y
			+ z.y * v.z
			+ t.y * w, x.z * v.x
			+ y.z * v.y
			+ z.z * v.z
			+ t.z * w);

	public function child(n:PGroup) {
		final l = identity();
		for (i in 0...3) {
			final axis = n.rotation.order.charAt(i);
			final u = axis == "X" ? l.y : axis == "Y" ? l.z : l.x, v = axis == "X" ? l.z : axis == "Y" ? l.x : l.y;
			final a = axis == "X" ? n.rotation.x : axis == "Y" ? n.rotation.y : n.rotation.z, c = Math.cos(a), s = Math.sin(a);
			final old = u.clone();
			u.multiplyScalar(c).addScaledVector(v, s);
			v.multiplyScalar(c).addScaledVector(old, -s);
		}
		return new Basis(apply(l.x.multiplyScalar(n.scale.x), 0, l.x), apply(l.y.multiplyScalar(n.scale.y), 0, l.y),
			apply(l.z.multiplyScalar(n.scale.z), 0, l.z), apply(n.position, 1, l.t));
	}
}

class SceneUpload {
	public final vertices:Bytes;
	public final lighting:Bytes;
	public final probe:Bytes;
	public final count:Int;
	public final background:Array<Float>;

	public function new(scene:PScene) {
		final meshes:Array<{mesh:PMesh, basis:Basis}> = [];
		final env = scene.environment, fog = scene.fog, bg = scene.background ?? new PColor(0);
		background = [PColor.srgb(bg.r), PColor.srgb(bg.g), PColor.srgb(bg.b)];
		final uniforms = [for (_ in 0...52) 0.];
		if (fog != null) {
			uniforms[0] = PColor.srgb(fog.color.r);
			uniforms[1] = PColor.srgb(fog.color.g);
			uniforms[2] = PColor.srgb(fog.color.b);
			uniforms[3] = fog.density;
		}
		var lightCount = 0, hemi = false, size = 0;
		function direction(ix:Int, b:Basis) {
			final v = b.t.clone().normalize();
			uniforms[ix] = v.x;
			uniforms[ix + 1] = v.y;
			uniforms[ix + 2] = v.z;
		}
		function rgb(ix:Int, c:PColor, intensity:Float) {
			uniforms[ix] = c.r * intensity;
			uniforms[ix + 1] = c.g * intensity;
			uniforms[ix + 2] = c.b * intensity;
		}
		function walk(n:PGroup, parent:Basis) {
			final b = parent.child(n);
			if (Std.isOfType(n, PMesh)) {
				final m:PMesh = cast n;
				meshes.push({mesh: m, basis: b});
				final g = m.geometry;
				size += g.indices == null ? g.attributes.position.count : g.indices.length;
			} else if (Std.isOfType(n, PDirectionalLight)) {
				if (lightCount == 4)
					throw "Metal supports four directional lights";
				final l:PDirectionalLight = cast n, ix = 16 + 8 * lightCount++;
				direction(ix, b);
				rgb(ix + 4, l.color, l.intensity);
			} else if (Std.isOfType(n, PHemisphereLight)) {
				if (hemi)
					throw "Metal supports one hemisphere light";
				hemi = true;
				final l:PHemisphereLight = cast n;
				direction(4, b);
				rgb(8, l.color, l.intensity);
				rgb(12, l.groundColor, l.intensity);
			}
			for (c in n.children)
				walk(c, b);
		}
		walk(scene, Basis.identity());
		count = size;
		vertices = Bytes.alloc(count * 64);
		var offset = 0;
		for (entry in meshes)
			offset = writeMesh(vertices, offset, entry.mesh, entry.basis);
		if (env != null) {
			final face = env.height / 4, mip = Math.log(face) / Math.log(2);
			if (env.mapping != 306 || env.width != 3 * Math.max(face, 112) || Math.abs(mip - Math.round(mip)) > 1e-7)
				throw "Expected a float cube-UV environment";
			uniforms[48] = env.width;
			uniforms[49] = env.height;
			uniforms[50] = mip;
			uniforms[51] = scene.environmentIntensity;
			probe = Bytes.alloc(env.pixels.data.length * 4);
			for (i in 0...env.pixels.data.length)
				probe.setFloat(i * 4, env.pixels.data[i]);
		} else
			probe = Bytes.alloc(16);
		lighting = Bytes.alloc(52 * 4);
		for (i in 0...52)
			lighting.setFloat(i * 4, uniforms[i]);
	}

	static function writeMesh(data:Bytes, offset:Int, mesh:PMesh, b:Basis):Int {
		final g = mesh.geometry, m = mesh.material, p = g.attributes.position, n = g.attributes.normal, c = g.attributes.color;
		if (p == null || (m.roughness >= 0 && n == null) || (m.vertexColors && c == null))
			throw "Missing mesh attribute";
		final length = g.indices == null ? p.count : g.indices.length;
		if (length % 3 != 0)
			throw "Invalid triangle count";
		final nx = new PVector3().crossVectors(b.y, b.z), ny = new PVector3().crossVectors(b.z, b.x), nz = new PVector3().crossVectors(b.x, b.y);
		final reverse = b.x.dot(nx) < 0, sign = reverse ? -1. : 1.;
		final normalBasis = new Basis(nx, ny, nz, new PVector3()), a = new PVector3(), edge = new PVector3(), normal = new PVector3();
		final points = [new PVector3(), new PVector3(), new PVector3()], ids = [0, 0, 0];
		var k = 0;
		while (k < length) {
			for (j in 0...3) {
				final ix = k + (reverse && j != 0 ? 3 - j : j), i = g.indices == null ? ix : g.indices[ix];
				ids[j] = i;
				if (i < 0 || i >= p.count)
					throw "Position index outside geometry";
				b.apply(a.fromBufferAttribute(p, i), 1, points[j]);
			}
			if (m.flatShading)
				normal.crossVectors(a.copy(points[1]).sub(points[0]), edge.copy(points[2]).sub(points[0])).normalize();
			for (j in 0...3) {
				final i = ids[j], v = points[j];
				if (!m.flatShading && n != null)
					normalBasis.apply(a.fromBufferAttribute(n, i), 0, normal).normalize().multiplyScalar(sign);
				data.setFloat(offset, v.x);
				data.setFloat(offset + 4, v.y);
				data.setFloat(offset + 8, v.z);
				data.setFloat(offset + 12, m.roughness);
				data.setFloat(offset + 16, normal.x);
				data.setFloat(offset + 20, normal.y);
				data.setFloat(offset + 24, normal.z);
				data.setFloat(offset + 28, m.metalness);
				data.setFloat(offset + 32, m.color.r * (m.vertexColors ? c.getX(i) : 1.));
				data.setFloat(offset + 36, m.color.g * (m.vertexColors ? c.getY(i) : 1.));
				data.setFloat(offset + 40, m.color.b * (m.vertexColors ? c.getZ(i) : 1.));
				data.setFloat(offset + 44, m.side);
				data.setFloat(offset + 48, m.emissive.r * m.emissiveIntensity);
				data.setFloat(offset + 52, m.emissive.g * m.emissiveIntensity);
				data.setFloat(offset + 56, m.emissive.b * m.emissiveIntensity);
				data.setFloat(offset + 60, m.fog ? 1 : 0);
				offset += 64;
			}
			k += 3;
		}
		return offset;
	}
}

// Keep buffers across camera frames. A changed mesh, light, texture or transform
// causes the next draw to upload the scene again.
class SceneSignature {
	final previous:Array<Dynamic> = [];
	var cursor:Int;
	var different:Bool;

	public function new() {}

	function record(value:Dynamic) {
		if (cursor >= previous.length || previous[cursor] != value) {
			previous[cursor] = value;
			different = true;
		}
		cursor++;
	}

	function color(c:PColor) {
		record(c);
		if (c != null) {
			record(c.r);
			record(c.g);
			record(c.b);
		}
	}

	function vector(v:PVector3) {
		record(v.x);
		record(v.y);
		record(v.z);
	}

	function node(n:PGroup) {
		record(n);
		vector(n.position);
		vector(n.scale);
		vector(n.rotation);
		record(n.rotation.order);
		if (Std.isOfType(n, PMesh)) {
			final m:PMesh = cast n, g = m.geometry, mat = m.material;
			record(g.version);
			for (a in [g.attributes.position, g.attributes.normal, g.attributes.color]) {
				record(a);
				if (a != null)
					record(a.version);
			}
			color(mat.color);
			color(mat.emissive);
			record(mat.vertexColors);
			record(mat.roughness);
			record(mat.metalness);
			record(mat.emissiveIntensity);
			record(mat.fog);
			record(mat.flatShading);
			record(mat.side);
		} else if (Std.isOfType(n, PDirectionalLight)) {
			final l:PDirectionalLight = cast n;
			color(l.color);
			record(l.intensity);
		} else if (Std.isOfType(n, PHemisphereLight)) {
			final l:PHemisphereLight = cast n;
			color(l.color);
			color(l.groundColor);
			record(l.intensity);
		}
		record(n.children.length);
		for (child in n.children)
			node(child);
	}

	public function changed(scene:PScene):Bool {
		cursor = 0;
		different = false;
		record(scene.name);
		color(scene.background);
		record(scene.fog);
		if (scene.fog != null) {
			color(scene.fog.color);
			record(scene.fog.density);
		}
		final env = scene.environment;
		record(env);
		if (env != null) {
			record(env.pixels.version);
			record(env.mapping);
		}
		record(scene.environmentIntensity);
		node(scene);
		if (previous.length != cursor) {
			different = true;
			previous.resize(cursor);
		}
		return different;
	}
}
