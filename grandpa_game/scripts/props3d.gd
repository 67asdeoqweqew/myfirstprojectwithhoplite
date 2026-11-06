extends RefCounted
## Procedural courtyard props (static functions only). Contract: MODELS3D.md, File B.
## Extras beyond the contract: set_night(root, on) toggles glowing materials and the
## OmniLight3D nodes named "Light" (lamps) / "Glow" (kiosk) found under root.

const GROW: float = 0.025
const OUTLINE_COL: Color = Color(0.06, 0.04, 0.07)

# Courtyard layout used by make_ground() to keep grass tufts out from under paths/zones.
const _AVOID_RECTS: Array = [
	[0.6, 5.4, 5.0, 11.2], [5.76, 9.4, 3.0, 3.2], [31.2, 8.8, 4.2, 4.4],
	[28.8, 9.8, 2.3, 2.4], [19.3, 2.5, 1.4, 1.0],
]
const _AVOID_CIRCLES: Array = [
	[18.0, 11.0, 1.7], [10.4, 8.2, 1.0], [17.8, 15.2, 1.2], [25.8, 14.0, 1.1],
]
const _AVOID_PATHS: Array = [
	[5.8, 11.0, 11.2, 11.0], [11.2, 11.0, 13.3, 8.4], [11.2, 11.0, 13.3, 13.6],
	[13.3, 8.4, 18.0, 7.2], [13.3, 13.6, 18.0, 15.0], [18.0, 7.2, 22.7, 5.6],
	[18.0, 15.0, 22.7, 16.4], [22.7, 5.6, 28.4, 11.0], [22.7, 16.4, 28.4, 11.0],
	[28.4, 11.0, 31.2, 11.0],
]

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _texs: Dictionary = {}
static var _glow: Array[StandardMaterial3D] = []
static var _outline_mat: StandardMaterial3D = null
static var _flat_black_mat: StandardMaterial3D = null
static var _night: bool = false


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

## Toggle night look: glowing materials (windows, lamp bulbs, kiosk interior) and the
## OmniLight3D children named "Light"/"Glow" under root.
static func set_night(root: Node, on: bool) -> void:
	_night = on
	for m: StandardMaterial3D in _glow:
		m.emission_enabled = on
	if root == null:
		return
	for n: Node in root.find_children("*", "OmniLight3D", true, false):
		if n.name == &"Light" or n.name == &"Glow":
			(n as OmniLight3D).visible = on


static func make_ground(size: Vector2, avoid: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = "Ground"
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = _grass_tex()
	gm.roughness = 1.0
	gm.metallic_specular = 0.1
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	gm.uv1_triplanar = true
	gm.uv1_world_triplanar = true
	gm.uv1_scale = Vector3(1.0 / 8.0, 1.0 / 8.0, 1.0 / 8.0)
	# Tiles keep per-mesh light counts low (GL Compatibility caps lights per object).
	var nx: int = maxi(1, ceili(size.x / 6.0))
	var nz: int = maxi(1, ceili(size.y / 6.0))
	var tile := Vector2(size.x / float(nx), size.y / float(nz))
	var pm := PlaneMesh.new()
	pm.size = tile
	for ix in nx:
		for iz in nz:
			var tp := Vector3(-size.x * 0.5 + tile.x * (float(ix) + 0.5), 0.0, -size.y * 0.5 + tile.y * (float(iz) + 0.5))
			_add(root, pm, gm, tp, Vector3.ZERO, false)

	var rng := _rng(4711)
	var use_default: bool = avoid.is_empty() and absf(size.x - 36.0) < 0.1 and absf(size.y - 22.0) < 0.1
	var count: int = int(size.x * size.y * 1.7)
	var tx: Array[Transform3D] = []
	var tc := PackedColorArray()
	for i in count:
		var p := Vector2(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(-0.5, 0.5) * size.y)
		var s: float = rng.randf_range(0.75, 1.5)
		var hs: float = s * rng.randf_range(0.8, 1.4)
		var yaw: float = rng.randf() * TAU
		var shade: float = rng.randf_range(0.8, 1.15)
		if _blocked(p, size, avoid, use_default):
			continue
		tx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, hs, s)), Vector3(p.x, 0.0, p.y)))
		tc.append(Color(shade, shade, shade))
	_multi(root, _tuft_mesh(), _vc_mat(0.95), tx, tc, false)

	var palette: Array[Color] = [
		Color(1.0, 0.45, 0.55), Color(1.0, 0.85, 0.2), Color(1.0, 1.0, 0.95), Color(0.75, 0.5, 1.0),
	]
	var per: int = int(size.x * size.y * 0.1)
	for ci in palette.size():
		var fx: Array[Transform3D] = []
		for i in per:
			var p := Vector2(rng.randf_range(-0.5, 0.5) * size.x, rng.randf_range(-0.5, 0.5) * size.y)
			var s: float = rng.randf_range(0.8, 1.3)
			var yaw: float = rng.randf() * TAU
			if _blocked(p, size, avoid, use_default):
				continue
			fx.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(p.x, 0.0, p.y)))
		_multi(root, _flower_mesh(palette[ci]), null, fx, PackedColorArray(), false)
	return root


static func make_path(a: Vector2, b: Vector2, width: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Path"
	var d: Vector2 = b - a
	var length: float = d.length()
	var yaw: float = atan2(-d.y, d.x)
	var lift: float = float(int(absf(a.x * 7.0 + a.y * 13.0 + b.x * 3.0 + b.y * 5.0)) % 5) * 0.001
	var top: float = 0.03 + lift
	var stone := _path_mat()
	var edge := _mat(Color(0.62, 0.46, 0.3), 1.0)
	var mid := (a + b) * 0.5
	var holder := Node3D.new()
	holder.position = Vector3(mid.x, 0.0, mid.y)
	holder.rotation.y = yaw
	root.add_child(holder)
	_add(holder, _bm(Vector3(length, top, width)), stone, Vector3(0, top * 0.5, 0), Vector3.ZERO, false)
	_add(holder, _bm(Vector3(length, top - 0.012, width + 0.14)), edge, Vector3(0, (top - 0.012) * 0.5, 0), Vector3.ZERO, false)
	for sx in [-1.0, 1.0]:
		var x: float = float(sx) * length * 0.5
		_add(holder, _cm(width * 0.5, width * 0.5, top, 28), stone, Vector3(x, top * 0.5, 0), Vector3.ZERO, false)
		_add(holder, _cm(width * 0.5 + 0.07, width * 0.5 + 0.07, top - 0.012, 28), edge,
			Vector3(x, (top - 0.012) * 0.5, 0), Vector3.ZERO, false)
	return root


static func make_wall(size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Wall"
	var cap_h: float = 0.16
	var brick := _brick_mat()
	var stone := _mat(Color(0.62, 0.54, 0.43), 0.9)
	var along_x: bool = size.x >= size.z
	_box(root, Vector3(size.x, size.y - cap_h, size.z), Vector3(0, (size.y - cap_h) * 0.5, 0), brick)
	_box(root, Vector3(size.x + 0.12, cap_h, size.z + 0.12), Vector3(0, size.y - cap_h * 0.5, 0), stone, true)
	var length: float = size.x if along_x else size.z
	var n: int = int(length / 3.0)
	if n >= 1:
		var tx: Array[Transform3D] = []
		var pil := _mat(Color(0.8, 0.45, 0.3), 0.95)
		var psize: Vector3
		if along_x:
			psize = Vector3(0.5, size.y - cap_h, size.z + 0.14)
		else:
			psize = Vector3(size.x + 0.14, size.y - cap_h, 0.5)
		for i in n + 1:
			var u: float = -length * 0.5 + length * float(i) / float(n)
			var pos := Vector3(u, psize.y * 0.5, 0) if along_x else Vector3(0, psize.y * 0.5, u)
			tx.append(Transform3D(Basis.IDENTITY, pos))
		_multi(root, _bm(psize), pil, tx, PackedColorArray(), true)
	return root


static func make_hedge(size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Hedge"
	var along_x: bool = size.x >= size.z
	var length: float = size.x if along_x else size.z
	var wid: float = size.z if along_x else size.x
	var body_h: float = size.y * 0.6
	var body := _mat(Color(0.2, 0.55, 0.2), 0.95)
	var bsize := Vector3(length, body_h, wid) if along_x else Vector3(wid, body_h, length)
	_box(root, bsize, Vector3(0, body_h * 0.5, 0), body, true)
	var br: float = wid * 0.5 + 0.07
	var vh: float = size.y - body_h
	var n: int = maxi(2, int(round(length / 0.55)))
	var step: float = length / float(n)
	var bump_tx: Array[Transform3D] = []
	var bump_c := PackedColorArray()
	var centers: Array[Vector3] = []
	var rng := _rng(77 + n)
	for i in n:
		var u: float = -length * 0.5 + step * (float(i) + 0.5)
		var w: float = sin(float(i) * 2.3) * 0.05
		var s: float = rng.randf_range(0.92, 1.1)
		var pos := Vector3(u, body_h, w) if along_x else Vector3(w, body_h, u)
		centers.append(pos)
		bump_tx.append(Transform3D(Basis.from_scale(Vector3(br * s, vh * s, br * s)), pos))
		var g: float = rng.randf_range(0.9, 1.15)
		bump_c.append(Color(g, g, g))
	_multi(root, _sm(1.0, 1.0, 16, 8), _vc_mat(0.95, Color(0.33, 0.72, 0.26), true), bump_tx, bump_c, true)
	var fx: Array[Transform3D] = []
	var fc := PackedColorArray()
	var fcols: Array[Color] = [Color(1.0, 0.45, 0.6), Color(1.0, 0.88, 0.25), Color(1, 1, 0.95), Color(1.0, 0.6, 0.2)]
	for i in n:
		for k in 3:
			var th: float = rng.randf() * TAU
			var ph: float = rng.randf_range(0.2, 1.25)
			var c: Vector3 = centers[i]
			var p := c + Vector3(br * sin(ph) * cos(th), vh * cos(ph), br * sin(ph) * sin(th)) * 1.0
			fx.append(Transform3D(Basis.IDENTITY, p))
			fc.append(fcols[(i + k) % fcols.size()])
	_multi(root, _sm(0.075, 1.0, 8, 4), _vc_mat(0.7), fx, fc, false)
	return root


static func make_bush(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Bush"
	var h: float = radius * 1.3
	var greens: Array[Color] = [Color(0.2, 0.62, 0.22), Color(0.3, 0.72, 0.25), Color(0.16, 0.54, 0.24)]
	_sph(root, radius * 0.8, Vector3(0, h * 0.5, 0), _mat(greens[0], 0.95, true), 1.2)
	for i in 4:
		var a: float = float(i) * TAU / 4.0 + 0.5
		var p := Vector3(cos(a) * radius * 0.55, h * (0.3 + 0.08 * float(i % 2)), sin(a) * radius * 0.55)
		_sph(root, radius * 0.5, p, _mat(greens[1 + i % 2], 0.95, true), 1.0)
	_sph(root, radius * 0.45, Vector3(0.05, h * 0.78, -0.05), _mat(greens[1], 0.95, true), 1.0)
	var bx: Array[Transform3D] = []
	var rng := _rng(int(radius * 1000.0))
	for i in 9:
		var th: float = rng.randf() * TAU
		var ph: float = rng.randf_range(0.3, 1.3)
		var rr: float = radius * 0.95
		var p := Vector3(rr * sin(ph) * cos(th), h * 0.45 + h * 0.55 * cos(ph), rr * sin(ph) * sin(th))
		bx.append(Transform3D(Basis.from_scale(Vector3.ONE * radius), p))
	_multi(root, _sm(0.1, 1.0, 10, 5), _mat(Color(0.95, 0.15, 0.25), 0.5), bx, PackedColorArray(), false)
	return root


static func make_tree(height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Tree"
	var h: float = height
	var trunk := _mat(Color(0.5, 0.31, 0.17), 0.95, true)
	var tr: float = 0.09 + 0.02 * h
	_cyl(root, tr * 0.7, tr * 1.1, h * 0.5, Vector3(0, h * 0.25, 0), trunk, Vector3.ZERO, true, 12)
	_cyl(root, tr * 1.1, tr * 1.7, h * 0.08, Vector3(0, h * 0.04, 0), trunk, Vector3.ZERO, true, 12)
	var g1 := _mat(Color(0.22, 0.62, 0.24), 0.95, true)
	var g2 := _mat(Color(0.34, 0.74, 0.27), 0.95, true)
	var g3 := _mat(Color(0.5, 0.82, 0.3), 0.95, true)
	_sph(root, h * 0.3, Vector3(0, h * 0.62, 0), g1, 0.95)
	for i in 5:
		var a: float = float(i) * TAU / 5.0 + 0.4
		var p := Vector3(cos(a) * h * 0.24, h * (0.55 + 0.07 * float(i % 3)), sin(a) * h * 0.24)
		_sph(root, h * 0.2, p, g2 if i % 2 == 0 else g1, 1.0)
	_sph(root, h * 0.22, Vector3(0.0, h * 0.84, 0.0), g3, 1.0)
	var ax: Array[Transform3D] = []
	var rng := _rng(int(h * 100.0))
	for i in 7:
		var th: float = rng.randf() * TAU
		var ph: float = rng.randf_range(0.5, 1.6)
		var rr: float = h * 0.36
		var p := Vector3(rr * sin(ph) * cos(th), h * 0.62 + rr * 0.85 * cos(ph), rr * sin(ph) * sin(th))
		ax.append(Transform3D(Basis.from_scale(Vector3.ONE * h * 0.28), p))
	_multi(root, _sm(0.1, 1.0, 8, 4), _mat(Color(0.95, 0.2, 0.15), 0.5), ax, PackedColorArray(), false)
	return root


static func make_lamp() -> Node3D:
	var root := Node3D.new()
	root.name = "Lamp"
	var iron := _mat(Color(0.16, 0.3, 0.27), 0.5, true)
	_cyl(root, 0.15, 0.2, 0.3, Vector3(0, 0.15, 0), iron)
	_cyl(root, 0.1, 0.13, 0.12, Vector3(0, 0.36, 0), iron)
	_cyl(root, 0.05, 0.06, 2.4, Vector3(0, 1.5, 0), iron, Vector3.ZERO, true, 10)
	_cyl(root, 0.17, 0.1, 0.08, Vector3(0, 2.66, 0), iron, Vector3.ZERO, true, 12)
	var gm := _glow_mat(Color(1.0, 0.95, 0.75), Color(1.0, 0.7, 0.3), 2.0)
	var bulb := _sph(root, 0.2, Vector3(0, 2.88, 0), gm, 1.15, false)
	bulb.name = "Bulb"
	bulb.mesh.set("material", gm)
	_cyl(root, 0.02, 0.32, 0.22, Vector3(0, 3.15, 0), iron, Vector3.ZERO, true, 12)
	_sph(root, 0.05, Vector3(0, 3.3, 0), iron, 1.0, false)
	var l := OmniLight3D.new()
	l.name = "Light"
	l.position = Vector3(0, 2.85, 0)
	l.omni_range = 8.0
	l.light_energy = 1.7
	l.light_color = Color(1.0, 0.8, 0.5)
	l.shadow_enabled = false
	l.visible = false
	root.add_child(l)
	return root


static func make_puddle(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Puddle"
	var rz: float = radius * 0.65
	var disc := _cm(1.0, 1.0, 0.004, 40)
	var wet := _add(root, disc, _mat(Color(0.28, 0.36, 0.5), 0.6), Vector3(0, 0.036, 0), Vector3.ZERO, false)
	wet.scale = Vector3(radius * 1.12, 1.0, rz * 1.14)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.35, 0.68, 1.0, 0.92)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.05
	wm.metallic = 0.2
	wm.metallic_specular = 1.0
	var water := _add(root, disc, wm, Vector3(0, 0.042, 0), Vector3.ZERO, false)
	water.scale = Vector3(radius, 1.0, rz)
	var shine := _unshaded(Color(1, 1, 1, 0.75))
	var s1 := _add(root, disc, shine, Vector3(-radius * 0.28, 0.048, -rz * 0.3), Vector3.ZERO, false)
	s1.scale = Vector3(radius * 0.28, 1.0, rz * 0.07)
	s1.rotation_degrees.y = -12.0
	var s2 := _add(root, disc, shine, Vector3(-radius * 0.02, 0.048, -rz * 0.5), Vector3.ZERO, false)
	s2.scale = Vector3(radius * 0.1, 1.0, rz * 0.06)
	s2.rotation_degrees.y = -12.0
	return root


static func make_fountain(radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Fountain"
	var stone := _mat(Color(0.62, 0.58, 0.54), 0.8, true)
	var stone_dark := _mat(Color(0.46, 0.43, 0.4), 0.85, true)
	_cyl(root, radius + 0.12, radius + 0.16, 0.16, Vector3(0, 0.08, 0), stone_dark, Vector3.ZERO, true, 40)
	_cyl(root, radius, radius, 0.4, Vector3(0, 0.36, 0), stone, Vector3.ZERO, true, 40)
	var tm := TorusMesh.new()
	tm.inner_radius = radius - 0.2
	tm.outer_radius = radius
	tm.rings = 40
	tm.ring_segments = 12
	_add(root, tm, stone, Vector3(0, 0.66, 0), Vector3.ZERO, true)
	# central tiered column
	_cyl(root, 0.2, 0.28, 0.9, Vector3(0, 0.85, 0), stone)
	_cyl(root, radius * 0.5, 0.26, 0.2, Vector3(0, 1.4, 0), stone)
	_cyl(root, 0.1, 0.16, 0.5, Vector3(0, 1.7, 0), stone)
	_cyl(root, radius * 0.28, 0.14, 0.14, Vector3(0, 2.0, 0), stone)
	_sph(root, 0.13, Vector3(0, 2.12, 0), stone, 1.0)

	var water := Node3D.new()
	water.name = "Water"
	root.add_child(water)
	var surf := StandardMaterial3D.new()
	surf.albedo_color = Color(0.3, 0.75, 0.98)
	surf.roughness = 0.08
	surf.metallic_specular = 1.0
	_add(water, _cm(radius - 0.18, radius - 0.18, 0.02, 40), surf, Vector3(0, 0.6, 0), Vector3.ZERO, false)
	var foam := _mat(Color(0.9, 0.98, 1.0), 0.4)
	for i in 6:
		var a: float = float(i) * TAU / 6.0
		var rr: float = radius * 0.6
		_sph(water, 0.1, Vector3(cos(a) * rr, 0.62, sin(a) * rr), foam, 0.35, false)
	var sheet := StandardMaterial3D.new()
	sheet.albedo_color = Color(0.6, 0.88, 1.0, 0.6)
	sheet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sheet.cull_mode = BaseMaterial3D.CULL_DISABLED
	sheet.roughness = 0.1
	_add(water, _cm(radius * 0.32, radius * 0.5, 0.78, 28, false, false), sheet, Vector3(0, 1.0, 0), Vector3.ZERO, false)
	_add(water, _cm(radius * 0.2, radius * 0.28, 0.2, 24, false, false), sheet, Vector3(0, 1.88, 0), Vector3.ZERO, false)
	var jet := _mat(Color(0.8, 0.95, 1.0, 0.85), 0.2)
	_add(water, _cm(0.02, 0.07, 0.55, 12), jet, Vector3(0, 2.42, 0), Vector3.ZERO, false)
	for i in 5:
		var a: float = float(i) * TAU / 5.0
		_sph(water, 0.06, Vector3(cos(a) * 0.3, 2.55 - 0.1 * float(i % 2), sin(a) * 0.3), foam, 1.0, false)
	return root


static func make_building(size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Building"
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var rise: float = minf(1.2, size.y * 0.27)
	var wall_h: float = size.y - rise
	var wall := _mat(Color(1.0, 0.85, 0.58), 0.9)
	var trim := _mat(Color(0.82, 0.78, 0.7), 0.85)
	var stone := _mat(Color(0.5, 0.47, 0.44), 0.95)
	var brick_dark := _mat(Color(0.75, 0.38, 0.28), 0.95)
	var wood := _mat(Color(0.52, 0.3, 0.17), 0.8)
	var plinth_h: float = 0.3

	_box(root, Vector3(size.x + 0.16, plinth_h, size.z + 0.16), Vector3(0, plinth_h * 0.5, 0), stone, true)
	_box(root, Vector3(size.x, wall_h - plinth_h, size.z), Vector3(0, plinth_h + (wall_h - plinth_h) * 0.5, 0), wall, true)
	_box(root, Vector3(size.x + 0.24, 0.16, size.z + 0.24), Vector3(0, wall_h - 0.08, 0), trim, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(root, Vector3(0.36, wall_h - plinth_h - 0.16, 0.36),
				Vector3(float(sx) * (hx - 0.08), plinth_h + (wall_h - plinth_h - 0.16) * 0.5, float(sz) * (hz - 0.08)), trim)
	# gable + roof slabs (ridge runs along Z)
	var pm := PrismMesh.new()
	pm.size = Vector3(size.x, rise, size.z)
	_add(root, pm, wall, Vector3(0, wall_h + rise * 0.5, 0), Vector3.ZERO, true)
	var ov: float = 0.4
	var th: float = atan2(rise, hx)
	var run: float = hx + ov
	var slab_len: float = run / cos(th) + 0.12
	var slab_t: float = 0.16
	var roof := _roof_mat()
	for s in [1.0, -1.0]:
		var sg: float = float(s)
		var mx: float = sg * run * 0.5
		var my: float = wall_h + rise - tan(th) * run * 0.5
		var off := Vector3(sg * sin(th), cos(th), 0.0) * (slab_t * 0.5)
		_box(root, Vector3(slab_len, slab_t, size.z + 0.5), Vector3(mx, my, 0) + off, roof, true, Vector3(0, 0, -sg * rad_to_deg(th)))
	_cyl(root, 0.13, 0.13, size.z + 0.5, Vector3(0, wall_h + rise + 0.1, 0), _mat(Color(0.62, 0.2, 0.15), 0.8, true),
		Vector3(90, 0, 0), true, 10)
	# chimney
	_box(root, Vector3(0.7, rise + 0.9, 0.7), Vector3(-hx * 0.55, wall_h + (rise + 0.9) * 0.5, -hz * 0.45), brick_dark, true)
	_box(root, Vector3(0.9, 0.14, 0.9), Vector3(-hx * 0.55, wall_h + rise + 0.9, -hz * 0.45), trim, true)
	# round gable windows
	var pane := _glow_mat(Color(0.55, 0.8, 0.95), Color(1.0, 0.8, 0.4), 2.0)
	for sz in [-1.0, 1.0]:
		var zz: float = float(sz) * (hz + 0.02)
		_cyl(root, 0.4, 0.4, 0.05, Vector3(0, wall_h + 0.42, zz), trim, Vector3(90, 0, 0), false, 20)
		_cyl(root, 0.3, 0.3, 0.06, Vector3(0, wall_h + 0.42, zz + float(sz) * 0.005), pane, Vector3(90, 0, 0), false, 20)

	# door on +X face
	var fx: float = hx
	_box(root, Vector3(0.16, 2.3, 2.15), Vector3(fx + 0.05, plinth_h + 1.15, 0), trim, true)
	_box(root, Vector3(0.1, 2.1, 1.8), Vector3(fx + 0.1, plinth_h + 1.05, 0), wood)
	_box(root, Vector3(0.03, 2.1, 0.05), Vector3(fx + 0.16, plinth_h + 1.05, 0), _mat(Color(0.3, 0.17, 0.1), 0.8), false, Vector3.ZERO, false)
	for sz in [-1.0, 1.0]:
		_box(root, Vector3(0.03, 0.6, 0.6), Vector3(fx + 0.16, plinth_h + 1.55, float(sz) * 0.45), pane, false, Vector3.ZERO, false)
		_sph(root, 0.055, Vector3(fx + 0.18, plinth_h + 1.0, float(sz) * 0.12), _mat(Color(1.0, 0.8, 0.2), 0.3), 1.0, false)
	_box(root, Vector3(0.18, 0.15, 2.8), Vector3(fx + 0.16, 0.075, 0), stone, true)
	var aw := _awning(2.7, 0.75, 0.25, 7, Color(0.85, 0.2, 0.2), Color(1, 1, 1))
	aw.position = Vector3(fx + 0.1, plinth_h + 2.45, 0)
	root.add_child(aw)

	# windows (MultiMesh: frames, panes, shutters, flower boxes, flowers)
	var frames: Array[Transform3D] = []
	var panes: Array[Transform3D] = []
	var shut: Array[Transform3D] = []
	var boxes: Array[Transform3D] = []
	var flw: Array[Transform3D] = []
	var flc := PackedColorArray()
	var fcols: Array[Color] = [Color(1.0, 0.4, 0.55), Color(0.35, 0.78, 0.3), Color(1.0, 0.85, 0.2), Color(0.35, 0.78, 0.3), Color(1, 1, 1), Color(0.35, 0.78, 0.3)]
	var wy: float = 1.85
	var spots: Array = []
	for z in [-4.5, -2.6, 2.6, 4.5]:
		spots.append([Vector3(hx, wy, float(z)), 0.0])
	for x in [-1.2, 1.2]:
		spots.append([Vector3(float(x), wy, hz), -90.0])
		spots.append([Vector3(float(x), wy, -hz), 90.0])
	for sp: Array in spots:
		var p: Vector3 = sp[0]
		var yaw_deg: float = sp[1]
		var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
		frames.append(Transform3D(b, p + b * Vector3(0.035, 0, 0)))
		panes.append(Transform3D(b, p + b * Vector3(0.06, 0, 0)))
		for sg in [-1.0, 1.0]:
			shut.append(Transform3D(b, p + b * Vector3(0.05, 0, float(sg) * 0.71)))
		boxes.append(Transform3D(b, p + b * Vector3(0.16, -0.78, 0)))
		for k in 6:
			var zo: float = -0.5 + float(k) * 0.2
			flw.append(Transform3D(b, p + b * Vector3(0.16, -0.64, zo)))
			flc.append(fcols[k])
	_multi(root, _bm(Vector3(0.07, 1.46, 1.16)), trim, frames, PackedColorArray(), true)
	_multi(root, _bm(Vector3(0.05, 1.3, 1.0)), _pane_mat(), panes, PackedColorArray(), false)
	_multi(root, _bm(Vector3(0.05, 1.46, 0.26)), _mat(Color(0.22, 0.6, 0.62), 0.85), shut, PackedColorArray(), false)
	_multi(root, _bm(Vector3(0.3, 0.2, 1.2)), wood, boxes, PackedColorArray(), true)
	_multi(root, _sm(0.1, 1.0, 10, 5), _vc_mat(0.8), flw, flc, false)

	# readable roof billboard (camera looks from +Z and above)
	var by: float = wall_h + rise + 1.15
	var piv := Node3D.new()
	piv.position = Vector3(0, by, hz * 0.28)
	piv.rotation_degrees.x = -28.0
	root.add_child(piv)
	var board_w: float = minf(size.x + 1.0, 5.8)
	_box(piv, Vector3(board_w, 1.5, 0.14), Vector3.ZERO, _mat(Color(0.2, 0.34, 0.62), 0.7), true)
	_box(piv, Vector3(board_w - 0.3, 1.3, 0.04), Vector3(0, 0, 0.08), _mat(Color(0.99, 0.92, 0.7), 0.8), false, Vector3.ZERO, false)
	var l1 := _label("ДОМ ПРЕСТАРЕЛЫХ", 72, board_w - 0.7, Color(0.15, 0.2, 0.4), Color(1, 0.95, 0.8, 0), 0)
	l1.position = Vector3(0, 0.38, 0.11)
	piv.add_child(l1)
	var l2 := _label("«ЗАКАТ»", 130, board_w - 1.2, Color(0.88, 0.18, 0.18), Color(1, 0.95, 0.8, 0), 0)
	l2.position = Vector3(0, -0.22, 0.11)
	piv.add_child(l2)
	for sx in [-1.0, 1.0]:
		var px: float = float(sx) * (board_w * 0.5 - 0.5)
		var ry: float = wall_h + rise * (1.0 - absf(px) / hx) if absf(px) < hx else wall_h - 0.1
		_box(root, Vector3(0.14, by - 0.35 - ry, 0.14), Vector3(px, ry + (by - 0.35 - ry) * 0.5, hz * 0.28), _mat(Color(0.4, 0.28, 0.2), 0.9))
	# facade sign on +X (text runs along Z)
	var fb: float = minf(size.z - 3.0, 6.4)
	_box(root, Vector3(0.1, 0.5, fb), Vector3(fx + 0.07, 3.0, 0), _mat(Color(0.2, 0.34, 0.62), 0.7), false, Vector3.ZERO, false)
	var fl := _label("ДОМ ПРЕСТАРЕЛЫХ «ЗАКАТ»", 72, fb - 0.3, Color(1, 0.95, 0.75), Color(0.1, 0.12, 0.3), 8)
	fl.position = Vector3(fx + 0.13, 3.0, 0)
	fl.rotation_degrees.y = 90.0
	root.add_child(fl)
	return root


static func make_kebab_stand(size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "KebabStand"
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var body_c := _mat(Color(1.0, 0.72, 0.2), 0.85)
	var red := _mat(Color(0.88, 0.16, 0.14), 0.7, true)
	var cream := _mat(Color(0.84, 0.79, 0.66), 0.85)
	var wood := _mat(Color(0.7, 0.45, 0.24), 0.8)
	var body_top: float = size.y - 0.8
	var front_x: float = -hx + 0.8
	var gl_day := Color(0.3, 0.16, 0.1)

	_box(root, Vector3(size.x, 0.1, size.z), Vector3(0, 0.05, 0), _mat(Color(0.6, 0.57, 0.55), 0.95), false)
	var body_len: float = hx - front_x
	_box(root, Vector3(body_len, body_top - 0.1, size.z - 0.2), Vector3((hx + front_x) * 0.5, 0.1 + (body_top - 0.1) * 0.5, 0), body_c, true)
	_box(root, Vector3(0.8, 1.05, size.z - 0.2), Vector3(-hx + 0.4, 0.1 + 0.525, 0), cream, true)
	_box(root, Vector3(0.86, 0.07, size.z - 0.04), Vector3(-hx + 0.43, 1.18, 0), wood, true)
	for k in 4:
		_box(root, Vector3(0.02, 0.8, 0.35), Vector3(-hx - 0.0, 0.62, -1.5 + float(k) * 1.0), red, false, Vector3.ZERO, false)
	# serving hatch + frame
	_box(root, Vector3(0.05, 1.12, 2.35), Vector3(front_x - 0.02, 1.8, -0.8), cream, false, Vector3.ZERO, false)
	var inner := _glow_mat(gl_day, Color(1.0, 0.65, 0.25), 2.0)
	_box(root, Vector3(0.05, 0.96, 2.15), Vector3(front_x - 0.045, 1.8, -0.8), inner, false, Vector3.ZERO, false)
	# roof + chimney
	_box(root, Vector3(hx + 0.25 - front_x + 0.15, 0.2, size.z + 0.2), Vector3((hx + 0.25 + front_x - 0.15) * 0.5, body_top + 0.1, 0), red, true)
	_box(root, Vector3(0.1, 0.5, 0.1), Vector3(hx - 0.5, body_top + 0.45, -hz + 0.6), cream, false)
	_cyl(root, 0.14, 0.14, 0.45, Vector3(hx - 0.5, body_top + 0.7, -hz + 0.6), _mat(Color(0.5, 0.52, 0.56), 0.5, true), Vector3.ZERO, true, 12)
	# awning over the hatch (extends towards -X)
	var aw := _awning(2.5, 0.75, 0.35, 8, Color(0.88, 0.16, 0.14), Color(1, 1, 1))
	aw.rotation_degrees.y = 180.0
	aw.position = Vector3(front_x + 0.02, body_top - 0.05, -0.9)
	root.add_child(aw)
	# doner spit on the counter, beyond the awning
	var spit := Node3D.new()
	spit.name = "Spit"
	spit.position = Vector3(-hx + 0.45, 1.22, 0.6)
	root.add_child(spit)
	var meat := _mat(Color(0.66, 0.36, 0.16), 0.8, true)
	var meat2 := _mat(Color(0.82, 0.5, 0.22), 0.8)
	var steel := _mat(Color(0.75, 0.77, 0.8), 0.3)
	_cyl(spit, 0.03, 0.03, 1.15, Vector3(0, 0.55, 0), steel, Vector3.ZERO, false, 8)
	_cyl(spit, 0.28, 0.17, 0.78, Vector3(0, 0.55, 0), meat, Vector3.ZERO, true, 20)
	for i in 3:
		var yy: float = 0.28 + 0.22 * float(i)
		var rr: float = 0.2 + 0.04 * float(i)
		_cyl(spit, rr + 0.025, rr + 0.025, 0.05, Vector3(0, yy, 0), meat2, Vector3.ZERO, false, 18)
	for i in 5:
		var a: float = float(i) * 1.9
		_sph(spit, 0.075, Vector3(cos(a) * 0.23, 0.35 + 0.1 * float(i), sin(a) * 0.23), meat2, 1.0, false)
	_sph(spit, 0.12, Vector3(0, 1.0, 0), _mat(Color(0.9, 0.2, 0.15), 0.6), 1.0, false)
	_cyl(root, 0.26, 0.26, 0.04, Vector3(-hx + 0.45, 1.24, 0.6), steel, Vector3.ZERO, false, 16)
	# red-hot heater strip beside the spit
	_box(root, Vector3(0.06, 0.8, 0.3), Vector3(-hx + 0.8, 1.9, 0.6), _glow_mat(Color(1.0, 0.45, 0.1), Color(1.0, 0.4, 0.1), 2.5), false, Vector3.ZERO, false)
	# menu board
	var mb := _mat(Color(0.14, 0.26, 0.2), 0.9)
	_box(root, Vector3(0.06, 1.0, 1.0), Vector3(front_x - 0.03, 1.8, 1.6), mb, true)
	var menu: Array = [["МЕНЮ", 0.35, 80, Color(1, 0.9, 0.3)], ["ШАУРМА", 0.0, 64, Color(1, 1, 1)], ["ЧАЙ", -0.25, 64, Color(1, 1, 1)]]
	for ml: Array in menu:
		var t: String = ml[0]
		var my: float = ml[1]
		var fs: int = ml[2]
		var mc: Color = ml[3]
		var lab := _label(t, fs, 0.8, mc, Color(0, 0, 0, 0), 0)
		lab.position = Vector3(front_x - 0.07, 1.8 + my, 1.6)
		lab.rotation_degrees.y = -90.0
		root.add_child(lab)
	# front fascia sign facing -X
	_box(root, Vector3(0.12, 0.62, size.z - 0.3), Vector3(front_x - 0.2, body_top + 0.5, 0), cream, true)
	var fl := _label("ШАУРМА", 110, size.z - 1.4, Color(0.88, 0.16, 0.14), Color(1, 1, 1, 0.0), 0)
	fl.position = Vector3(front_x - 0.27, body_top + 0.5, 0)
	fl.rotation_degrees.y = -90.0
	root.add_child(fl)
	# roof billboard facing +Z (readable from the game camera)
	var piv := Node3D.new()
	piv.position = Vector3(0.55, body_top + 1.0, 0.4)
	piv.rotation_degrees.x = -26.0
	root.add_child(piv)
	_box(piv, Vector3(3.5, 0.95, 0.12), Vector3.ZERO, _mat(Color(0.88, 0.16, 0.14), 0.7), true)
	_box(piv, Vector3(3.3, 0.77, 0.04), Vector3(0, 0, 0.07), _mat(Color(1.0, 0.92, 0.55), 0.8), false, Vector3.ZERO, false)
	var rl := _label("ШАУРМА", 120, 3.0, Color(0.85, 0.12, 0.1), Color(0.5, 0.05, 0.05, 0.0), 0)
	rl.position = Vector3(0, 0, 0.1)
	piv.add_child(rl)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.12, 0.7, 0.12), Vector3(0.55 + float(sx) * 1.4, body_top + 0.35 + 0.2, 0.4), _mat(Color(0.4, 0.28, 0.2), 0.9))
	# side window on +Z wall
	_box(root, Vector3(1.3, 1.0, 0.06), Vector3(0.7, 1.55, hz - 0.1 + 0.03), cream, false, Vector3.ZERO, false)
	_box(root, Vector3(1.1, 0.8, 0.06), Vector3(0.7, 1.55, hz - 0.1 + 0.05), _pane_mat(), false, Vector3.ZERO, false)
	_box(root, Vector3(0.3, 0.8, 0.05), Vector3(-0.2, 1.55, hz - 0.1 + 0.05), red, false, Vector3.ZERO, false)
	_box(root, Vector3(0.3, 0.8, 0.05), Vector3(1.6, 1.55, hz - 0.1 + 0.05), red, false, Vector3.ZERO, false)
	var gl := OmniLight3D.new()
	gl.name = "Glow"
	gl.position = Vector3(-hx + 0.2, 1.9, -0.2)
	gl.omni_range = 6.0
	gl.light_energy = 1.6
	gl.light_color = Color(1.0, 0.7, 0.35)
	gl.shadow_enabled = false
	gl.visible = false
	root.add_child(gl)
	return root


static func make_banana_cart() -> Node3D:
	var root := Node3D.new()
	root.name = "BananaCart"
	var teal := _mat(Color(0.16, 0.7, 0.78), 0.7, true)
	var white := _mat(Color(0.98, 0.97, 0.92), 0.7)
	var wood := _mat(Color(0.72, 0.46, 0.24), 0.85, true)
	var dark := _mat(Color(0.32, 0.2, 0.12), 0.9, true)
	_box(root, Vector3(1.4, 0.5, 0.9), Vector3(0, 0.66, 0), teal, true)
	_box(root, Vector3(1.42, 0.08, 0.92), Vector3(0, 0.46, 0), white)
	_box(root, Vector3(1.28, 0.03, 0.78), Vector3(0, 0.915, 0), _mat(Color(0.9, 0.7, 0.4), 0.9), false, Vector3.ZERO, false)
	for sz in [-1.0, 1.0]:
		_box(root, Vector3(1.4, 0.14, 0.06), Vector3(0, 0.97, float(sz) * 0.42), wood, true)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.06, 0.14, 0.9), Vector3(float(sx) * 0.67, 0.97, 0), wood, true)
	for sz in [-1.0, 1.0]:
		_cyl(root, 0.3, 0.3, 0.07, Vector3(0.3, 0.3, float(sz) * 0.5), dark, Vector3(90, 0, 0), true, 18)
		_cyl(root, 0.09, 0.09, 0.1, Vector3(0.3, 0.3, float(sz) * 0.51), _mat(Color(1.0, 0.8, 0.2), 0.4), Vector3(90, 0, 0), false, 10)
		_box(root, Vector3(0.7, 0.05, 0.05), Vector3(-1.0, 0.7, float(sz) * 0.32), wood, false, Vector3(0, 0, 8))
	_box(root, Vector3(0.08, 0.45, 0.7), Vector3(-0.55, 0.22, 0), dark)
	# umbrella (leans over the back half so bananas stay visible from +Z)
	_cyl(root, 0.025, 0.025, 1.7, Vector3(-0.45, 1.75, -0.38), _mat(Color(0.8, 0.8, 0.82), 0.4), Vector3.ZERO, false, 8)
	var um := StandardMaterial3D.new()
	um.albedo_texture = _stripe_tex()
	um.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	um.roughness = 0.8
	um.cull_mode = BaseMaterial3D.CULL_DISABLED
	um.next_pass = _outline()
	_add(root, _cm(0.02, 1.0, 0.4, 24, true, false), um, Vector3(-0.45, 2.12, -0.38), Vector3.ZERO, true)
	_sph(root, 0.06, Vector3(-0.45, 2.36, -0.38), _mat(Color(1, 0.8, 0.2), 0.4), 1.0, false)
	# sign on the front panel (faces +Z)
	_box(root, Vector3(1.1, 0.34, 0.03), Vector3(0, 0.66, 0.46), white, false, Vector3.ZERO, false)
	var sl := _label("БАНАНЫ", 84, 1.0, Color(0.95, 0.65, 0.05), Color(0.3, 0.15, 0.0), 10)
	sl.position = Vector3(0, 0.66, 0.485)
	root.add_child(sl)
	# banana stock
	for i in 3:
		var st := Node3D.new()
		st.name = "Stock%d" % i
		st.position = Vector3(-0.42 + 0.42 * float(i), 0.96, 0.02)
		root.add_child(st)
		for j in 4:
			var b := _add(st, _banana_mesh(), _banana_mat(), Vector3(0.02 * float(j % 2), 0.03 + 0.045 * float(j), 0.0), Vector3.ZERO, true)
			b.rotation_degrees = Vector3(0.0 if j % 2 == 0 else 80.0, -36.0 + 24.0 * float(j), 0.0)
			b.scale = Vector3.ONE * 1.15
	return root


static func make_bench(length: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Bench"
	var wood := _mat(Color(0.82, 0.52, 0.26), 0.8, true)
	var wood2 := _mat(Color(0.74, 0.44, 0.2), 0.8, true)
	var iron := _mat(Color(0.2, 0.28, 0.42), 0.5, true)
	var sh: float = 0.45
	for i in 3:
		_box(root, Vector3(length, 0.06, 0.2), Vector3(0, sh, -0.18 + 0.2 * float(i)), wood if i % 2 == 0 else wood2, true)
	for i in 3:
		var yy: float = sh + 0.2 + 0.17 * float(i)
		_box(root, Vector3(length, 0.14, 0.05), Vector3(0, yy, -0.36 - 0.045 * float(i)), wood if i % 2 == 0 else wood2, true, Vector3(-10, 0, 0))
	for sx in [-1.0, 1.0]:
		var x: float = float(sx) * (length * 0.5 - 0.14)
		_box(root, Vector3(0.08, sh, 0.62), Vector3(x, sh * 0.5, 0.0), iron, true)
		_box(root, Vector3(0.1, 0.07, 0.6), Vector3(x, sh + 0.28, 0.0), iron, true)
		_box(root, Vector3(0.08, 0.3, 0.08), Vector3(x, sh + 0.14, 0.26), iron, true)
		_box(root, Vector3(0.08, 0.95, 0.07), Vector3(x, 0.47, -0.4), iron, true, Vector3(-10, 0, 0))
	return root


static func make_entrance_zone(size: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "EntranceZone"
	var top: float = 0.04
	_add(root, _bm(Vector3(size.x, top, size.y)), _mat(Color(0.2, 0.42, 0.92), 0.8), Vector3(0, top * 0.5, 0), Vector3.ZERO, false)
	_zone_border(root, size, top, _glow_mat_on(Color(0.45, 0.88, 1.0), 2.0))
	var fill := _fill(size, top + 0.01, Color(0.45, 0.82, 1.0))
	root.add_child(fill)
	var l := _label("ВХОД", 80, size.x * 0.85, Color(1, 1, 1), Color(0.05, 0.15, 0.5), 12)
	l.rotation_degrees.x = -90.0
	l.position = Vector3(0, top + 0.03, 0.0)
	root.add_child(l)
	return root


static func make_order_zone(size: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "OrderZone"
	var top: float = 0.04
	_add(root, _bm(Vector3(size.x, top, size.y)), _mat(Color(1.0, 0.55, 0.12), 0.8), Vector3(0, top * 0.5, 0), Vector3.ZERO, false)
	_zone_border(root, size, top, _glow_mat_on(Color(1.0, 0.85, 0.2), 2.0))
	var fill := _fill(size, top + 0.01, Color(1.0, 0.85, 0.3))
	root.add_child(fill)
	var l := _label("ЗАКАЗ", 80, size.x * 0.85, Color(1, 1, 1), Color(0.6, 0.12, 0.05), 12)
	l.rotation_degrees.x = -90.0
	l.position = Vector3(0, top + 0.03, size.y * 0.28)
	root.add_child(l)
	var metal := _mat(Color(0.22, 0.22, 0.28), 0.4, true)
	var zc: float = -size.y * 0.12
	_cyl(root, 0.07, 0.09, 0.5, Vector3(0, 0.3, zc), metal, Vector3.ZERO, true, 12)
	_cyl(root, 0.26, 0.3, 0.12, Vector3(0, 0.6, zc), metal, Vector3.ZERO, true, 20)
	_cyl(root, 0.2, 0.2, 0.03, Vector3(0, 0.67, zc), _mat(Color(1.0, 0.8, 0.2), 0.3), Vector3.ZERO, false, 20)
	_sph(root, 0.17, Vector3(0, 0.67, zc), _glow_mat_on(Color(1.0, 0.15, 0.15), 1.2), 0.75, true)
	return root


# ----------------------------------------------------------------------------
# Helpers: caches, primitives
# ----------------------------------------------------------------------------

static func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


static func _outline() -> StandardMaterial3D:
	if _outline_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = OUTLINE_COL
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_FRONT
		m.grow = true
		m.grow_amount = GROW
		_outline_mat = m
	return _outline_mat


static func _flat_black() -> StandardMaterial3D:
	if _flat_black_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = OUTLINE_COL
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_FRONT
		_flat_black_mat = m
	return _flat_black_mat


static func _mat(c: Color, rough: float = 0.85, outline: bool = false) -> StandardMaterial3D:
	var key: String = "m%s|%.2f|%d" % [c.to_html(true), rough, 1 if outline else 0]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic_specular = 0.3
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if outline:
		m.next_pass = _outline()
	_mats[key] = m
	return m


## Vertex-colour material (instance/mesh colours drive albedo).
static func _vc_mat(rough: float, tint: Color = Color.WHITE, outline: bool = false) -> StandardMaterial3D:
	var key: String = "v%.2f|%s|%d" % [rough, tint.to_html(true), 1 if outline else 0]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.roughness = rough
	m.metallic_specular = 0.2
	if outline:
		m.next_pass = _outline()
	_mats[key] = m
	return m


static func _unshaded(c: Color) -> StandardMaterial3D:
	var key: String = "u%s" % c.to_html(true)
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## Emissive only at night (toggled by set_night).
static func _glow_mat(day: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var key: String = "g%s|%s|%.1f" % [day.to_html(true), glow.to_html(true), energy]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = day
	m.roughness = 0.4
	m.emission = glow
	m.emission_energy_multiplier = energy
	m.emission_enabled = _night
	_mats[key] = m
	_glow.append(m)
	return m


## Always emissive (zone borders, buttons).
static func _glow_mat_on(c: Color, energy: float) -> StandardMaterial3D:
	var key: String = "go%s|%.1f" % [c.to_html(true), energy]
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func _bm(size: Vector3) -> BoxMesh:
	var key: String = "b" + str(size)
	if _meshes.has(key):
		return _meshes[key] as BoxMesh
	var m := BoxMesh.new()
	m.size = size
	_meshes[key] = m
	return m


static func _sm(radius: float, ratio: float = 1.0, seg: int = 20, rings: int = 10) -> SphereMesh:
	var key: String = "s%.3f|%.3f|%d|%d" % [radius, ratio, seg, rings]
	if _meshes.has(key):
		return _meshes[key] as SphereMesh
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * ratio
	m.radial_segments = seg
	m.rings = rings
	_meshes[key] = m
	return m


static func _cm(top: float, bottom: float, h: float, seg: int = 20, cap_top: bool = true, cap_bottom: bool = true) -> CylinderMesh:
	var key: String = "c%.3f|%.3f|%.3f|%d|%d%d" % [top, bottom, h, seg, 1 if cap_top else 0, 1 if cap_bottom else 0]
	if _meshes.has(key):
		return _meshes[key] as CylinderMesh
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	m.cap_top = cap_top
	m.cap_bottom = cap_bottom
	_meshes[key] = m
	return m


static func _add(parent: Node, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent != null:
		parent.add_child(mi)
	return mi


## Box with optional black outline (an inflated back-face-only child, so edges stay closed).
static func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material, outline: bool = false, rot_deg: Vector3 = Vector3.ZERO, shadow: bool = true) -> MeshInstance3D:
	var mi := _add(parent, _bm(size), mat, pos, rot_deg, shadow)
	if outline:
		var o := MeshInstance3D.new()
		o.mesh = _bm(size + Vector3.ONE * GROW * 2.0)
		o.material_override = _flat_black()
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(o)
	return mi


static func _sph(parent: Node, radius: float, pos: Vector3, mat: Material, ratio: float = 1.0, shadow: bool = true) -> MeshInstance3D:
	return _add(parent, _sm(radius, ratio), mat, pos, Vector3.ZERO, shadow)


static func _cyl(parent: Node, top: float, bottom: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, shadow: bool = true, seg: int = 20) -> MeshInstance3D:
	return _add(parent, _cm(top, bottom, h, seg), mat, pos, rot_deg, shadow)


static func _multi(parent: Node, mesh: Mesh, mat: Material, xf: Array[Transform3D], cols: PackedColorArray, shadow: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var use_c: bool = cols.size() == xf.size() and xf.size() > 0
	mm.use_colors = use_c
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if use_c:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	if not shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


static func _label(text: String, font_px: int, max_w: float, col: Color, ocol: Color, ol: int) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_px
	l.outline_size = ol
	l.modulate = col
	l.outline_modulate = ocol
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	var font: Font = ThemeDB.fallback_font
	var wpx: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x + float(ol) * 2.0
	l.pixel_size = minf(0.01, max_w / maxf(wpx, 1.0))
	return l


static func _fill(size: Vector2, y: float, c: Color) -> MeshInstance3D:
	var fz: float = size.y - 0.3
	var pm := PlaneMesh.new()
	pm.size = Vector2(size.x - 0.3, fz)
	pm.center_offset = Vector3(0, 0, fz * 0.5)
	var mi := _add(null, pm, _glow_mat_on(c, 0.6), Vector3(0, y, -fz * 0.5), Vector3.ZERO, false)
	mi.name = "Fill"
	mi.scale = Vector3(1, 1, 0.001)
	return mi


static func _zone_border(root: Node3D, size: Vector2, top: float, mat: Material) -> void:
	var t: float = 0.1
	var h: float = 0.02
	_add(root, _bm(Vector3(size.x, h, t)), mat, Vector3(0, top + h * 0.5 - 0.005, -size.y * 0.5 + t * 0.5), Vector3.ZERO, false)
	_add(root, _bm(Vector3(size.x, h, t)), mat, Vector3(0, top + h * 0.5 - 0.005, size.y * 0.5 - t * 0.5), Vector3.ZERO, false)
	_add(root, _bm(Vector3(t, h, size.y - t * 2.0)), mat, Vector3(-size.x * 0.5 + t * 0.5, top + h * 0.5 - 0.005, 0), Vector3.ZERO, false)
	_add(root, _bm(Vector3(t, h, size.y - t * 2.0)), mat, Vector3(size.x * 0.5 - t * 0.5, top + h * 0.5 - 0.005, 0), Vector3.ZERO, false)


## Striped awning hanging off the wall at x=0, extending towards +X, top edge at y=0.
static func _awning(width: float, depth: float, drop: float, stripes: int, c1: Color, c2: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Awning"
	var sw: float = width / float(stripes)
	var slen: float = sqrt(depth * depth + drop * drop)
	var ang: float = rad_to_deg(atan2(drop, depth))
	var slabs: Array[Transform3D] = []
	var vals: Array[Transform3D] = []
	var scal: Array[Transform3D] = []
	var cols := PackedColorArray()
	for i in stripes:
		var zc: float = -width * 0.5 + sw * (float(i) + 0.5)
		slabs.append(Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(-ang)), Vector3(depth * 0.5, -drop * 0.5, zc)))
		vals.append(Transform3D(Basis.IDENTITY, Vector3(depth, -drop - 0.07, zc)))
		scal.append(Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(90.0)), Vector3(depth, -drop - 0.14, zc)))
		cols.append(c1 if i % 2 == 0 else c2)
	var m := _vc_mat(0.8)
	_multi(root, _bm(Vector3(slen, 0.05, sw)), m, slabs, cols, true)
	_multi(root, _bm(Vector3(0.05, 0.14, sw)), m, vals, cols, false)
	_multi(root, _cm(sw * 0.5, sw * 0.5, 0.05, 14), m, scal, cols, false)
	return root


# ----------------------------------------------------------------------------
# Helpers: materials with textures
# ----------------------------------------------------------------------------

static func _tri_mat(key: String, tex: Texture2D, scale: float, world: bool, tint: Color = Color.WHITE) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = 0.95
	m.metallic_specular = 0.2
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


static func _brick_mat() -> StandardMaterial3D:
	return _tri_mat("brick", _brick_tex(), 1.0, false)


static func _path_mat() -> StandardMaterial3D:
	return _tri_mat("path", _cobble_tex(), 0.9, true)


static func _roof_mat() -> StandardMaterial3D:
	return _tri_mat("roof", _roof_tex(), 0.8, false)


static func _pane_mat() -> StandardMaterial3D:
	if _mats.has("pane"):
		return _mats["pane"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_texture = _window_tex(false)
	m.roughness = 0.25
	m.emission_texture = _window_tex(true)
	m.emission = Color.WHITE
	m.emission_energy_multiplier = 1.1
	m.emission_enabled = _night
	_mats["pane"] = m
	_glow.append(m)
	return m


static func _hash2(a: int, b: int) -> float:
	return fposmod(sin(float(a) * 12.9898 + float(b) * 78.233) * 43758.5453, 1.0)


static func _finish(key: String, img: Image) -> ImageTexture:
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_texs[key] = t
	return t


static func _grass_tex() -> ImageTexture:
	if _texs.has("grass"):
		return _texs["grass"] as ImageTexture
	var n := FastNoiseLite.new()
	n.seed = 31
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 3
	var src: Image = n.get_seamless_image(128, 128)
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
	var a := Color(0.3, 0.64, 0.2)
	var b := Color(0.44, 0.76, 0.24)
	for y in 128:
		for x in 128:
			var v: float = clampf(src.get_pixel(x, y).r * 1.6 - 0.2, 0.0, 1.0)
			var c: Color = a.lerp(b, v)
			var spot: float = _hash2(x >> 1, y >> 1)
			if spot > 0.93:
				c = c.darkened(0.12)
			elif spot < 0.04:
				c = c.lightened(0.1)
			img.set_pixel(x, y, c)
	return _finish("grass", img)


static func _brick_tex() -> ImageTexture:
	if _texs.has("brick"):
		return _texs["brick"] as ImageTexture
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
	var mortar := Color(0.93, 0.87, 0.74)
	for y in 128:
		var row: int = y >> 5
		var ly: int = y & 31
		for x in 128:
			var xo: int = (x + (row & 1) * 32) & 127
			var col: int = xo >> 6
			var lx: int = xo & 63
			if lx < 3 or ly < 3:
				img.set_pixel(x, y, mortar)
				continue
			var h: float = _hash2(col + row * 2, row)
			var c := Color(0.86, 0.42, 0.28).lerp(Color(0.95, 0.58, 0.34), h)
			if ly > 27:
				c = c.darkened(0.12)
			elif ly < 6:
				c = c.lightened(0.07)
			img.set_pixel(x, y, c)
	return _finish("brick", img)


static func _cobble_tex() -> ImageTexture:
	if _texs.has("cobble"):
		return _texs["cobble"] as ImageTexture
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
	var gap := Color(0.66, 0.5, 0.32)
	for y in 128:
		var row: int = y >> 5
		var ly: int = y & 31
		for x in 128:
			var xo: int = (x + (row & 1) * 16) & 127
			var col: int = xo >> 5
			var lx: int = xo & 31
			var dx: float = absf(float(lx) - 15.5) / 14.5
			var dy: float = absf(float(ly) - 15.5) / 14.5
			var e: float = pow(dx, 4.0) + pow(dy, 4.0)
			if e > 1.0:
				img.set_pixel(x, y, gap)
				continue
			var h: float = _hash2(col + 7, row + 3)
			var c := Color(0.9, 0.74, 0.5).lerp(Color(0.8, 0.62, 0.4), h)
			c = c.darkened(clampf(e * 0.18, 0.0, 0.2))
			img.set_pixel(x, y, c)
	return _finish("cobble", img)


static func _roof_tex() -> ImageTexture:
	if _texs.has("roof"):
		return _texs["roof"] as ImageTexture
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			# rows vary along x (down the slope), tiles along y
			var row: int = x >> 4
			var lx: int = x & 15
			var yo: int = (y + (row & 1) * 8) & 63
			var col: int = yo >> 4
			var ly: int = yo & 15
			var h: float = _hash2(col + 3, row)
			var c := Color(0.86, 0.3, 0.22).lerp(Color(0.95, 0.42, 0.26), h)
			if lx > 12:
				c = c.darkened(0.3)
			elif lx < 3:
				c = c.lightened(0.08)
			if ly < 1 or ly > 14:
				c = c.darkened(0.15)
			img.set_pixel(x, y, c)
	return _finish("roof", img)


static func _window_tex(emit: bool) -> ImageTexture:
	var key: String = "win_e" if emit else "win"
	if _texs.has(key):
		return _texs[key] as ImageTexture
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var bar: bool = x < 4 or x > 59 or y < 4 or y > 59 or absi(x - 32) < 2 or absi(y - 32) < 2
			var c: Color
			if emit:
				c = Color(0, 0, 0) if bar else Color(1.0, 0.82, 0.45).lerp(Color(1.0, 0.65, 0.3), float(y) / 64.0)
			else:
				c = Color(1, 1, 1) if bar else Color(0.62, 0.84, 0.98).lerp(Color(0.38, 0.62, 0.9), float(y) / 64.0)
				if not bar and absi((x + y) % 32 - 16) < 3:
					c = c.lightened(0.25)
			img.set_pixel(x, y, c)
	return _finish(key, img)


static func _stripe_tex() -> ImageTexture:
	if _texs.has("stripe"):
		return _texs["stripe"] as ImageTexture
	var img := Image.create_empty(64, 4, false, Image.FORMAT_RGB8)
	for y in 4:
		for x in 64:
			img.set_pixel(x, y, Color(1.0, 0.78, 0.1) if ((x >> 3) & 1) == 0 else Color(1, 1, 1))
	var t := ImageTexture.create_from_image(img)
	_texs["stripe"] = t
	return t


# ----------------------------------------------------------------------------
# Helpers: custom meshes
# ----------------------------------------------------------------------------

static func _vtx(st: SurfaceTool, p: Vector3, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	st.add_vertex(p)


## Single triangle wound clockwise as seen from the side its normals point to (needed for outlines).
static func _tri1(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var g: Vector3 = (b - a).cross(c - a)
	if g.dot(na + nb + nc) > 0.0:
		_vtx(st, a, na, ca)
		_vtx(st, c, nc, cc)
		_vtx(st, b, nb, cb)
	else:
		_vtx(st, a, na, ca)
		_vtx(st, b, nb, cb)
		_vtx(st, c, nc, cc)


## Both windings are emitted so the mesh renders whatever the culling/winding.
static func _tri2(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	_vtx(st, a, na, ca)
	_vtx(st, b, nb, cb)
	_vtx(st, c, nc, cc)
	_vtx(st, a, na, ca)
	_vtx(st, c, nc, cc)
	_vtx(st, b, nb, cb)


static func _tuft_mesh() -> ArrayMesh:
	if _meshes.has("tuft"):
		return _meshes["tuft"] as ArrayMesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Color(0.2, 0.52, 0.16)
	var tip := Color(0.62, 0.92, 0.32)
	for k in 6:
		var a: float = float(k) * TAU / 6.0 + 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var h: float = 0.17 + 0.07 * float(k % 3)
		var p0: Vector3 = dir * 0.035
		_tri2(st, p0 - side * 0.03, p0 + side * 0.03, p0 + dir * 0.09 + Vector3(0, h, 0),
			Vector3.UP, Vector3.UP, Vector3.UP, base, base, tip)
	var m: ArrayMesh = st.commit()
	_meshes["tuft"] = m
	return m


static func _flower_mesh(petal: Color) -> ArrayMesh:
	var key: String = "flower" + petal.to_html(false)
	if _meshes.has(key):
		return _meshes[key] as ArrayMesh
	var m := ArrayMesh.new()
	var stem := SurfaceTool.new()
	stem.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sc := Color(0.3, 0.7, 0.22)
	_tri2(stem, Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0), Vector3(0, 0.17, 0), Vector3.UP, Vector3.UP, Vector3.UP, sc, sc, sc)
	_tri2(stem, Vector3(0, 0, -0.012), Vector3(0, 0, 0.012), Vector3(0, 0.17, 0), Vector3.UP, Vector3.UP, Vector3.UP, sc, sc, sc)
	stem.commit(m)
	var head := SurfaceTool.new()
	head.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cen := Vector3(0, 0.185, 0)
	var np := 6
	for i in np:
		var a0: float = float(i) * TAU / float(np)
		var a1: float = a0 + TAU / float(np) * 0.5
		var a2: float = a0 + TAU / float(np)
		var r: float = 0.095
		var p0 := cen + Vector3(cos(a0), 0.0, sin(a0)) * r
		var pm := cen + Vector3(cos(a1), 0.0, sin(a1)) * r * 0.55
		var p2 := cen + Vector3(cos(a2), 0.0, sin(a2)) * r
		_tri2(head, cen, p0, pm, Vector3.UP, Vector3.UP, Vector3.UP, petal, petal, petal)
		_tri2(head, cen, pm, p2, Vector3.UP, Vector3.UP, Vector3.UP, petal, petal, petal)
	head.commit(m)
	var ctr := SurfaceTool.new()
	ctr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var yc := Color(1.0, 0.8, 0.1)
	for i in 6:
		var a0: float = float(i) * TAU / 6.0
		var a2: float = a0 + TAU / 6.0
		_tri2(ctr, cen + Vector3(0, 0.006, 0), cen + Vector3(cos(a0), 0.006, sin(a0)) * 0.035,
			cen + Vector3(cos(a2), 0.006, sin(a2)) * 0.035, Vector3.UP, Vector3.UP, Vector3.UP, yc, yc, yc)
	ctr.commit(m)
	var vm := _vc_mat(0.8)
	m.surface_set_material(0, vm)
	m.surface_set_material(1, vm)
	m.surface_set_material(2, vm)
	_meshes[key] = m
	return m


static func _banana_mesh() -> ArrayMesh:
	if _meshes.has("banana"):
		return _meshes["banana"] as ArrayMesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps: int = 10
	var sides: int = 6
	var rad: float = 0.24
	var rings: Array = []
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var a: float = lerpf(-0.85, 0.85, t)
		var c := Vector3(rad * sin(a), rad * (1.0 - cos(a)), 0.0)
		var nn := Vector3(-sin(a), cos(a), 0.0)
		var bb := Vector3(0, 0, 1)
		var r: float = 0.012 + 0.05 * pow(sin(PI * t), 0.5)
		var col := Color(1.0, 0.84, 0.12)
		if t < 0.1 or t > 0.9:
			col = Color(0.3, 0.2, 0.08)
		elif t < 0.2:
			col = Color(0.75, 0.8, 0.2)
		var ring: Array = []
		for j in sides:
			var ph: float = float(j) * TAU / float(sides)
			var n: Vector3 = nn * cos(ph) + bb * sin(ph)
			ring.append([c + n * r, n, col])
		rings.append(ring)
	for i in steps:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for j in sides:
			var j2: int = (j + 1) % sides
			var a0: Array = r0[j]
			var a1: Array = r0[j2]
			var b0: Array = r1[j]
			var b1: Array = r1[j2]
			_tri1(st, a0[0], b0[0], a1[0], a0[1], b0[1], a1[1], a0[2], b0[2], a1[2])
			_tri1(st, a1[0], b0[0], b1[0], a1[1], b0[1], b1[1], a1[2], b0[2], b1[2])
	var m: ArrayMesh = st.commit()
	_meshes["banana"] = m
	return m


static func _banana_mat() -> StandardMaterial3D:
	if _mats.has("banana"):
		return _mats["banana"] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.55
	m.next_pass = _outline()
	_mats["banana"] = m
	return m


# ----------------------------------------------------------------------------
# Helpers: ground-avoid test
# ----------------------------------------------------------------------------

static func _blocked(p: Vector2, size: Vector2, avoid: Array, use_default: bool) -> bool:
	for r in avoid:
		if r is Rect2 and (r as Rect2).has_point(p):
			return true
	if not use_default:
		return false
	var w := p + size * 0.5
	for r: Array in _AVOID_RECTS:
		var rx: float = r[0]
		var rz: float = r[1]
		var rw: float = r[2]
		var rh: float = r[3]
		if w.x > rx - 0.2 and w.x < rx + rw + 0.2 and w.y > rz - 0.2 and w.y < rz + rh + 0.2:
			return true
	for c: Array in _AVOID_CIRCLES:
		var cx: float = c[0]
		var cz: float = c[1]
		var cr: float = c[2]
		if w.distance_to(Vector2(cx, cz)) < cr:
			return true
	for s: Array in _AVOID_PATHS:
		var a := Vector2(float(s[0]), float(s[1]))
		var b := Vector2(float(s[2]), float(s[3]))
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(w, a, b)
		if closest.distance_to(w) < 0.85:
			return true
	return false
