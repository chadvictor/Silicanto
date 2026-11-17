private typedef Point2 = {x:Float, y:Float};

/** Device-space line segments for the Canvas current path. */
class WebPath {
	public final contours:Array<Array<Point2>> = [];

	var current:Array<Point2>;

	public var minX = Math.POSITIVE_INFINITY;
	public var minY = Math.POSITIVE_INFINITY;
	public var maxX = Math.NEGATIVE_INFINITY;
	public var maxY = Math.NEGATIVE_INFINITY;

	public function new() {}

	public function point(t:WebTransform, x:Float, y:Float, move:Bool) {
		devicePoint(t.x(x, y), t.y(x, y), move);
	}

	function devicePoint(x:Float, y:Float, move:Bool) {
		if (!Math.isFinite(x) || !Math.isFinite(y))
			return;
		final p = {x: x, y: y};
		if (current == null || move) {
			current = [];
			contours.push(current);
		}
		current.push(p);
		minX = Math.min(p.x, minX);
		maxX = Math.max(p.x, maxX);
		minY = Math.min(p.y, minY);
		maxY = Math.max(p.y, maxY);
	}

	public function ellipse(t:WebTransform, cx:Float, cy:Float, rx:Float, ry:Float, angle:Float, start:Float, end:Float, reverse:Bool) {
		if (rx < 0 || ry < 0)
			throw "IndexSizeError: negative ellipse radius";
		if (!Math.isFinite(cx + cy + rx + ry + angle + start + end))
			return;
		final turn = 2 * Math.PI;
		var sweep = end - start;
		if (!reverse)
			sweep = sweep >= turn ? turn : (sweep % turn + turn) % turn;
		else
			sweep = sweep <= -turn ? -turn : -((-sweep % turn + turn) % turn);
		final co = Math.cos(angle), si = Math.sin(angle);
		final scale = Math.max(Math.sqrt(t.a * t.a + t.b * t.b), Math.sqrt(t.c * t.c + t.d * t.d));
		final n = Std.int(Math.min(4096, Math.max(1, Math.ceil(Math.abs(sweep) * Math.sqrt(Math.max(1, scale * Math.max(rx, ry)))))));
		for (i in 0...n + 1) {
			final theta = start + sweep * i / n, x = rx * Math.cos(theta), y = ry * Math.sin(theta);
			point(t, cx + co * x - si * y, cy + si * x + co * y, false);
		}
	}

	public function curve(t:WebTransform, coords:Array<Float>, cubic:Bool) {
		for (v in coords)
			if (!Math.isFinite(v))
				return;
		if (current == null)
			point(t, coords[0], coords[1], true);
		final first = current[current.length - 1];
		final p1 = {x: t.x(coords[0], coords[1]), y: t.y(coords[0], coords[1])};
		final p2 = {x: t.x(coords[2], coords[3]), y: t.y(coords[2], coords[3])};
		final end = cubic ? {x: t.x(coords[4], coords[5]), y: t.y(coords[4], coords[5])} : p2;
		inline function distance(a:Point2, b:Point2):Float
			return Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
		final length = distance(first, p1) + distance(p1, p2) + distance(p2, end);
		final n = Std.int(Math.max(1, Math.min(4096, Math.ceil(2 * Math.sqrt(length)))));
		for (i in 1...n + 1) {
			final u = i / n, v = 1 - u;
			if (cubic)
				devicePoint(v * v * v * first.x
					+ 3 * v * v * u * p1.x
					+ 3 * v * u * u * p2.x
					+ u * u * u * end.x,
					v * v * v * first.y
					+ 3 * v * v * u * p1.y
					+ 3 * v * u * u * p2.y
					+ u * u * u * end.y, false);
			else
				devicePoint(v * v * first.x + 2 * v * u * p1.x + u * u * end.x, v * v * first.y + 2 * v * u * p1.y + u * u * end.y, false);
		}
	}

	public function snapshot():WebPath {
		final p = new WebPath();
		for (poly in contours)
			p.contours.push(poly.copy());
		p.minX = minX;
		p.maxX = maxX;
		p.minY = minY;
		p.maxY = maxY;
		return p;
	}

	public function close() {
		if (current != null && current.length > 0)
			current.push(current[0]);
	}

	public function rect(t:WebTransform, x:Float, y:Float, w:Float, h:Float) {
		point(t, x, y, true);
		point(t, x + w, y, false);
		point(t, x + w, y + h, false);
		point(t, x, y + h, false);
		close();
	}

	public function contains(x:Float, y:Float):Bool {
		if (x < minX || x > maxX || y < minY || y > maxY)
			return false;
		var winding = 0;
		for (poly in contours) {
			var prev = poly[poly.length - 1];
			for (p in poly) {
				final cross = (p.x - prev.x) * (y - prev.y) - (x - prev.x) * (p.y - prev.y);
				if (prev.y <= y && p.y > y && cross > 0)
					winding++;
				else if (prev.y > y && p.y <= y && cross < 0)
					winding--;
				prev = p;
			}
		}
		return winding != 0;
	}

	public function onStroke(x:Float, y:Float, r:Float):Bool {
		for (poly in contours)
			for (i in 1...poly.length) {
				final p = poly[i - 1], q = poly[i], dx = q.x - p.x, dy = q.y - p.y, dd = dx * dx + dy * dy;
				if (dd > 0) {
					final u = ((x - p.x) * dx + (y - p.y) * dy) / dd;
					if (u >= 0 && u <= 1) {
						final a = x - p.x - u * dx, b = y - p.y - u * dy;
						if (a * a + b * b <= r * r)
							return true;
					}
				}
			}
		return false;
	}
}
