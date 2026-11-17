package;

import haxe.io.Bytes;
import haxe.io.Path;
import sys.io.File;
import hxn.gpu.metal.Device;
import hxn.gpu.metal.Buffer;

class SceneBuffers {
  public final vertices:Buffer;
  public final uniforms:Buffer;
  public final probe:Buffer;
  public final vertexCount:Int;
  public final background:Array<Float>;
  public final name:String;
  public function new(device:Device,id:String,?scene:SceneGraph.PScene) {
    if(scene!=null){
      final upload=new SceneUpload(scene);
      name=scene.name; vertexCount=upload.count; background=upload.background;
      vertices=device.newBufferWith(upload.vertices); uniforms=device.newBufferWith(upload.lighting); probe=device.newBufferWith(upload.probe);
      return;
    }
    final exe=Path.directory(Sys.programPath());
    var assets=Path.join([exe,"assets"]);
    if (!sys.FileSystem.exists(assets)) assets=Path.join([exe,"../Resources/assets"]);
    final base=Path.join([assets,id]);
    final meta=haxe.Json.parse(File.getContent(base+".json"));
    name=meta.name; vertexCount=meta.vertexCount; background=meta.background;
    final compressed=File.getBytes(base+".vertices.z");
    #if hl
    final data=haxe.zip.InflateImpl.run(new haxe.io.BytesInput(compressed));
    if(data.length!=vertexCount*64) throw "Invalid compiled vertex data";
    #else
    final data=Bytes.alloc(vertexCount*64);
    final inflater=new haxe.zip.Uncompress();
    final decoded=inflater.execute(compressed,0,data,0);
    inflater.close();
    if(!decoded.done || decoded.write!=data.length) throw "Invalid compiled vertex data";
    #end
    vertices=device.newBufferWith(data);
    final values:Array<Float>=meta.uniforms, bytes=Bytes.alloc(values.length*4);
    for(i in 0...values.length) bytes.setFloat(i*4,values[i]);
    uniforms=device.newBufferWith(bytes);
    probe=device.newBufferWith(values[48]>0?File.getBytes(base+".probe"):Bytes.alloc(16));
  }
  public function close(){vertices.close(); uniforms.close(); probe.close();}
}
