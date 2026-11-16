package;

import Three;
#if !js
import hxn.window.Window;
import hxn.window.WindowAttributes;
#end
typedef Keyboard = {code:String, repeat:Bool};

#if js
typedef Host = BrowserHost;
#else

class Host {
  public static var innerWidth = 300;
  public static var innerHeight = 150;
  public static var loop:Float->Void;
  static final keyHandlers:Array<Keyboard->Void> = [];
  public static function onKey(cb:Keyboard->Void) keyHandlers.push(cb);
  static var pending:Array<Float->Void> = [];
  static var window:Window;
  static var surface:MetalSurface;
  static var capturePath:String;
  static var frameLimit = 0;
  static var captureTime:Null<Float>;
  static var lastScene:Scene;
  static var lastCamera:PerspectiveCamera;
  static var antialias:Bool;

  public static function init() {
    final args = Sys.args();
    while (args.length > 0) {
      switch args.shift() {
        case "--frames":
          final n = Std.parseInt(args.shift());
          if (n == null || n < 1) throw "Expected --frames N with N >= 1";
          frameLimit = n;
        case "--time-ms":
          captureTime=Std.parseFloat(args.shift());
          if(!Math.isFinite(captureTime) || captureTime<0) throw "Expected a nonnegative timestamp";
        case "--capture":
          capturePath = args.shift();
          if (capturePath == null) throw "Expected --capture output.ppm";
        case arg: throw "Unknown argument: "+arg;
      }
    }
    if(captureTime!=null && (capturePath==null || frameLimit>1)) throw "--time-ms requires a single captured frame";
    if (capturePath != null && frameLimit == 0) frameLimit = 1;
  }

  public static function mount() {}
  public static function requestFrame(cb:Float->Void) pending.push(cb);

  public static function setSize(w:Int,h:Int) {
    if (w < 1 || h < 1) throw "Expected a positive drawing size";
    if (surface != null && (w != innerWidth || h != innerHeight)) throw "Changing the drawing size after the first frame is not supported";
    innerWidth = w; innerHeight = h;
  }

  public static function draw(scene:Scene,camera:PerspectiveCamera,aa:Bool) {
    if (surface == null) {
      if (capturePath == null) {
        final a = new WindowAttributes();
        a.title("Three.js · Metal"); a.width(innerWidth); a.height(innerHeight); a.resizable(false);
        window = Window.open(a); a.close();
      }
      surface = new MetalSurface(window);
    }
    lastScene = scene; lastCamera = camera; antialias = aa;
    surface.draw(scene,camera,aa,innerWidth,innerHeight);
  }

  public static function run() {
    final start = haxe.Timer.stamp();
    var frame = 0, open = true;
    while (open) {
      if (window != null) {
        var polling = true;
        while (polling) switch window.poll() {
          case None: polling = false;
          case Closed | Destroyed: open = false; polling = false;
          case KeyboardInput(_,Input(Code(Space),_,_,_,Pressed,repeated,_),_):
            for (cb in keyHandlers) cb({code:"Space", repeat:repeated});
          case RedrawRequested:
            if (pending.length == 0 && loop == null && lastScene != null) draw(lastScene,lastCamera,antialias);
          case _:
        }
      }
      if (!open) break;
      final time = captureTime!=null ? captureTime : frameLimit > 0 ? frame*(1000.0/60.0) : (haxe.Timer.stamp()-start)*1000;
      final callbacks = pending;
      pending = [];
      for (callback in callbacks) callback(time);
      if (loop != null) loop(time);
      frame++;
      if (frameLimit > 0 && frame >= frameLimit) break;
      if (window == null && pending.length == 0 && loop == null) break;
      if (capturePath == null) Sys.sleep(1/60);
    }
    if (capturePath != null) {
      if (surface == null) throw "The application did not call render";
      surface.capture(capturePath);
    }
    if (surface != null) surface.close();
    if (window != null) window.close();
  }
}
#end
