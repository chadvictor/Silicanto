class WebArray {
  public static function read<T>(array:Array<T>, index:Float):T {
    if (!(index >= 0 && index < array.length && index == Math.ffloor(index)))
      throw "E-JS-UNDEFINED: array read outside the dense array profile";
    return array[Std.int(index)];
  }
}
