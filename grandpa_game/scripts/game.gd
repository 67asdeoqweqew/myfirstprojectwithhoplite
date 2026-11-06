extends Node
## Courtyard rules. The host runs `host_step` (authoritative simulation) and produces snapshots;
## the client only applies snapshots. Rendering lives in view3d.gd, which reads this state.

signal fx_emitted(d: Dictionary)
signal map_built
signal burst(pos: Vector2, color: Color, count: int, strong: bool)

const WORLD := Rect2(0, 0, 1800, 1100)
const ROUND_TIME := 180.0
const INTRO_TIME := 7.0
const COUNTDOWN_TIME := 3.0
const HOLD_TIME := 3.0
const GP_R := 16.0
const GD_R := 24.0
const GP_SPEED := 268.0
const GD_SPEED := 232.0
const GD_CARRY_GP_SPEED := 150.0
const GD_CARRY_BENCH_SPEED := 175.0
const CANE_CD := 2.4
const DASH_CD := 2.2
const DASH_TIME := 0.24
const DASH_SPEED := 780.0
const STATUE_CD := 7.0
const STATUE_MAX := 4.0
const BENCH_CD := 3.0
const CRASH_SPEED := 330.0

# --- map (static per chapter, built identically on both instances) ---
var chapter: Dictionary = {}
var walls: Array = []
var hedges: Array = []
var bushes: Array = []      # [Vector2 centre, float radius]
var puddles: Array = []     # [Vector2 centre, float radius]
var statues: Array = []     # [Vector2 pos, int pose]
var paths: Array = []       # [Vector2 a, Vector2 b]
var fountain := [Vector2(900, 550), 70.0]
var building := Rect2(30, 270, 250, 560)
var door := Rect2(266, 500, 22, 100)
var entrance_zone := Rect2(288, 470, 150, 160)
var stand := Rect2(1560, 440, 210, 220)
var order_zone := Rect2(1440, 490, 115, 120)
var cart := Rect2(965, 125, 70, 50)
var solid_rects: Array = []  # [Rect2, kind]

# --- synchronized state ---
var phase := "idle"          # idle | intro | countdown | play | over
var phase_t := 0.0
var time_left := ROUND_TIME
var gp: Dictionary = {}
var gd: Dictionary = {}
var benches: Array = []      # {r: Rect2, carried: bool}
var bananas: Array = []      # {p: Vector2, rot: float, immune: float}
var cart_stock := 2
var cart_t := 0.0
var order_progress := 0.0
var entrance_progress := 0.0
var stats: Dictionary = {}
var winner := ""             # "grandpa" | "guard"
var win_reason := ""

# --- local presentation ---
var local_role := "guard"
var is_host := false
var anim_t := 0.0
var shake := 0.0
var bubbles: Array = []      # {who, text, t}
var gp_draw := Vector2.ZERO
var gd_draw := Vector2.ZERO
var last_seen_gp := Vector2.ZERO  # guard's tracker freezes while grandpa plays statue
var sfx: Node




# ------------------------------------------------------------------ map

func build_map(ch: Dictionary) -> void:
	chapter = ch
	walls = [Rect2(0, 0, 1800, 30), Rect2(0, 1070, 1800, 30), Rect2(0, 0, 30, 1100), Rect2(1770, 0, 30, 1100)]
	hedges = [
		Rect2(640, 30, 50, 340), Rect2(640, 470, 50, 160), Rect2(640, 730, 50, 340),
		Rect2(1110, 30, 50, 200), Rect2(1110, 330, 50, 440), Rect2(1110, 870, 50, 200),
	]
	bushes = [[Vector2(450, 890), 38.0], [Vector2(1350, 175), 40.0], [Vector2(1350, 940), 40.0],
		[Vector2(800, 160), 34.0], [Vector2(1000, 960), 34.0], [Vector2(150, 960), 48.0],
		[Vector2(150, 150), 48.0], [Vector2(1660, 150), 50.0], [Vector2(1660, 960), 50.0]]
	statues = [[Vector2(900, 270), 0], [Vector2(900, 850), 1], [Vector2(1360, 560), 2], [Vector2(470, 190), 1]]
	puddles = [[Vector2(520, 410), 46.0], [Vector2(890, 760), 55.0], [Vector2(1290, 700), 50.0]]
	if ch.get("rain", false):
		puddles += [[Vector2(1000, 360), 60.0], [Vector2(480, 720), 52.0], [Vector2(1440, 330), 48.0],
			[Vector2(760, 560), 40.0], [Vector2(1480, 800), 55.0], [Vector2(560, 560), 34.0]]
	paths = [
		[Vector2(290, 550), Vector2(560, 550)], [Vector2(560, 550), Vector2(665, 420)],
		[Vector2(560, 550), Vector2(665, 680)], [Vector2(665, 420), Vector2(900, 360)],
		[Vector2(665, 680), Vector2(900, 750)], [Vector2(900, 360), Vector2(1135, 280)],
		[Vector2(900, 750), Vector2(1135, 820)], [Vector2(1135, 280), Vector2(1420, 550)],
		[Vector2(1135, 820), Vector2(1420, 550)], [Vector2(1420, 550), Vector2(1560, 550)],
	]
	solid_rects = []
	for r in walls:
		solid_rects.append([r, "wall"])
	for r in hedges:
		solid_rects.append([r, "hedge"])
	solid_rects.append([building, "wall"])
	solid_rects.append([stand, "stand"])
	solid_rects.append([cart, "cart"])
	for s in statues:
		solid_rects.append([_pedestal(s[0]), "statue"])
	map_built.emit()




func _pedestal(p: Vector2) -> Rect2:
	return Rect2(p.x - 22, p.y - 15, 44, 30)




# ------------------------------------------------------------------ round setup (host)

func host_start_round(ch: Dictionary) -> void:
	build_map(ch)
	gp = {"pos": Vector2(560, 550), "vel": Vector2.ZERO, "facing": Vector2.RIGHT, "state": "normal", "st": 0.0,
		"cane_cd": 0.0, "swing": 0.0, "statue_cd": 0.0, "pose": 0, "has_banana": false, "escape": 0.0,
		"invuln": 0.0, "splash_cd": 0.0}
	gd = {"pos": Vector2(360, 550), "vel": Vector2.ZERO, "facing": Vector2.RIGHT, "state": "normal", "st": 0.0,
		"carry": "", "bench": -1, "dash_cd": 0.0, "bench_cd": 0.0, "splash_cd": 0.0}
	benches = []
	var bench_rects := [Rect2(835, 380, 130, 40), Rect2(835, 690, 130, 40), Rect2(1240, 420, 40, 120)]
	if ch.get("benches", false):
		bench_rects += [Rect2(420, 290, 130, 40), Rect2(1290, 800, 130, 40), Rect2(790, 950, 130, 40),
			Rect2(450, 640, 40, 120), Rect2(1440, 250, 40, 120)]
	for r in bench_rects:
		benches.append({"r": r, "carried": false})
	bananas = []
	var peel_spots := [Vector2(560, 300), Vector2(990, 300), Vector2(1250, 620), Vector2(760, 870)]
	if ch.get("bananas", false):
		peel_spots += [Vector2(470, 470), Vector2(800, 560), Vector2(1000, 640), Vector2(1220, 280),
			Vector2(1420, 420), Vector2(1430, 700), Vector2(600, 800), Vector2(980, 480)]
	for i in peel_spots.size():
		bananas.append({"p": peel_spots[i], "rot": float(i) * 1.7, "immune": 0.0})
	cart_stock = 2
	cart_t = 0.0
	order_progress = 0.0
	entrance_progress = 0.0
	time_left = ROUND_TIME
	stats = {"escapes": 0, "slips_gp": 0, "slips_gd": 0, "cane_hits": 0, "crashes": 0, "grabs": 0,
		"dashes": 0, "peels": 0, "statues": 0, "bench_moves": 0, "time": 0.0}
	winner = ""
	win_reason = ""
	phase = "intro"
	phase_t = INTRO_TIME
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scenario="):
			_apply_test_scenario(a.trim_prefix("--scenario="))


## Test hook (--scenario=NAME): only places characters/props and shortens the intro.
## Every action after that comes from real keyboard input sent over the network.
func _apply_test_scenario(sc: String) -> void:
	phase_t = 0.5
	match sc:
		"grab", "statue":
			gp["pos"] = Vector2(560, 550)
			gd["pos"] = Vector2(515, 550)
		"order":
			gp["pos"] = order_zone.get_center()
		"entrance":
			gd["pos"] = Vector2(470, 550)
			gd["facing"] = Vector2.LEFT
			gd["carry"] = "grandpa"
			gp["state"] = "grabbed"
			gp["cane_cd"] = 60.0
		"slip":
			gd["pos"] = Vector2(470, 550)
			gd["carry"] = "grandpa"
			gp["state"] = "grabbed"
			gp["cane_cd"] = 60.0
			bananas.append({"p": Vector2(540, 550), "rot": 0.0, "immune": 0.0})
		"dash":
			gd["pos"] = Vector2(760, 400)
			gp["pos"] = Vector2(1300, 950)
		"bench":
			gd["pos"] = Vector2(800, 400)
			gp["pos"] = Vector2(1300, 950)
		"cane":
			gp["pos"] = Vector2(870, 310)
			gp["facing"] = Vector2.DOWN
			gd["pos"] = Vector2(870, 352)


# ------------------------------------------------------------------ host simulation

func host_step(dt: float, in_gp: Dictionary, in_gd: Dictionary) -> void:
	match phase:
		"intro":
			phase_t -= dt
			if phase_t <= 0.0:
				phase = "countdown"
				phase_t = COUNTDOWN_TIME
				fx({"sfx": "countdown"})
			return
		"countdown":
			var before := ceili(phase_t)
			phase_t -= dt
			if phase_t <= 0.0:
				phase = "play"
				fx({"sfx": "go", "banner": "ВПЕРЁД!"})
				fx({"who": "gp", "text": "Я ТОЛЬКО ЗА ХЛЕБУШКОМ!"})
				fx({"who": "gd", "text": "СТОЙ, ТВОЮ ПЕНСИЮ!", "sfx": "whistle"})
			elif ceili(phase_t) != before:
				fx({"sfx": "countdown"})
			return
		"play":
			pass
		_:
			return

	time_left -= dt
	stats["time"] += dt
	if int(time_left + dt) != int(time_left) and time_left < 10.0 and time_left > 0.0:
		fx({"sfx": "tick"})
	_tick_timers(dt)
	_step_guard(dt, in_gd)
	_step_grandpa(dt, in_gp)
	_resolve_players()
	_check_bananas()
	_check_puddles(gp, GP_R)
	_check_puddles(gd, GD_R)
	_update_goals(dt, in_gp)
	if time_left <= 0.0 and phase == "play":
		time_left = 0.0
		_end_round("grandpa", "Время вышло — дед свободен!")


func _tick_timers(dt: float) -> void:
	for k in ["cane_cd", "statue_cd", "invuln", "splash_cd"]:
		gp[k] = maxf(0.0, gp[k] - dt)
	for k in ["dash_cd", "bench_cd", "splash_cd"]:
		gd[k] = maxf(0.0, gd[k] - dt)
	gp["swing"] = maxf(0.0, gp["swing"] - dt * 4.0)
	for b in bananas:
		b["immune"] = maxf(0.0, b["immune"] - dt)
	if gp["state"] == "grabbed":
		gp["escape"] = maxf(0.0, gp["escape"] - dt * 0.2)
	if cart_stock < 3:
		cart_t += dt
		if cart_t >= (4.0 if chapter.get("bananas", false) else 7.0):
			cart_t = 0.0
			cart_stock += 1


func _accel_for(b: Dictionary, radius: float) -> float:
	return 420.0 if _in_puddle(b["pos"], radius) else 2400.0


func _step_guard(dt: float, inp: Dictionary) -> void:
	var st: String = gd["state"]
	var move: Vector2 = inp["move"]
	if st == "normal":
		var speed := GD_SPEED
		if gd["carry"] == "grandpa":
			speed = GD_CARRY_GP_SPEED
		elif gd["carry"] == "bench":
			speed = GD_CARRY_BENCH_SPEED
		gd["vel"] = gd["vel"].move_toward(move * speed, _accel_for(gd, GD_R) * dt)
		if move.length() > 0.2:
			gd["facing"] = move.normalized()
		if inp["p1"]:
			_guard_grab()
		if inp["p2"] and gd["dash_cd"] <= 0.0:
			gd["state"] = "dash"
			gd["st"] = DASH_TIME
			var dir: Vector2 = move.normalized() if move.length() > 0.2 else gd["facing"]
			gd["facing"] = dir
			gd["vel"] = dir * (DASH_SPEED * (0.75 if gd["carry"] != "" else 1.0))
			gd["dash_cd"] = DASH_CD
			stats["dashes"] += 1
			fx({"sfx": "dash", "pos": gd["pos"], "color": Color(1, 1, 1), "n": 8})
		if inp["p3"]:
			_guard_bench()
	else:
		gd["st"] -= dt
		var friction: float = {"dash": 300.0, "knocked": 700.0, "stun": 1800.0, "slip": 160.0}.get(st, 1000.0)
		gd["vel"] = gd["vel"].move_toward(Vector2.ZERO, friction * dt)
		if gd["st"] <= 0.0:
			gd["state"] = "normal"
	var hit := _move_body(gd, GD_R, dt)
	if hit["into"] > CRASH_SPEED and (st == "dash" or st == "knocked" or st == "slip"):
		_guard_crash(hit)
	if gd["carry"] == "grandpa":
		gp["pos"] = gd["pos"] + gd["facing"] * (GD_R + 4.0)
		gp["vel"] = gd["vel"]
	# A dashing guard who bumps a free grandpa bowls him over.
	if st == "dash" and gd["carry"] == "" and gp["state"] != "grabbed" and gp["invuln"] <= 0.0:
		if gd["pos"].distance_to(gp["pos"]) < GD_R + GP_R + 4.0:
			gp["state"] = "knocked"
			gp["st"] = 0.8
			gp["vel"] = gd["vel"].normalized() * 420.0
			gd["vel"] *= 0.3
			gd["state"] = "normal"
			fx({"sfx": "thud", "pos": gp["pos"], "shake": 6.0, "color": Color(1, 0.9, 0.4), "n": 14,
				"who": "gp", "text": "МОЯ ПОЯСНИЦА!"})


func _guard_grab() -> void:
	if gd["carry"] != "":
		return
	if gp["state"] == "grabbed" or gp["invuln"] > 0.0:
		return
	if gd["pos"].distance_to(gp["pos"]) > GD_R + GP_R + 24.0:
		fx({"sfx": "swing", "pos": gd["pos"] + gd["facing"] * 30.0})
		return
	var was_statue: bool = gp["state"] == "statue"
	var was_ordering := order_progress
	gd["carry"] = "grandpa"
	gp["state"] = "grabbed"
	gp["escape"] = 0.0
	gp["cane_cd"] = maxf(gp["cane_cd"], 1.0)
	if gp["has_banana"]:
		gp["has_banana"] = false
		bananas.append({"p": gp["pos"], "rot": anim_t, "immune": 0.5})
	order_progress = 0.0
	stats["grabs"] += 1
	var line := "ПОПАЛСЯ, ДЕДУЛЯ!"
	if was_statue:
		line = "ЭТО НЕ СТАТУЯ!"
	elif was_ordering > 0.5:
		line = "ШАУРМА НЕ ДОЖДЁТСЯ!"
	fx({"sfx": "grab", "pos": gp["pos"], "shake": 4.0, "color": Color(0.5, 0.7, 1), "n": 10, "who": "gd", "text": line})
	fx({"who": "gp", "text": "ПУСТИ, ИРОД!" if was_ordering <= 0.5 else "ДА Я ЖЕ ПОЧТИ ЗАКАЗАЛ!"})


func _guard_bench() -> void:
	if gd["carry"] == "bench":
		_drop_bench(true)
		return
	if gd["carry"] != "" or gd["bench_cd"] > 0.0:
		return
	var best := -1
	var best_d := 50.0
	for i in benches.size():
		if benches[i]["carried"]:
			continue
		var d := _dist_point_rect(gd["pos"], benches[i]["r"]) - GD_R
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return
	benches[best]["carried"] = true
	gd["carry"] = "bench"
	gd["bench"] = best
	stats["bench_moves"] += 1
	fx({"sfx": "pick", "pos": gd["pos"], "who": "gd", "text": "ХЭК!"})


func _drop_bench(on_purpose: bool) -> void:
	var i: int = gd["bench"]
	if i < 0 or i >= benches.size():
		gd["carry"] = ""
		return
	var f: Vector2 = gd["facing"]
	# The bench lands across the guard's facing direction, so it can plug a corridor in front of him.
	var size := Vector2(40, 130) if absf(f.x) > absf(f.y) else Vector2(130, 40)
	var c: Vector2 = gd["pos"] + f * (GD_R + 30.0 + (20.0 if size.x == 40.0 else 4.0))
	c.x = clampf(c.x, 60.0, WORLD.size.x - 60.0)
	c.y = clampf(c.y, 90.0, WORLD.size.y - 90.0)
	benches[i]["r"] = Rect2(c - size * 0.5, size)
	benches[i]["carried"] = false
	gd["carry"] = ""
	gd["bench"] = -1
	gd["bench_cd"] = BENCH_CD
	if on_purpose:
		fx({"sfx": "drop", "pos": c, "shake": 3.0, "color": Color(0.7, 0.5, 0.3), "n": 8, "who": "gd", "text": "ПРОХОДА НЕТ!"})
	else:
		fx({"sfx": "drop", "pos": c, "color": Color(0.7, 0.5, 0.3), "n": 8})


func _guard_drop_carry() -> void:
	if gd["carry"] == "grandpa":
		gd["carry"] = ""
		gp["state"] = "knocked"
		gp["st"] = 0.35
		gp["invuln"] = 0.9
		gp["escape"] = 0.0
		gp["vel"] = -gd["facing"] * 150.0 + Vector2(0, 60)
	elif gd["carry"] == "bench":
		_drop_bench(false)


func _guard_crash(hit: Dictionary) -> void:
	var kind: String = hit["kind"]
	gd["state"] = "stun"
	gd["st"] = 1.4
	gd["vel"] = hit["normal"] * 160.0
	_guard_drop_carry()
	stats["crashes"] += 1
	var line: String = ["МАМА...", "КТО ЗДЕСЬ ПОСТАВИЛ СТЕНУ?!", "ОЙ-ОЙ-ОЙ"][stats["crashes"] % 3]
	if kind == "bench":
		line = "СКАМЕЙКА, ЗА ЧТО?!"
	elif kind == "statue":
		line = "ИЗВИНИТЕ, ТОВАРИЩ ПАМЯТНИК"
	elif kind == "hedge":
		line = "ТЬФУ! КУСТЫ!"
	fx({"sfx": "thud", "pos": gd["pos"] - hit["normal"] * GD_R, "shake": 12.0, "color": Color(1, 0.85, 0.2), "n": 22,
		"who": "gd", "text": line})


func _step_grandpa(dt: float, inp: Dictionary) -> void:
	var st: String = gp["state"]
	var move: Vector2 = inp["move"]
	if st == "grabbed":
		if inp["p2"]:
			gp["escape"] += 0.1
			fx({"sfx": "pick", "pitch": 1.0 + gp["escape"]})
			if gp["escape"] >= 1.0:
				_escape("Я ЕЩЁ В ДЕСАНТЕ СЛУЖИЛ!")
				return
		if inp["p1"]:
			_cane()
		if move.length() > 0.2:
			gp["facing"] = move.normalized()
		return
	if st == "normal":
		gp["vel"] = gp["vel"].move_toward(move * GP_SPEED, _accel_for(gp, GP_R) * dt)
		if move.length() > 0.2:
			gp["facing"] = move.normalized()
		if inp["p1"]:
			_cane()
		if inp["p2"]:
			_banana_action()
		if inp["p3"] and not order_zone.has_point(gp["pos"]) and gp["statue_cd"] <= 0.0:
			gp["state"] = "statue"
			gp["st"] = STATUE_MAX
			gp["pose"] = (gp["pose"] + 1) % 3
			gp["vel"] = Vector2.ZERO
			stats["statues"] += 1
			fx({"sfx": "statue", "pos": gp["pos"], "color": Color(0.7, 0.7, 0.7), "n": 6})
	elif st == "statue":
		gp["vel"] = Vector2.ZERO
		gp["st"] -= dt
		var held: float = STATUE_MAX - gp["st"]
		if gp["st"] <= 0.0 or (held > 0.35 and (move.length() > 0.2 or inp["p3"])):
			gp["state"] = "normal"
			gp["statue_cd"] = STATUE_CD
	else:
		gp["st"] -= dt
		var friction: float = {"slip": 160.0, "knocked": 900.0, "stun": 1500.0}.get(st, 1000.0)
		gp["vel"] = gp["vel"].move_toward(Vector2.ZERO, friction * dt)
		if gp["st"] <= 0.0:
			gp["state"] = "normal"
	_move_body(gp, GP_R, dt)


func _cane() -> void:
	if gp["cane_cd"] > 0.0:
		return
	gp["cane_cd"] = CANE_CD
	gp["swing"] = 1.0
	var to_guard: Vector2 = gd["pos"] - gp["pos"]
	var grabbed: bool = gp["state"] == "grabbed"
	var in_front: bool = to_guard.normalized().dot(gp["facing"]) > -0.2
	if to_guard.length() > GP_R + GD_R + 36.0 or not (grabbed or in_front):
		fx({"sfx": "swing", "pos": gp["pos"] + gp["facing"] * 24.0})
		return
	var dir: Vector2 = to_guard.normalized() if to_guard.length() > 1.0 else -gd["facing"]
	if grabbed:
		dir = -gd["facing"]
	var dashing: bool = gd["state"] == "dash"
	_guard_drop_carry()
	gd["state"] = "knocked"
	gd["st"] = 0.55
	gd["vel"] = dir * (900.0 if dashing else 640.0)
	stats["cane_hits"] += 1
	if grabbed:
		stats["escapes"] += 1
		gp["state"] = "normal"
		gp["invuln"] = 1.0
	fx({"sfx": "bonk", "pos": gd["pos"] + Vector2(0, -40), "shake": 9.0, "color": Color(1, 1, 0.5), "n": 16,
		"who": "gp", "text": ["ПОЛУЧИ, МОЛОДЁЖЬ!", "НА ТЕБЕ, ОКАЯННЫЙ!", "ЭТО ЗА МАННУЮ КАШУ!"][stats["cane_hits"] % 3]})
	fx({"who": "gd", "text": "АЙ!"})


func _escape(line: String) -> void:
	gd["carry"] = ""
	gd["state"] = "stun"
	gd["st"] = 0.8
	gp["state"] = "normal"
	gp["escape"] = 0.0
	gp["invuln"] = 1.0
	gp["vel"] = gd["facing"] * 460.0
	stats["escapes"] += 1
	fx({"sfx": "escape", "pos": gp["pos"], "shake": 5.0, "color": Color(0.6, 1, 0.6), "n": 14, "who": "gp", "text": line})


func _banana_action() -> void:
	if gp["has_banana"]:
		gp["has_banana"] = false
		var p: Vector2 = gp["pos"] - gp["facing"] * (GP_R + 12.0)
		bananas.append({"p": p, "rot": anim_t * 3.0, "immune": 0.7})
		stats["peels"] += 1
		fx({"sfx": "drop", "pos": p, "who": "gp", "text": "ОСТОРОЖНО, СКОЛЬЗКО! ХЕ-ХЕ"})
		return
	for i in bananas.size():
		if bananas[i]["p"].distance_to(gp["pos"]) < GP_R + 26.0:
			bananas.remove_at(i)
			gp["has_banana"] = true
			fx({"sfx": "pick", "pos": gp["pos"]})
			return
	if cart_stock > 0 and _dist_point_rect(gp["pos"], cart) < GP_R + 26.0:
		cart_stock -= 1
		gp["has_banana"] = true
		fx({"sfx": "pick", "pos": gp["pos"], "who": "gp", "text": "ВИТАМИНЧИКИ!"})


func _resolve_players() -> void:
	if gd["carry"] == "grandpa":
		return
	var d: Vector2 = gp["pos"] - gd["pos"]
	var min_d := GP_R + GD_R
	if d.length() < min_d and d.length() > 0.01:
		var push := d.normalized() * (min_d - d.length())
		gp["pos"] += push * 0.7
		gd["pos"] -= push * 0.3


func _check_bananas() -> void:
	var i := bananas.size() - 1
	while i >= 0:
		var b: Dictionary = bananas[i]
		var victim := ""
		if gd["state"] != "slip" and b["p"].distance_to(gd["pos"]) < GD_R + 6.0:
			victim = "gd"
		elif b["immune"] <= 0.0 and gp["state"] in ["normal", "knocked", "stun"] and b["p"].distance_to(gp["pos"]) < GP_R + 6.0:
			victim = "gp"
		if victim != "":
			bananas.remove_at(i)
			_slip(victim)
		i -= 1


func _slip(victim: String) -> void:
	var body: Dictionary = gd if victim == "gd" else gp
	var v: Vector2 = body["vel"]
	var dir: Vector2 = v.normalized() if v.length() > 20.0 else body["facing"]
	body["vel"] = dir * maxf(v.length() * 1.4, 300.0)
	body["state"] = "slip"
	body["st"] = 1.2
	if victim == "gd":
		stats["slips_gd"] += 1
		var had_gp: bool = gd["carry"] == "grandpa"
		_guard_drop_carry()
		var line := "ЧЬЯ ЭТО КОЖУРА?!"
		if had_gp:
			line = "ДЕДА УРОНИЛ!"
		fx({"sfx": "slip", "pos": gd["pos"], "shake": 5.0, "color": Color(1, 0.9, 0.2), "n": 12, "who": "gd", "text": line})
		if had_gp:
			fx({"who": "gp", "text": "СПАСИБО, БАНАНЧИК!"})
	else:
		stats["slips_gp"] += 1
		gp["has_banana"] = false
		fx({"sfx": "slip", "pos": gp["pos"], "shake": 3.0, "color": Color(1, 0.9, 0.2), "n": 10, "who": "gp", "text": "ОЙ, РАДИКУЛИТ!"})


func _check_puddles(b: Dictionary, radius: float) -> void:
	if b["splash_cd"] <= 0.0 and b["vel"].length() > 180.0 and _in_puddle(b["pos"], radius):
		b["splash_cd"] = 0.8
		fx({"sfx": "splash", "pos": b["pos"], "color": Color(0.5, 0.75, 1.0), "n": 10})


func _update_goals(dt: float, in_gp: Dictionary) -> void:
	var ordering: bool = gp["state"] == "normal" and order_zone.has_point(gp["pos"]) and in_gp["h3"]
	if ordering:
		if order_progress == 0.0:
			fx({"who": "gp", "text": "ОДНУ С СЫРОМ, ПОЖАЛУЙСТА!"})
		var before := int(order_progress * 3.0)
		order_progress += dt / HOLD_TIME
		if int(order_progress * 3.0) != before:
			fx({"sfx": "order_tick", "pitch": 1.0 + order_progress * 0.5})
		if order_progress >= 1.0:
			order_progress = 1.0
			_end_round("grandpa", "Дед заказал шаурму!")
			return
	else:
		order_progress = 0.0
	if gd["carry"] == "grandpa" and gd["state"] == "normal" and entrance_zone.has_point(gd["pos"]):
		var before_e := int(entrance_progress * 3.0)
		entrance_progress += dt / HOLD_TIME
		if int(entrance_progress * 3.0) != before_e:
			fx({"sfx": "tick", "pitch": 1.2})
		if entrance_progress >= 1.0:
			entrance_progress = 1.0
			_end_round("guard", "Охранник вернул деда в «Закат»!")
	else:
		entrance_progress = 0.0


func _end_round(who: String, reason: String) -> void:
	phase = "over"
	winner = who
	win_reason = reason
	var line := "ШАУРМА МОЯ!" if who == "grandpa" else "ОТБОЙ, ДЕДУЛЯ! КИСЕЛЬ СТЫНЕТ!"
	fx({"sfx": "win", "who": "gp" if who == "grandpa" else "gd", "text": line, "banner": reason, "shake": 6.0,
		"pos": gp["pos"] if who == "grandpa" else gd["pos"], "color": Color(1, 0.6, 0.1), "n": 40})


# ------------------------------------------------------------------ collision helpers

func _move_body(b: Dictionary, radius: float, dt: float) -> Dictionary:
	b["pos"] += b["vel"] * dt
	var res := {"into": 0.0, "normal": Vector2.ZERO, "kind": ""}
	var rects: Array = solid_rects.duplicate()
	for bench in benches:
		if not bench["carried"]:
			rects.append([bench["r"], "bench"])
	for pass_i in 2:
		for entry in rects:
			_push_out_rect(b, radius, entry[0], entry[1], res)
		for bush in bushes:
			_push_out_circle(b, radius, bush[0], bush[1], "hedge", res)
		_push_out_circle(b, radius, fountain[0], fountain[1], "wall", res)
	return res


func _push_out_rect(b: Dictionary, radius: float, r: Rect2, kind: String, res: Dictionary) -> void:
	var p: Vector2 = b["pos"]
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	var d := p - q
	var n := Vector2.ZERO
	var depth := 0.0
	if d.length_squared() > 0.0001:
		if d.length() >= radius:
			return
		n = d.normalized()
		depth = radius - d.length()
	else:
		# Centre inside the rect: push out along the shallowest side.
		var left := p.x - r.position.x
		var right := r.end.x - p.x
		var top := p.y - r.position.y
		var bottom := r.end.y - p.y
		var m := minf(minf(left, right), minf(top, bottom))
		if m == left:
			n = Vector2.LEFT
		elif m == right:
			n = Vector2.RIGHT
		elif m == top:
			n = Vector2.UP
		else:
			n = Vector2.DOWN
		depth = m + radius
	_apply_push(b, n, depth, kind, res)


func _push_out_circle(b: Dictionary, radius: float, c: Vector2, cr: float, kind: String, res: Dictionary) -> void:
	var d: Vector2 = b["pos"] - c
	var min_d := radius + cr
	if d.length() >= min_d:
		return
	var n := d.normalized() if d.length() > 0.01 else Vector2.UP
	_apply_push(b, n, min_d - d.length(), kind, res)


func _apply_push(b: Dictionary, n: Vector2, depth: float, kind: String, res: Dictionary) -> void:
	b["pos"] += n * depth
	var into: float = -b["vel"].dot(n)
	if into > 0.0:
		b["vel"] += n * into
		if into > res["into"]:
			res["into"] = into
			res["normal"] = n
			res["kind"] = kind


func _dist_point_rect(p: Vector2, r: Rect2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)


func _in_puddle(p: Vector2, radius: float) -> bool:
	for pu in puddles:
		var d: Vector2 = p - pu[0]
		d.y /= 0.65
		if d.length() < pu[1] + radius * 0.3:
			return true
	return false


# ------------------------------------------------------------------ effects & sync

func fx(d: Dictionary) -> void:
	fx_emitted.emit(d)


## Plays an effect event locally (called on both instances).
func apply_fx(d: Dictionary) -> void:
	if d.has("sfx") and sfx:
		sfx.play(d["sfx"], 0.0, d.get("pitch", 1.0))
	if d.has("shake"):
		shake = maxf(shake, d["shake"])
	if d.has("n") and d.has("pos"):
		burst.emit(d["pos"], d.get("color", Color.WHITE), int(d["n"]), d.get("shake", 0.0) >= 8.0)
	if d.has("text") and d.has("who"):
		for b in bubbles:
			if b["who"] == d["who"]:
				b["t"] = 0.0
		bubbles = bubbles.filter(func(b): return b["t"] > 0.0)
		bubbles.append({"who": d["who"], "text": d["text"], "t": 2.2})
	print("[EVT] ", JSON.stringify(_printable(d)))


func _printable(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if k in ["sfx", "text", "who", "banner"]:
			out[k] = d[k]
	return out


func make_snapshot() -> Dictionary:
	var bs := []
	for b in benches:
		bs.append([b["r"], b["carried"]])
	var ns := []
	for n in bananas:
		ns.append([n["p"], n["rot"]])
	return {"ph": phase, "pt": phase_t, "tl": time_left, "gp": gp.duplicate(), "gd": gd.duplicate(), "b": bs,
		"n": ns, "cs": cart_stock, "op": order_progress, "ep": entrance_progress, "st": stats.duplicate(),
		"w": winner, "wr": win_reason}


func apply_snapshot(s: Dictionary) -> void:
	phase = s["ph"]
	phase_t = s["pt"]
	time_left = s["tl"]
	gp = s["gp"]
	gd = s["gd"]
	benches = []
	for b in s["b"]:
		benches.append({"r": b[0], "carried": b[1]})
	bananas = []
	for n in s["n"]:
		bananas.append({"p": n[0], "rot": n[1], "immune": 0.0})
	cart_stock = s["cs"]
	order_progress = s["op"]
	entrance_progress = s["ep"]
	stats = s["st"]
	winner = s["w"]
	win_reason = s["wr"]


# ------------------------------------------------------------------ presentation

func local_body() -> Dictionary:
	return gp if local_role == "grandpa" else gd


func local_draw_pos() -> Vector2:
	return gp_draw if local_role == "grandpa" else gd_draw


func _process(dt: float) -> void:
	anim_t += dt
	if gp.is_empty():
		return
	var k := minf(1.0, dt * 28.0)
	gp_draw = gp_draw.lerp(gp["pos"], k) if gp_draw.distance_to(gp["pos"]) < 200.0 else gp["pos"]
	gd_draw = gd_draw.lerp(gd["pos"], k) if gd_draw.distance_to(gd["pos"]) < 200.0 else gd["pos"]
	if gp["state"] != "statue":
		last_seen_gp = gp_draw
	shake = maxf(0.0, shake - dt * 30.0)
	for b in bubbles:
		b["t"] -= dt
	bubbles = bubbles.filter(func(b): return b["t"] > 0.0)
