class Point3 {
  public var x:Float;
  public var y:Float;
  public var z:Float;
  public function new(x:Float, y:Float, z:Float) {
    this.x=x; this.y=y; this.z=z;
  }
  public function dot(a:Float, b:Float, c:Float):Float {
    return x*a + y*b + z*c;
  }
}

class Projection {
  static function main() {
    final point = new Point3(1.5, -2.0, 4.0);
    final weights = [0.0, 0.25, 0.5, 1.0];
    var sum = 0.0;
    for (w in weights) sum += point.dot(w, 0.5, 2.0);
    js.Browser.console.log(sum);
  }
}
