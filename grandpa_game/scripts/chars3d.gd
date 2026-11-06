extends RefCounted
## Procedural 3D characters: Grandpa Semyon, Guard Valera, statues, banana peel, dizzy stars.
## Characters face +Z. animate_* only touches inner pivots, never the root transform.

const OUTLINE: float = 0.03
const G_LEAN: float = 0.40       # grandpa hunch (Upper pivot pitch)
const G_HEAD0: float = -0.36     # head pitch that cancels the hunch
const G_ARM0: float = -0.46      # arm pitch that makes arms hang vertically
const G_HIP: float = 0.42
const K_HIP: float = 0.72

const SKIN: Color = Color(0.98, 0.68, 0.57)
const WHITE: Color = Color(0.99, 0.99, 0.97)
const GREEN: Color = Color(0.27, 0.64, 0.30)
const BEIGE: Color = Color(1.0, 0.93, 0.72)
const BROWN: Color = Color(0.52, 0.33, 0.18)
const WOOD: Color = Color(0.66, 0.42, 0.18)
const BLACK: Color = Color(0.05, 0.05, 0.07)
const NAVY: Color = Color(0.13, 0.20, 0.47)
const NAVY2: Color = Color(0.17, 0.26, 0.56)
const GOLD: Color = Color(1.0, 0.80, 0.12)
const PINK: Color = Color(1.0, 0.52, 0.48)
const BANANA: Color = Color(1.0, 0.86, 0.16)

static var _mats: Dictionary = {}
static var _outlines: Dictionary = {}
static var _ghosts: Dictionary = {}
static var _meshes: Dictionary = {}
static var _tex_check: ImageTexture = null
static var _tex_stone: ImageTexture = null


class _Rig extends RefCounted:
	var hips: Node3D
	var upper: Node3D
	var head: Node3D
	var arm_l: Node3D
	var arm_r: Node3D
	var leg_l: Node3D
	var leg_r: Node3D
	var mustache: Node3D
	var cane: Node3D
	var banana: Node3D
	var cap: Node3D
	var shades: Node3D
	var whistle: Node3D
	var belly: Node3D
	var pupil_l: Node3D
	var pupil_r: Node3D
	var meshes: Array[MeshInstance3D] = []
	var mode: int = 0
	var last_t: float = -1.0
	var phase: float = 0.0
	var k: float = 0.0


# ───────────────────────────── materials / meshes ─────────────────────────────

static func _outline_mat(grow: float) -> StandardMaterial3D:
	var key: int = roundi(grow * 1000.0)
	if _outlines.has(key):
		return _outlines[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.03, 0.02, 0.05)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_FRONT
	m.grow = true
	m.grow_amount = float(key) / 1000.0
	_outlines[key] = m
	return m


static func _mat(c: Color, grow: float = OUTLINE, rough: float = 0.7, tex: Texture2D = null, uvs: float = 1.0) -> StandardMaterial3D:
	var key: String = "%s|%d|%.2f|%d|%.1f" % [c.to_html(false), roundi(grow * 1000.0), rough, tex.get_instance_id() if tex != null else 0, uvs]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_scale = Vector3(uvs, uvs, 1.0)
	if grow > 0.0:
		m.next_pass = _outline_mat(grow)
	_mats[key] = m
	return m


static func _stone_mat(grow: float) -> StandardMaterial3D:
	var key: String = "stone|%d" % roundi(grow * 1000.0)
	if _mats.has(key):
		return _mats[key]
	if _tex_stone == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y: int in 64:
			for x: int in 64:
				var h: float = fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
				var v: float = 0.80 + 0.20 * h
				img.set_pixel(x, y, Color(v, v, v))
		_tex_stone = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.64, 0.68)
	m.albedo_texture = _tex_stone
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.6, 1.6, 1.6)
	m.roughness = 0.95
	m.next_pass = _outline_mat(grow)
	_mats[key] = m
	return m


static func _ghost_mat(base: StandardMaterial3D) -> StandardMaterial3D:
	if _ghosts.has(base):
		return _ghosts[base]
	var m: StandardMaterial3D = base.duplicate()
	var c: Color = base.albedo_color.lerp(Color(0.85, 0.95, 1.0), 0.7)
	c.a = 0.5
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	m.emission_enabled = true
	m.emission = Color(0.55, 0.75, 1.0)
	m.emission_energy_multiplier = 0.8
	if base.next_pass != null:
		var o := StandardMaterial3D.new()
		o.albedo_color = Color(0.15, 0.25, 0.5, 0.55)
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		o.grow = true
		o.grow_amount = (base.next_pass as StandardMaterial3D).grow_amount
		m.next_pass = o
	_ghosts[base] = m
	return m


static func _check_tex() -> ImageTexture:
	if _tex_check == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
		img.set_pixel(0, 0, Color(0.9, 0.12, 0.12))
		img.set_pixel(1, 1, Color(0.9, 0.12, 0.12))
		img.set_pixel(1, 0, Color(1, 1, 1))
		img.set_pixel(0, 1, Color(1, 1, 1))
		_tex_check = ImageTexture.create_from_image(img)
	return _tex_check


static func _sphere() -> SphereMesh:
	if _meshes.has("sph"):
		return _meshes["sph"]
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 20
	m.rings = 10
	_meshes["sph"] = m
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var key: String = "cap%.3f|%.3f" % [r, h]
	if _meshes.has(key):
		return _meshes[key]
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 14
	m.rings = 5
	_meshes[key] = m
	return m


static func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var key: String = "cyl%.3f|%.3f|%.3f" % [rt, rb, h]
	if _meshes.has(key):
		return _meshes[key]
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 18
	m.rings = 1
	_meshes[key] = m
	return m


static func _torus(inner: float, outer: float) -> TorusMesh:
	var key: String = "tor%.3f|%.3f" % [inner, outer]
	if _meshes.has(key):
		return _meshes[key]
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 20
	m.ring_segments = 8
	_meshes[key] = m
	return m


static func _tri_out(idx: PackedInt32Array, v: PackedVector3Array, a: int, b: int, c: int, out_n: Vector3) -> void:
	var cr: Vector3 = (v[b] - v[a]).cross(v[c] - v[a])
	if cr.dot(out_n) > 0.0:
		idx.append_array(PackedInt32Array([a, c, b]))
	else:
		idx.append_array(PackedInt32Array([a, b, c]))


static func _rb_coords(hv: float, r: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	const STEPS: int = 4
	for i: int in range(STEPS + 1):
		var th: float = deg_to_rad(-45.0 + 45.0 * float(i) / float(STEPS))
		out.append(-(hv - r) + r * tan(th))
	for i: int in range(STEPS, -1, -1):
		var th: float = deg_to_rad(-45.0 + 45.0 * float(i) / float(STEPS))
		out.append((hv - r) - r * tan(th))
	return out


## Rounded box (size is full extents, r is corner radius).
static func _rbox(size: Vector3, r: float) -> ArrayMesh:
	var key: String = "rb%s|%.3f" % [size, r]
	if _meshes.has(key):
		return _meshes[key]
	var h: Vector3 = size * 0.5
	var rad: float = minf(r, minf(h.x, minf(h.y, h.z)) * 0.999)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var inner_lim: Vector3 = h - Vector3(rad, rad, rad)
	for axis: int in 3:
		var u: int = (axis + 1) % 3
		var w: int = (axis + 2) % 3
		var cu: PackedFloat32Array = _rb_coords(h[u], rad)
		var cw: PackedFloat32Array = _rb_coords(h[w], rad)
		var m: int = cw.size()
		for sgn: int in [-1, 1]:
			var base: int = verts.size()
			var out_n := Vector3.ZERO
			out_n[axis] = float(sgn)
			for i: int in cu.size():
				for j: int in cw.size():
					var c := Vector3.ZERO
					c[axis] = float(sgn) * h[axis]
					c[u] = cu[i]
					c[w] = cw[j]
					var inn := Vector3(clampf(c.x, -inner_lim.x, inner_lim.x), clampf(c.y, -inner_lim.y, inner_lim.y), clampf(c.z, -inner_lim.z, inner_lim.z))
					var nrm: Vector3 = (c - inn).normalized()
					verts.append(inn + nrm * rad)
					norms.append(nrm)
					uvs.append(Vector2(float(i) / float(cu.size() - 1), float(j) / float(m - 1)))
			for i: int in cu.size() - 1:
				for j: int in m - 1:
					var a: int = base + i * m + j
					var b: int = base + (i + 1) * m + j
					var c2: int = base + (i + 1) * m + j + 1
					var d: int = base + i * m + j + 1
					_tri_out(idx, verts, a, b, c2, out_n)
					_tri_out(idx, verts, a, c2, d, out_n)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh


static func _star_mesh(r_out: float, r_in: float, thick: float) -> ArrayMesh:
	var key: String = "star%.3f|%.3f|%.3f" % [r_out, r_in, thick]
	if _meshes.has(key):
		return _meshes[key]
	var pts: Array[Vector2] = []
	for i: int in 10:
		var ang: float = PI * 0.5 + float(i) * PI * 0.2
		var rr: float = r_out if i % 2 == 0 else r_in
		pts.append(Vector2(cos(ang), sin(ang)) * rr)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var ht: float = thick * 0.5
	# front and back fans
	for face: int in 2:
		var z: float = ht if face == 0 else -ht
		var nz := Vector3(0, 0, 1.0 if face == 0 else -1.0)
		var base: int = verts.size()
		verts.append(Vector3(0, 0, z * 1.35))
		norms.append(nz)
		for i: int in 10:
			verts.append(Vector3(pts[i].x, pts[i].y, z))
			norms.append(nz)
		for i: int in 10:
			_tri_out(idx, verts, base, base + 1 + i, base + 1 + (i + 1) % 10, nz)
	# sides
	for i: int in 10:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[(i + 1) % 10]
		var e: Vector2 = (p1 - p0)
		var sn := Vector3(e.y, -e.x, 0.0).normalized()
		var base2: int = verts.size()
		verts.append(Vector3(p0.x, p0.y, ht))
		verts.append(Vector3(p1.x, p1.y, ht))
		verts.append(Vector3(p1.x, p1.y, -ht))
		verts.append(Vector3(p0.x, p0.y, -ht))
		for q: int in 4:
			norms.append(sn)
		_tri_out(idx, verts, base2, base2 + 1, base2 + 2, sn)
		_tri_out(idx, verts, base2, base2 + 2, base2 + 3, sn)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh


# ───────────────────────────── node helpers ─────────────────────────────

static func _pivot(parent: Node3D, nm: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var p := Node3D.new()
	p.name = nm
	p.position = pos
	parent.add_child(p)
	return p


## Generic mesh instance; `scl` scales the node, outline width is compensated for it.
static func _mi(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO, outline: bool = true, shadow: bool = false, tex: Texture2D = null, uvs: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	var grow: float = 0.0
	if outline:
		var avg: float = (absf(scl.x) + absf(scl.y) + absf(scl.z)) / 3.0
		grow = clampf(OUTLINE / maxf(avg, 0.25), 0.012, 0.09)
		grow = roundf(grow * 200.0) / 200.0
	var m: StandardMaterial3D = _mat(c, grow, 0.7, tex, uvs)
	mi.material_override = m
	mi.set_meta("mat", m)
	mi.set_meta("grow", grow)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Ellipsoid with full extents `size`.
static func _ell(parent: Node3D, c: Color, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO, shadow: bool = false, outline: bool = true) -> MeshInstance3D:
	return _mi(parent, _sphere(), c, pos, size, rot, outline, shadow)


static func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	for ch: Node in n.get_children():
		if ch is MeshInstance3D:
			out.append(ch as MeshInstance3D)
		_collect(ch, out)


static func _apply_mode(r: _Rig, mode: int) -> void:
	r.mode = mode
	for mi: MeshInstance3D in r.meshes:
		var base: StandardMaterial3D = mi.get_meta("mat")
		var shadow_on: bool = mi.get_meta("shadow_on", false)
		match mode:
			1:
				mi.material_override = _stone_mat(mi.get_meta("grow"))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow_on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			2:
				mi.material_override = _ghost_mat(base)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				mi.material_override = base
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow_on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _finish(root: Node3D, r: _Rig) -> void:
	_collect(root, r.meshes)
	for mi: MeshInstance3D in r.meshes:
		mi.set_meta("shadow_on", mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	root.set_meta("rig", r)


static func _mode_for(stone: bool, ghost: bool) -> int:
	if ghost:
		return 2
	return 1 if stone else 0


# ───────────────────────────── grandpa ─────────────────────────────

static func make_grandpa(stone: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Grandpa"
	var r := _Rig.new()
	r.hips = _pivot(root, "Hips", Vector3(0, G_HIP, 0))
	var hips: Node3D = r.hips

	# legs (left = +X)
	for side: int in 2:
		var sx: float = 0.1 if side == 0 else -0.1
		var leg: Node3D = _pivot(hips, "LegL" if side == 0 else "LegR", Vector3(sx, 0, 0))
		_mi(leg, _capsule(0.08, 0.38), BROWN, Vector3(0, -0.18, 0), Vector3.ONE, Vector3.ZERO, true, true)
		_mi(leg, _rbox(Vector3(0.17, 0.1, 0.28), 0.045), Color.WHITE, Vector3(0, -0.37, 0.05), Vector3.ONE, Vector3.ZERO, true, false, _check_tex(), 2.0)
		if side == 0:
			r.leg_l = leg
		else:
			r.leg_r = leg
	_ell(hips, BROWN, Vector3(0, 0.0, -0.01), Vector3(0.36, 0.28, 0.3), Vector3.ZERO, true)

	# upper body (hunched)
	r.upper = _pivot(hips, "Upper")
	r.upper.rotation.x = G_LEAN
	var up: Node3D = r.upper
	_ell(up, GREEN, Vector3(0, 0.25, 0), Vector3(0.5, 0.54, 0.42), Vector3.ZERO, true)
	_ell(up, GREEN, Vector3(0, 0.42, -0.15), Vector3(0.34, 0.3, 0.3), Vector3.ZERO, true)
	_ell(up, BEIGE, Vector3(0, 0.36, 0.14), Vector3(0.24, 0.34, 0.14))
	for i: int in 3:
		var by: float = 0.08 + 0.085 * float(i)
		var bz: float = 0.21 * sqrt(maxf(1.0 - pow((by - 0.25) / 0.27, 2.0), 0.05))
		_ell(up, Color(0.95, 0.75, 0.2), Vector3(0, by, bz + 0.005), Vector3(0.055, 0.055, 0.04), Vector3.ZERO, false, false)

	# head
	r.head = _pivot(up, "Head", Vector3(0, 0.66, 0.1))
	r.head.rotation.x = G_HEAD0
	var hd: Node3D = r.head
	_ell(hd, SKIN, Vector3.ZERO, Vector3(0.46, 0.44, 0.46), Vector3.ZERO, true)
	_ell(hd, SKIN, Vector3(0.225, -0.02, 0.0), Vector3(0.06, 0.12, 0.09))
	_ell(hd, SKIN, Vector3(-0.225, -0.02, 0.0), Vector3(0.06, 0.12, 0.09))
	for sx2: float in [1.0, -1.0]:
		_ell(hd, WHITE, Vector3(0.21 * sx2, 0.07, -0.04), Vector3(0.16, 0.13, 0.16))
		_ell(hd, WHITE, Vector3(0.2 * sx2, -0.04, -0.06), Vector3(0.12, 0.1, 0.12))
		_ell(hd, WHITE, Vector3(0.095 * sx2, 0.14, 0.19), Vector3(0.14, 0.06, 0.08), Vector3(0, 0, 0.35 * sx2))
		_ell(hd, WHITE, Vector3(0.095 * sx2, 0.065, 0.2), Vector3(0.115, 0.115, 0.07), Vector3.ZERO, false, true)
		_mi(hd, _torus(0.052, 0.075), Color(0.2, 0.12, 0.08), Vector3(0.095 * sx2, 0.065, 0.225), Vector3.ONE, Vector3(PI * 0.5, 0, 0), false)
	r.pupil_l = _ell(hd, BLACK, Vector3(0.095, 0.065, 0.24), Vector3(0.05, 0.05, 0.03), Vector3.ZERO, false, false)
	r.pupil_r = _ell(hd, BLACK, Vector3(-0.095, 0.065, 0.24), Vector3(0.05, 0.05, 0.03), Vector3.ZERO, false, false)
	_mi(hd, _cyl(0.008, 0.008, 0.06), Color(0.2, 0.12, 0.08), Vector3(0, 0.075, 0.23), Vector3.ONE, Vector3(0, 0, PI * 0.5), false)
	_ell(hd, PINK, Vector3(0, -0.015, 0.225), Vector3(0.1, 0.09, 0.1))

	# the moustache
	r.mustache = _pivot(hd, "Mustache", Vector3(0, -0.08, 0.2))
	var mu: Node3D = r.mustache
	_ell(mu, WHITE, Vector3(0, 0.0, 0.01), Vector3(0.22, 0.12, 0.13))
	for sx3: float in [1.0, -1.0]:
		_ell(mu, WHITE, Vector3(0.15 * sx3, -0.02, -0.02), Vector3(0.3, 0.12, 0.13), Vector3(0, 0, -0.4 * sx3))
		_ell(mu, WHITE, Vector3(0.3 * sx3, -0.12, -0.04), Vector3(0.12, 0.17, 0.11), Vector3(0, 0, -0.25 * sx3))

	# arms
	for side2: int in 2:
		var sgn: float = 1.0 if side2 == 0 else -1.0
		var arm: Node3D = _pivot(up, "ArmL" if side2 == 0 else "ArmR", Vector3(0.26 * sgn, 0.4, 0.0))
		arm.rotation.x = G_ARM0
		_mi(arm, _capsule(0.06, 0.34), GREEN, Vector3(0, -0.15, 0), Vector3.ONE, Vector3.ZERO, true, true)
		_ell(arm, SKIN, Vector3(0, -0.33, 0), Vector3(0.14, 0.14, 0.14))
		if side2 == 0:
			r.arm_l = arm
			r.banana = _pivot(arm, "Banana", Vector3(0, -0.36, 0.06))
			for i: int in 3:
				var a: float = float(i) * TAU / 3.0
				_ell(r.banana, BANANA, Vector3(sin(a) * 0.07, 0.0, cos(a) * 0.07), Vector3(0.07, 0.03, 0.18), Vector3(0.0, a, 0.0))
			r.banana.visible = false
		else:
			r.arm_r = arm
			r.cane = _pivot(arm, "Cane", Vector3(0, -0.33, 0))
			_mi(r.cane, _cyl(0.022, 0.022, 0.78), WOOD, Vector3(0, -0.14, 0), Vector3.ONE, Vector3.ZERO, true)
			_mi(r.cane, _torus(0.035, 0.085), WOOD, Vector3(0, 0.3, 0.05), Vector3.ONE, Vector3(0, 0, PI * 0.5))

	_finish(root, r)
	if stone:
		_apply_mode(r, 1)
	return root


static func _g_reset(r: _Rig) -> void:
	r.hips.position = Vector3(0, G_HIP, 0)
	r.hips.rotation = Vector3.ZERO
	r.hips.scale = Vector3.ONE
	r.upper.rotation = Vector3(G_LEAN, 0, 0)
	r.upper.scale = Vector3.ONE
	r.head.rotation = Vector3(G_HEAD0, 0, 0)
	r.arm_l.rotation = Vector3(G_ARM0, 0, 0.06)
	r.arm_r.rotation = Vector3(G_ARM0, 0, -0.06)
	r.leg_l.rotation = Vector3.ZERO
	r.leg_r.rotation = Vector3.ZERO
	r.mustache.rotation = Vector3.ZERO
	r.cane.rotation = Vector3.ZERO
	r.pupil_l.position = Vector3(0.095, 0.065, 0.24)
	r.pupil_r.position = Vector3(-0.095, 0.065, 0.24)


static func animate_grandpa(n: Node3D, s: Dictionary) -> void:
	var r: _Rig = n.get_meta("rig")
	var t: float = s["t"]
	var speed: float = s["speed"]
	var state: String = s["state"]
	var stone: bool = s.get("stone", false)
	var ghost: bool = s.get("ghost", false)
	var mode: int = _mode_for(stone, ghost)
	if mode != r.mode:
		_apply_mode(r, mode)
	var dt: float = 0.0
	if r.last_t >= 0.0:
		dt = clampf(t - r.last_t, 0.0, 0.1)
	r.last_t = t
	r.banana.visible = s.get("has_banana", false)
	_g_reset(r)

	match state:
		"slip":
			_g_slip(r, t)
		"stun":
			_g_stun(r, t)
		"knocked":
			_g_knocked(r, t)
		"grabbed":
			_g_grabbed(r, t)
		"statue":
			_g_statue(r, s.get("pose", 0))
		_:
			var target: float = clampf(speed / 5.0, 0.0, 1.25)
			r.k = lerpf(r.k, target, 1.0 - exp(-dt * 14.0))
			r.phase += dt * (7.0 + speed * 1.7)
			_g_normal(r, t)

	var swing: float = s.get("swing", 0.0)
	if swing > 0.0 and state != "statue" and state != "knocked":
		_g_swing(r, swing)
	if ghost:
		r.hips.position.y += 0.1 + sin(t * 2.7) * 0.05


static func _g_normal(r: _Rig, t: float) -> void:
	var k: float = r.k
	var p: float = r.phase
	var sn: float = sin(p)
	var iw: float = 1.0 - clampf(k * 3.0, 0.0, 1.0)
	var breath: float = sin(t * 2.6)
	r.leg_l.rotation.x = sn * 1.0 * k
	r.leg_r.rotation.x = -sn * 1.0 * k
	r.arm_l.rotation.x = G_ARM0 - sn * 1.1 * k + sin(t * 1.7) * 0.05 * iw
	r.arm_r.rotation.x = G_ARM0 + sn * 0.45 * k
	r.arm_l.rotation.z = 0.06 + 0.32 * k + 0.04 * breath * iw
	r.arm_r.rotation.z = -0.06 - 0.32 * k - 0.04 * breath * iw
	r.cane.rotation.x = -sn * 0.4 * k
	r.hips.position.y = G_HIP + absf(sn) * 0.09 * k + breath * 0.006 * iw
	r.hips.rotation = Vector3(0.14 * k, sn * 0.14 * k, sn * 0.1 * k)
	var sq: float = cos(2.0 * p) * k
	r.hips.scale = Vector3(1.0 - 0.03 * sq, 1.0 + 0.06 * sq, 1.0 - 0.03 * sq)
	r.upper.scale.y = 1.0 + breath * 0.025 * iw
	r.head.rotation.x = G_HEAD0 - 0.2 * k
	r.head.rotation.y = sin(t * 0.9) * 0.3 * iw - sn * 0.12 * k
	r.head.rotation.z = sin(t * 0.6) * 0.05 * iw - sn * 0.1 * k
	r.mustache.rotation.z = sin(t * 2.6 + 1.0) * 0.05 * iw + sin(p * 2.0 + 0.6) * 0.12 * k
	r.mustache.rotation.x = cos(p * 2.0) * 0.1 * k


static func _g_slip(r: _Rig, t: float) -> void:
	r.hips.position.y = G_HIP + 0.38 + absf(sin(t * 5.0)) * 0.22
	r.hips.rotation = Vector3(-1.2 + sin(t * 11.0) * 0.15, t * 8.0, sin(t * 7.0) * 0.2)
	r.upper.rotation.x = 0.0
	r.leg_l.rotation = Vector3(-1.0 + sin(t * 17.0) * 0.5, 0, 0.3)
	r.leg_r.rotation = Vector3(-1.3 + sin(t * 17.0 + 2.0) * 0.5, 0, -0.3)
	r.arm_l.rotation = Vector3(-2.0 + sin(t * 15.0) * 1.5, 0, 1.5 + sin(t * 13.0) * 0.6)
	r.arm_r.rotation = Vector3(-2.0 + sin(t * 14.0 + 1.0) * 1.5, 0, -1.5 - sin(t * 12.0) * 0.6)
	r.cane.rotation.x = PI
	r.head.rotation = Vector3(0.5 + sin(t * 20.0) * 0.1, 0, sin(t * 19.0) * 0.12)
	r.mustache.rotation.z = sin(t * 24.0) * 0.2
	r.pupil_l.position += Vector3(0, 0.012, 0)
	r.pupil_r.position += Vector3(0, 0.012, 0)


static func _g_stun(r: _Rig, t: float) -> void:
	var w: float = t * 3.1
	r.hips.position.y = G_HIP - 0.03 + sin(t * 6.0) * 0.02
	r.hips.rotation = Vector3(0.05 + sin(t * 2.3) * 0.18, sin(t * 1.3) * 0.5, sin(w) * 0.25)
	r.hips.scale = Vector3(1.03, 0.94, 1.03)
	r.leg_l.rotation = Vector3(sin(w) * 0.25, 0, 0.25)
	r.leg_r.rotation = Vector3(-sin(w) * 0.25, 0, -0.25)
	r.arm_l.rotation = Vector3(G_ARM0 + sin(w + 1.0) * 0.4, 0, 0.3 + sin(w) * 0.25)
	r.arm_r.rotation = Vector3(G_ARM0 - sin(w + 1.0) * 0.4, 0, -0.3 - sin(w) * 0.25)
	r.head.rotation = Vector3(G_HEAD0 + 0.25 + sin(t * 2.2) * 0.15, 0, sin(w + 0.7) * 0.4)
	r.mustache.rotation.z = sin(w) * 0.2
	var ca: float = cos(t * 8.0) * 0.022
	var sa: float = sin(t * 8.0) * 0.022
	r.pupil_l.position += Vector3(ca, sa, 0)
	r.pupil_r.position += Vector3(-ca, -sa, 0)


static func _g_knocked(r: _Rig, t: float) -> void:
	r.hips.position.y = 0.22
	r.hips.rotation = Vector3(-PI * 0.5, 0, 0)
	r.upper.rotation.x = -0.05
	r.leg_l.rotation = Vector3(-0.5 + sin(t * 18.0) * 0.35, 0, 0.18)
	r.leg_r.rotation = Vector3(-0.5 - sin(t * 18.0) * 0.35, 0, -0.18)
	r.arm_l.rotation = Vector3(0.0 + sin(t * 9.0) * 0.15, 0, 1.2)
	r.arm_r.rotation = Vector3(0.0 - sin(t * 9.0) * 0.15, 0, -1.2)
	r.cane.rotation.x = PI
	r.head.rotation = Vector3(-0.2, sin(t * 1.5) * 0.2, sin(t * 3.0) * 0.1)
	r.mustache.rotation.z = sin(t * 3.4) * 0.06
	var ca: float = cos(t * 5.0) * 0.022
	var sa: float = sin(t * 5.0) * 0.022
	r.pupil_l.position += Vector3(ca, sa, 0)
	r.pupil_r.position += Vector3(-ca, -sa, 0)


static func _g_grabbed(r: _Rig, t: float) -> void:
	r.hips.position.y = 0.34
	r.hips.rotation = Vector3(0.05 + sin(t * 9.0) * 0.08, sin(t * 5.5) * 0.3, sin(t * 7.0) * 0.12)
	r.hips.scale.y = 1.0 + sin(t * 20.0) * 0.03
	r.upper.rotation.x = 0.0
	r.leg_l.rotation = Vector3(sin(t * 20.0) * 1.0, 0, 0.15)
	r.leg_r.rotation = Vector3(-sin(t * 20.0) * 1.0, 0, -0.15)
	r.arm_l.rotation = Vector3(sin(t * 11.0) * 0.4, 0, 2.4 + sin(t * 14.0) * 0.5)
	r.arm_r.rotation = Vector3(sin(t * 11.0 + 1.0) * 0.4, 0, -2.6 - sin(t * 13.0 + 1.0) * 0.5)
	r.cane.rotation.x = PI + sin(t * 12.0) * 0.8
	r.head.rotation = Vector3(-0.15, 0, sin(t * 9.0) * 0.12)
	r.mustache.rotation.z = sin(t * 30.0) * 0.15
	r.pupil_l.position += Vector3(0, 0.012, 0)
	r.pupil_r.position += Vector3(0, 0.012, 0)


static func _g_statue(r: _Rig, pose: int) -> void:
	match pose:
		1: # flamingo
			r.hips.rotation = Vector3(0, 0, 0.12)
			r.upper.rotation.x = 0.28
			r.leg_l.rotation = Vector3(-1.45, 0, 0.12)
			r.leg_r.rotation = Vector3(0, 0, -0.05)
			r.arm_l.rotation = Vector3(0.0, 0, 1.5)
			r.arm_r.rotation = Vector3(0.0, 0, -1.5)
			r.cane.rotation.x = PI
			r.head.rotation = Vector3(G_HEAD0 - 0.1, 0.2, -0.22)
			r.mustache.rotation.z = 0.05
		2: # dramatic point
			r.hips.position.y = G_HIP - 0.02
			r.hips.rotation = Vector3(0.12, 0, 0)
			r.upper.rotation.x = 0.62
			r.leg_l.rotation = Vector3(-0.8, 0, 0.1)
			r.leg_r.rotation = Vector3(0.55, 0, -0.1)
			r.arm_l.rotation = Vector3(-1.45, 0, 0.05)
			r.arm_r.rotation = Vector3(-2.75, 0, -0.1)
			r.cane.rotation.x = PI
			r.head.rotation = Vector3(G_HEAD0 - 0.4, 0, 0.1)
		_: # victory V
			r.hips.rotation = Vector3(-0.08, 0, 0)
			r.upper.rotation.x = 0.12
			r.leg_l.rotation = Vector3(0, 0, 0.22)
			r.leg_r.rotation = Vector3(0, 0, -0.22)
			r.arm_l.rotation = Vector3(-0.1, 0, 2.7)
			r.arm_r.rotation = Vector3(-0.1, 0, -2.7)
			r.cane.rotation.x = PI
			r.head.rotation = Vector3(G_HEAD0 - 0.45, 0, 0)
			r.mustache.rotation.z = 0.0


static func _g_swing(r: _Rig, w: float) -> void:
	var u: float = 1.0 - clampf(w, 0.0, 1.0)
	var a: float
	if u < 0.4:
		a = lerpf(-3.5, -1.5, smoothstep(0.0, 1.0, u / 0.4))
	else:
		a = lerpf(-1.5, G_ARM0, smoothstep(0.0, 1.0, (u - 0.4) / 0.6))
	r.arm_r.rotation = Vector3(a, 0, -0.1)
	r.cane.rotation.x = PI * clampf(w * 1.6, 0.0, 1.0)
	r.upper.rotation.x += 0.25 * sin(u * PI)
	r.hips.rotation.y += sin(u * PI) * 0.5
	r.hips.scale.y *= 1.0 - 0.08 * sin(u * PI)


# ───────────────────────────── guard ─────────────────────────────

static func make_guard() -> Node3D:
	var root := Node3D.new()
	root.name = "Guard"
	var r := _Rig.new()
	r.hips = _pivot(root, "Hips", Vector3(0, K_HIP, 0))
	var hips: Node3D = r.hips

	for side: int in 2:
		var sx: float = 0.2 if side == 0 else -0.2
		var leg: Node3D = _pivot(hips, "LegL" if side == 0 else "LegR", Vector3(sx, 0, 0))
		_mi(leg, _capsule(0.15, 0.58), NAVY, Vector3(0, -0.3, 0), Vector3.ONE, Vector3.ZERO, true, true)
		_mi(leg, _rbox(Vector3(0.34, 0.2, 0.5), 0.08), BLACK, Vector3(0, -0.62, 0.08), Vector3.ONE, Vector3.ZERO, true, true)
		if side == 0:
			r.leg_l = leg
		else:
			r.leg_r = leg
	_mi(hips, _rbox(Vector3(0.82, 0.3, 0.52), 0.12), NAVY, Vector3(0, 0.0, 0), Vector3.ONE, Vector3.ZERO, true, true)

	r.upper = _pivot(hips, "Upper")
	r.upper.rotation.x = 0.04
	var up: Node3D = r.upper
	_mi(up, _rbox(Vector3(0.94, 0.62, 0.52), 0.18), NAVY, Vector3(0, 0.34, 0), Vector3.ONE, Vector3.ZERO, true, true)
	r.belly = _pivot(up, "Belly", Vector3(0, 0.2, 0.2))
	_ell(r.belly, NAVY2, Vector3.ZERO, Vector3(0.78, 0.52, 0.5), Vector3.ZERO, true)
	_mi(up, _rbox(Vector3(0.84, 0.08, 0.6), 0.03), BLACK, Vector3(0, 0.0, 0.05), Vector3.ONE, Vector3.ZERO, true)
	_mi(up, _rbox(Vector3(0.14, 0.1, 0.05), 0.02), GOLD, Vector3(0, 0.0, 0.36), Vector3.ONE, Vector3.ZERO, true)
	for i: int in 3:
		var by: float = 0.14 + 0.1 * float(i)
		var bz: float = 0.2 + 0.25 * sqrt(maxf(1.0 - pow((by - 0.2) / 0.26, 2.0), 0.05))
		_ell(up, GOLD, Vector3(0, by, bz + 0.01), Vector3(0.07, 0.07, 0.05), Vector3.ZERO, false, false)
	for sx2: float in [1.0, -1.0]:
		_mi(up, _rbox(Vector3(0.22, 0.06, 0.3), 0.025), GOLD, Vector3(0.36 * sx2, 0.66, 0.0), Vector3.ONE, Vector3(0, 0, -0.15 * sx2), true)
	# yellow badge on the chest
	_mi(up, _rbox(Vector3(0.13, 0.15, 0.04), 0.03), GOLD, Vector3(0.24, 0.53, 0.265), Vector3.ONE, Vector3(-0.1, 0, 0), true)
	# neck, cord and whistle
	_mi(up, _cyl(0.13, 0.15, 0.14), SKIN, Vector3(0, 0.7, 0.03))
	_mi(up, _torus(0.2, 0.225), GOLD, Vector3(0, 0.66, 0.06), Vector3(1.0, 0.7, 1.0), Vector3(0.28, 0, 0), false)
	r.whistle = _pivot(up, "Whistle", Vector3(0, 0.62, 0.3))
	_mi(r.whistle, _cyl(0.01, 0.01, 0.2), GOLD, Vector3(0, -0.1, 0), Vector3.ONE, Vector3.ZERO, false)
	_ell(r.whistle, Color(0.85, 0.85, 0.9), Vector3(0, -0.21, 0.02), Vector3(0.1, 0.06, 0.07))

	r.head = _pivot(up, "Head", Vector3(0, 0.88, 0.04))
	var hd: Node3D = r.head
	_ell(hd, SKIN, Vector3.ZERO, Vector3(0.52, 0.5, 0.52), Vector3.ZERO, true)
	_mi(hd, _rbox(Vector3(0.52, 0.22, 0.42), 0.09), SKIN, Vector3(0, -0.19, 0.04), Vector3.ONE, Vector3.ZERO, true, true)
	_ell(hd, SKIN, Vector3(0.27, -0.03, 0.0), Vector3(0.07, 0.13, 0.1))
	_ell(hd, SKIN, Vector3(-0.27, -0.03, 0.0), Vector3(0.07, 0.13, 0.1))
	_ell(hd, PINK, Vector3(0, -0.07, 0.265), Vector3(0.11, 0.1, 0.1))
	_ell(hd, Color(0.45, 0.1, 0.1), Vector3(0, -0.24, 0.245), Vector3(0.13, 0.04, 0.05), Vector3.ZERO, false, false)
	for sx3: float in [1.0, -1.0]:
		_ell(hd, BLACK, Vector3(0.075 * sx3, -0.15, 0.255), Vector3(0.2, 0.08, 0.1), Vector3(0, 0, 0.25 * sx3), false, false)
	r.shades = _pivot(hd, "Shades", Vector3(0, 0.05, 0))
	for sx4: float in [1.0, -1.0]:
		_mi(r.shades, _rbox(Vector3(0.22, 0.13, 0.07), 0.035), BLACK, Vector3(0.12 * sx4, 0, 0.24), Vector3.ONE, Vector3(0, 0.25 * sx4, 0), false)
		_mi(r.shades, _rbox(Vector3(0.05, 0.025, 0.02), 0.01), WHITE, Vector3(0.17 * sx4, 0.03, 0.285), Vector3.ONE, Vector3.ZERO, false)
	_mi(r.shades, _rbox(Vector3(0.08, 0.03, 0.05), 0.012), BLACK, Vector3(0, 0.02, 0.26), Vector3.ONE, Vector3.ZERO, false)

	r.cap = _pivot(hd, "Cap", Vector3(0, 0.2, 0.0))
	_mi(r.cap, _cyl(0.33, 0.27, 0.2), NAVY, Vector3(0, 0.1, 0), Vector3.ONE, Vector3.ZERO, true, true)
	_mi(r.cap, _cyl(0.3, 0.3, 0.05), GOLD, Vector3(0, 0.035, 0), Vector3.ONE, Vector3.ZERO, true)
	_mi(r.cap, _rbox(Vector3(0.44, 0.04, 0.24), 0.018), BLACK, Vector3(0, 0.0, 0.33), Vector3.ONE, Vector3(0.12, 0, 0), true)
	_ell(r.cap, GOLD, Vector3(0, 0.1, 0.31), Vector3(0.1, 0.11, 0.04), Vector3.ZERO, false, true)

	for side2: int in 2:
		var sgn: float = 1.0 if side2 == 0 else -1.0
		var arm: Node3D = _pivot(up, "ArmL" if side2 == 0 else "ArmR", Vector3(0.56 * sgn, 0.54, 0.0))
		_mi(arm, _capsule(0.125, 0.64), NAVY, Vector3(0, -0.3, 0), Vector3.ONE, Vector3.ZERO, true, true)
		_ell(arm, SKIN, Vector3(0, -0.64, 0), Vector3(0.27, 0.27, 0.27), Vector3.ZERO, true)
		_mi(arm, _cyl(0.13, 0.13, 0.05), GOLD, Vector3(0, -0.52, 0), Vector3.ONE, Vector3.ZERO, true)
		if side2 == 0:
			r.arm_l = arm
		else:
			r.arm_r = arm

	_finish(root, r)
	return root


static func carry_anchor(carry: String) -> Vector3:
	match carry:
		"grandpa":
			return Vector3(0.0, 0.75, 0.55)
		"bench":
			return Vector3(0.0, 2.0, 0.2)
	return Vector3.ZERO


static func _k_reset(r: _Rig) -> void:
	r.hips.position = Vector3(0, K_HIP, 0)
	r.hips.rotation = Vector3.ZERO
	r.hips.scale = Vector3.ONE
	r.upper.rotation = Vector3(0.04, 0, 0)
	r.upper.scale = Vector3.ONE
	r.head.rotation = Vector3.ZERO
	r.head.position = Vector3(0, 0.88, 0.04)
	r.arm_l.rotation = Vector3(0, 0, 0.16)
	r.arm_r.rotation = Vector3(0, 0, -0.16)
	r.leg_l.rotation = Vector3.ZERO
	r.leg_r.rotation = Vector3.ZERO
	r.cap.rotation = Vector3.ZERO
	r.cap.position = Vector3(0, 0.2, 0)
	r.shades.rotation = Vector3.ZERO
	r.shades.position = Vector3(0, 0.05, 0)
	r.whistle.rotation = Vector3.ZERO
	r.belly.scale = Vector3.ONE


static func animate_guard(n: Node3D, s: Dictionary) -> void:
	var r: _Rig = n.get_meta("rig")
	var t: float = s["t"]
	var speed: float = s["speed"]
	var state: String = s["state"]
	var carry: String = s.get("carry", "")
	var dt: float = 0.0
	if r.last_t >= 0.0:
		dt = clampf(t - r.last_t, 0.0, 0.1)
	r.last_t = t
	_k_reset(r)

	match state:
		"slip":
			_k_slip(r, t)
		"stun":
			_k_stun(r, t)
		"knocked":
			_k_knocked(r, t)
		"dash":
			r.phase += dt * 24.0
			_k_dash(r, t)
		_:
			var target: float = clampf(speed / 7.0, 0.0, 1.3)
			r.k = lerpf(r.k, target, 1.0 - exp(-dt * 12.0))
			r.phase += dt * (5.0 + minf(speed, 16.0) * 0.75)
			_k_normal(r, t, speed, carry)


static func _k_normal(r: _Rig, t: float, speed: float, carry: String) -> void:
	var k: float = r.k
	var p: float = r.phase
	var sn: float = sin(p)
	var iw: float = 1.0 - clampf(k * 3.0, 0.0, 1.0)
	var breath: float = sin(t * 2.2)
	var load_k: float = 0.0 if carry == "" else 1.0
	var bob: float = 0.09 * (1.0 - 0.7 * load_k)
	r.leg_l.rotation.x = sn * 0.9 * k
	r.leg_r.rotation.x = -sn * 0.9 * k
	r.hips.position.y = K_HIP + absf(sn) * bob * k + breath * 0.008 * iw
	var sq: float = cos(2.0 * p) * k
	r.hips.scale = Vector3(1.0 - 0.025 * sq, 1.0 + 0.05 * sq, 1.0 - 0.025 * sq)
	var lean: float = minf(0.08 + speed * 0.02, 0.34) * k
	r.hips.rotation = Vector3(lean - 0.1 * load_k, sn * 0.08 * k, sn * 0.08 * k)
	r.belly.scale = Vector3(1.0, 1.0 + 0.05 * breath * iw + 0.07 * sq, 1.0 + 0.05 * breath * iw)
	r.head.rotation = Vector3(-lean * 0.9 + 0.1 * load_k, sin(t * 0.8) * 0.35 * iw, -sn * 0.07 * k)
	r.cap.position.y = 0.2 + maxf(-cos(2.0 * p + 0.5), 0.0) * 0.03 * k
	r.cap.rotation.x = cos(2.0 * p) * 0.08 * k
	r.whistle.rotation.x = sin(p * 2.0 + 1.0) * 0.5 * k + sin(t * 1.9) * 0.05
	match carry:
		"grandpa":
			var strain: float = sin(t * 9.0) * 0.04
			r.arm_l.rotation = Vector3(-1.72 + strain, 0, -0.36)
			r.arm_r.rotation = Vector3(-1.72 - strain, 0, 0.36)
		"bench":
			var strain2: float = sin(t * 7.0) * 0.04
			r.arm_l.rotation = Vector3(-2.95 + strain2, 0, 0.08)
			r.arm_r.rotation = Vector3(-2.95 - strain2, 0, -0.08)
			r.hips.scale.y *= 1.0 - 0.02 * (1.0 + sin(t * 7.0))
		_:
			r.arm_l.rotation = Vector3(-sn * 1.05 * k + sin(t * 1.5) * 0.04 * iw, 0, 0.16 + 0.24 * k)
			r.arm_r.rotation = Vector3(sn * 1.05 * k - sin(t * 1.5) * 0.04 * iw, 0, -0.16 - 0.24 * k)


static func _k_slip(r: _Rig, t: float) -> void:
	r.hips.position.y = K_HIP + 0.45 + absf(sin(t * 4.0)) * 0.25
	r.hips.rotation = Vector3(-1.1 + sin(t * 10.0) * 0.12, 0, sin(t * 8.0) * 0.15)
	r.upper.rotation.x = 0.0
	r.leg_l.rotation = Vector3(-1.1 + sin(t * 16.0) * 0.6, 0, 0.3)
	r.leg_r.rotation = Vector3(-1.5 + sin(t * 16.0 + 2.0) * 0.6, 0, -0.3)
	r.arm_l.rotation = Vector3(t * 14.0, 0, 0.5)
	r.arm_r.rotation = Vector3(-t * 12.0 + 1.0, 0, -0.5)
	r.head.rotation = Vector3(0.6, 0, sin(t * 18.0) * 0.1)
	r.cap.position = Vector3(0, 0.32, -0.04)
	r.cap.rotation = Vector3(-0.5, 0, sin(t * 12.0) * 0.2)
	r.shades.position.y = 0.02
	r.whistle.rotation.x = sin(t * 15.0) * 0.8


static func _k_stun(r: _Rig, t: float) -> void:
	var w: float = t * 2.8
	r.hips.position.y = K_HIP - 0.06 + sin(t * 5.0) * 0.02
	r.hips.rotation = Vector3(0.05 + sin(t * 2.1) * 0.14, sin(t * 1.2) * 0.45, sin(w) * 0.2)
	r.hips.scale = Vector3(1.04, 0.92, 1.04)
	r.leg_l.rotation = Vector3(sin(w) * 0.2, 0, 0.22)
	r.leg_r.rotation = Vector3(-sin(w) * 0.2, 0, -0.22)
	r.arm_l.rotation = Vector3(sin(w + 1.0) * 0.35, 0, 0.3 + sin(w) * 0.2)
	r.arm_r.rotation = Vector3(-sin(w + 1.0) * 0.35, 0, -0.3 - sin(w) * 0.2)
	r.head.rotation = Vector3(0.3 + sin(t * 2.0) * 0.12, 0, sin(w + 0.7) * 0.35)
	r.cap.rotation = Vector3(0.0, 0, 0.3 + sin(w) * 0.2)
	r.cap.position.x = 0.04
	r.shades.rotation.z = 0.2 + sin(w * 2.0) * 0.1
	r.shades.position.y = 0.03
	r.belly.scale.y = 1.0 + sin(t * 6.0) * 0.06
	r.whistle.rotation.x = sin(w * 2.0) * 0.4


static func _k_dash(r: _Rig, t: float) -> void:
	var p: float = r.phase
	r.hips.position.y = K_HIP + 0.12 + sin(t * 30.0) * 0.015
	r.hips.rotation = Vector3(0.64, 0, sin(p * 0.5) * 0.06)
	r.hips.scale = Vector3(0.94, 1.04, 1.1)
	r.upper.rotation.x = 0.08
	r.leg_l.rotation = Vector3(0.8 + sin(p) * 0.3, 0, 0.16)
	r.leg_r.rotation = Vector3(1.1 - sin(p) * 0.3, 0, -0.16)
	r.arm_l.rotation = Vector3(2.1 + sin(p) * 0.12, 0, 0.35)
	r.arm_r.rotation = Vector3(2.1 - sin(p) * 0.12, 0, -0.35)
	r.head.rotation = Vector3(-0.55, 0, 0)
	r.cap.rotation = Vector3(0.2, 0, 0)
	r.belly.scale = Vector3(1.0, 1.0, 1.05)
	r.whistle.rotation.x = -0.9 + sin(t * 25.0) * 0.1


static func _k_knocked(r: _Rig, t: float) -> void:
	r.hips.position.y = 0.3
	r.hips.rotation = Vector3(-PI * 0.5, 0, 0)
	r.upper.rotation.x = -0.04
	r.leg_l.rotation = Vector3(-0.3 + sin(t * 16.0) * 0.25, 0, 0.55)
	r.leg_r.rotation = Vector3(-0.3 - sin(t * 16.0) * 0.25, 0, -0.55)
	r.arm_l.rotation = Vector3(sin(t * 8.0) * 0.12, 0, 1.55)
	r.arm_r.rotation = Vector3(-sin(t * 8.0) * 0.12, 0, -1.55)
	r.head.rotation = Vector3(-0.15, sin(t * 1.4) * 0.15, sin(t * 3.0) * 0.08)
	r.cap.position = Vector3(0.06, 0.28, 0.18)
	r.cap.rotation = Vector3(-0.8, 0.0, 0.35)
	r.shades.rotation.z = -0.2
	r.shades.position.y = 0.0
	r.belly.scale.y = 1.0 + sin(t * 3.0) * 0.04


# ───────────────────────────── statues, banana, stars ─────────────────────────────

static func make_statue(pose: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Statue"
	_mi(root, _rbox(Vector3(0.9, 0.45, 0.6), 0.06), Color.WHITE, Vector3(0, 0.225, 0), Vector3.ONE, Vector3.ZERO, true, true)
	var base_mi: MeshInstance3D = root.get_child(0) as MeshInstance3D
	base_mi.material_override = _stone_mat(OUTLINE)
	_mi(root, _rbox(Vector3(0.34, 0.12, 0.03), 0.01), Color.WHITE, Vector3(0, 0.2, 0.3), Vector3.ONE, Vector3.ZERO, true)
	var plaque: MeshInstance3D = root.get_child(1) as MeshInstance3D
	plaque.material_override = _mat(Color(0.82, 0.68, 0.25), OUTLINE, 0.4)
	var g: Node3D = make_grandpa(true)
	g.position = Vector3(0, 0.45, 0)
	root.add_child(g)
	animate_grandpa(g, {"t": 0.0, "speed": 0.0, "state": "statue", "pose": pose, "stone": true, "ghost": false, "has_banana": false, "swing": 0.0})
	return root


static func make_banana() -> Node3D:
	var root := Node3D.new()
	root.name = "Banana"
	_ell(root, Color(1.0, 0.78, 0.1), Vector3(0, 0.05, 0), Vector3(0.2, 0.11, 0.2))
	for i: int in 4:
		var ang: float = float(i) * TAU / 4.0 + 0.4 + float(i % 2) * 0.12
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var lift: float = -0.55 + 0.25 * float(i % 2)
		var petal: MeshInstance3D = _ell(root, BANANA, dir * 0.17 + Vector3(0, 0.1, 0), Vector3.ONE)
		petal.basis = (Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, lift)).scaled(Vector3(0.17, 0.05, 0.38))
		var tip: MeshInstance3D = _ell(root, Color(0.42, 0.25, 0.1), dir * 0.33 + Vector3(0, 0.1 - lift * 0.1, 0), Vector3(0.08, 0.06, 0.1))
		tip.rotation.y = ang
	return root


static func make_stars() -> Node3D:
	var root := Node3D.new()
	root.name = "Stars"
	var mesh: ArrayMesh = _star_mesh(0.2, 0.09, 0.08)
	var sm: StandardMaterial3D = _mat(Color(1.0, 0.88, 0.1), 0.03, 0.4)
	if sm.emission_enabled == false:
		sm.emission_enabled = true
		sm.emission = Color(1.0, 0.8, 0.0)
		sm.emission_energy_multiplier = 0.6
	for i: int in 3:
		var a: float = float(i) * TAU / 3.0
		var st := MeshInstance3D.new()
		st.name = "Star%d" % i
		st.mesh = mesh
		st.material_override = sm
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		st.position = Vector3(sin(a) * 0.5, 0.0, cos(a) * 0.5)
		st.basis = Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -1.1)
		root.add_child(st)
	return root
