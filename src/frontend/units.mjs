// A class file has a finite method size on the JVM. Keep closed JS functions
// in separate Haxe methods and split large literal tables across methods.
export class Units {
  constructor(index) {
    this.prefix = "JsUnit" + index + "_";
    this.groups = [];
  }
  method(params, result, body) {
    let group = this.groups.at(-1);
    if (!group || group.size + body.length > 64000) {
      group = { name: this.prefix + this.groups.length, methods: [], size: 0 };
      this.groups.push(group);
    }
    const method = "part" + group.methods.length;
    group.methods.push(
      "public static function " +
        method +
        "(" +
        params +
        "):" +
        result +
        " " +
        body,
    );
    group.size += body.length;
    return group.name + "." + method;
  }
  sources() {
    return Object.fromEntries(
      this.groups.map((g) => [
        g.name + ".hx",
        "class " + g.name + " {\n" + g.methods.join("\n") + "\n}\n",
      ]),
    );
  }
}
