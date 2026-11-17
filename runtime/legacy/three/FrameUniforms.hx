import haxe.io.Bytes;
import Three;

class FrameUniforms {
  public static function floats(values:Array<Float>):Bytes {
    final bytes = Bytes.alloc(values.length*4);
    for (i in 0...values.length) bytes.setFloat(i*4,values[i]);
    return bytes;
  }

  public static function camera(camera:PerspectiveCamera):Bytes {
      final f=1/Math.tan(camera.fov*Math.PI/360), z=camera.far/(camera.near-camera.far);
      final p=camera.position, r=camera.right, u=camera.up, b=camera.back;
      return floats([p.x,p.y,p.z,0,r.x,r.y,r.z,0,u.x,u.y,u.z,0,b.x,b.y,b.z,0,f/camera.aspect,f,z,z*camera.near]);
  }
  public static function box(m:Mesh,camera:PerspectiveCamera):Bytes {
      final d = m.geometry.dimensions, r = m.rotation, p = m.position, eye = camera.position;
      final f = 1/Math.tan(camera.fov*Math.PI/360);
      final z = camera.far/(camera.near-camera.far);
      return floats([d.x*m.scale.x,d.y*m.scale.y,d.z*m.scale.z,0, r.x,r.y,r.z,0,
        p.x-eye.x,p.y-eye.y,p.z-eye.z,0, f/camera.aspect,f,z,z*camera.near, camera.right.x,camera.right.y,camera.right.z,0, camera.up.x,camera.up.y,camera.up.z,0, camera.back.x,camera.back.y,camera.back.z,0]);
  }
  public static function color(rgb:Int):Bytes
    return floats([((rgb>>16)&255)/255,((rgb>>8)&255)/255,(rgb&255)/255,1]);
}
