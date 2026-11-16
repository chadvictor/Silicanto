import Three;
import js.Browser;
import js.html.CanvasElement;
import js.Syntax;

class BrowserHost {
  public static var innerWidth:Int;
  public static var innerHeight:Int;
  public static var loop(default,set):Float->Void;
  static var canvas:CanvasElement;
  static var renderer:Dynamic;
  static var scene:Dynamic;
  static var camera:Dynamic;
  static var box:Dynamic;
  static var mesh:Mesh;

  public static function init() {
    canvas = cast Browser.document.querySelector("canvas");
    if (canvas == null) canvas = Browser.document.createCanvasElement();
    innerWidth = canvas.width;
    innerHeight = canvas.height;
  }
  public static function mount() {
    if (canvas.parentNode == null) Browser.document.body.appendChild(canvas);
  }
  public static function onKey(cb:Host.Keyboard->Void) {
    Browser.window.addEventListener("keydown", function(e:js.html.KeyboardEvent) cb({code:e.code,repeat:e.repeat}));
  }
  public static function requestFrame(cb:Float->Void) { Browser.window.requestAnimationFrame(cb); }
  static function set_loop(cb:Float->Void):Float->Void {
    if (cb != null && loop == null) requestFrame(tick);
    return loop = cb;
  }
  static function tick(t:Float) {
    if (loop != null) { loop(t); if (loop != null) requestFrame(tick); }
  }
  public static function setSize(w:Int,h:Int) {
    innerWidth=w; innerHeight=h;
    if (renderer == null) { canvas.width=w; canvas.height=h; } else renderer.setSize(w,h);
  }
  public static function draw(s:Scene,c:PerspectiveCamera,antialias:Bool) {
    final three:Dynamic = Syntax.code("ThreecBrowserLibrary");
    if (renderer == null) {
      renderer=Syntax.construct(three.WebGLRenderer, {canvas:canvas,antialias:antialias});
      scene=Syntax.construct(three.Scene);
      camera=Syntax.construct(three.PerspectiveCamera);
    }
    if (s.mesh != mesh) {
      if (box != null) { scene.remove(box); box.geometry.dispose(); box.material.dispose(); }
      mesh=s.mesh;
      if (mesh != null) {
        final d=mesh.geometry.dimensions;
        final geometry=Syntax.construct(three.BoxGeometry,d.x,d.y,d.z);
        box=Syntax.construct(three.Mesh,geometry,Syntax.construct(three.MeshBasicMaterial,{color:mesh.material.color}));
        scene.add(box);
      }
    }
    if (mesh != null) {
      box.position.set(mesh.position.x,mesh.position.y,mesh.position.z);
      box.rotation.set(mesh.rotation.x,mesh.rotation.y,mesh.rotation.z);
      box.scale.set(mesh.scale.x,mesh.scale.y,mesh.scale.z);
    }
    camera.fov=c.fov; camera.aspect=c.aspect; camera.near=c.near; camera.far=c.far;
    camera.position.set(c.position.x,c.position.y,c.position.z);
    camera.up.set(c.up.x,c.up.y,c.up.z);
    camera.lookAt(c.position.x-c.back.x,c.position.y-c.back.y,c.position.z-c.back.z);
    camera.updateProjectionMatrix();
    renderer.render(scene,camera);
  }
  public static function run() {}
}
