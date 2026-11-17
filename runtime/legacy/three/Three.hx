package;

class Vec {
  public var x:Float;
  public var y:Float;
  public var z:Float;
  public function set(x:Float,y:Float,z:Float) { this.x=x; this.y=y; this.z=z; }
  public function new(x = 0.0, y = 0.0, z = 0.0) {
    this.x = x; this.y = y; this.z = z;
  }
}

class PerspectiveCamera {
  public final position = new Vec();
  public final right = new Vec(1,0,0);
  public final up = new Vec(0,1,0);
  public final back = new Vec(0,0,1);
  public function lookAt(x:Float,y:Float,z:Float) {
    var dx=position.x-x, dy=position.y-y, dz=position.z-z;
    if (dx==0 && dy==0 && dz==0) dz=1;
    if (dx==0 && dz==0) dz=0.0001;
    final length=Math.sqrt(dx*dx+dy*dy+dz*dz), horizontal=Math.sqrt(dx*dx+dz*dz);
    back.set(dx/length,dy/length,dz/length);
    right.set(dz/horizontal,0,-dx/horizontal);
    up.set(back.y*right.z,back.z*right.x-back.x*right.z,-back.y*right.x);
  }
  public final fov:Float;
  public final aspect:Float;
  public final near:Float;
  public final far:Float;
  public function new(fov:Float, aspect:Float, near:Float, far:Float) {
    this.fov = fov; this.aspect = aspect; this.near = near; this.far = far;
  }
}

class BoxGeometry {
  public final dimensions:Vec;
  public function new(w:Float, h:Float, d:Float) dimensions = new Vec(w,h,d);
}

class MeshBasicMaterial {
  public final color:Int;
  public function new(hex:Float) color = Std.int(hex);
}

class Mesh {
  public final geometry:BoxGeometry;
  public final material:MeshBasicMaterial;
  public final position = new Vec();
  public final rotation = new Vec();
  public final scale = new Vec(1,1,1);
  public function new(geometry:BoxGeometry, material:MeshBasicMaterial) {
    this.geometry = geometry; this.material = material;
  }
}

class Scene {
  #if !js public var procedural:SceneGraph.PScene; #end
  public var assetId(default,null):String;
  public static function fromAsset(id:String):Scene { final s=new Scene(); s.assetId=id; return s; }
  public var mesh(default,null):Mesh;
  public function new() {}
  public function add(child:Mesh) {
    if (mesh != null && mesh != child) throw "E-DEPTH: this backend currently accepts one opaque box per scene";
    mesh = child;
  }
}

class WebGLRenderer {
  final antialias:Bool;
  public function new(antialias:Bool) this.antialias = antialias;
  public function setSize(w:Float, h:Float) Host.setSize(Std.int(w), Std.int(h));
  public function render(scene:Scene, camera:PerspectiveCamera) Host.draw(scene, camera, antialias);
}
