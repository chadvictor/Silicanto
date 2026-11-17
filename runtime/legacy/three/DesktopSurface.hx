import hxn.window.Window;
import hxn.window.WindowAttributes;

// Default desktop provider. Other payloads can shadow this module on the Haxe classpath.
class DesktopSurface extends MetalSurface {
  final desktop:Null<Window>;
  public function new(w:Int,h:Int,visible:Bool) {
    var win:Window = null;
    if (visible) {
      final a = new WindowAttributes();
      a.title("Three.js · Metal"); a.width(w); a.height(h); a.resizable(false);
      win = Window.open(a); a.close();
    }
    super(win);
    desktop = win;
  }

  public function poll(key:Bool->Void, redraw:Void->Void):Bool {
    if (desktop != null) while (true) switch desktop.poll() {
      case None: return true;
      case Closed | Destroyed: return false;
      case KeyboardInput(_,Input(Code(Space),_,_,_,Pressed,repeated,_),_): key(repeated);
      case RedrawRequested: redraw();
      case _:
    }
    return true;
  }

  override public function close() {
    super.close();
    if (desktop != null) desktop.close();
  }
}
