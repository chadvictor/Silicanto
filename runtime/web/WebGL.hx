import haxe.io.Bytes;
import haxe.crypto.Base64;

private class GLResource extends JsObject {
	public final owner:WebGL;
	public final kind:String;
	public final id:Int;
	public var deleted = false;
	public var program:GLResource;
	public var generation = 0;

	public function new(owner:WebGL, kind:String, id:Int) {
		super(WebGL.resourceTypes.get(kind));
		this.owner = owner;
		this.kind = kind;
		this.id = id;
	}
}

/** WebGL objects belong to one context. EGL and GLES operations live in the target payload. */
class WebGL extends JsObject {
	static var proto:JsObject;
	public static final resourceTypes:Map<String, JsObject> = [];
	static final methods = [
		"activeTexture",
		"attachShader",
		"bindAttribLocation",
		"bindBuffer",
		"bindFramebuffer",
		"bindRenderbuffer",
		"bindTexture",
		"blendColor",
		"blendEquation",
		"blendEquationSeparate",
		"blendFunc",
		"blendFuncSeparate",
		"bufferData",
		"bufferSubData",
		"checkFramebufferStatus",
		"clear",
		"clearColor",
		"clearDepth",
		"clearStencil",
		"colorMask",
		"compileShader",
		"compressedTexImage2D",
		"compressedTexSubImage2D",
		"copyTexImage2D",
		"copyTexSubImage2D",
		"createBuffer",
		"createFramebuffer",
		"createProgram",
		"createRenderbuffer",
		"createShader",
		"createTexture",
		"cullFace",
		"deleteBuffer",
		"deleteFramebuffer",
		"deleteProgram",
		"deleteRenderbuffer",
		"deleteShader",
		"deleteTexture",
		"depthFunc",
		"depthMask",
		"depthRange",
		"detachShader",
		"disable",
		"disableVertexAttribArray",
		"drawArrays",
		"drawElements",
		"enable",
		"enableVertexAttribArray",
		"finish",
		"flush",
		"framebufferRenderbuffer",
		"framebufferTexture2D",
		"frontFace",
		"generateMipmap",
		"getActiveAttrib",
		"getActiveUniform",
		"getAttachedShaders",
		"getAttribLocation",
		"getBufferParameter",
		"getContextAttributes",
		"getError",
		"getExtension",
		"getFramebufferAttachmentParameter",
		"getParameter",
		"getProgramInfoLog",
		"getProgramParameter",
		"getRenderbufferParameter",
		"getShaderInfoLog",
		"getShaderParameter",
		"getShaderPrecisionFormat",
		"getShaderSource",
		"getSupportedExtensions",
		"getTexParameter",
		"getUniform",
		"getUniformLocation",
		"getVertexAttrib",
		"getVertexAttribOffset",
		"hint",
		"isBuffer",
		"isContextLost",
		"isEnabled",
		"isFramebuffer",
		"isProgram",
		"isRenderbuffer",
		"isShader",
		"isTexture",
		"lineWidth",
		"linkProgram",
		"pixelStorei",
		"polygonOffset",
		"readPixels",
		"renderbufferStorage",
		"sampleCoverage",
		"scissor",
		"shaderSource",
		"stencilFunc",
		"stencilFuncSeparate",
		"stencilMask",
		"stencilMaskSeparate",
		"stencilOp",
		"stencilOpSeparate",
		"texImage2D",
		"texParameterf",
		"texParameteri",
		"texSubImage2D",
		"uniform1f",
		"uniform1fv",
		"uniform1i",
		"uniform1iv",
		"uniform2f",
		"uniform2fv",
		"uniform2i",
		"uniform2iv",
		"uniform3f",
		"uniform3fv",
		"uniform3i",
		"uniform3iv",
		"uniform4f",
		"uniform4fv",
		"uniform4i",
		"uniform4iv",
		"uniformMatrix2fv",
		"uniformMatrix3fv",
		"uniformMatrix4fv",
		"useProgram",
		"validateProgram",
		"vertexAttrib1f",
		"vertexAttrib1fv",
		"vertexAttrib2f",
		"vertexAttrib2fv",
		"vertexAttrib3f",
		"vertexAttrib3fv",
		"vertexAttrib4f",
		"vertexAttrib4fv",
		"vertexAttribPointer",
		"viewport",
	];
	static final extensions = [
		"ANGLE_instanced_arrays",
		"OES_vertex_array_object",
		"OES_standard_derivatives",
		"OES_element_index_uint",
		"OES_texture_float",
		"OES_texture_float_linear"
	];

	final objects:Map<String, GLResource> = [];
	final extObjects:Map<String, JsObject> = [];
	final canvas:WebCanvas;
	final driver:Int;
	final attributes:JsObject;
	final premultiplied:Bool;
	var unpackFlip = false;
	var unpackPremultiply = false;
	var colorSpace = 0x9244;
	var pendingError = 0;
	var currentProgram:GLResource;
	var unpackAlignment = 4;

	public static function install() {
		if (!WebGLNative.available())
			return;
		final ctor = Js.fn((_, _) -> {
			throw "TypeError: illegal WebGL constructor";
		}, true);
		proto = ctor.read("prototype");
		Js.realm.define("WebGLRenderingContext", ctor);
		WebGLEnums.install(proto, ctor);
		for (kind in [
			"Buffer",
			"Framebuffer",
			"Program",
			"Renderbuffer",
			"Shader",
			"Texture",
			"UniformLocation",
			"VertexArrayObjectOES"
		]) {
			final type = Js.fn((_, _) -> {
				throw "TypeError: illegal WebGL object constructor";
			}, true);
			resourceTypes.set(kind, type.read("prototype"));
			Js.realm.define("WebGL" + kind, type);
		}
		for (name in methods)
			proto.values.set(name, Js.fn((r, a) -> (cast r : WebGL).invokeMethod(name, a), false));
	}

	public static function create(canvas:WebCanvas, options:Dynamic):WebGL {
		if (proto == null)
			return null;
		final attrs = Js.obj();
		for (k in ["alpha", "depth", "stencil", "premultipliedAlpha", "preserveDrawingBuffer"]) {
			final value = options == null || options == Js.u ? Js.u : Js.get(options, k);
			attrs.define(k, value == Js.u ? ["alpha", "depth", "premultipliedAlpha"].contains(k) : Js.truth(value));
		}
		attrs.define("antialias", false);
		final id:Int = WebGLNative.call(0, "createContext", [
			canvas.width,
			canvas.height,
			attrs.read("alpha"),
			attrs.read("depth"),
			attrs.read("stencil")
		]);
		return id == 0 ? null : new WebGL(canvas, id, attrs);
	}

	function new(canvas:WebCanvas, driver:Int, attrs:JsObject) {
		super(proto);
		this.canvas = canvas;
		this.driver = driver;
		this.attributes = attrs;
		premultiplied = Js.truth(attrs.read("premultipliedAlpha"));
		getters.set("canvas", () -> canvas);
		getters.set("drawingBufferWidth", () -> canvas.width);
		getters.set("drawingBufferHeight", () -> canvas.height);
	}

	public function resize() {
		if (!Js.truth(WebGLNative.call(driver, "resize", [canvas.width, canvas.height])))
			throw "E-WEBGL: drawing buffer resize failed";
	}

	function fail(code:Int):Dynamic {
		if (pendingError == 0)
			pendingError = code;
		return Js.u;
	}

	public function snapshot():Bytes {
		final bits = Base64.decode(WebGLNative.call(driver, "snapshot", []));
		final w = canvas.width, h = canvas.height, rgba = Bytes.alloc(bits.length);
		for (y in 0...h)
			rgba.blit(y * w * 4, bits, (h - y - 1) * w * 4, w * 4);
		final opaque = !Js.truth(attributes.read("alpha"));
		for (i in 0...w * h) {
			final offset = i * 4, a = rgba.get(offset + 3);
			if (opaque)
				rgba.set(offset + 3, 255);
			else if (premultiplied && a > 0 && a < 255)
				for (k in 0...3)
					rgba.set(offset + k, Std.int(Math.min(255, Math.round(rgba.get(offset + k) * 255 / a))));
		}
		return rgba;
	}

	function resource(kind:String, id:Int):GLResource {
		if (id == 0 && kind != "UniformLocation" || id < 0)
			return null;
		final key = kind + ":" + id;
		if (!objects.exists(key))
			objects.set(key, new GLResource(this, kind, id));
		return objects.get(key);
	}

	function extensionList():Array<String> {
		final driverExtensions:Array<Dynamic> = WebGLNative.call(driver, "extensions", []);
		return [for (k in extensions) if (driverExtensions.contains("GL_" + k)) k];
	}

	function extension(name:String):JsObject {
		if (extObjects.exists(name))
			return extObjects.get(name);
		if (!extensionList().contains(name) || !Js.truth(WebGLNative.call(driver, "enableExtension", ["GL_" + name])))
			return null;
		final e = Js.obj();
		final ops = switch name {
			case "ANGLE_instanced_arrays":
				e.define("VERTEX_ATTRIB_ARRAY_DIVISOR_ANGLE", 0x88fe);
				[
					"drawArraysInstancedANGLE",
					"drawElementsInstancedANGLE",
					"vertexAttribDivisorANGLE"
				];
			case "OES_vertex_array_object":
				e.define("VERTEX_ARRAY_BINDING_OES", 0x85b5);
				[
					"createVertexArrayOES",
					"deleteVertexArrayOES",
					"bindVertexArrayOES",
					"isVertexArrayOES"
				];
			case "OES_standard_derivatives":
				e.define("FRAGMENT_SHADER_DERIVATIVE_HINT_OES", 0x8b8b);
				[];
			default: [];
		};
		for (op in ops)
			e.values.set(op, Js.fn((_, args) -> invokeMethod(op, args), false));
		extObjects.set(name, e);
		return e;
	}

	function parameter(key:Int):Dynamic {
		switch key {
			case 0x9240:
				return unpackFlip;
			case 0x9241:
				return unpackPremultiply;
			case 0x9243:
				return colorSpace;
		}
		final value:Dynamic = WebGLNative.call(driver, "getParameter", [key]);
		final kind = switch key {
			case 0x8894, 0x8895: "Buffer";
			case 0x8b8d: "Program";
			case 0x8ca6: "Framebuffer";
			case 0x8ca7: "Renderbuffer";
			case 0x8069, 0x8514: "Texture";
			case 0x85b5: "VertexArrayObjectOES";
			default: null;
		};
		if (kind != null)
			return resource(kind, Std.int(Js.num(value)));
		if (Std.isOfType(value, Array)) {
			final ctor = switch key {
				case 0x0ba2, 0x0c10, 0x0d3a: "Int32Array";
				case 0x846d, 0x846e, 0x0b70, 0x0c22, 0x8005: "Float32Array";
				case 0x86a3: "Uint32Array";
				default: null;
			};
			if (ctor != null)
				return Js.construct(Js.global(ctor), [value]);
		}
		return value;
	}

	static function viewBytes(view:JsTypedArray):Bytes
		return view.buffer.bytes.sub(view.offset, Std.int(Js.num(view.read("byteLength"))));

	function texture(name:String, args:Array<Dynamic>):Dynamic {
		final a = args.copy(), sub = name == "texSubImage2D";
		if (a.length == (sub ? 7 : 6)) {
			final src = a.pop();
			var bytes:Bytes, w:Int, h:Int;
			if (Std.isOfType(src, WebImage)) {
				final img:WebImage = src;
				bytes = img.pixels;
				w = img.width;
				h = img.height;
			} else if (Std.isOfType(src, WebCanvas)) {
				final c:WebCanvas = src;
				bytes = c.surface();
				w = c.width;
				h = c.height;
			} else if (Std.isOfType(src, JsObject) && Std.isOfType(Js.get(src, "data"), JsTypedArray)) {
				bytes = viewBytes(Js.get(src, "data"));
				w = Std.int(Js.num(Js.get(src, "width")));
				h = Std.int(Js.num(Js.get(src, "height")));
			} else
				return fail(0x0501);
			if (bytes == null || w < 0 || h < 0 || 4. * w * h != bytes.length)
				return fail(0x0501);
			final format = Std.int(Js.num(a[sub ? 4 : 3]));
			if ((format != 0x1908 && format != 0x1907) || Js.num(a[sub ? 5 : 4]) != 0x1401)
				return fail(0x0502);
			final channels = format == 0x1907 ? 3 : 4;
			final pitch = Std.int(Math.ceil(w * channels / unpackAlignment)) * unpackAlignment;
			final data = Bytes.alloc(pitch * h);
			for (y in 0...h)
				for (x in 0...w) {
					final srcIndex = ((unpackFlip ? h - 1 - y : y) * w + x) * 4, dstIndex = y * pitch + x * channels, alpha = bytes.get(srcIndex + 3);
					for (k in 0...3)
						data.set(dstIndex + k, unpackPremultiply ? Math.round(bytes.get(srcIndex + k) * alpha / 255) : bytes.get(srcIndex + k));
					if (channels == 4)
						data.set(dstIndex + 3, alpha);
				}
			final extra:Array<Dynamic> = sub ? [w, h] : [w, h, 0];
			final pos = sub ? 4 : 3;
			for (i in 0...extra.length)
				a.insert(pos + i, extra[i]);
			a.push(Base64.encode(data));
		} else if (a.length == 9) {
			if (Std.isOfType(a[8], JsTypedArray))
				a[8] = Base64.encode(viewBytes(a[8]));
			else if (a[8] != null)
				return fail(0x0501);
		} else
			return fail(0x0501);
		return WebGLNative.call(driver, name, a);
	}

	static final parameterObjects:Map<String, Array<String>> = [
		"attachShader" => ["Program", "Shader"],
		"detachShader" => ["Program", "Shader"],
		"bindAttribLocation" => ["Program"],
		"getAttachedShaders" => ["Program"],
		"getProgramInfoLog" => ["Program"],
		"getProgramParameter" => ["Program"],
		"validateProgram" => ["Program"],
		"getActiveUniform" => ["Program"],
		"getActiveAttrib" => ["Program"],
		"getAttribLocation" => ["Program"],
		"getUniformLocation" => ["Program"],
		"getUniform" => ["Program", "UniformLocation"],
		"linkProgram" => ["Program"],
		"useProgram" => ["Program"],
		"compileShader" => ["Shader"],
		"getShaderParameter" => ["Shader"],
		"getShaderSource" => ["Shader"],
		"getShaderInfoLog" => ["Shader"],
		"shaderSource" => ["Shader"],
		"bindBuffer" => ["", "Buffer"],
		"bindTexture" => ["", "Texture"],
		"bindFramebuffer" => ["", "Framebuffer"],
		"bindRenderbuffer" => ["", "Renderbuffer"],
		"framebufferTexture2D" => ["", "", "", "Texture"],
		"framebufferRenderbuffer" => ["", "", "", "Renderbuffer"],
		"bindVertexArrayOES" => ["VertexArrayObjectOES"]
	];

	function validateResources(name:String, args:Array<Dynamic>):Bool {
		var types = parameterObjects.get(name);
		if (StringTools.startsWith(name, "uniform"))
			types = ["UniformLocation"];
		if (StringTools.startsWith(name, "delete"))
			types = [name.substr(6)];
		if (StringTools.startsWith(name, "is") && name != "isEnabled" && name != "isContextLost")
			types = [name.substr(2)];
		if (types == null)
			return true;
		for (i in 0...types.length) {
			var kind = types[i];
			if (kind == "")
				continue;
			if (kind == "VertexArrayOES")
				kind = "VertexArrayObjectOES";
			final value:Dynamic = Js.at(args, i);
			if (value == null || value == Js.u)
				continue;
			if (!Std.isOfType(value, GLResource))
				return false;
			final res:GLResource = value;
			if (res.owner != this || res.kind != kind || res.deleted)
				return false;
			if (kind == "UniformLocation"
				&& (res.program == null
					|| res.generation != res.program.generation
					|| res.program != (name == "getUniform" ? args[0] : currentProgram)))
				return false;
		}
		return true;
	}

	function invokeMethod(name:String, args:Array<Dynamic>):Dynamic {
		if (!validateResources(name, args)) {
			if (StringTools.startsWith(name, "is"))
				return false;
			fail(0x0502);
			return StringTools.startsWith(name, "get") ? null : Js.u;
		}
		switch name {
			case "isContextLost":
				return false;
			case "getContextAttributes":
				final copy = Js.obj();
				JsProperties.copy(copy, attributes);
				return copy;
			case "getSupportedExtensions":
				return extensionList();
			case "getExtension":
				return extension(Js.str(Js.at(args, 0)));
			case "getError" if (pendingError != 0):
				final e = pendingError;
				pendingError = 0;
				return e;
			case "getParameter":
				return parameter(Std.int(Js.num(Js.at(args, 0))));
			case "pixelStorei":
				switch Std.int(Js.num(args[0])) {
					case 0x0cf5:
						final n = Std.int(Js.num(args[1]));
						if ([1, 2, 4, 8].contains(n)) unpackAlignment = n;
					case 0x9240:
						unpackFlip = Js.truth(args[1]);
						return Js.u;
					case 0x9241:
						unpackPremultiply = Js.truth(args[1]);
						return Js.u;
					case 0x9243:
						colorSpace = Std.int(Js.num(args[1]));
						return Js.u;
				}
			case "texImage2D", "texSubImage2D":
				texture(name, args);
				return Js.u;
			case "readPixels":
				final v:Dynamic = Js.at(args, 6);
				if (!Std.isOfType(v, JsTypedArray))
					return fail(0x0502);
				final dst:JsTypedArray = v, n = Std.int(Js.num(dst.read("byteLength"))), a = args.slice(0, 6);
				a.push(n);
				final data:String = WebGLNative.call(driver, name, a);
				if (data == "INVALID_VALUE")
					return fail(0x0501);
				final bytes = Base64.decode(data);
				dst.buffer.bytes.blit(dst.offset, bytes, 0, n);
				return Js.u;
		}
		final a:Array<Dynamic> = [];
		for (v in args) {
			if (Std.isOfType(v, GLResource)) {
				final obj:GLResource = v;
				if (obj.owner != this)
					return fail(0x0502);
				a.push(obj.id);
			} else if (Std.isOfType(v, JsTypedArray)) {
				final view:JsTypedArray = v;
				if (name == "bufferData" || name == "bufferSubData" || StringTools.startsWith(name, "compressedTex"))
					a.push(Base64.encode(viewBytes(view)));
				else
					a.push(Js.items(v));
			} else if (Std.isOfType(v, JsTypedArray.JsBuffer))
				a.push(Base64.encode((cast v : JsTypedArray.JsBuffer).bytes));
			else if (v == Js.u || v == null)
				a.push(null);
			else if (Std.isOfType(v, JsObject))
				return fail(0x0502);
			else
				a.push(v);
		}
		// WebIDL converts scalar uniform arguments even when the caller passes
		// an array or an object with a numeric string representation.
		if (~/^uniform[1-4][fi]$/.match(name) || ~/^vertexAttrib[1-4]f$/.match(name)) {
			for (i in 1...args.length) {
				final n = Js.num(args[i]);
				a[i] = StringTools.endsWith(name, "i") ? WebBits.signed(n) : n;
			}
		}
		if (StringTools.startsWith(name, "uniform") && Js.at(args, 0) == null)
			return Js.u;
		final result:Dynamic = WebGLNative.call(driver, name, a);
		if (Std.isOfType(result, String) && result == "INVALID_OPERATION")
			return fail(0x0502);
		if (Std.isOfType(result, String) && result == "INVALID_VALUE")
			return fail(0x0501);
		switch name {
			case "getAttachedShaders":
				return [
					for (id in (cast result : Array<Dynamic>))
						resource("Shader", Std.int(Js.num(id)))
				];
			case "getFramebufferAttachmentParameter" if (Std.isOfType(result, Array)):
				final reply:Array<Dynamic> = result;
				return resource(reply[0] == 0x1702 ? "Texture" : "Renderbuffer", Std.int(Js.num(reply[1])));
			case "getVertexAttrib" if (Js.num(args[1]) == 0x889f):
				return resource("Buffer", Std.int(Js.num(result)));
			case "getVertexAttrib" if (Std.isOfType(result, Array)):
				return Js.construct(Js.global("Float32Array"), [result]);
			case "getUniform" if (result != null):
				final reply:Array<Dynamic> = result, values:Array<Dynamic> = reply[1];
				return values.length == 1 ? values[0] : reply[0] == "Array" ? values : Js.construct(Js.global(Js.str(reply[0])), [values]);
		}
		if (StringTools.startsWith(name, "create")) {
			final kind = name == "createVertexArrayOES" ? "VertexArrayObjectOES" : name.substr(6);
			return resource(kind, Std.int(Js.num(result)));
		}
		if (name == "getUniformLocation") {
			final id = Std.int(Js.num(result));
			if (id < 0)
				return null;
			final loc = new GLResource(this, "UniformLocation", id), program:GLResource = args[0];
			loc.program = program;
			loc.generation = program.generation;
			return loc;
		}
		if (name == "linkProgram" && args[0] != null)
			(cast args[0] : GLResource).generation++;
		if (name == "useProgram")
			currentProgram = args[0];
		if (StringTools.startsWith(name, "delete") && args.length > 0 && Std.isOfType(args[0], GLResource)) {
			final obj:GLResource = args[0];
			obj.deleted = true;
			objects.remove(obj.kind + ":" + obj.id);
		}
		return result == null && !StringTools.startsWith(name, "get") ? Js.u : result;
	}
}
