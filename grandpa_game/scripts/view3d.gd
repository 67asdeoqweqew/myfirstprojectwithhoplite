extends Node3D
## 3D presentation of the courtyard. Reads state from game.gd (2D simulation in pixels) and maps it to
## metres on the ground plane: pixel (x, y) -> world (x * S, height, y * S).

const C = preload("res://scripts/chars3d.gd")
const P = preload("res://scripts/props3d.gd")

const S := 0.02
const CAM_OFFSET := Vector3(0, 10.5, 7.5)
const POP_WORDS := ["БАМ!", "БУМ!", "ХРЯСЬ!", "БДЫЩ!"]

var game: Node
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var static_root: Node3D
var dyn_root: Node3D
var grandpa: Node3D
var guard: Node3D
var gp_stars: Node3D
var gd_stars: Node3D
var flashlight: SpotLight3D
var rain: CPUParticles3D
var bench_nodes: Array[Node3D] = []
var banana_nodes: Array[Node3D] = []
var bubble_labels: Dictionary = {}   # who -> Label3D
var cart_node: Node3D
var entrance_fill: Node3D
var order_fill: Node3D
var spit: Node3D
var water: Node3D
var cam_target := Vector3(18, 0, 11)
var orbit_t := 0.0
var pops: Array = []                 # {node: Label3D, t: float}


func setup(g: Node) -> void:
	game = g
	game.map_built.connect(_rebuild_static)
	game.burst.connect(_on_burst)


func _ready() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true    # Forward+ only; ignored by the Compatibility renderer
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 45.0
	camera.far = 200.0
	add_child(camera)
	camera.current = true

	static_root = Node3D.new()
	add_child(static_root)
	dyn_root = Node3D.new()
	add_child(dyn_root)

	grandpa = C.make_grandpa(false)
	guard = C.make_guard()
	dyn_root.add_child(grandpa)
	dyn_root.add_child(guard)
	gp_stars = C.make_stars()
	gd_stars = C.make_stars()
	dyn_root.add_child(gp_stars)
	dyn_root.add_child(gd_stars)
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1, 0.95, 0.75)
	flashlight.light_energy = 4.0
	flashlight.spot_range = 11.0
	flashlight.spot_angle = 28.0
	flashlight.position = Vector3(0.35, 1.5, 0.3)
	flashlight.rotation_degrees = Vector3(-18, 180, 0)
	flashlight.visible = false
	guard.add_child(flashlight)
	for who in ["gp", "gd"]:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 10
		l.outline_render_priority = 9
		l.font_size = 64
		l.outline_size = 26
		l.pixel_size = 0.0052
		l.modulate = Color(0.16, 0.07, 0.1)
		l.outline_modulate = Color(1, 1, 1)
		l.width = 520.0
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.visible = false
		dyn_root.add_child(l)
		bubble_labels[who] = l
	rain = CPUParticles3D.new()
	rain.amount = 700
	rain.lifetime = 0.7
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(15, 0.5, 11)
	rain.direction = Vector3(0.15, -1, 0)
	rain.spread = 3.0
	rain.gravity = Vector3(0, -20, 0)
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 20.0
	var drop := BoxMesh.new()
	drop.size = Vector3(0.025, 0.45, 0.025)
	var drop_mat := StandardMaterial3D.new()
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.albedo_color = Color(0.75, 0.85, 1.0, 0.55)
	drop.material = drop_mat
	rain.mesh = drop
	rain.emitting = false
	rain.visible = false
	add_child(rain)


func set_low_quality(on: bool) -> void:
	var vp := get_viewport()
	vp.scaling_3d_scale = 0.6 if on else 1.0
	vp.msaa_3d = Viewport.MSAA_DISABLED if on else Viewport.MSAA_2X
	sun.shadow_enabled = not on
	env.ssao_enabled = not on
	env.glow_enabled = not on
	rain.amount = 250 if on else 700


# ------------------------------------------------------------------ static scene

func p3(v: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(v.x * S, y, v.y * S)


func _place(n: Node3D, pos: Vector3, rot_y: float = 0.0) -> Node3D:
	n.position = pos
	n.rotation.y = rot_y
	static_root.add_child(n)
	return n


func _rect_box(r: Rect2, h: float) -> Vector3:
	return Vector3(r.size.x * S, h, r.size.y * S)


func _rebuild_static() -> void:
	for c in static_root.get_children():
		c.queue_free()
	for n in bench_nodes:
		n.queue_free()
	bench_nodes.clear()
	for n in banana_nodes:
		n.queue_free()
	banana_nodes.clear()
	var world: Rect2 = game.WORLD
	_place(P.make_ground(world.size * S), p3(world.get_center()))
	# Cheap plain lawn around the courtyard (outside the walls, where trees stand).
	var lawn := MeshInstance3D.new()
	var lawn_mesh := PlaneMesh.new()
	lawn_mesh.size = Vector2(120, 100)
	var lawn_mat := StandardMaterial3D.new()
	lawn_mat.albedo_color = Color(0.36, 0.62, 0.27)
	lawn_mat.roughness = 1.0
	lawn_mesh.material = lawn_mat
	lawn.mesh = lawn_mesh
	lawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_place(lawn, p3(world.get_center(), -0.03))
	for pa in game.paths:
		_place(P.make_path(Vector2(pa[0].x, pa[0].y) * S, Vector2(pa[1].x, pa[1].y) * S, 64.0 * S), Vector3.ZERO)
	for r in game.walls:
		_place(P.make_wall(_rect_box(r, 1.6)), p3(r.get_center()))
	for r in game.hedges:
		_place(P.make_hedge(_rect_box(r, 1.4)), p3(r.get_center()))
	for b in game.bushes:
		_place(P.make_bush(float(b[1]) * S), p3(b[0]))
	for pu in game.puddles:
		_place(P.make_puddle(float(pu[1]) * S), p3(pu[0]))
	_place(P.make_fountain(float(game.fountain[1]) * S), p3(game.fountain[0]))
	water = static_root.get_child(static_root.get_child_count() - 1).find_child("Water", true, false) as Node3D
	var b_rect: Rect2 = game.building
	_place(P.make_building(_rect_box(b_rect, 4.5)), p3(b_rect.get_center()))
	var st_rect: Rect2 = game.stand
	var stand_node := _place(P.make_kebab_stand(_rect_box(st_rect, 3.2)), p3(st_rect.get_center()))
	spit = stand_node.find_child("Spit", true, false) as Node3D
	var cart_rect: Rect2 = game.cart
	cart_node = _place(P.make_banana_cart(), p3(cart_rect.get_center()))
	var ez: Rect2 = game.entrance_zone
	var ez_node := _place(P.make_entrance_zone(ez.size * S), p3(ez.get_center()))
	entrance_fill = ez_node.find_child("Fill", true, false) as Node3D
	var oz: Rect2 = game.order_zone
	var oz_node := _place(P.make_order_zone(oz.size * S), p3(oz.get_center()))
	order_fill = oz_node.find_child("Fill", true, false) as Node3D
	for s in game.statues:
		_place(C.make_statue(int(s[1])), p3(s[0]), PI)
	# Decoration outside the courtyard walls.
	var w := world.size.x * S
	var h := world.size.y * S
	for i in 9:
		var x := 2.0 + i * 4.2
		_place(P.make_tree(4.5 + float(i % 3) * 0.8), Vector3(x, 0, -2.4 - float(i % 2)))
		_place(P.make_tree(4.0 + float((i + 1) % 3) * 0.8), Vector3(x + 1.5, 0, h + 2.6 + float(i % 2)))
	for i in 5:
		_place(P.make_tree(4.8), Vector3(w + 2.6, 0, 2.0 + i * 4.6))
		_place(P.make_tree(4.2), Vector3(-2.6, 0, 1.5 + i * 4.8))
	var night: bool = game.chapter.get("night", false)
	# Lamps stand next to walls and around the fountain, out of the main walkways.
	for lp in [Vector2(780, 440), Vector2(1020, 660), Vector2(330, 60), Vector2(1450, 60), Vector2(450, 1040),
			Vector2(1450, 1040), Vector2(1250, 300)]:
		_place(P.make_lamp(), p3(lp))
	P.set_night(static_root, night)
	for l in static_root.find_children("Light", "OmniLight3D", true, false):
		(l as OmniLight3D).light_energy = 1.1
	_apply_weather()


func _apply_weather() -> void:
	var night: bool = game.chapter.get("night", false)
	var wet: bool = game.chapter.get("rain", false)
	if night:
		sky_mat.sky_top_color = Color(0.03, 0.04, 0.14)
		sky_mat.sky_horizon_color = Color(0.12, 0.1, 0.25)
		sky_mat.ground_horizon_color = Color(0.08, 0.07, 0.15)
		sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.05)
		sun.light_color = Color(0.55, 0.62, 1.0)
		sun.light_energy = 0.1
		env.ambient_light_energy = 0.14
	elif wet:
		sky_mat.sky_top_color = Color(0.42, 0.48, 0.58)
		sky_mat.sky_horizon_color = Color(0.65, 0.68, 0.72)
		sky_mat.ground_horizon_color = Color(0.5, 0.52, 0.55)
		sky_mat.ground_bottom_color = Color(0.25, 0.25, 0.28)
		sun.light_color = Color(0.9, 0.93, 1.0)
		sun.light_energy = 0.6
		env.ambient_light_energy = 0.55
	else:
		sky_mat.sky_top_color = Color(0.25, 0.55, 0.95)
		sky_mat.sky_horizon_color = Color(0.75, 0.88, 1.0)
		sky_mat.ground_horizon_color = Color(0.7, 0.8, 0.85)
		sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)
		sun.light_color = Color(1.0, 0.95, 0.85)
		sun.light_energy = 0.95
		env.ambient_light_energy = 0.55
	flashlight.visible = night
	rain.emitting = wet
	rain.visible = wet


# ------------------------------------------------------------------ effects

func _on_burst(pos: Vector2, color: Color, count: int, strong: bool) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.amount = maxi(4, count)
	ps.lifetime = 0.8
	ps.direction = Vector3.UP
	ps.spread = 75.0
	ps.gravity = Vector3(0, -12, 0)
	ps.initial_velocity_min = 3.0
	ps.initial_velocity_max = 7.5 if strong else 5.0
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.09
	m.height = 0.18
	m.radial_segments = 8
	m.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	m.material = mat
	ps.mesh = m
	ps.position = p3(pos, 0.9)
	dyn_root.add_child(ps)
	ps.emitting = true
	get_tree().create_timer(1.6).timeout.connect(ps.queue_free)
	if strong:
		var l := Label3D.new()
		l.text = POP_WORDS[count % POP_WORDS.size()]
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 96
		l.outline_size = 30
		l.pixel_size = 0.0065
		l.modulate = Color(1, 0.85, 0.1)
		l.outline_modulate = Color(0.55, 0.05, 0.05)
		l.position = p3(pos, 2.4 + 0.7 * float(pops.size()))
		dyn_root.add_child(l)
		pops.append({"node": l, "t": 0.0})


# ------------------------------------------------------------------ per frame

func to_screen(p: Vector2, height: float = 1.0) -> Vector2:
	return camera.unproject_position(p3(p, height))


func _process(dt: float) -> void:
	if game == null:
		return
	var t: float = game.anim_t
	if spit:
		spit.rotation.y += dt * 1.6
	if water:
		water.position.y = sin(t * 3.0) * 0.03
		water.rotation.y += dt * 0.4
	for pop in pops:
		pop["t"] += dt
		var n: Label3D = pop["node"]
		var k: float = pop["t"]
		n.scale = Vector3.ONE * (0.4 + minf(k * 6.0, 1.0) * 0.8)
		n.position.y += dt * 0.8
		n.modulate.a = clampf(1.6 - k * 1.6, 0.0, 1.0)
		n.outline_modulate.a = n.modulate.a
		if k > 1.0:
			n.queue_free()
	pops = pops.filter(func(pp: Dictionary) -> bool: return pp["t"] <= 1.0)

	if game.gp.is_empty():
		_update_menu_camera(dt)
		return
	grandpa.visible = true
	guard.visible = true
	_update_characters(t)
	_update_props()
	_update_bubbles()
	var target := p3(game.local_draw_pos())
	cam_target = cam_target.lerp(target, minf(1.0, dt * 7.0)) if cam_target.distance_to(target) < 8.0 else target
	camera.position = cam_target + CAM_OFFSET
	camera.look_at(cam_target + Vector3(0, 0.6, 0), Vector3.UP)
	var shake: float = game.shake * 0.012
	camera.h_offset = randf_range(-1.0, 1.0) * shake
	camera.v_offset = randf_range(-1.0, 1.0) * shake
	rain.position = cam_target + Vector3(0, 10, 2)


func _update_menu_camera(dt: float) -> void:
	grandpa.visible = false
	guard.visible = false
	gp_stars.visible = false
	gd_stars.visible = false
	for l in bubble_labels.values():
		(l as Label3D).visible = false
	for n in bench_nodes:
		n.visible = false
	for n in banana_nodes:
		n.visible = false
	orbit_t += dt * 0.08
	var c := Vector3(18, 0, 11)
	camera.position = c + Vector3(sin(orbit_t) * 24.0, 15.0, cos(orbit_t) * 24.0)
	camera.look_at(c, Vector3.UP)
	camera.h_offset = 0.0
	camera.v_offset = 0.0


func _facing_angle(f: Vector2) -> float:
	return atan2(f.x, f.y)


func _update_characters(t: float) -> void:
	var gd: Dictionary = game.gd
	var gp: Dictionary = game.gp
	var gd_vel: Vector2 = gd["vel"]
	var gp_vel: Vector2 = gp["vel"]
	var gd_face: Vector2 = gd["facing"]
	var gp_face: Vector2 = gp["facing"]
	guard.position = p3(game.gd_draw)
	guard.rotation.y = lerp_angle(guard.rotation.y, _facing_angle(gd_face), 0.35)
	var carry: String = gd["carry"]
	C.animate_guard(guard, {"t": t, "speed": gd_vel.length() * S, "state": gd["state"], "carry": carry})

	var statue: bool = gp["state"] == "statue"
	var mine: bool = game.local_role == "grandpa"
	if carry == "grandpa":
		grandpa.global_transform = guard.global_transform * Transform3D(Basis(), C.carry_anchor("grandpa"))
	else:
		grandpa.position = p3(game.gp_draw)
		grandpa.rotation = Vector3(0, lerp_angle(grandpa.rotation.y, _facing_angle(gp_face), 0.35), 0)
	C.animate_grandpa(grandpa, {"t": t, "speed": gp_vel.length() * S, "state": gp["state"], "pose": gp["pose"],
		"ghost": statue and mine, "has_banana": gp["has_banana"], "swing": gp["swing"], "stone": statue})

	var gd_dazed: bool = gd["state"] == "stun"
	gd_stars.visible = gd_dazed
	if gd_dazed:
		gd_stars.position = guard.position + Vector3(0, 2.25, 0)
		gd_stars.rotation.y = t * 5.0
	var gp_dazed: bool = gp["state"] == "stun" or gp["state"] == "knocked"
	gp_stars.visible = gp_dazed
	if gp_dazed:
		gp_stars.position = grandpa.global_position + Vector3(0, 0.9 if gp["state"] == "knocked" else 1.5, 0)
		gp_stars.rotation.y = t * 5.0


func _update_props() -> void:
	var benches: Array = game.benches
	while bench_nodes.size() < benches.size():
		var bn := P.make_bench(2.6)
		dyn_root.add_child(bn)
		bench_nodes.append(bn)
	for i in bench_nodes.size():
		var n := bench_nodes[i]
		n.visible = i < benches.size()
		if not n.visible:
			continue
		var b: Dictionary = benches[i]
		var r: Rect2 = b["r"]
		if b["carried"]:
			n.global_transform = guard.global_transform * Transform3D(Basis(), C.carry_anchor("bench"))
		else:
			n.position = p3(r.get_center())
			n.rotation = Vector3(0, 0.0 if r.size.x > r.size.y else PI * 0.5, 0)
	var bananas: Array = game.bananas
	while banana_nodes.size() < bananas.size():
		var bn2 := C.make_banana()
		dyn_root.add_child(bn2)
		banana_nodes.append(bn2)
	for i in banana_nodes.size():
		var n2 := banana_nodes[i]
		n2.visible = i < bananas.size()
		if n2.visible:
			var nb: Dictionary = bananas[i]
			n2.position = p3(nb["p"], 0.02)
			n2.rotation.y = float(nb["rot"])
	if cart_node:
		for i in 3:
			var stock := cart_node.find_child("Stock%d" % i, true, false) as Node3D
			if stock:
				stock.visible = i < int(game.cart_stock)
	if entrance_fill:
		entrance_fill.scale.z = maxf(0.001, float(game.entrance_progress))
	if order_fill:
		order_fill.scale.z = maxf(0.001, float(game.order_progress))


func _update_bubbles() -> void:
	var active := {}
	for b in game.bubbles:
		active[b["who"]] = b
	for who in bubble_labels:
		var l: Label3D = bubble_labels[who]
		if not active.has(who):
			l.visible = false
			continue
		var b: Dictionary = active[who]
		l.visible = true
		l.text = b["text"]
		var a := clampf(float(b["t"]) * 3.0, 0.0, 1.0)
		l.modulate.a = a
		l.outline_modulate.a = a
		var close: bool = grandpa.global_position.distance_to(guard.global_position) < 3.0
		var side := 1.0 if grandpa.global_position.x >= guard.global_position.x else -1.0
		if who == "gp":
			l.position = grandpa.global_position + Vector3(side * 1.1 if close else 0.0, 1.75, 0)
		else:
			l.position = guard.position + Vector3(-side * 1.1 if close else 0.0, 2.9 if close else 2.6, 0)
