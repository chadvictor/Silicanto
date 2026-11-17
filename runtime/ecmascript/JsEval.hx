private enum EvalExpr {
	Literal(value:Dynamic);
	Name(key:String);
	Member(owner:EvalExpr, key:EvalExpr);
	Invoke(callee:EvalExpr, args:Array<EvalExpr>);
	Unary(op:String, operand:EvalExpr);
	Binary(op:String, left:EvalExpr, right:EvalExpr);
}

/** Dynamic expression strings are parsed inside the native process. All object
	access, calls, comparison and coercion use the compiled application's realm. */
class JsEval {
	public static var builtin(default, null):JsObject;

	public static function install():JsObject {
		builtin = Js.fn((_, args) -> evaluate(Js.at(args, 0), globalRead, Js.realm), false);
		return builtin;
	}

	public static function globalRead(name:String, typeOnly:Bool):Dynamic
		return typeOnly ? Js.globalType(name) : Js.global(name);

	public static function direct(fn:Dynamic, args:Array<Dynamic>, read:(String, Bool)->Dynamic, self:Dynamic):Dynamic
		return fn == builtin ? evaluate(Js.at(args, 0), read, self) : Js.call(fn, Js.u, args);

	static function evaluate(value:Dynamic, read:(String, Bool)->Dynamic, self:Dynamic):Dynamic {
		if (!Std.isOfType(value, String)) return value;
		final source:String = value;
		final parser = new EvalParser(source);
		final expr = parser.expressionBody();
		return expr == null ? Js.u : run(expr, read, self);
	}

	static function run(expr:EvalExpr, read:(String, Bool)->Dynamic, self:Dynamic):Dynamic {
		function get(e:EvalExpr):Dynamic return run(e, read, self);
		return switch expr {
			case Literal(value): value;
			case Name("this"): self;
			case Name(key): read(key, false);
			case Member(owner, key): Js.get(get(owner), get(key));
			case Invoke(Name("eval"), args):
				final fn = read("eval", false);
				direct(fn, [for (arg in args) get(arg)], read, self);
			case Invoke(callee, args):
				var receiver:Dynamic = Js.u;
				final fn = switch callee {
					case Member(owner, key):
						receiver = get(owner);
						Js.get(receiver, get(key));
					default: get(callee);
				};
				Js.call(fn, receiver, [for (arg in args) get(arg)]);
			case Unary("typeof", Name(name)) if (name != "this"): read(name, true);
			case Unary(op, operand):
				final a = get(operand);
				switch op {
					case "!": !Js.truth(a);
					case "+": Js.num(a);
					case "-": -Js.num(a);
					case "void": Js.u;
					default: Js.type(a);
				}
			case Binary(op, left, right):
				final a = get(left);
				if (op == "&&") Js.truth(a) ? get(right) : a;
				else if (op == "||") Js.truth(a) ? a : get(right);
				else {
					final b = get(right);
					switch op {
						case "+": Js.add(a, b);
						case "-": Js.num(a) - Js.num(b);
						case "*": Js.num(a) * Js.num(b);
						case "/": Js.num(a) / Js.num(b);
						case "%": Js.num(a) % Js.num(b);
						case "===": Js.equal(a, b);
						case "!==": !Js.equal(a, b);
						case "==": Js.loose(a, b);
						case "!=": !Js.loose(a, b);
						case "<": Js.less(a, b);
						case ">": Js.less(b, a);
						case "<=": Js.lessEqual(a, b);
						case ">=": Js.lessEqual(b, a);
						case "instanceof": Js.instance(a, b);
						case "in": Js.has(b, a);
						default: throw "Unknown eval operator " + op;
					}
				}
		}
	}
}

private class EvalParser {
	static final token = ~/^(?:[ \t\r\n\x0c]+|[a-zA-Z_$][a-zA-Z_$0-9]*|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|\+\+|--|===|!==|==|!=|<=|>=|&&|\|\||.)/;
	static final name = ~/^[a-zA-Z_$][a-zA-Z_$0-9]*$/;
	static final number = ~/^(?:[0-9]|\.[0-9])/;
	static final precedence = [
		"||" => 1, "&&" => 2, "==" => 3, "!=" => 3, "===" => 3, "!==" => 3,
		"<" => 4, ">" => 4, "<=" => 4, ">=" => 4, "in" => 4, "instanceof" => 4,
		"+" => 5, "-" => 5, "*" => 6, "/" => 6, "%" => 6
	];
	final source:String;
	var pos = 0;
	var next:String;

	public function new(source:String) {
		this.source = source;
		advance();
	}

	function unsupported():Dynamic
		throw Js.construct(Js.global("EvalError"), ["Unsupported native eval expression at offset " + (pos - next.length)]);

	function advance():String {
		final old = next;
		next = "";
		while (pos < source.length) {
			if (!token.match(source.substr(pos))) unsupported();
			next = token.matched(0);
			pos += next.length;
			if (StringTools.trim(next) != "") break;
			next = "";
		}
		return old;
	}

	function take(value:String):Bool {
		if (next != value) return false;
		advance();
		return true;
	}

	function expect(value:String):Void {
		if (!take(value)) unsupported();
	}

	function stringValue(quote:String):String {
		final result = new StringBuf();
		while (pos < source.length) {
			var c = source.charAt(pos++);
			if (c == quote) {
				advance();
				return result.toString();
			}
			if (c == "\n" || c == "\r") unsupported();
			if (c == "\\") {
				c = source.charAt(pos++);
				switch c {
					case "t": c = "\t";
					case "n": c = "\n";
					case "r": c = "\r";
					case "\\", "'", "\"":
					default: unsupported();
				}
			}
			result.add(c);
		}
		return unsupported();
	}

	public function expressionBody():Null<EvalExpr> {
		if (next == "") return null;
		final result = expression(0);
		while (take(";")) {}
		if (next != "") unsupported();
		return result;
	}

	function expression(minimum:Int):EvalExpr {
		var left = operand();
		while (precedence.exists(next) && precedence.get(next) >= minimum) {
			final op = advance();
			left = Binary(op, left, expression(precedence.get(op) + 1));
		}
		return left;
	}

	function operand():EvalExpr {
		switch next {
			case "!", "+", "-", "typeof", "void": return Unary(advance(), operand());
			default:
		}
		var expr:EvalExpr;
		if (take("(")) {
			expr = expression(0);
			expect(")");
		} else if (next == "'" || next == "\"") expr = Literal(stringValue(next));
		else if (number.match(next)) expr = Literal(Std.parseFloat(advance()));
		else if (name.match(next)) expr = switch advance() {
			case "true": Literal(true);
			case "false": Literal(false);
			case "null": Literal(null);
			case "new", "class", "function", "delete", "var", "let", "const", "super", "import", "return", "throw": unsupported();
			case key: Name(key);
		};
		else return unsupported();
		while (true) {
			if (take(".")) {
				if (!name.match(next)) unsupported();
				expr = Member(expr, Literal(advance()));
			} else if (take("[")) {
				final key = expression(0);
				expect("]");
				expr = Member(expr, key);
			} else if (take("(")) {
				final args = [];
				if (!take(")")) {
					do args.push(expression(0)) while (take(",") && next != ")");
					expect(")");
				}
				expr = Invoke(expr, args);
			} else return expr;
		}
	}
}
