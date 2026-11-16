package;

import Three;
import haxe.io.Bytes;
import hxn.gpu.metal.*;
import hxn.window.Window;

class MetalSurface {
  final device:Device;
  final queue:CommandQueue;
  final box:RenderPipeline;
  final resolve:RenderPipeline;
  var scenePipeline:RenderPipeline;
  final scenes:Map<String,SceneBuffers> = [];
  var liveBuffers:SceneBuffers;
  final liveSignature=new SceneUpload.SceneSignature();
  var wideColor=false;
  final layer:Layer;
  final window:Null<Window>;
  var intermediate:Texture;
  var output:Texture;
  var factor:Int;
  var width:Int;
  var height:Int;

  public function new(window:Null<Window>) {
    this.window=window;
    device = Device.systemDefault();
    Sys.stderr().writeString('Metal / '+device.name()+'\n');
    queue = device.newCommandQueue();
    final lib = device.newLibraryFromSource(haxe.Resource.getString("box.metal"));
    function pipeline(v:String, f:String) {
      final vert = lib.functionNamed(v), frag = lib.functionNamed(f);
      final p = device.newRenderPipeline(vert, frag, Bgra8Unorm, [], []);
      vert.close(); frag.close();
      return p;
    }
    box = pipeline("boxVertex", "boxColor");
    resolve = pipeline("screenVertex", "resolveColor");
    lib.close();
    layer = window == null ? null : Layer.attach(device, window.raw(0), Bgra8Unorm);
  }

  function configure(w:Int, h:Int, aa:Bool, world:Bool) {
    final scale = aa ? 2 : 1;
    if (intermediate != null && w == width && h == height && scale == factor && world == wideColor) return;
    if (intermediate != null) intermediate.close();
    if (output != null) output.close();
    width = w; height = h; factor = scale; wideColor = world;
    intermediate = device.newTexture({width:w*scale, height:h*scale, format:world ? Rgba32Float : Bgra8Unorm,
      usage:TextureUsage.RenderTarget | TextureUsage.ShaderRead, storage:StorageMode.Private});
    if (layer == null) {
      output = device.newTexture({width:w, height:h, format:Bgra8Unorm, usage:TextureUsage.RenderTarget, storage:StorageMode.Shared});
    } else layer.setDrawableSize(w,h);
  }

  static function floats(values:Array<Float>):Bytes {
    final bytes = Bytes.alloc(values.length*4);
    for (i in 0...values.length) bytes.setFloat(i*4,values[i]);
    return bytes;
  }

  public function draw(scene:Scene, camera:PerspectiveCamera, aa:Bool, w:Int, h:Int) {
    final world = scene.assetId!=null || scene.procedural!=null;
    configure(w,h,aa,world);
    var geometry:SceneBuffers=null;
    if(world) {
      if(scene.procedural!=null){
        if(liveSignature.changed(scene.procedural)){
          final updated=new SceneBuffers(device,null,scene.procedural);
          if(liveBuffers!=null)liveBuffers.close();
          liveBuffers=updated;
          if(window!=null && liveBuffers.name!="")window.setTitle(liveBuffers.name);
        }
        geometry=liveBuffers;
      }else geometry=scenes.get(scene.assetId);
      if(geometry==null){ geometry=new SceneBuffers(device,scene.assetId); scenes.set(scene.assetId,geometry);
        if(window!=null && geometry.name!="") window.setTitle(geometry.name); }
      if(scenePipeline==null){
        final lib=device.newLibraryFromSource(haxe.Resource.getString("scene.metal"));
        final v=lib.functionNamed("sceneVertex"), f=lib.functionNamed("sceneColor");
        scenePipeline=device.newRenderPipeline(v,f,Rgba32Float,[],[]);
        v.close(); f.close(); lib.close();
      }
    }
    final drawable = layer == null ? null : layer.nextDrawable();
    if (layer != null && drawable == null) return;
    final target = drawable == null ? output : drawable.texture();
    final cmd = queue.commandBuffer();
    final bg=world?geometry.background:[0.,0.,0.];
    final pass = cmd.renderEncoder(intermediate, Clear, bg[0],bg[1],bg[2],1);
    if(world){
      final f=1/Math.tan(camera.fov*Math.PI/360), z=camera.far/(camera.near-camera.far);
      final p=camera.position, r=camera.right, u=camera.up, b=camera.back;
      final frame=floats([p.x,p.y,p.z,0,r.x,r.y,r.z,0,u.x,u.y,u.z,0,b.x,b.y,b.z,0,f/camera.aspect,f,z,z*camera.near]);
      pass.setPipeline(scenePipeline);
      pass.setVertexBuffer(geometry.vertices,0,0);
      pass.setVertexBytes(frame,1);
      pass.setFragmentBuffer(geometry.uniforms,0,0);
      pass.setFragmentBuffer(geometry.probe,0,2);
      pass.setFragmentBytes(frame,1);
      pass.draw(Triangle,0,geometry.vertexCount,1);
    }
    final m = scene.mesh;
    if (m != null) {
      final d = m.geometry.dimensions, r = m.rotation, p = m.position, eye = camera.position;
      final f = 1/Math.tan(camera.fov*Math.PI/360);
      final z = camera.far/(camera.near-camera.far);
      final params = floats([d.x*m.scale.x,d.y*m.scale.y,d.z*m.scale.z,0, r.x,r.y,r.z,0,
        p.x-eye.x,p.y-eye.y,p.z-eye.z,0, f/camera.aspect,f,z,z*camera.near, camera.right.x,camera.right.y,camera.right.z,0, camera.up.x,camera.up.y,camera.up.z,0, camera.back.x,camera.back.y,camera.back.z,0]);
      final rgb = m.material.color;
      pass.setPipeline(box);
      pass.setVertexBytes(params,0);
      pass.setFragmentBytes(floats([((rgb>>16)&255)/255,((rgb>>8)&255)/255,(rgb&255)/255,1]),0);
      pass.draw(Triangle,0,36,1);
    }
    pass.end(); pass.close();
    final screen = cmd.renderEncoder(target, Clear,0,0,0,1);
    screen.setPipeline(resolve);
    screen.setFragmentTexture(intermediate,0);
    final scale = Bytes.alloc(4);
    scale.setInt32(0,factor);
    screen.setFragmentBytes(scale,0);
    screen.draw(Triangle,0,3,1);
    screen.end(); screen.close();
    if (drawable != null) cmd.present(drawable);
    cmd.commit();
    cmd.waitUntilCompleted();
    cmd.close();
    if (drawable != null) { target.close(); drawable.close(); }
  }

  public function capture(path:String) {
    if (output == null) throw "The application did not render a frame";
    final bgra = output.read(width*4);
    final file = sys.io.File.write(path,true);
    file.writeString('P6\n'+width+' '+height+'\n255\n');
    final rgb = Bytes.alloc(width*height*3);
    for (i in 0...width*height) {
      rgb.set(i*3,bgra.get(i*4+2));
      rgb.set(i*3+1,bgra.get(i*4+1));
      rgb.set(i*3+2,bgra.get(i*4));
    }
    file.write(rgb); file.close();
  }

  public function close() {
    if (intermediate != null) intermediate.close();
    if (output != null) output.close();
    if (layer != null) layer.close();
    for (geometry in scenes) geometry.close();
    if(liveBuffers!=null)liveBuffers.close();
    if (scenePipeline!=null) scenePipeline.close();
    box.close(); resolve.close(); queue.close(); device.close();
  }
}
