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
		final p = {x: t.x(x, y), y: t.y(x, y)};
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
