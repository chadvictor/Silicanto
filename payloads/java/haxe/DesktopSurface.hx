import Three;
import haxe.io.BytesData;

@:native("org.silicanto.desktop.MetalDisplay")
private extern class MetalDisplay {
  function new(w:Int,h:Int,visible:Bool);
  function upload(vertices:BytesData, lighting:BytesData, probe:BytesData, count:Int):Void;
  function frame(aa:Bool, camera:BytesData, box:BytesData, color:BytesData, r:Float,g:Float,b:Float):Void;
  function title(text:String):Void;
  function nextKey():Int;
  function isOpen():Bool;
  function capture(path:String):Void;
  function close():Void;
}

class DesktopSurface {
  final display:MetalDisplay;
  final signature = new SceneUpload.SceneSignature();
  var background = [0.,0.,0.];

  public function new(w:Int,h:Int,visible:Bool) display = new MetalDisplay(w,h,visible);

  public function poll(key:Bool->Void, redraw:Void->Void):Bool {
    var event:Int;
    while ((event = display.nextKey()) >= 0) key(event == 1);
    return display.isOpen();
  }

  public function draw(scene:Scene,camera:PerspectiveCamera,aa:Bool,w:Int,h:Int) {
    final world = scene.procedural;
    if (scene.assetId != null) throw "This Java graphics payload cannot read packed scenes";
    if (world != null && signature.changed(world)) {
      final data = new SceneUpload(world);
      display.upload(data.vertices.getData(),data.lighting.getData(),data.probe.getData(),data.count);
      background = data.background;
      if (world.name != "") display.title(world.name);
    }
    final m = scene.mesh;
    display.frame(aa, world == null ? null : FrameUniforms.camera(camera).getData(),
      m == null ? null : FrameUniforms.box(m,camera).getData(), m == null ? null : FrameUniforms.color(m.material.color).getData(),
      world == null ? 0 : background[0],world == null ? 0 : background[1],world == null ? 0 : background[2]);
  }

  public function capture(path:String) display.capture(path);
  public function close() display.close();
}
