extends RefCounted
# Procedural cartoon art: static draw functions only. See INTERFACE.md.

const OL := Color(0.12, 0.08, 0.1)
const SKIN := Color(1.0, 0.78, 0.64)
const WHITE := Color(0.98, 0.98, 1.0)

static var _xf: Transform2D = Transform2D.IDENTITY
static var _stone: bool = false
static var _ghost: bool = false
static var _bold: FontVariation = null


# ---------------------------------------------------------------- helpers

static func _reset() -> void:
	_xf = Transform2D.IDENTITY
	_stone = false
	_ghost = false


static func _h(x: float, y: float) -> float:
	var v: float = sin(x * 12.9898 + y * 78.233) * 43758.5453
	return v - floorf(v)


static func _k(c: Color) -> Color:
	if _stone:
		var g: float = 0.12 + c.get_luminance() * 0.80
		c = Color(g * 0.96, g * 0.99, g * 1.05, c.a)
	if _ghost:
		c = c.lerp(Color(0.85, 0.93, 1.0, c.a), 0.35)
		c.a *= 0.55
	return c


static func _font() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = 0.9
		_bold = fv
	return _bold


# part: 0 outline+fill, 1 outline only, 2 fill only
static func _e(ci: CanvasItem, c: Vector2, r: Vector2, col: Color, ol: float = 2.5, rot: float = 0.0, part: int = 0) -> void:
	var m: Transform2D = _xf * Transform2D(rot, c)
	if ol > 0.0 and part != 2:
		var ro := Vector2(r.x + ol, r.y + ol)
		var mo: float = maxf(ro.x, ro.y)
		ci.draw_set_transform_matrix(m * Transform2D(Vector2(ro.x / mo, 0), Vector2(0, ro.y / mo), Vector2.ZERO))
		ci.draw_circle(Vector2.ZERO, mo, _k(OL))
	if part != 1:
		var mf: float = maxf(r.x, r.y)
		ci.draw_set_transform_matrix(m * Transform2D(Vector2(r.x / mf, 0), Vector2(0, r.y / mf), Vector2.ZERO))
		ci.draw_circle(Vector2.ZERO, mf, _k(col))


static func _circ(ci: CanvasItem, c: Vector2, r: float, col: Color, ol: float = 2.5) -> void:
	ci.draw_set_transform_matrix(_xf)
	if ol > 0.0:
		ci.draw_circle(c, r + ol, _k(OL))
	ci.draw_circle(c, r, _k(col))


# items: Array of [Vector2 centre, Vector2 radii, float rot]; merged silhouette with one outline
static func _merge(ci: CanvasItem, items: Array, col: Color, ol: float = 2.5) -> void:
	for it in items:
		_e(ci, it[0], it[1], col, ol, it[2], 1)
	for it in items:
		_e(ci, it[0], it[1], col, ol, it[2], 2)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, ol: float = 2.5) -> void:
	ci.draw_set_transform_matrix(_xf)
	ci.draw_colored_polygon(pts, _k(col))
	if ol > 0.0:
		var p2 := pts.duplicate()
		p2.append(pts[0])
		ci.draw_polyline(p2, _k(OL), ol * 2.0)


static func _limb(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color, ol: float = 2.2) -> void:
	ci.draw_set_transform_matrix(_xf)
	if ol > 0.0:
		var wo: float = w + ol * 2.0
		ci.draw_line(a, b, _k(OL), wo)
		ci.draw_circle(a, wo * 0.5, _k(OL))
		ci.draw_circle(b, wo * 0.5, _k(OL))
	ci.draw_line(a, b, _k(col), w)
	ci.draw_circle(a, w * 0.5, _k(col))
	ci.draw_circle(b, w * 0.5, _k(col))


static func _line(ci: CanvasItem, a: Vector2, b: Vector2, w: float, col: Color) -> void:
	ci.draw_set_transform_matrix(_xf)
	ci.draw_line(a, b, _k(col), w)


static func _arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	ci.draw_set_transform_matrix(_xf)
	ci.draw_arc(c, r, a0, a1, 16, _k(col), w)


static func _rect(ci: CanvasItem, rc: Rect2, col: Color, ol: float = 2.5) -> void:
	ci.draw_set_transform_matrix(_xf)
	if ol > 0.0:
		ci.draw_rect(rc.grow(ol), _k(OL))
	ci.draw_rect(rc, _k(col))


static func _rr_pts(rc: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	rad = minf(rad, minf(rc.size.x, rc.size.y) * 0.5)
	var cs: Array[Vector2] = [
		Vector2(rc.end.x - rad, rc.position.y + rad),
		Vector2(rc.end.x - rad, rc.end.y - rad),
		Vector2(rc.position.x + rad, rc.end.y - rad),
		Vector2(rc.position.x + rad, rc.position.y + rad)]
	for k in 4:
		var a0: float = -PI * 0.5 + k * PI * 0.5
		for i in 5:
			var a: float = a0 + i * (PI * 0.5 / 4.0)
			pts.append(cs[k] + Vector2(cos(a), sin(a)) * rad)
	return pts


static func _rr(ci: CanvasItem, rc: Rect2, rad: float, col: Color, ol: float = 2.5) -> void:
	_poly(ci, _rr_pts(rc, rad), col, ol)


static func _txt(ci: CanvasItem, pos: Vector2, text: String, size: int, col: Color, olc: Color = OL, ols: int = 4) -> void:
	var f: Font = _font()
	var w: float = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var bp := Vector2(pos.x - w * 0.5, pos.y + size * 0.36)
	ci.draw_set_transform_matrix(_xf)
	if ols > 0:
		ci.draw_string_outline(f, bp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ols, _k(olc))
	ci.draw_string(f, bp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _k(col))


static func _fit(text: String, max_w: float, size: int) -> int:
	var w: float = _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w > max_w and w > 0.0:
		return maxi(6, int(size * max_w / w))
	return size


static func _star_pts(c: Vector2, ro: float, ri: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a: float = rot + i * PI / 5.0 - PI * 0.5
		var r: float = ro if i % 2 == 0 else ri
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _dashed_rect(ci: CanvasItem, rc: Rect2, col: Color, width: float, dash: float, gap: float, off: float) -> void:
	var corners: Array[Vector2] = [rc.position, Vector2(rc.end.x, rc.position.y), rc.end, Vector2(rc.position.x, rc.end.y)]
	var per: float = dash + gap
	var seg := PackedVector2Array()
	var acc: float = 0.0
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var d: Vector2 = b - a
		var len: float = d.length()
		var dir: Vector2 = d / len
		var k: int = int(floor((acc - off - dash) / per))
		while k * per + off - acc < len:
			var s0: float = maxf(0.0, k * per + off - acc)
			var s1: float = minf(len, k * per + off - acc + dash)
			if s1 > s0:
				seg.append(a + dir * s0)
				seg.append(a + dir * s1)
			k += 1
		acc += len
	ci.draw_set_transform_matrix(_xf)
	if seg.size() > 0:
		ci.draw_multiline(seg, _k(col), width)


static func _spiral(ci: CanvasItem, c: Vector2, r: float, rot: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a: float = rot + i * 0.85
		pts.append(c + Vector2(cos(a), sin(a)) * r * (i / 13.0))
	ci.draw_set_transform_matrix(_xf)
	ci.draw_polyline(pts, _k(col), w)


static func _shadow(ci: CanvasItem, c: Vector2, r: Vector2, a: float = 0.28) -> void:
	_e(ci, c, r, Color(0.05, 0.1, 0.05, a), 0.0)


static func _end(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_reset()


# ---------------------------------------------------------------- environment

static func draw_ground(ci: CanvasItem, world: Rect2, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_rect(world, Color(0.36, 0.73, 0.30))
	# mowing stripes
	var sw: float = 96.0
	var n: int = int(ceil(world.size.x / sw))
	for i in range(0, n, 2):
		var x: float = world.position.x + i * sw
		ci.draw_rect(Rect2(x, world.position.y, minf(sw, world.end.x - x), world.size.y), Color(0.41, 0.78, 0.33))
	# soft blotches
	var bs: float = 220.0
	var nx: int = int(world.size.x / bs) + 1
	var ny: int = int(world.size.y / bs) + 1
	for j in ny:
		for i in nx:
			var h1: float = _h(i * 1.7, j * 3.1)
			var h2: float = _h(i * 5.3, j * 2.3)
			var c := Vector2(world.position.x + (i + h1) * bs, world.position.y + (j + h2) * bs)
			var col := Color(0.25, 0.6, 0.25, 0.16) if h1 > 0.5 else Color(0.6, 0.9, 0.4, 0.14)
			ci.draw_circle(c, 40.0 + h2 * 50.0, col)
	# tufts on a coarse grid
	var cell: float = maxf(58.0, sqrt(world.size.x * world.size.y / 230.0))
	var cx: int = int(world.size.x / cell) + 1
	var cy: int = int(world.size.y / cell) + 1
	var dark := PackedVector2Array()
	var lite := PackedVector2Array()
	for j in cy:
		for i in cx:
			var hh: float = _h(i + 0.5, j + 0.5)
			if hh > 0.85:
				continue
			var b := Vector2(world.position.x + (i + _h(i, j * 2.0)) * cell, world.position.y + (j + _h(i * 2.0, j)) * cell)
			var sway: float = sin(t * 1.6 + hh * 20.0) * 1.6
			var arr: PackedVector2Array = dark if hh < 0.45 else lite
			arr.append(b)
			arr.append(b + Vector2(-5.0 + sway, -9.0))
			arr.append(b)
			arr.append(b + Vector2(sway, -13.0))
			arr.append(b)
			arr.append(b + Vector2(5.0 + sway, -8.0))
			if hh < 0.45:
				dark = arr
			else:
				lite = arr
	ci.draw_multiline(dark, Color(0.2, 0.52, 0.2), 2.6)
	ci.draw_multiline(lite, Color(0.62, 0.9, 0.4), 2.6)
	# flowers
	var fc: float = cell * 1.9
	var fx: int = int(world.size.x / fc) + 1
	var fy: int = int(world.size.y / fc) + 1
	var pal: Array[Color] = [Color(1, 1, 1), Color(1, 0.55, 0.75), Color(1, 0.9, 0.25), Color(1, 0.55, 0.2), Color(0.8, 0.6, 1)]
	for j in fy:
		for i in fx:
			var hh: float = _h(i * 3.3 + 1.0, j * 1.9 + 4.0)
			if hh < 0.45:
				continue
			var pos := Vector2(world.position.x + (i + _h(i + 7.0, j)) * fc, world.position.y + (j + _h(i, j + 9.0)) * fc)
			pos.y += sin(t * 2.0 + hh * 30.0) * 0.8
			ci.draw_circle(pos, 5.0, OL * Color(1, 1, 1, 0.5))
			ci.draw_circle(pos, 4.0, pal[int(hh * 10.0) % 5])
			ci.draw_circle(pos, 1.7, Color(1, 0.8, 0.1) if hh < 0.9 else Color(0.9, 0.3, 0.2))


static func draw_path(ci: CanvasItem, a: Vector2, b: Vector2, width: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var edge := Color(0.62, 0.45, 0.27)
	var sand := Color(0.95, 0.82, 0.55)
	var wo: float = width + 8.0
	ci.draw_line(a, b, edge, wo)
	ci.draw_circle(a, wo * 0.5, edge)
	ci.draw_circle(b, wo * 0.5, edge)
	ci.draw_line(a, b, sand, width)
	ci.draw_circle(a, width * 0.5, sand)
	ci.draw_circle(b, width * 0.5, sand)
	var d: Vector2 = b - a
	var len: float = d.length()
	if len < 1.0:
		return
	var perp := Vector2(-d.y, d.x) / len
	var n: int = mini(int(len / 24.0), 70)
	for k in n:
		var h: float = _h(a.x * 0.1 + k, a.y * 0.1 + k * 0.5)
		var pos: Vector2 = a + d * ((k + 0.5) / maxf(n, 1)) + perp * (_h(k, 3.0) - 0.5) * width * 0.75
		var r: float = 2.5 + h * 3.0
		ci.draw_circle(pos, r, Color(0.8, 0.65, 0.4))
		ci.draw_circle(pos + Vector2(-0.8, -0.8), r * 0.5, Color(1.0, 0.92, 0.7))


static func draw_wall(ci: CanvasItem, r: Rect2) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_rect(Rect2(r.position + Vector2(3, 6), r.size), Color(0.05, 0.1, 0.05, 0.28))
	ci.draw_rect(r.grow(3.0), OL)
	ci.draw_rect(r, Color(0.84, 0.43, 0.30))
	var rowh: float = 14.0
	var bw: float = 30.0
	var seg := PackedVector2Array()
	var rows: int = int(ceil(r.size.y / rowh))
	var cols: int = int(ceil(r.size.x / bw)) + 1
	var tiles: int = 0
	for j in rows:
		var y: float = r.position.y + j * rowh
		var yh: float = minf(rowh, r.end.y - y)
		if j > 0:
			seg.append(Vector2(r.position.x, y))
			seg.append(Vector2(r.end.x, y))
		for i in cols:
			var x: float = r.position.x + i * bw + (bw * 0.5 if j % 2 == 1 else 0.0) - bw * 0.5
			if x > r.position.x and x < r.end.x:
				seg.append(Vector2(x, y))
				seg.append(Vector2(x, y + yh))
			var hh: float = _h(i + j * 17.0, j * 3.0)
			if hh > 0.78 and tiles < 90:
				var x0: float = maxf(x + 1.0, r.position.x)
				var x1: float = minf(x + bw - 1.0, r.end.x)
				if x1 > x0:
					ci.draw_rect(Rect2(x0, y + 1.0, x1 - x0, yh - 1.0), Color(0.93, 0.52, 0.34) if hh > 0.9 else Color(0.72, 0.34, 0.26))
					tiles += 1
	ci.draw_multiline(seg, Color(0.5, 0.22, 0.2), 2.0)
	var cap: float = minf(8.0, r.size.y * 0.3)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, cap)), Color(0.97, 0.72, 0.5))
	ci.draw_line(Vector2(r.position.x, r.position.y + cap), Vector2(r.end.x, r.position.y + cap), OL, 2.0)
	ci.draw_rect(Rect2(r.position.x, r.end.y - cap * 0.5, r.size.x, cap * 0.5), Color(0.3, 0.1, 0.1, 0.25))


static func draw_hedge(ci: CanvasItem, r: Rect2, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	ci.draw_rect(Rect2(r.position + Vector2(4, 8), r.size), Color(0.05, 0.1, 0.05, 0.3))
	var br: float = clampf(minf(r.size.x, r.size.y) * 0.4, 9.0, 20.0)
	var nb: int = maxi(2, int(r.size.x / (br * 1.35)))
	var step: float = r.size.x / nb
	var body := Rect2(r.position.x, r.position.y + br * 0.3, r.size.x, r.size.y - br * 0.3)
	var dk := Color(0.12, 0.45, 0.2)
	var md := Color(0.22, 0.62, 0.26)
	var lt := Color(0.4, 0.8, 0.32)
	ci.draw_rect(body.grow(3.0), OL)
	for i in nb:
		var c := Vector2(r.position.x + (i + 0.5) * step, r.position.y + br * 0.3 + sin(t * 1.4 + i * 1.7) * 0.8)
		ci.draw_circle(c, br + 3.0, OL)
	ci.draw_rect(body, md)
	for i in nb:
		var c := Vector2(r.position.x + (i + 0.5) * step, r.position.y + br * 0.3 + sin(t * 1.4 + i * 1.7) * 0.8)
		ci.draw_circle(c, br, lt if i % 2 == 0 else Color(0.34, 0.74, 0.3))
	# darker front face
	var fh: float = minf(body.size.y * 0.4, 16.0)
	ci.draw_rect(Rect2(body.position.x, body.end.y - fh, body.size.x, fh), dk)
	ci.draw_line(Vector2(body.position.x, body.end.y - fh), Vector2(body.end.x, body.end.y - fh), Color(0.08, 0.3, 0.14), 2.0)
	# leaf specks
	var cs: float = 22.0
	var lx: int = int(r.size.x / cs)
	var ly: int = int(r.size.y / cs)
	for j in ly:
		for i in lx:
			var hh: float = _h(i + r.position.x * 0.1, j + r.position.y * 0.1)
			var p := Vector2(r.position.x + (i + hh) * cs, r.position.y + br * 0.5 + (j + _h(i, j + 3.0)) * cs * 0.8)
			if p.y > body.end.y - fh or p.y < r.position.y + 2.0:
				continue
			ci.draw_circle(p, 2.2, Color(0.55, 0.9, 0.4, 0.8) if hh > 0.5 else Color(0.1, 0.4, 0.18, 0.7))


static func draw_bush(ci: CanvasItem, c: Vector2, radius: float, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_xf = Transform2D(0.0, c)
	_shadow(ci, Vector2(radius * 0.1, radius * 0.75), Vector2(radius * 1.15, radius * 0.4))
	var items: Array = []
	for k in 7:
		var a: float = k * TAU / 7.0 + 0.3
		var wob: float = sin(t * 1.5 + k) * 0.03 * radius
		items.append([Vector2(cos(a), sin(a) * 0.9) * radius * 0.55 + Vector2(0, wob), Vector2(radius * 0.52, radius * 0.5), 0.0])
	items.append([Vector2.ZERO, Vector2(radius * 0.7, radius * 0.68), 0.0])
	_merge(ci, items, Color(0.16, 0.55, 0.24), 3.0)
	for k in 4:
		var a: float = k * TAU / 4.0 + 0.9
		_e(ci, Vector2(cos(a), sin(a)) * radius * 0.45 + Vector2(-radius * 0.1, -radius * 0.18), Vector2(radius * 0.33, radius * 0.28), Color(0.32, 0.72, 0.3), 0.0)
	for k in 6:
		var a: float = k * 1.1 + 0.4
		var rr: float = radius * (0.25 + 0.5 * _h(k, c.x * 0.01))
		var bp := Vector2(cos(a), sin(a) * 0.9) * rr
		_circ(ci, bp, maxf(3.2, radius * 0.1), Color(0.95, 0.15, 0.25), 1.5)
		_circ(ci, bp + Vector2(-1.0, -1.2), 1.1, Color(1, 0.85, 0.85), 0.0)
	_end(ci)


static func draw_puddle(ci: CanvasItem, c: Vector2, radius: float, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_xf = Transform2D(0.0, c)
	var ry: float = radius * 0.65
	_e(ci, Vector2(0, 2), Vector2(radius + 3.0, ry + 3.0), Color(0.2, 0.35, 0.6), 0.0)
	_e(ci, Vector2.ZERO, Vector2(radius, ry), Color(0.35, 0.66, 0.96), 2.5)
	_e(ci, Vector2(0, -ry * 0.08), Vector2(radius * 0.82, ry * 0.78), Color(0.55, 0.82, 1.0), 0.0)
	# ripple
	var ph: float = fposmod(t * 0.7, 1.0)
	ci.draw_set_transform_matrix(_xf * Transform2D(Vector2(1, 0), Vector2(0, 0.65), Vector2.ZERO))
	ci.draw_arc(Vector2.ZERO, radius * (0.2 + 0.6 * ph), 0.0, TAU, 28, Color(1, 1, 1, 0.7 * (1.0 - ph)), 2.0)
	# shimmer
	for k in 3:
		var a: float = t * 0.8 + k * 2.1
		ci.draw_arc(Vector2.ZERO, radius * (0.45 + 0.2 * k), a, a + 0.6, 8, Color(1, 1, 1, 0.85), 2.5)
	ci.draw_set_transform_matrix(_xf)
	var sp: float = 0.5 + 0.5 * sin(t * 5.0)
	var sc := Vector2(-radius * 0.35, -ry * 0.3)
	ci.draw_line(sc + Vector2(-4, 0) * sp, sc + Vector2(4, 0) * sp, WHITE, 2.0)
	ci.draw_line(sc + Vector2(0, -4) * sp, sc + Vector2(0, 4) * sp, WHITE, 2.0)
	_end(ci)


static func draw_fountain(ci: CanvasItem, c: Vector2, radius: float, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_xf = Transform2D(0.0, c)
	var R: float = radius
	_shadow(ci, Vector2(R * 0.1, R * 0.15), Vector2(R * 1.1, R * 1.0), 0.25)
	_circ(ci, Vector2.ZERO, R, Color(0.72, 0.74, 0.82), 3.0)
	_circ(ci, Vector2.ZERO, R * 0.88, Color(0.86, 0.88, 0.95), 2.0)
	_circ(ci, Vector2.ZERO, R * 0.76, Color(0.3, 0.68, 0.98), 2.0)
	ci.draw_set_transform_matrix(_xf)
	for k in 3:
		var ph: float = fposmod(t * 0.45 + k / 3.0, 1.0)
		ci.draw_arc(Vector2.ZERO, R * (0.2 + 0.52 * ph), 0.0, TAU, 32, Color(1, 1, 1, 0.8 * (1.0 - ph)), 2.5)
	for k in 6:
		var a: float = k * TAU / 6.0 + t * 0.3
		ci.draw_arc(Vector2.ZERO, R * 0.62, a, a + 0.5, 8, Color(1, 1, 1, 0.6), 2.5)
	# pillar, bowl, spout
	var top := Vector2(0, -R * 0.5)
	_circ(ci, Vector2(0, -R * 0.1), R * 0.28, Color(0.7, 0.72, 0.8), 2.5)
	_circ(ci, Vector2(0, -R * 0.1), R * 0.2, Color(0.3, 0.68, 0.98), 1.5)
	_limb(ci, Vector2(0, -R * 0.12), top, R * 0.14, Color(0.78, 0.8, 0.88), 2.5)
	_circ(ci, top, R * 0.2, Color(0.86, 0.88, 0.95), 2.5)
	_circ(ci, top, R * 0.13, Color(0.3, 0.68, 0.98), 1.5)
	_limb(ci, top, top + Vector2(0, -R * 0.38 - sin(t * 6.0) * 2.0), R * 0.07, Color(0.7, 0.9, 1.0), 0.0)
	for k in 12:
		var ph: float = fposmod(t * 0.9 + k / 12.0, 1.0)
		var a: float = k * TAU / 12.0
		var dist: float = R * 0.42 * ph
		var pos: Vector2 = top + Vector2(cos(a) * dist, sin(a) * dist * 0.5 - sin(ph * PI) * R * 0.45 + ph * ph * R * 0.5)
		ci.draw_circle(pos, 3.0, Color(0.65, 0.88, 1.0))
		ci.draw_circle(pos + Vector2(-0.8, -0.8), 1.1, WHITE)
	_end(ci)


# ---------------------------------------------------------------- buildings

static func _granny_face(ci: CanvasItem, c: Vector2, kind: int, t: float, idx: int) -> void:
	var hair := Color(0.85, 0.85, 0.92)
	if kind == 0:
		_circ(ci, c + Vector2(0, -9), 5.0, hair, 1.8)
		_circ(ci, c + Vector2(0, 1), 12.5, hair, 1.8)
	elif kind == 1:
		_circ(ci, c + Vector2(-11, 2), 4.5, hair, 1.5)
		_circ(ci, c + Vector2(11, 2), 4.5, hair, 1.5)
	_circ(ci, c + Vector2(0, 2), 10.5, SKIN, 1.8)
	if kind == 0:
		_e(ci, c + Vector2(0, -6), Vector2(10.5, 5.5), hair, 0.0)
	for sx in [-1.0, 1.0]:
		_circ(ci, c + Vector2(sx * 4.2, 1), 3.4, Color(0.95, 0.98, 1.0), 1.3)
		_circ(ci, c + Vector2(sx * 4.2 + 0.4, 1.4), 1.2, OL, 0.0)
		_circ(ci, c + Vector2(sx * 7.0, 6.5), 2.2, Color(1, 0.55, 0.6, 0.7), 0.0)
	if kind == 1:
		_e(ci, c + Vector2(0, 7.5), Vector2(7.5, 3.0), WHITE, 1.4)
	else:
		_arc(ci, c + Vector2(0, 5.5), 4.0, 0.3, PI - 0.3, 1.6, OL)
	# body
	_e(ci, c + Vector2(0, 22), Vector2(15, 9), Color(0.7, 0.55, 0.9) if kind == 0 else Color(0.5, 0.75, 0.55), 2.0)
	# waving hand
	var w: float = sin(t * 7.0 + idx * 2.0)
	_circ(ci, c + Vector2(18 + w * 3.0, 6 - absf(w) * 3.0), 3.8, SKIN, 1.6)


static func _window(ci: CanvasItem, c: Vector2, idx: int, t: float) -> void:
	var w: float = 52.0
	var h: float = 58.0
	var kind: int = idx % 4
	_rr(ci, Rect2(c.x - w * 0.5 - 4, c.y - h * 0.5 - 4, w + 8, h + 8), 6.0, Color(0.96, 0.96, 1.0), 2.5)
	var glass := Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(glass, Color(1.0, 0.92, 0.6) if idx % 3 != 1 else Color(0.6, 0.82, 0.98))
	if kind == 2:
		# sleeping cat
		_e(ci, c + Vector2(0, 14), Vector2(16, 9), Color(1.0, 0.6, 0.25), 2.0)
		_circ(ci, c + Vector2(6, 6), 8.0, Color(1.0, 0.6, 0.25), 2.0)
		_poly(ci, PackedVector2Array([c + Vector2(0, 2), c + Vector2(2, -6), c + Vector2(6, 0)]), Color(1.0, 0.6, 0.25), 1.5)
		_poly(ci, PackedVector2Array([c + Vector2(7, 0), c + Vector2(11, -7), c + Vector2(13, 1)]), Color(1.0, 0.6, 0.25), 1.5)
		_arc(ci, c + Vector2(4, 6), 2.0, 0.2, PI - 0.2, 1.4, OL)
		_arc(ci, c + Vector2(9, 6), 2.0, 0.2, PI - 0.2, 1.4, OL)
	else:
		_granny_face(ci, c + Vector2(-2, -6), kind, t, idx)
	# curtains
	_poly(ci, PackedVector2Array([glass.position, glass.position + Vector2(15, 0), glass.position + Vector2(5, 26), glass.position + Vector2(0, 40)]), Color(0.95, 0.4, 0.5), 1.8)
	var re := Vector2(glass.end.x, glass.position.y)
	_poly(ci, PackedVector2Array([re, re + Vector2(-15, 0), re + Vector2(-5, 26), re + Vector2(0, 40)]), Color(0.95, 0.4, 0.5), 1.8)
	_rect(ci, Rect2(c.x - w * 0.5 - 7, c.y + h * 0.5 - 2, w + 14, 8), Color(0.6, 0.38, 0.22), 2.0)
	if idx % 2 == 0:
		_circ(ci, Vector2(c.x - 16, c.y + h * 0.5 - 6), 4.0, Color(1, 0.3, 0.4), 1.5)
	else:
		_circ(ci, Vector2(c.x + 16, c.y + h * 0.5 - 6), 4.0, Color(1, 0.55, 0.9), 1.5)


static func draw_building(ci: CanvasItem, r: Rect2, door: Rect2, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fw: float = r.size.x * 0.38
	var roof := Rect2(r.position, Vector2(r.size.x - fw, r.size.y))
	var fac := Rect2(Vector2(roof.end.x, r.position.y), Vector2(fw, r.size.y))
	_rect(ci, Rect2(r.position + Vector2(14, 10), r.size), Color(0.05, 0.1, 0.05, 0.28), 0.0)
	# facade
	_rect(ci, fac, Color(1.0, 0.91, 0.7), 3.0)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(Rect2(fac.position.x, fac.position.y, 12, fac.size.y), Color(0.3, 0.15, 0.1, 0.2))
	# roof
	_rect(ci, roof, Color(0.86, 0.34, 0.27), 3.0)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(Rect2(roof.position, Vector2(roof.size.x * 0.5, roof.size.y)), Color(0.74, 0.26, 0.22))
	var seg := PackedVector2Array()
	var j: int = 0
	var y: float = roof.position.y + 20.0
	while y < roof.end.y:
		seg.append(Vector2(roof.position.x, y))
		seg.append(Vector2(roof.end.x, y))
		var xo: float = 11.0 if j % 2 == 1 else 0.0
		var x: float = roof.position.x + xo
		while x < roof.end.x:
			if x > roof.position.x + 1.0:
				seg.append(Vector2(x, y - 20.0))
				seg.append(Vector2(x, y))
			x += 22.0
		y += 20.0
		j += 1
	ci.draw_multiline(seg, Color(0.5, 0.16, 0.16, 0.7), 1.6)
	ci.draw_line(Vector2(roof.position.x + roof.size.x * 0.5, roof.position.y), Vector2(roof.position.x + roof.size.x * 0.5, roof.end.y), Color(1.0, 0.62, 0.45), 6.0)
	# chimney + smoke
	var ch := Vector2(roof.position.x + 28.0, roof.position.y + 30.0)
	_rect(ci, Rect2(ch.x - 13, ch.y - 13, 26, 26), Color(0.8, 0.4, 0.3), 2.5)
	_rect(ci, Rect2(ch.x - 16, ch.y - 16, 32, 8), Color(0.6, 0.3, 0.25), 2.5)
	for k in 3:
		var ph: float = fposmod(t * 0.35 + k / 3.0, 1.0)
		_circ(ci, ch + Vector2(sin(ph * 6.0 + k) * 5.0 - ph * 6.0, -16.0 - ph * 40.0), 5.0 + ph * 7.0, Color(0.95, 0.95, 0.98, 0.8 * (1.0 - ph)), 0.0)
	# sign board lying on the roof, reads top-to-bottom
	var l1 := "ДОМ ПРЕСТАРЕЛЫХ"
	var l2 := "«ЗАКАТ»"
	var bl: float = minf(r.size.y - 100.0, 470.0)
	var bh: float = minf(roof.size.x - 36.0, 92.0)
	var center: Vector2 = roof.get_center() + Vector2(0, 20)
	var xf0: Transform2D = _xf
	_xf = xf0 * Transform2D(PI * 0.5, center)
	_rr(ci, Rect2(-bl * 0.5, -bh * 0.5, bl, bh), 10.0, Color(1.0, 0.86, 0.3), 3.5)
	_rr(ci, Rect2(-bl * 0.5 + 7, -bh * 0.5 + 7, bl - 14, bh - 14), 6.0, Color(0.98, 0.97, 0.88), 2.0)
	var nb: int = int(bl / 26.0)
	for i in nb:
		var bx: float = -bl * 0.5 + 14.0 + i * (bl - 28.0) / (nb - 1)
		var on: bool = sin(t * 5.0 + i * 1.3) > 0.0
		var bc := Color(1.0, 0.45, 0.2) if on else Color(1.0, 0.95, 0.6)
		_circ(ci, Vector2(bx, -bh * 0.5 + 0.5), 3.0, bc, 1.5)
		_circ(ci, Vector2(bx, bh * 0.5 - 0.5), 3.0, bc, 1.5)
	_txt(ci, Vector2(0, -bh * 0.17), l1, _fit(l1, bl - 40.0, 27), Color(0.75, 0.15, 0.2), Color(1, 1, 1), 0)
	_txt(ci, Vector2(0, bh * 0.2), l2, _fit(l2, bl - 40.0, 32), Color(0.25, 0.12, 0.45), Color(1, 1, 1), 0)
	_xf = xf0
	# windows
	var n: int = maxi(2, int((r.size.y - 40.0) / 96.0))
	var step: float = (r.size.y - 40.0) / n
	var dc: float = door.get_center().y
	var wx: float = fac.position.x + (fac.size.x - 10.0) * 0.5 - 2.0
	for i in n:
		var wy: float = r.position.y + 20.0 + step * (i + 0.5)
		if absf(wy - dc) < door.size.y * 0.5 + 29.0 + 12.0:
			continue
		_window(ci, Vector2(wx, wy), i, t)
	# door
	var dr: Rect2 = door
	_rect(ci, Rect2(dr.position.x - 6, dr.end.y - 4, dr.size.x + 12, 10), Color(0.75, 0.75, 0.8), 2.5)
	_rr(ci, dr.grow(5.0), 12.0, Color(0.95, 0.95, 1.0), 2.5)
	_rr(ci, dr, 11.0, Color(0.62, 0.36, 0.2), 2.5)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_line(Vector2(dr.get_center().x, dr.position.y + 8), Vector2(dr.get_center().x, dr.end.y), Color(0.35, 0.18, 0.1), 2.0)
	_circ(ci, Vector2(dr.position.x + dr.size.x * 0.5, dr.position.y + dr.size.y * 0.3), dr.size.x * 0.22, Color(0.75, 0.9, 1.0), 2.0)
	_circ(ci, Vector2(dr.end.x - 6, dr.position.y + dr.size.y * 0.6), 3.0, Color(1.0, 0.85, 0.2), 1.5)
	var cx: float = dr.position.x - 8.0
	var awn := PackedVector2Array([Vector2(cx, dr.position.y - 2), Vector2(cx + dr.size.x + 16, dr.position.y - 2), Vector2(cx + dr.size.x + 22, dr.position.y - 14), Vector2(cx - 6, dr.position.y - 14)])
	_poly(ci, awn, Color(0.95, 0.3, 0.3), 2.5)
	_end(ci)


static func draw_entrance_zone(ci: CanvasItem, r: Rect2, progress: float, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pulse: float = 0.5 + 0.5 * sin(t * 4.0)
	_rr(ci, r, 14.0, Color(0.3, 0.6, 1.0, 0.28 + 0.1 * pulse), 0.0)
	var pr: float = clampf(progress, 0.0, 1.0)
	if pr > 0.0:
		var fh: float = r.size.y * pr
		ci.draw_rect(Rect2(r.position.x + 3, r.end.y - fh, r.size.x - 6, fh - 3.0 if fh > 3.0 else 0.0), Color(0.3, 1.0, 0.6, 0.38))
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(r.grow(-2.0), Color(0.2, 0.45, 0.95, 0.9), false, 5.0)
	_dashed_rect(ci, r.grow(-2.0), Color(1, 1, 1, 0.55 + 0.4 * pulse), 3.0, 14.0, 10.0, t * 30.0)
	var size: int = int(clampf(r.size.y * 0.32, 14.0, 30.0))
	var c: Vector2 = r.get_center()
	_txt(ci, c + Vector2(0, -r.size.y * 0.06), "ВХОД", _fit("ВХОД", r.size.x - 16.0, size), Color(1, 1, 1), Color(0.1, 0.25, 0.7), 6)
	# progress bar
	var bw: float = minf(r.size.x, 130.0)
	var bar := Rect2(c.x - bw * 0.5, r.position.y - 18.0, bw, 12.0)
	_rr(ci, bar, 6.0, Color(0.15, 0.2, 0.35), 2.5)
	if pr > 0.0:
		_rr(ci, Rect2(bar.position + Vector2(1.5, 1.5), Vector2(maxf(8.0, (bw - 3.0) * pr), bar.size.y - 3.0)), 4.0, Color(0.3, 1.0, 0.45).lerp(Color(1.0, 0.9, 0.2), 1.0 - pr), 0.0)
	_end(ci)


static func draw_kebab_stand(ci: CanvasItem, r: Rect2, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var w: float = r.size.x
	var h: float = r.size.y
	var x0: float = r.position.x
	var y0: float = r.position.y
	_e(ci, Vector2(x0 + w * 0.5 + 6, y0 + h - 2), Vector2(w * 0.58, 17), Color(0.05, 0.1, 0.05, 0.3), 0.0)
	# walls
	var body := Rect2(x0 + 8, y0 + h * 0.18, w - 16, h * 0.78)
	_rect(ci, body, Color(1.0, 0.93, 0.78), 3.0)
	# window
	var win := Rect2(x0 + w * 0.14, y0 + h * 0.4, w * 0.72, h * 0.27)
	_rect(ci, win, Color(0.36, 0.14, 0.1), 3.0)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(Rect2(win.position + Vector2(0, 0), Vector2(win.size.x, win.size.y * 0.5)), Color(0.5, 0.2, 0.12))
	# spit
	var sx: float = win.get_center().x + w * 0.14
	_limb(ci, Vector2(sx, win.position.y - 2), Vector2(sx, win.end.y), 4.0, Color(0.7, 0.7, 0.75), 2.0)
	var flick: float = 0.5 + 0.5 * sin(t * 14.0)
	for sd in [-1.0, 1.0]:
		_line(ci, Vector2(sx + sd * 30.0, win.position.y + 6), Vector2(sx + sd * 30.0, win.end.y - 6), 5.0, Color(1.0, 0.45 + 0.3 * flick, 0.1))
	var nl: int = 9
	var ly0: float = win.end.y - 8.0
	var span: float = win.size.y - 12.0
	for k in nl:
		var f: float = k / (nl - 1.0)
		var rx: float = lerpf(11.0, 21.0, f)
		var yy: float = ly0 - f * span
		var on: bool = sin(t * 3.0 + k * 0.9) > 0.0
		_e(ci, Vector2(sx, yy), Vector2(rx, 5.0), Color(0.62, 0.32, 0.15) if on else Color(0.8, 0.5, 0.26), 2.0)
		var gx: float = cos(t * 3.0 + k * 1.7) * rx * 0.7
		_e(ci, Vector2(sx + gx, yy + 1.0), Vector2(3.0, 1.8), Color(1.0, 0.75, 0.4), 0.0)
	_circ(ci, Vector2(sx, win.position.y + 1), 4.0, Color(0.75, 0.75, 0.8), 2.0)
	# vendor
	var vc := Vector2(win.position.x + win.size.x * 0.24, win.position.y + win.size.y * 0.62 + sin(t * 3.0) * 1.2)
	_e(ci, vc + Vector2(0, 18), Vector2(20, 12), Color(1, 1, 1), 2.5)
	_circ(ci, vc, 14.0, SKIN, 2.5)
	var hat: Array = [[vc + Vector2(-9, -16), Vector2(9, 9), 0.0], [vc + Vector2(9, -16), Vector2(9, 9), 0.0], [vc + Vector2(0, -22), Vector2(11, 11), 0.0], [vc + Vector2(0, -10), Vector2(16, 6), 0.0]]
	_merge(ci, hat, Color(1, 1, 1), 2.5)
	for sd in [-1.0, 1.0]:
		_circ(ci, vc + Vector2(sd * 5.5, -3), 3.6, Color(1, 1, 1), 1.6)
		_circ(ci, vc + Vector2(sd * 5.5 + 0.8, -2.6), 1.5, OL, 0.0)
		_limb(ci, vc + Vector2(sd * 9.0, -8.5), vc + Vector2(sd * 2.5, -7.0 - sd * 1.0 * 0.0), 2.6, Color(0.25, 0.15, 0.12), 1.0)
	_e(ci, vc + Vector2(-6, 5), Vector2(8, 3.6), Color(0.25, 0.15, 0.12), 1.6, 0.25)
	_e(ci, vc + Vector2(6, 5), Vector2(8, 3.6), Color(0.25, 0.15, 0.12), 1.6, -0.25)
	_circ(ci, vc + Vector2(0, 1), 3.2, Color(1, 0.6, 0.55), 1.5)
	# awning
	var ay: float = y0 + h * 0.2
	var ah: float = h * 0.2
	var ns: int = 8
	var sw: float = (w + 8.0) / ns
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(Rect2(x0 - 4 - 3, ay - 3, w + 14, ah + 6), _k(OL))
	for i in ns:
		ci.draw_circle(Vector2(x0 - 4 + (i + 0.5) * sw, ay + ah), sw * 0.5 + 3.0, _k(OL))
	for i in ns:
		var cc := Color(0.96, 0.22, 0.2) if i % 2 == 0 else Color(1, 1, 1)
		ci.draw_rect(Rect2(x0 - 4 + i * sw, ay, sw, ah), _k(cc))
		ci.draw_circle(Vector2(x0 - 4 + (i + 0.5) * sw, ay + ah), sw * 0.5, _k(cc))
	# counter
	var cnt := Rect2(x0 + 2, y0 + h * 0.68, w - 4, h * 0.26)
	_rect(ci, cnt, Color(0.78, 0.5, 0.26), 3.0)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(Rect2(cnt.position, Vector2(cnt.size.x, 9)), _k(Color(0.95, 0.75, 0.45)))
	ci.draw_line(Vector2(cnt.position.x, cnt.position.y + 9), Vector2(cnt.end.x, cnt.position.y + 9), _k(OL), 2.0)
	for i in range(1, 5):
		ci.draw_line(Vector2(cnt.position.x + i * cnt.size.x / 5.0, cnt.position.y + 9), Vector2(cnt.position.x + i * cnt.size.x / 5.0, cnt.end.y), _k(Color(0.45, 0.28, 0.14)), 2.0)
	_circ(ci, Vector2(cnt.position.x + 24, cnt.position.y - 2), 7.0, Color(0.95, 0.2, 0.2), 2.0)
	_circ(ci, Vector2(cnt.position.x + 40, cnt.position.y - 1), 6.0, Color(0.5, 0.85, 0.25), 2.0)
	_rr(ci, Rect2(cnt.end.x - 40, cnt.position.y - 14, 18, 18), 4.0, Color(1, 1, 1), 2.0)
	_rect(ci, Rect2(cnt.end.x - 40, cnt.position.y - 6, 18, 4), Color(1, 0.3, 0.3), 0.0)
	# sign
	var sg := Rect2(x0 + w * 0.06, y0, w * 0.88, h * 0.17)
	_rr(ci, sg, 9.0, Color(1.0, 0.85, 0.2), 3.0)
	_rr(ci, sg.grow(-5.0), 6.0, Color(0.85, 0.15, 0.15), 0.0)
	_txt(ci, sg.get_center(), "ШАУРМА", _fit("ШАУРМА", sg.size.x - 24.0, 28), Color(1, 0.95, 0.5), OL, 4)
	for i in 6:
		var on: bool = sin(t * 6.0 + i) > 0.0
		_circ(ci, Vector2(sg.position.x + 8 + i * (sg.size.x - 16) / 5.0, sg.position.y - 1), 2.6, Color(1, 1, 0.5) if on else Color(1, 0.6, 0.2), 1.2)
	# steam
	for k in 5:
		var ph: float = fposmod(t * 0.45 + k * 0.2, 1.0)
		var sp := Vector2(sx - 6.0 + sin(ph * 7.0 + k * 2.0) * 7.0 + ph * 18.0, win.position.y - 4.0 - ph * 52.0)
		_circ(ci, sp, 4.0 + ph * 7.0, Color(1, 1, 1, 0.75 * (1.0 - ph)), 0.0)
	_end(ci)


static func draw_order_zone(ci: CanvasItem, r: Rect2, progress: float, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pulse: float = 0.5 + 0.5 * sin(t * 4.0)
	_rr(ci, r, 14.0, Color(1.0, 0.6, 0.15, 0.26 + 0.08 * pulse), 0.0)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(r.grow(-2.0), Color(1.0, 0.5, 0.05, 0.95), false, 5.0)
	_dashed_rect(ci, r.grow(-2.0), Color(1, 1, 0.8, 0.5 + 0.4 * pulse), 3.0, 14.0, 10.0, -t * 30.0)
	var pr: float = clampf(progress, 0.0, 1.0)
	var c: Vector2 = r.get_center()
	var R: float = minf(r.size.x, r.size.y) * 0.27
	var press: float = 3.0 if pr > 0.0 else 9.0
	var shake := Vector2(sin(t * 40.0) * 0.8, 0.0) if pr > 0.0 else Vector2.ZERO
	_e(ci, c + Vector2(4, 12), Vector2(R * 1.35, R * 1.0), Color(0.05, 0.05, 0.05, 0.3), 0.0)
	_e(ci, c, Vector2(R * 1.3, R * 1.02), Color(0.62, 0.64, 0.7), 3.0)
	for k in 12:
		var a: float = k * TAU / 12.0
		ci.draw_set_transform_matrix(_xf * Transform2D(Vector2(1, 0), Vector2(0, 0.8), c))
		ci.draw_arc(Vector2.ZERO, R * 1.17, a, a + TAU / 24.0, 6, _k(Color(1, 0.85, 0.1) if k % 2 == 0 else OL), 5.0)
	var bc: Vector2 = c + shake
	# side, then top
	_e(ci, bc + Vector2(0, press), Vector2(R, R * 0.8), Color(0.62, 0.08, 0.1), 2.8, 0.0, 1)
	_e(ci, bc, Vector2(R, R * 0.8), Color(0.62, 0.08, 0.1), 2.8, 0.0, 1)
	_rect(ci, Rect2(bc.x - R - 2.8, bc.y, R * 2.0 + 5.6, press), Color(0.62, 0.08, 0.1), 0.0)
	_e(ci, bc + Vector2(0, press), Vector2(R, R * 0.8), Color(0.62, 0.08, 0.1), 0.0, 0.0, 2)
	_rect(ci, Rect2(bc.x - R, bc.y, R * 2.0, press), Color(0.62, 0.08, 0.1), 0.0)
	_e(ci, bc, Vector2(R, R * 0.8), Color(1.0, 0.18, 0.2), 0.0, 0.0, 2)
	_e(ci, bc + Vector2(-R * 0.25, -R * 0.28), Vector2(R * 0.45, R * 0.2), Color(1, 0.7, 0.7, 0.8), 0.0, -0.3)
	_txt(ci, bc + Vector2(0, R * 0.08), "ЗАКАЗ", _fit("ЗАКАЗ", R * 1.75, 22), Color(1, 1, 1), Color(0.5, 0.0, 0.05), 4)
	# progress ring
	var rr: float = minf(r.size.x, r.size.y) * 0.47
	ci.draw_set_transform_matrix(_xf)
	ci.draw_arc(c, rr, 0.0, TAU, 40, _k(OL), 13.0)
	ci.draw_arc(c, rr, 0.0, TAU, 40, _k(Color(0.62, 0.45, 0.22)), 8.0)
	if pr > 0.0:
		ci.draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * pr, 48, _k(Color(1.0, 0.9, 0.2).lerp(Color(0.4, 1.0, 0.4), pr)), 9.0)
		for k in 3:
			var ph: float = fposmod(t * 0.9 + k / 3.0, 1.0)
			var cp := Vector2(c.x + (k - 1) * R * 0.7, c.y - R * 0.6 - ph * R)
			_circ(ci, cp, 6.0, Color(1.0, 0.85, 0.2, 1.0 - ph), 1.5)
			_txt(ci, cp, "$", 9, Color(0.6, 0.35, 0.0, 1.0 - ph), OL, 0)
	_end(ci)


# ---------------------------------------------------------------- props

static func draw_bench(ci: CanvasItem, r: Rect2, lifted: bool) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var horiz: bool = r.size.x > r.size.y
	var L: float = maxf(r.size.x, r.size.y)
	var W: float = minf(r.size.x, r.size.y)
	var c: Vector2 = r.get_center()
	if lifted:
		var sh: Rect2 = Rect2(r.position + Vector2(10, 24), r.size).grow(-3.0)
		_rr(ci, sh, 8.0, Color(0.05, 0.1, 0.05, 0.22), 0.0)
	else:
		_rr(ci, Rect2(r.position + Vector2(3, 6), r.size), 6.0, Color(0.05, 0.1, 0.05, 0.28), 0.0)
	var rot: float = 0.0 if horiz else -PI * 0.5
	var lift: float = -14.0 if lifted else 0.0
	_xf = Transform2D(rot + (0.07 if lifted else 0.0), c + Vector2(0, lift))
	var metal := Color(0.3, 0.3, 0.38)
	var wood := Color(0.82, 0.52, 0.26)
	var wood2 := Color(0.9, 0.62, 0.34)
	var wd: Color = Color(0.62, 0.38, 0.18)
	# legs
	for sd in [-1.0, 1.0]:
		var lx: float = sd * (L * 0.5 - 9.0)
		_rect(ci, Rect2(lx - 3.5, -W * 0.5 + 2, 7, W - 2), metal, 2.0)
		_rect(ci, Rect2(lx - 5.5, W * 0.5 - 4, 11, 5), metal, 2.0)
	var sl: float = W * 0.24
	# backrest
	_rr(ci, Rect2(-L * 0.5, -W * 0.5, L, sl), 3.0, wood2, 2.0)
	_rr(ci, Rect2(-L * 0.5 + 2, -W * 0.5 + sl + 2, L - 4, sl), 3.0, wood, 2.0)
	# seat
	_rr(ci, Rect2(-L * 0.5, W * 0.0 + 1, L, sl), 3.0, wood2, 2.0)
	_rr(ci, Rect2(-L * 0.5, W * 0.0 + sl + 3, L, sl + 1), 3.0, wd, 2.0)
	_rr(ci, Rect2(-L * 0.5, W * 0.0 + 1, L, sl), 3.0, wood2, 2.0)
	for sd in [-1.0, 1.0]:
		_circ(ci, Vector2(sd * (L * 0.5 - 6.0), W * 0.0 + 1 + sl * 0.5), 1.5, Color(0.35, 0.35, 0.4), 0.0)
		_circ(ci, Vector2(sd * (L * 0.5 - 6.0), -W * 0.5 + sl * 0.5), 1.5, Color(0.35, 0.35, 0.4), 0.0)
	_end(ci)


static func _banana_local(ci: CanvasItem, scale: float) -> void:
	var yl := Color(1.0, 0.9, 0.2)
	for k in 3:
		var a: float = k * TAU / 3.0 + 0.4
		var dir := Vector2(cos(a), sin(a))
		_e(ci, dir * 6.5 * scale, Vector2(7.5, 3.8) * scale, yl, 2.0 * scale, a)
		_e(ci, dir * 6.5 * scale, Vector2(4.2, 1.6) * scale, Color(1.0, 0.97, 0.7), 0.0, a)
		_e(ci, dir * 13.0 * scale, Vector2(2.0, 2.0) * scale, Color(0.45, 0.28, 0.1), 0.0)
	_circ(ci, Vector2.ZERO, 4.0 * scale, Color(1.0, 0.82, 0.15), 2.0 * scale)
	_circ(ci, Vector2(-1, -1) * scale, 1.3 * scale, Color(0.45, 0.28, 0.1), 0.0)


static func draw_banana(ci: CanvasItem, p: Vector2, rot: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_xf = Transform2D(0.0, p)
	_shadow(ci, Vector2(1, 5), Vector2(14, 6), 0.25)
	_xf = Transform2D(rot, p)
	_banana_local(ci, 1.0)
	_end(ci)


static func draw_banana_cart(ci: CanvasItem, p: Vector2, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_xf = Transform2D(0.0, p)
	_shadow(ci, Vector2(3, 24), Vector2(42, 9), 0.3)
	# poles + canopy back
	for sd in [-1.0, 1.0]:
		_limb(ci, Vector2(sd * 30.0, -4), Vector2(sd * 30.0, -32), 3.5, Color(0.55, 0.35, 0.18), 1.8)
	# bananas pile
	_e(ci, Vector2(0, -4), Vector2(31, 11), Color(0.78, 0.5, 0.26), 2.5)
	var cfg: Array = [[-16.0, -6.0, 0.3], [-4.0, -9.0, -0.2], [9.0, -6.0, 0.15], [20.0, -4.0, -0.35], [0.0, -2.0, 0.1], [-12.0, -1.0, -0.15], [12.0, -1.0, 0.25]]
	for cf in cfg:
		var bc := Vector2(cf[0], cf[1])
		var rt: float = cf[2]
		_xf = Transform2D(0.0, p) * Transform2D(rt, bc)
		_arc(ci, Vector2(0, 0), 8.0, 0.35, PI - 0.35, 8.0, OL)
		_arc(ci, Vector2(0, 0), 8.0, 0.45, PI - 0.45, 4.5, Color(1.0, 0.9, 0.2))
		_circ(ci, Vector2(7.5, 3), 1.6, Color(0.4, 0.25, 0.1), 0.0)
		_circ(ci, Vector2(-7.5, 3), 1.6, Color(0.4, 0.25, 0.1), 0.0)
	_xf = Transform2D(0.0, p)
	# box
	_rr(ci, Rect2(-34, 2, 68, 22), 5.0, Color(0.74, 0.46, 0.22), 3.0)
	_rr(ci, Rect2(-28, 6, 56, 14), 4.0, Color(1.0, 0.95, 0.75), 2.0)
	_txt(ci, Vector2(0, 13), "БАНАНЫ", _fit("БАНАНЫ", 50.0, 12), Color(0.8, 0.45, 0.0), OL, 0)
	# wheels
	for sd in [-1.0, 1.0]:
		_circ(ci, Vector2(sd * 22.0, 25), 7.0, Color(0.3, 0.3, 0.35), 2.5)
		_circ(ci, Vector2(sd * 22.0, 25), 2.5, Color(0.8, 0.8, 0.85), 0.0)
	# canopy
	var bob: float = sin(t * 2.0) * 1.0
	var ns: int = 6
	var cw: float = 76.0 / ns
	ci.draw_set_transform_matrix(_xf)
	ci.draw_rect(Rect2(-38 - 3, -42 - 3, 76 + 6, 14 + 6), _k(OL))
	for i in ns:
		ci.draw_circle(Vector2(-38 + (i + 0.5) * cw, -28 + bob), cw * 0.5 + 3.0, _k(OL))
	for i in ns:
		var cc := Color(1.0, 0.85, 0.15) if i % 2 == 0 else Color(1, 1, 1)
		ci.draw_rect(Rect2(-38 + i * cw, -42, cw, 14), _k(cc))
		ci.draw_circle(Vector2(-38 + (i + 0.5) * cw, -28 + bob), cw * 0.5, _k(cc))
	_end(ci)


static func draw_statue(ci: CanvasItem, p: Vector2, pose: int) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_stone = true
	_xf = Transform2D(0.0, p)
	_shadow(ci, Vector2(3, 14), Vector2(30, 8), 0.3)
	_rect(ci, Rect2(-22, -5, 44, 20), Color(0.62, 0.64, 0.7), 2.5)
	ci.draw_set_transform_matrix(_xf)
	ci.draw_line(Vector2(-22, 6), Vector2(22, 6), _k(Color(0.35, 0.35, 0.4)), 1.5)
	_rect(ci, Rect2(-8, 5, 16, 6), Color(0.38, 0.4, 0.46), 1.5)
	_rr(ci, Rect2(-25, -16, 50, 12), 4.0, Color(0.84, 0.86, 0.9), 2.5)
	var s := {"facing": Vector2.RIGHT, "vel": Vector2.ZERO, "t": 0.0, "state": "statue", "pose": pose, "stone": true, "ghost": false, "has_banana": false, "swing": 0.0}
	_grandpa(ci, p + Vector2(0, -11), s, false)


# ---------------------------------------------------------------- grandpa

static func _brow(ci: CanvasItem, lens: Vector2, left: bool, y_out: float, y_in: float) -> void:
	var o: float = -4.2 if left else 4.2
	var i: float = 3.6 if left else -3.6
	_limb(ci, lens + Vector2(o, y_out), lens + Vector2(i, y_in), 2.8, WHITE, 1.5)


static func _grandpa_head(ci: CanvasItem, hc: Vector2, back: bool, expr: String, mouth: float, tongue: bool, look: Vector2, t: float) -> void:
	_e(ci, hc + Vector2(-14, 2), Vector2(3.4, 4.8), SKIN, 2.0)
	_e(ci, hc + Vector2(14, 2), Vector2(3.4, 4.8), SKIN, 2.0)
	_e(ci, hc, Vector2(14.5, 15), SKIN, 2.8)
	_e(ci, hc + Vector2(-4, -9.5), Vector2(5.0, 2.4), Color(1, 0.96, 0.9, 0.9), 0.0, -0.3)
	for sd in [-1.0, 1.0]:
		var tuft: Array = [
			[hc + Vector2(sd * 14.0, -6.5), Vector2(3.6, 3.4), 0.0],
			[hc + Vector2(sd * 15.0, -2.0), Vector2(3.8, 3.4), 0.0],
			[hc + Vector2(sd * 14.0, 2.0), Vector2(3.2, 3.0), 0.0]]
		_merge(ci, tuft, WHITE, 2.0)
	if back:
		_e(ci, hc + Vector2(0, 9), Vector2(10, 5), Color(0.96, 0.72, 0.6), 0.0)
		return
	var f: Vector2 = hc + Vector2(2.5, 0)
	for sd in [-1.0, 1.0]:
		_e(ci, f + Vector2(sd * 10.5, 5.5), Vector2(3.0, 2.0), Color(1, 0.5, 0.55, 0.6), 0.0)
	var rl: float = 6.2 if expr == "wide" else 5.3
	var l1: Vector2 = f + Vector2(-5.8, -2.0)
	var l2: Vector2 = f + Vector2(5.8, -2.0)
	_line(ci, l1 + Vector2(-rl, 0), hc + Vector2(-14, -1), 2.0, OL)
	_line(ci, l2 + Vector2(rl, 0), hc + Vector2(14, -1), 2.0, OL)
	_line(ci, l1, l2, 2.4, OL)
	_circ(ci, l1, rl, Color(0.93, 0.98, 1.0), 2.2)
	_circ(ci, l2, rl, Color(0.93, 0.98, 1.0), 2.2)
	for lens in [l1, l2]:
		var lv: Vector2 = lens
		match expr:
			"spiral":
				_spiral(ci, lv, rl - 1.0, t * 8.0, 1.5, OL)
			"xx":
				_line(ci, lv + Vector2(-3, -3), lv + Vector2(3, 3), 2.0, OL)
				_line(ci, lv + Vector2(3, -3), lv + Vector2(-3, 3), 2.0, OL)
			"smug":
				_arc(ci, lv + Vector2(0, 1.5), 3.2, PI + 0.4, TAU - 0.4, 2.0, OL)
			"wide":
				_circ(ci, lv, 1.3, OL, 0.0)
			"angry":
				_circ(ci, lv + look * 1.0, 1.8, OL, 0.0)
			_:
				_circ(ci, lv + look * 1.6, 2.1, OL, 0.0)
				_circ(ci, lv + look * 1.6 + Vector2(-0.7, -0.8), 0.7, Color(1, 1, 1), 0.0)
	match expr:
		"wide":
			_brow(ci, l1, true, -9.5, -10.5)
			_brow(ci, l2, false, -9.5, -10.5)
		"angry":
			_brow(ci, l1, true, -9.5, -4.5)
			_brow(ci, l2, false, -9.5, -4.5)
		"smug":
			_brow(ci, l1, true, -8.5, -9.5)
			_brow(ci, l2, false, -8.5, -9.5)
		"spiral", "xx":
			_brow(ci, l1, true, -7.5, -8.5)
			_brow(ci, l2, false, -8.5, -7.5)
		_:
			_brow(ci, l1, true, -8.5, -6.5)
			_brow(ci, l2, false, -8.5, -6.5)
	var my: float = 9.5 - 2.8 * mouth
	if mouth > 0.0:
		_e(ci, f + Vector2(0, 10.5), Vector2(4.4 * mouth, 4.8 * mouth), Color(0.55, 0.06, 0.1), 2.0)
		_e(ci, f + Vector2(0, 12.5), Vector2(2.6 * mouth, 1.8 * mouth), Color(1, 0.45, 0.5), 0.0)
	if tongue:
		_e(ci, f + Vector2(1.5, 14.5), Vector2(2.8, 4.0), Color(1, 0.4, 0.5), 1.8)
	var mus: Array = [
		[f + Vector2(-5.8, my), Vector2(7.6, 4.4), 0.3],
		[f + Vector2(5.8, my), Vector2(7.6, 4.4), -0.3],
		[f + Vector2(-12.5, my - 3.0), Vector2(3.0, 3.0), 0.0],
		[f + Vector2(12.5, my - 3.0), Vector2(3.0, 3.0), 0.0]]
	_merge(ci, mus, WHITE, 2.2)
	_e(ci, f + Vector2(0.8, 5.0), Vector2(4.4, 4.0), Color(1.0, 0.5, 0.45), 2.0)
	_circ(ci, f + Vector2(-0.4, 3.8), 1.1, Color(1, 0.85, 0.8), 0.0)


static func _grandpa_front(ci: CanvasItem, hand_f: Vector2, sh_f: Vector2, cane_ang: float, cane_len: float, green: Color, state: String, pose: int, swing: float) -> void:
	var dir := Vector2(sin(cane_ang), -cos(cane_ang))
	var low: float = cane_len
	if low < 0.0:
		low = clampf(-hand_f.y / maxf(cos(cane_ang), 0.3), 10.0, 60.0)
	var tip: Vector2 = hand_f - dir * low
	var top: Vector2 = hand_f + dir * 9.0
	if swing > 0.0 and state == "normal":
		var e2: float = clampf(swing, 0.0, 1.0)
		e2 = e2 * e2 * (3.0 - 2.0 * e2)
		var a1: float = lerpf(-2.4, 1.9, e2) - PI * 0.5
		ci.draw_set_transform_matrix(_xf)
		ci.draw_arc(hand_f, 46.0, a1 - 1.1, a1, 12, Color(1, 1, 1, 0.45 if not _ghost else 0.3), 9.0)
		ci.draw_arc(hand_f, 46.0, a1 - 0.9, a1, 12, Color(1, 1, 0.85, 0.9 if not _ghost else 0.5), 4.0)
	_limb(ci, tip, top, 3.6, Color(0.62, 0.38, 0.18), 1.8)
	var nrm := Vector2(dir.y, -dir.x)
	if nrm.x < 0.0:
		nrm = -nrm
	var k1: Vector2 = top + dir * 2.0 + nrm * 6.0
	_limb(ci, top, k1, 3.6, Color(0.62, 0.38, 0.18), 1.8)
	_limb(ci, k1, k1 + nrm * 2.0 - dir * 6.0, 3.6, Color(0.62, 0.38, 0.18), 1.8)
	_limb(ci, sh_f, hand_f, 7.0, green)
	_circ(ci, hand_f, 3.8, SKIN, 2.0)
	if state == "statue" and pose == 2:
		_limb(ci, hand_f + dir * 2.0, hand_f + dir * 6.0, 2.5, SKIN, 1.0)


static func _grandpa(ci: CanvasItem, p: Vector2, s: Dictionary, shadow: bool) -> void:
	_reset()
	var facing: Vector2 = s.get("facing", Vector2.DOWN)
	var vel: Vector2 = s.get("vel", Vector2.ZERO)
	var t: float = s.get("t", 0.0)
	var state: String = s.get("state", "normal")
	var pose: int = s.get("pose", 0)
	var banana: bool = s.get("has_banana", false)
	var swing: float = s.get("swing", 0.0)
	_stone = s.get("stone", false)
	_ghost = s.get("ghost", false)
	var sgn: float = -1.0 if facing.x < -0.05 else 1.0
	var back: bool = facing.y < -0.6
	var spd: float = vel.length()
	var run: float = clampf(spd / 110.0, 0.0, 1.0)
	var ph: float = t * (8.0 + spd * 0.03)
	var f: float = sin(ph)

	var rot: float = 0.0
	var lift: float = 0.0
	var bob: float = 0.0
	var sx: float = 1.0
	var sy: float = 1.0
	var pivot := Vector2(0, -24)
	var foot_f := Vector2(6, 0)
	var foot_b := Vector2(-6, 0)
	var hand_f := Vector2(14, -23)
	var hand_b := Vector2(-14, -20)
	var cane_ang: float = 0.1
	var cane_len: float = -1.0
	var expr: String = "grumpy"
	var mouth: float = 0.0
	var tongue: bool = false
	var head_off := Vector2.ZERO
	var look := Vector2(minf(absf(facing.x) + 0.25, 1.0), clampf(facing.y, -1.0, 1.0))
	var swirl: bool = false

	match state:
		"normal":
			bob = absf(f) * 3.5 * run
			sy = 1.0 + 0.05 * sin(ph * 2.0) * run + 0.018 * sin(t * 3.0)
			sx = 1.0 / sy
			rot = 0.1 * run + 0.04 * f * run
			foot_f = Vector2(6 + f * 7.0 * run, -maxf(0.0, f) * 5.0 * run)
			foot_b = Vector2(-6 - f * 7.0 * run, -maxf(0.0, -f) * 5.0 * run)
			hand_b = Vector2(-14 - f * 4.0 * run, -20 + absf(f) * 2.0 * run)
			hand_f = Vector2(14 - f * 2.0 * run, -23 - maxf(0.0, -f) * 3.0 * run)
			cane_ang = 0.1 + 0.35 * f * run
			if swing > 0.0:
				var u: float = clampf(swing, 0.0, 1.0)
				var e: float = u * u * (3.0 - 2.0 * u)
				hand_f = Vector2(17, -30)
				cane_ang = lerpf(-2.4, 1.9, e)
				cane_len = 28.0
				rot += 0.22 * sin(u * PI)
				expr = "angry"
				mouth = 0.8
				head_off = Vector2(2, 1)
		"slip":
			rot = t * 10.0
			lift = 11.0 + 3.0 * sin(t * 9.0)
			foot_f = Vector2(10, -6 + sin(t * 15.0) * 5.0)
			foot_b = Vector2(-10, -6 - sin(t * 15.0) * 5.0)
			hand_f = Vector2(21, -47 + sin(t * 13.0) * 5.0)
			hand_b = Vector2(-21, -47 - sin(t * 13.0) * 5.0)
			cane_ang = 0.5 + sin(t * 11.0) * 1.2
			cane_len = 26.0
			expr = "wide"
			mouth = 1.0
			swirl = true
		"stun":
			rot = sin(t * 3.6) * 0.17
			sy = 0.95 + 0.03 * sin(t * 7.2)
			sx = 1.0 / sy
			foot_f = Vector2(9, 0)
			foot_b = Vector2(-9, 0)
			hand_f = Vector2(15, -15)
			hand_b = Vector2(-15, -14)
			cane_ang = 0.7 + sin(t * 3.6) * 0.12
			expr = "spiral"
			tongue = true
			head_off = Vector2(3, 3)
		"grabbed":
			lift = 20.0
			rot = sin(t * 22.0) * 0.08
			sy = 1.12
			sx = 0.92
			foot_f = Vector2(5 + sin(t * 24.0) * 8.0, sin(t * 24.0 + 1.0) * 4.0)
			foot_b = Vector2(-5 - sin(t * 24.0 + 2.0) * 8.0, sin(t * 24.0 + 3.0) * 4.0)
			hand_f = Vector2(20 + sin(t * 18.0) * 5.0, -43 + cos(t * 18.0) * 5.0)
			hand_b = Vector2(-20 - sin(t * 18.0 + 1.0) * 5.0, -41 + cos(t * 18.0) * 5.0)
			cane_ang = 0.9 + sin(t * 17.0) * 1.1
			cane_len = 26.0
			expr = "angry"
			mouth = 1.0
		"knocked":
			rot = -PI * 0.5 + sin(t * 2.0) * 0.03
			lift = -11.0
			sy = 0.92
			foot_f = Vector2(10, 0)
			foot_b = Vector2(-10, -2)
			hand_f = Vector2(21, -26)
			hand_b = Vector2(-21, -26)
			cane_ang = 1.4
			cane_len = 26.0
			expr = "xx"
			tongue = true
		"statue":
			match pose:
				0:
					rot = -0.07
					foot_f = Vector2(8, 0)
					foot_b = Vector2(-8, 0)
					hand_f = Vector2(18, -60)
					hand_b = Vector2(-16, -60)
					cane_ang = 0.15
					cane_len = 26.0
					expr = "wide"
					mouth = 1.0
				1:
					rot = 0.06
					foot_f = Vector2(17, -12)
					foot_b = Vector2(-3, 0)
					hand_f = Vector2(26, -38)
					hand_b = Vector2(-24, -40)
					cane_ang = 0.6
					cane_len = 26.0
					expr = "smug"
					head_off = Vector2(1, -2)
				_:
					rot = -0.14
					foot_f = Vector2(11, 0)
					foot_b = Vector2(-10, 0)
					hand_f = Vector2(24, -47)
					hand_b = Vector2(-12, -21)
					cane_ang = 1.0
					cane_len = 34.0
					expr = "angry"
					mouth = 0.9
					head_off = Vector2(2, -1)

	if shadow:
		var sr: float = 1.0 - minf(lift, 24.0) * 0.012
		_xf = Transform2D(0.0, p)
		var sw: float = 16.0 * sr
		if state == "knocked":
			sw = 30.0
		_shadow(ci, Vector2(1, 1), Vector2(sw, 6.0 * sr))

	var base := Transform2D(Vector2(sgn * sx, 0), Vector2(0, sy), p + Vector2(0, -lift - bob))
	_xf = base * Transform2D(rot, pivot) * Transform2D(0.0, -pivot)
	var green := Color(0.5, 0.72, 0.3)
	var pants := Color(0.6, 0.46, 0.32)
	var slip_c := Color(0.92, 0.25, 0.32)
	var sh_b := Vector2(-10, -33)
	var sh_f := Vector2(10, -33)

	# back arm
	_limb(ci, sh_b, hand_b, 7.0, green)
	_circ(ci, hand_b, 3.8, SKIN, 2.0)
	if banana and state != "statue":
		_xf = base * Transform2D(rot, pivot) * Transform2D(0.0, -pivot) * Transform2D(0.5, hand_b + Vector2(-2, -7))
		_banana_local(ci, 0.62)
		_xf = base * Transform2D(rot, pivot) * Transform2D(0.0, -pivot)
		_circ(ci, hand_b, 3.8, SKIN, 2.0)
	# legs
	for lg in [[Vector2(-5, -16), foot_b], [Vector2(5, -16), foot_f]]:
		var hip: Vector2 = lg[0]
		var ft: Vector2 = lg[1]
		_limb(ci, hip, ft + Vector2(0, -3), 6.5, pants)
		_e(ci, ft + Vector2(2.5, -1.0), Vector2(8.0, 4.4), slip_c, 2.2)
		_circ(ci, ft + Vector2(7.5, -2.5), 1.8, Color(1, 0.8, 0.85), 0.0)
	# body
	var hump: Array = [
		[Vector2(-8, -32), Vector2(8.5, 8.0), 0.0],
		[Vector2(-0.5, -26), Vector2(13.5, 13.5), 0.0]]
	_merge(ci, hump, green, 2.6)
	_e(ci, Vector2(4.5, -27), Vector2(5.2, 11.5), Color(0.98, 0.9, 0.7), 1.6)
	if not back:
		for by in [-32.0, -27.0, -22.0]:
			_circ(ci, Vector2(5.5, by), 1.5, Color(0.7, 0.4, 0.15), 0.0)
		_rr(ci, Rect2(-12, -23, 8, 6), 2.0, Color(0.4, 0.6, 0.22), 1.6)
	else:
		_line(ci, Vector2(-1, -34), Vector2(-1, -12), 2.0, Color(0.3, 0.5, 0.2))
	_e(ci, Vector2(-0.5, -14.0), Vector2(12.5, 2.6), Color(0.42, 0.6, 0.24), 0.0)
	var late: bool = hand_f.y < -34.0 or swing > 0.0
	if not late:
		_grandpa_front(ci, hand_f, sh_f, cane_ang, cane_len, green, state, pose, swing)
	_grandpa_head(ci, Vector2(3, -46) + head_off, back, expr, mouth, tongue, look, t)
	if late:
		_grandpa_front(ci, hand_f, sh_f, cane_ang, cane_len, green, state, pose, swing)
	if _stone:
		ci.draw_set_transform_matrix(_xf)
		var cr := Color(0.12, 0.1, 0.12, 0.8)
		ci.draw_polyline(PackedVector2Array([Vector2(-6, -35), Vector2(-2, -30), Vector2(-5, -26), Vector2(0, -21)]), cr, 1.6)
		ci.draw_polyline(PackedVector2Array([Vector2(6, -58), Vector2(4, -54), Vector2(8, -51)]), cr, 1.6)
		ci.draw_polyline(PackedVector2Array([Vector2(8, -22), Vector2(5, -18), Vector2(7, -15)]), cr, 1.4)
		ci.draw_circle(Vector2(-9, -15), 3.0, Color(0.55, 0.7, 0.5, 0.0))
	if swirl:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_xf = Transform2D.IDENTITY
		var cc: Vector2 = p + Vector2(0, -30 - lift)
		var a: float = t * 10.0
		for k in 3:
			_arc(ci, cc, 32.0, a + k * TAU / 3.0 + 1.5, a + k * TAU / 3.0 + 2.4, 3.5, Color(1, 1, 1, 0.85))
	_end(ci)


static func draw_grandpa(ci: CanvasItem, p: Vector2, s: Dictionary) -> void:
	_grandpa(ci, p, s, true)


# ---------------------------------------------------------------- guard

static func _guard_head(ci: CanvasItem, hc: Vector2, back: bool, expr: String, mouth: float, look: Vector2, cap_off: Vector2, cap_rot: float, t: float) -> void:
	_e(ci, hc + Vector2(-15.5, -1), Vector2(3.6, 5.2), SKIN, 2.2)
	_e(ci, hc + Vector2(15.5, -1), Vector2(3.6, 5.2), SKIN, 2.2)
	_rr(ci, Rect2(hc.x - 15.5, hc.y - 12, 31, 31), 11.0, SKIN, 3.0)
	if not back:
		var f: Vector2 = hc + Vector2(3, 0)
		for sd in [-1.0, 1.0]:
			_e(ci, f + Vector2(sd * 10.5, 5.5), Vector2(3.4, 2.4), Color(1, 0.45, 0.5, 0.65), 0.0)
		# sunglasses
		var gy: float = -1.5
		var ls: Array[Vector2] = [f + Vector2(-6.8, gy), f + Vector2(6.8, gy)]
		var tilt: float = 0.0
		if expr == "dizzy":
			tilt = 0.28
		var gx: Transform2D = Transform2D(tilt, f + Vector2(0, gy))
		var sav: Transform2D = _xf
		_xf = sav * gx
		_line(ci, Vector2(-16, 0), Vector2(16, 0), 3.0, OL)
		var big: float = 1.15 if expr == "wide" else 1.0
		_e(ci, Vector2(-7.4, 0), Vector2(6.6, 5.0) * big, Color(0.12, 0.14, 0.26), 2.2)
		_e(ci, Vector2(7.4, 0), Vector2(6.6, 5.0) * big, Color(0.12, 0.14, 0.26), 2.2)
		_e(ci, Vector2(-9.4, -1.8), Vector2(2.6, 1.3), Color(0.8, 0.92, 1.0), 0.0, -0.4)
		_e(ci, Vector2(5.4, -1.8), Vector2(2.6, 1.3), Color(0.8, 0.92, 1.0), 0.0, -0.4)
		if expr == "dizzy":
			_spiral(ci, Vector2(-7, 0), 4.6, t * 8.0, 1.3, Color(0.9, 0.95, 1.0))
			_spiral(ci, Vector2(7, 0), 4.6, -t * 8.0, 1.3, Color(0.9, 0.95, 1.0))
		_xf = sav
		_circ(ci, f + Vector2(1, 5.0), 3.2, Color(1.0, 0.6, 0.5), 1.8)
		# mouth
		var my: float = 12.5
		if mouth > 0.0:
			_e(ci, f + Vector2(0, my + 1.5), Vector2(6.0 * mouth, 4.5 * mouth), Color(0.45, 0.04, 0.08), 2.2)
			if expr == "strain":
				_rect(ci, Rect2(f.x - 4.5, f.y + my - 0.5, 9, 3.0), WHITE, 0.0)
		else:
			_arc(ci, f + Vector2(0, my - 0.5), 4.5, 0.3, PI - 0.3, 2.0, OL)
		var mus: Array = [
			[f + Vector2(-4.0, 9.0), Vector2(5.0, 2.4), 0.2],
			[f + Vector2(4.0, 9.0), Vector2(5.0, 2.4), -0.2]]
		_merge(ci, mus, Color(0.38, 0.22, 0.14), 1.8)
		if expr == "dizzy":
			_e(ci, f + Vector2(1, 19.0), Vector2(3.0, 4.2), Color(1, 0.4, 0.5), 1.8)
	else:
		_rr(ci, Rect2(hc.x - 14.0, hc.y - 9, 28, 20), 8.0, Color(0.38, 0.24, 0.15), 2.2)
		_rr(ci, Rect2(hc.x - 8.0, hc.y + 12, 16, 5), 2.0, Color(0.9, 0.66, 0.52), 0.0)
	# cap
	var save: Transform2D = _xf
	_xf = save * Transform2D(cap_rot, hc + Vector2(0, -10) + cap_off)
	var navy := Color(0.2, 0.3, 0.7)
	var dome: Array = [[Vector2(0, -5), Vector2(17.5, 11.5), 0.0]]
	_merge(ci, dome, navy, 3.0)
	_rr(ci, Rect2(-17.5, -4.5, 35, 7), 3.0, Color(0.12, 0.18, 0.45), 2.4)
	if not back:
		_e(ci, Vector2(8, 1.0), Vector2(14, 3.4), Color(0.1, 0.12, 0.28), 2.2)
		_circ(ci, Vector2(6, -6), 4.6, Color(1.0, 0.82, 0.2), 1.8)
		ci.draw_set_transform_matrix(_xf)
		ci.draw_colored_polygon(_star_pts(Vector2(6, -6), 3.0, 1.4, 0.0), _k(Color(0.85, 0.15, 0.15)))
	else:
		_line(ci, Vector2(-14, 1), Vector2(14, 1), 3.0, Color(0.1, 0.1, 0.14))
	_xf = save


static func _guard(ci: CanvasItem, p: Vector2, s: Dictionary) -> void:
	_reset()
	var facing: Vector2 = s.get("facing", Vector2.DOWN)
	var vel: Vector2 = s.get("vel", Vector2.ZERO)
	var t: float = s.get("t", 0.0)
	var state: String = s.get("state", "normal")
	var carry: String = s.get("carry", "")
	_ghost = s.get("ghost", false)
	var sgn: float = -1.0 if facing.x < -0.05 else 1.0
	var back: bool = facing.y < -0.6
	var spd: float = vel.length()
	var run: float = clampf(spd / 120.0, 0.0, 1.0)
	var ph: float = t * (7.0 + spd * 0.025)
	var f: float = sin(ph)

	var rot: float = 0.0
	var lift: float = 0.0
	var bob: float = 0.0
	var sx: float = 1.0
	var sy: float = 1.0
	var jig := Vector2.ZERO
	var pivot := Vector2(0, -34)
	var foot_f := Vector2(9, 0)
	var foot_b := Vector2(-9, 0)
	var hand_f := Vector2(28, -32)
	var hand_b := Vector2(-28, -32)
	var expr: String = "normal"
	var mouth: float = 0.0
	var cap_off := Vector2.ZERO
	var cap_rot: float = 0.0
	var look := Vector2.ZERO
	var arms_front: bool = false
	var lines: bool = false
	var swirl: bool = false
	var sweat: bool = false
	var shadow_w: float = 26.0

	match state:
		"normal":
			bob = absf(f) * 3.0 * run
			sy = 1.0 + 0.04 * sin(ph * 2.0) * run + 0.012 * sin(t * 2.5)
			sx = 1.0 / sy
			rot = 0.05 * run + 0.03 * f * run
			foot_f = Vector2(9 + f * 8.0 * run, -maxf(0.0, f) * 6.0 * run)
			foot_b = Vector2(-9 - f * 8.0 * run, -maxf(0.0, -f) * 6.0 * run)
			hand_f = Vector2(28 - f * 5.0 * run, -32 + absf(f) * 3.0 * run)
			hand_b = Vector2(-28 + f * 5.0 * run, -32 + absf(f) * 3.0 * run)
		"slip":
			rot = t * 9.0
			lift = 14.0 + 3.0 * sin(t * 9.0)
			foot_f = Vector2(14, -8 + sin(t * 14.0) * 5.0)
			foot_b = Vector2(-14, -8 - sin(t * 14.0) * 5.0)
			hand_f = Vector2(32, -64 + sin(t * 12.0) * 6.0)
			hand_b = Vector2(-32, -64 - sin(t * 12.0) * 6.0)
			expr = "wide"
			mouth = 1.0
			cap_off = Vector2(sin(t * 5.0) * 5.0, -16.0)
			cap_rot = t * 4.0
			swirl = true
			arms_front = true
		"stun":
			rot = sin(t * 3.2) * 0.14
			sy = 0.96 + 0.025 * sin(t * 6.4)
			sx = 1.0 / sy
			foot_f = Vector2(11, 0)
			foot_b = Vector2(-11, 0)
			hand_f = Vector2(27, -28)
			hand_b = Vector2(-27, -28)
			expr = "dizzy"
			cap_rot = 0.45 + sin(t * 3.2) * 0.1
			cap_off = Vector2(4, 4)
		"dash":
			rot = 0.4
			bob = absf(sin(t * 22.0)) * 3.0
			foot_f = Vector2(14 + sin(t * 22.0) * 11.0, -maxf(0.0, sin(t * 22.0)) * 8.0)
			foot_b = Vector2(-14 - sin(t * 22.0) * 11.0, -maxf(0.0, -sin(t * 22.0)) * 8.0)
			hand_f = Vector2(34, -56 + sin(t * 22.0) * 4.0)
			hand_b = Vector2(-32, -50 - sin(t * 22.0) * 4.0)
			expr = "shout"
			mouth = 0.9
			lines = true
			arms_front = false
			pivot = Vector2(0, -20)
		"knocked":
			rot = -0.75 + sin(t * 10.0) * 0.06
			lift = 16.0
			foot_f = Vector2(16 + sin(t * 17.0) * 6.0, -7)
			foot_b = Vector2(-10, -14 + sin(t * 17.0 + 1.0) * 5.0)
			hand_f = Vector2(30 + sin(t * 15.0) * 5.0, -74 + cos(t * 15.0) * 4.0)
			hand_b = Vector2(-30 - sin(t * 15.0 + 1.0) * 5.0, -72 + cos(t * 15.0) * 4.0)
			expr = "wide"
			mouth = 1.0
			cap_off = Vector2(-4.0, -20.0)
			cap_rot = -0.6
			arms_front = true
			shadow_w = 22.0
	if carry == "grandpa":
		hand_f = Vector2(36, -58 + sin(t * 30.0) * 0.8)
		hand_b = Vector2(28, -49 + sin(t * 30.0 + 1.0) * 0.8)
		arms_front = true
		expr = "strain"
		mouth = 0.6
		sweat = true
		rot += 0.04
		jig = Vector2(sin(t * 33.0) * 0.8, 0)
	elif carry == "bench":
		hand_f = Vector2(34, -88 + sin(t * 30.0) * 0.8)
		hand_b = Vector2(22, -90 + sin(t * 30.0 + 1.0) * 0.8)
		arms_front = true
		expr = "strain"
		mouth = 0.7
		sweat = true
		rot -= 0.07
		jig = Vector2(sin(t * 33.0) * 0.8, 0)

	_xf = Transform2D(0.0, p)
	_shadow(ci, Vector2(2, 1), Vector2(shadow_w * (1.0 - minf(lift, 20.0) * 0.012), 8.5))
	var base := Transform2D(Vector2(sgn * sx, 0), Vector2(0, sy), p + Vector2(0, -lift - bob) + jig)
	var body_xf: Transform2D = base * Transform2D(rot, pivot) * Transform2D(0.0, -pivot)
	_xf = base
	if lines:
		for k in 5:
			var ly: float = -14.0 - k * 17.0
			var off: float = fposmod(t * 6.0 + k * 0.37, 1.0)
			var x1: float = -34.0 - off * 14.0 - k % 2 * 8.0
			_line(ci, Vector2(x1, ly), Vector2(x1 - 22.0 - (k % 3) * 8.0, ly), 4.0, Color(1, 1, 1, 0.8))
		for k in 3:
			var off: float = fposmod(t * 3.0 + k * 0.33, 1.0)
			_circ(ci, Vector2(-26.0 - off * 24.0, -4.0 - k * 3.0), 5.0 + off * 6.0, Color(0.95, 0.9, 0.8, 0.8 * (1.0 - off)), 0.0)
	_xf = body_xf

	var navy := Color(0.2, 0.32, 0.72)
	var navy_d := Color(0.13, 0.2, 0.5)
	var boot := Color(0.16, 0.13, 0.15)
	var sh_f := Vector2(22, -56)
	var sh_b := Vector2(-22, -56)
	if carry != "":
		sh_b = Vector2(8, -58)
	elif arms_front:
		sh_b = Vector2(-6, -58)
	var back_late: bool = carry == "grandpa"
	if not back_late:
		_limb(ci, sh_b, hand_b, 13.0, navy)
		_circ(ci, hand_b, 6.2, SKIN, 2.4)
	# legs
	for lg in [[Vector2(-9, -24), foot_b], [Vector2(9, -24), foot_f]]:
		var hip: Vector2 = lg[0]
		var ft: Vector2 = lg[1]
		_limb(ci, hip, ft + Vector2(0, -5), 12.0, navy_d, 2.6)
		_e(ci, ft + Vector2(3.5, -2.5), Vector2(11.5, 6.2), boot, 2.6)
		_e(ci, ft + Vector2(5.0, -4.5), Vector2(5.0, 1.6), Color(0.45, 0.45, 0.55), 0.0)
	# torso
	_rr(ci, Rect2(-25, -65, 50, 42), 15.0, navy, 3.0)
	_e(ci, Vector2(-14, -50), Vector2(5, 11), Color(0.3, 0.45, 0.85, 0.6), 0.0, 0.1)
	if not back:
		_poly(ci, PackedVector2Array([Vector2(-6, -65), Vector2(8, -65), Vector2(1, -54)]), Color(0.95, 0.95, 1.0), 2.0)
		_poly(ci, PackedVector2Array([Vector2(0, -63), Vector2(4, -62), Vector2(5, -46), Vector2(1, -41), Vector2(-3, -46), Vector2(-2, -62)]), Color(0.9, 0.2, 0.25), 1.8)
		_e(ci, Vector2(4, -32), Vector2(23.5, 16.5), Color(0.24, 0.37, 0.8), 3.0)
		for by in [-41.0, -33.0]:
			_circ(ci, Vector2(12, by), 2.4, Color(1.0, 0.82, 0.2), 1.4)
		# belt
		_rr(ci, Rect2(-24, -28, 52, 7), 3.0, Color(0.1, 0.1, 0.12), 2.2)
		_rr(ci, Rect2(-1, -29.5, 11, 10), 2.5, Color(1.0, 0.82, 0.2), 2.0)
		# badge, whistle
		ci.draw_set_transform_matrix(_xf)
		_circ(ci, Vector2(-13, -51), 5.4, Color(1.0, 0.82, 0.2), 2.0)
		ci.draw_set_transform_matrix(_xf)
		ci.draw_colored_polygon(_star_pts(Vector2(-13, -51), 3.4, 1.6, 0.0), _k(Color(0.85, 0.2, 0.15)))
		_line(ci, Vector2(-4, -63), Vector2(8, -46), 1.8, Color(0.9, 0.9, 0.95))
		_rr(ci, Rect2(4, -48, 13, 7), 3.0, Color(0.85, 0.87, 0.95), 1.8)
		_circ(ci, Vector2(8, -44.5), 1.6, OL, 0.0)
	else:
		_rr(ci, Rect2(-24, -28, 50, 7), 3.0, Color(0.1, 0.1, 0.12), 2.2)
		_line(ci, Vector2(0, -62), Vector2(0, -30), 2.5, navy_d)
	_e(ci, Vector2(-23, -61), Vector2(8.5, 4.4), Color(1.0, 0.82, 0.2), 2.2, 0.2)
	_e(ci, Vector2(23, -61), Vector2(8.5, 4.4), Color(1.0, 0.82, 0.2), 2.2, -0.2)
	if back_late:
		_limb(ci, sh_b, hand_b, 13.0, navy)
		_circ(ci, hand_b, 6.2, SKIN, 2.4)
	# head
	_guard_head(ci, Vector2(3, -78), back, expr, mouth, look, cap_off, cap_rot, t)
	if carry == "bench":
		_limb(ci, sh_b, hand_b, 13.0, navy)
		_circ(ci, hand_b, 6.2, SKIN, 2.4)
	_limb(ci, sh_f, hand_f, 13.0, navy)
	_circ(ci, hand_f, 6.2, SKIN, 2.4)
	if sweat:
		for k in 2:
			var ph2: float = fposmod(t * 2.0 + k * 0.5, 1.0)
			var sp := Vector2(-6.0 - ph2 * 14.0 + k * 4.0, -88.0 + ph2 * 22.0)
			_e(ci, sp, Vector2(2.6, 3.6), Color(0.6, 0.85, 1.0, 1.0 - ph2 * 0.6), 1.5)
	if swirl:
		_xf = Transform2D(0.0, p)
		var cc := Vector2(0, -40 - lift)
		var a: float = t * 9.0
		for k in 3:
			_arc(ci, cc, 44.0, a + k * TAU / 3.0 + 1.5, a + k * TAU / 3.0 + 2.4, 3.5, Color(1, 1, 1, 0.85))
	_end(ci)


static func draw_guard(ci: CanvasItem, p: Vector2, s: Dictionary) -> void:
	_guard(ci, p, s)


# ---------------------------------------------------------------- ui bits

static func draw_bubble(ci: CanvasItem, anchor: Vector2, text: String, size: int, alpha: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var a: float = clampf(alpha, 0.0, 1.0)
	if a <= 0.0:
		return
	var f: Font = _font()
	var lines: PackedStringArray = text.split("\n")
	var wmax: float = 0.0
	for l in lines:
		wmax = maxf(wmax, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var lh: float = size * 1.2
	var pad: float = 13.0
	var bw: float = wmax + pad * 2.0
	var bh: float = lines.size() * lh + pad * 1.2
	var tail: float = 16.0
	var rc := Rect2(anchor.x - bw * 0.5, anchor.y - tail - bh, bw, bh)
	var pts: PackedVector2Array = _rr_pts(rc, 14.0)
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(3, 4))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.22 * a))
	var white := Color(1, 1, 1, a)
	var line := Color(OL.r, OL.g, OL.b, a)
	var tl := Vector2(anchor.x - 9.0, rc.end.y)
	var tr := Vector2(anchor.x + 9.0, rc.end.y)
	ci.draw_colored_polygon(pts, white)
	ci.draw_colored_polygon(PackedVector2Array([tl + Vector2(0, -2), tr + Vector2(0, -2), anchor]), white)
	var p2 := pts.duplicate()
	p2.append(pts[0])
	ci.draw_polyline(p2, line, 3.5)
	ci.draw_line(tl, anchor, line, 3.5)
	ci.draw_line(tr, anchor, line, 3.5)
	ci.draw_line(tl + Vector2(1.5, 0), tr + Vector2(-1.5, 0), white, 5.0)
	for i in lines.size():
		var w: float = f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var bp := Vector2(anchor.x - w * 0.5, rc.position.y + pad * 0.6 + i * lh + size * 0.95)
		ci.draw_string(f, bp, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.1, 0.05, 0.1, a))


static func draw_stars(ci: CanvasItem, p: Vector2, t: float) -> void:
	_reset()
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 4:
		var a: float = t * 3.4 + i * TAU / 4.0
		var pos: Vector2 = p + Vector2(cos(a) * 24.0, sin(a) * 8.0)
		var sc: float = 0.8 + 0.25 * sin(a)
		_xf = Transform2D.IDENTITY
		_poly(ci, _star_pts(pos, 8.5 * sc, 3.8 * sc, t * 3.0 + i), Color(1.0, 0.9, 0.2), 1.8 * sc)
	_end(ci)
