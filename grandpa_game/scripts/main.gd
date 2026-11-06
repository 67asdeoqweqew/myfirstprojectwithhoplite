extends Node
## Menu, ENet localhost networking, shared keyboard input, HUD, story chapters and rematch flow.

const GameScript = preload("res://scripts/game.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const ViewScript = preload("res://scripts/view3d.gd")

const DEFAULT_PORT := 7777
const ADDRESS := "127.0.0.1"
const CONNECT_TIMEOUT := 6.0
# The first launch on a new GPU can freeze both windows for many seconds while shaders compile,
# so a join keeps retrying for this long before reporting failure.
const JOIN_RETRY_WINDOW := 30.0

# Physical keys, so the controls work with any keyboard layout (including Russian).
const SEATS := [
	{"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"act": [[KEY_F], [KEY_G], [KEY_H]], "labels": ["F", "G", "H"], "move": "W A S D"},
	{"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
		"act": [[KEY_COMMA, KEY_KP_1], [KEY_PERIOD, KEY_KP_2], [KEY_SLASH, KEY_KP_3]],
		"labels": [",", ".", "/"], "move": "Стрелки"},
]

const CHAPTERS := [
	{"title": "Глава 1. Великий побег",
		"text": "Пятница, 12:00. В доме престарелых «Закат» опять манная каша.\nДед Семён учуял шаурму через три забора и рванул прямо в тапочках.\nОхранник Валера отложил кроссворд. Теперь это личное."},
	{"title": "Глава 2. Дождливый четверг", "rain": true,
		"text": "Ночью прошёл ливень. Двор превратился в каток с лужами.\nВалера надел новые ботинки. Дед надел старые тапочки.\nКто-то сегодня поедет на спине."},
	{"title": "Глава 3. Банановый завоз", "bananas": true,
		"text": "Во двор привезли ящик бананов «для витаминов».\nДед съел всё. Кожуру — сохранил.\nТележка с бананами пополняется вдвое быстрее."},
	{"title": "Глава 4. Ночная смена", "night": true,
		"text": "Отбой в 21:00, но шаурмичная работает до полуночи.\nВо дворе темно, светят только фонари.\nСтатуи в темноте выглядят особенно подозрительно…"},
	{"title": "Глава 5. Скамеечный бунт", "benches": true,
		"text": "Завхоз расставил во дворе новые скамейки.\nВалера понял: скамейка — это стена, которую можно носить.\nГлавное — не замуровать самого себя."},
	{"title": "Глава 6. Шаурма-фест", "rain": true, "bananas": true, "benches": true,
		"text": "У шаурмичной фестиваль: вторая шаурма бесплатно!\nЛужи, бананы, скамейки — всё сразу.\nФинал саги. Кто кого?"},
]
const BONUS := [
	{"title": "Бонус: Банановый ливень", "rain": true, "bananas": true,
		"text": "Сага окончена, но дед не сдаётся. Мокро и скользко."},
	{"title": "Бонус: Ночной рейд", "night": true, "benches": true,
		"text": "Темно, повсюду скамейки. Валера взял фонарик. Фонарик не помог."},
	{"title": "Бонус: Полный хаос", "night": true, "bananas": true, "rain": true,
		"text": "Всё и сразу, да ещё и ночью. Удачи."},
]

var game: Node
var view: Node3D
var sfx: Node
var ui: CanvasLayer
var menu: Control
var status_label: Label
var low_check: CheckBox
var port_edit: LineEdit
var host_btn: Button
var join_btn: Button
var cancel_btn: Button
var hud: Control
var results: Control
var results_title: Label
var results_body: Label
var rematch_btn: Button
var rematch_info: Label

var peer: ENetMultiplayerPeer
var connecting_t := -1.0
var join_started := -1.0
var in_session := false
var round_idx := 0
var guard_is_host := true
var saga := [0, 0]                # wins per seat: 0 = host's player, 1 = client's player
var ready_flags := [false, false]
var results_shown := false
var banner_text := ""
var banner_t := 0.0
var counted_round := -1
var log_state := false
var ping_t := 0.0
var silence_t := 0.0
const PEER_SILENCE_LIMIT := 6.0
var log_t := 0.0

# Shared input: whichever window is focused samples BOTH key sets and sends them to the host.
var press_count := [[0, 0, 0], [0, 0, 0]]
var was_focused := false
var host_inputs := [{"move": Vector2.ZERO, "held": [false, false, false]}, {"move": Vector2.ZERO, "held": [false, false, false]}]
var host_pending := [[0, 0, 0], [0, 0, 0]]
var host_last_counts := {}


func _ready() -> void:
	sfx = SfxScript.new()
	add_child(sfx)
	game = GameScript.new()
	game.sfx = sfx
	add_child(game)
	view = ViewScript.new()
	add_child(view)
	view.setup(game)
	game.fx_emitted.connect(_on_game_fx)
	game.build_map(CHAPTERS[0])  # courtyard shown behind the menu
	_build_ui()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_handle_cmdline()


func _handle_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	log_state = "--log-state" in args
	if "--low" in args:
		low_check.button_pressed = true
	for a in args:
		if a.begins_with("--port="):
			port_edit.text = a.trim_prefix("--port=")
	if "--host" in args:
		_on_host_pressed()
	elif "--join" in args:
		_on_join_pressed()


# ------------------------------------------------------------------ UI construction

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.1))
	l.add_theme_constant_override("outline_size", 6 if size >= 24 else 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(0, 46)
	b.pressed.connect(func(): sfx.play("click"); cb.call())
	return b


func _panel_style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.12, 0.08, 0.1)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	return sb


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	ui.add_child(hud)

	# --- start screen ---
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.72, 0.3, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu.add_child(scroll)
	var center := MarginContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		center.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var title := _label("ДЕД, СТОЯТЬ!", 56, Color(1, 0.35, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := _label("Дед Семён сбежал из дома престарелых «Закат» за шаурмой. Охранник Валера обязан вернуть его до конца смены.", 18)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)

	var how := PanelContainer.new()
	how.add_theme_stylebox_override("panel", _panel_style(Color(1, 0.97, 0.88)))
	col.add_child(how)
	var how_text := _label(
		"КАК ИГРАТЬ ВДВОЁМ НА ОДНОМ КОМПЬЮТЕРЕ\n" +
		"1) Запустите игру два раза (два окна).  2) В первом окне нажмите «СОЗДАТЬ ИГРУ».  3) Во втором — «ПОДКЛЮЧИТЬСЯ».\n" +
		"Хост играет за ОХРАННИКА, второе окно — за ДЕДА. В реванше роли меняются.\n\n" +
		"ИГРОК 1 (окно-хост): движение W A S D, действия F / G / H\n" +
		"ИГРОК 2 (второе окно): движение стрелками, действия  ,  .  /  (или Num1 Num2 Num3)\n\n" +
		"ДЕД:  [1] трость (сбивает охранника, освобождает из захвата)  [2] взять/бросить кожуру; в захвате — жми часто, чтобы вырваться  [3] статуя (обманка); у шаурмы — держи, чтобы заказать\n" +
		"ОХРАННИК:  [1] схватить деда  [2] рывок (не врежься!)  [3] поднять/поставить скамейку\n\n" +
		"ДЕД побеждает, если 3 секунды держит кнопку заказа у шаурмичной или если вышло время (3 минуты).\n" +
		"ОХРАННИК побеждает, если 3 секунды держит деда у входа в «Закат».\n\n" +
		"Клавиатура общая: активное окно ловит клавиши ОБОИХ игроков и передаёт их по сети, поэтому ваше окно может быть не в фокусе. Esc — выйти в меню.",
		15, Color(0.15, 0.1, 0.12))
	how_text.remove_theme_color_override("font_outline_color")
	how_text.add_theme_constant_override("outline_size", 0)
	how.add_child(how_text)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var addr := _label("Адрес: " + ADDRESS + "   Порт:", 20)
	addr.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(addr)
	port_edit = LineEdit.new()
	port_edit.text = str(DEFAULT_PORT)
	port_edit.custom_minimum_size = Vector2(110, 40)
	port_edit.add_theme_font_size_override("font_size", 20)
	row.add_child(port_edit)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	col.add_child(btns)
	host_btn = _button("СОЗДАТЬ ИГРУ (хост)", _on_host_pressed)
	join_btn = _button("ПОДКЛЮЧИТЬСЯ к 127.0.0.1", _on_join_pressed)
	cancel_btn = _button("ОТМЕНА", _leave_session)
	var quit_btn := _button("ВЫХОД", func(): get_tree().quit())
	for b in [host_btn, join_btn, cancel_btn, quit_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btns.add_child(b)
	cancel_btn.visible = false
	low_check = CheckBox.new()
	low_check.text = "Упрощённая графика (для слабых компьютеров)"
	low_check.add_theme_font_size_override("font_size", 18)
	low_check.toggled.connect(func(on: bool): view.set_low_quality(on))
	col.add_child(low_check)
	status_label = _label("", 20, Color(1, 1, 1))
	col.add_child(status_label)

	# --- results screen ---
	results = CenterContainer.new()
	results.set_anchors_preset(Control.PRESET_FULL_RECT)
	results.visible = false
	ui.add_child(results)
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _panel_style(Color(0.15, 0.12, 0.25, 0.94)))
	rp.custom_minimum_size = Vector2(620, 0)
	results.add_child(rp)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 8)
	rp.add_child(rcol)
	results_title = _label("", 40, Color(1, 0.8, 0.2))
	results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rcol.add_child(results_title)
	results_body = _label("", 18)
	rcol.add_child(results_body)
	rematch_info = _label("", 17, Color(0.7, 1, 0.7))
	rematch_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rcol.add_child(rematch_info)
	var rbtns := HBoxContainer.new()
	rbtns.add_theme_constant_override("separation", 12)
	rcol.add_child(rbtns)
	rematch_btn = _button("РЕВАНШ — смена ролей", _on_rematch_pressed)
	var menu_btn := _button("В МЕНЮ", _leave_session)
	for b in [rematch_btn, menu_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rbtns.add_child(b)


func _set_status(text: String, color := Color.WHITE) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


func _set_menu_busy(busy: bool) -> void:
	host_btn.disabled = busy
	join_btn.disabled = busy
	port_edit.editable = not busy
	cancel_btn.visible = busy


# ------------------------------------------------------------------ networking

func _port() -> int:
	var p := port_edit.text.strip_edges().to_int()
	return p if p > 1024 and p < 65536 else DEFAULT_PORT


func _place_window(left: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# Deferred: window managers may re-place a window that is moved before it is mapped.
	await get_tree().create_timer(0.3).timeout
	var win := get_window()
	var screen := DisplayServer.screen_get_usable_rect(win.current_screen)
	var w := mini(screen.size.x / 2, 960)
	var h := mini(screen.size.y - 60, 640)
	win.size = Vector2i(w, h)
	win.position = screen.position + Vector2i(0 if left else screen.size.x - w, 30)


func _on_host_pressed() -> void:
	peer = ENetMultiplayerPeer.new()
	peer.set_bind_ip(ADDRESS)
	var err := peer.create_server(_port(), 1)
	if err != OK:
		_set_status("Не удалось создать игру на %s:%d (ошибка %d). Порт занят? Укажите другой порт в обоих окнах." % [ADDRESS, _port(), err], Color(1, 0.3, 0.3))
		peer = null
		return
	multiplayer.multiplayer_peer = peer
	_set_menu_busy(true)
	_place_window(true)
	get_window().title = "ДЕД, СТОЯТЬ! — ИГРОК 1 (хост)"
	_set_status("Игра создана на %s:%d. Ждём второго игрока… Запустите второе окно и нажмите «ПОДКЛЮЧИТЬСЯ»." % [ADDRESS, _port()], Color(1, 1, 0.6))
	print("[NET] hosting on %s:%d" % [ADDRESS, _port()])


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_join_pressed() -> void:
	join_started = _now()
	_place_window(false)
	get_window().title = "ДЕД, СТОЯТЬ! — ИГРОК 2"
	_start_client()


func _start_client() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ADDRESS, _port())
	if err != OK:
		_set_status("Не удалось начать подключение (ошибка %d)." % err, Color(1, 0.3, 0.3))
		peer = null
		return
	multiplayer.multiplayer_peer = peer
	connecting_t = _now() + CONNECT_TIMEOUT  # real-time deadline
	_set_menu_busy(true)
	_set_status("Подключаемся к %s:%d…" % [ADDRESS, _port()], Color(1, 1, 0.6))
	print("[NET] joining %s:%d" % [ADDRESS, _port()])


func _on_connected_to_server() -> void:
	connecting_t = -1.0
	join_started = -1.0
	_set_status("Подключено! Ждём начала раунда…", Color(0.6, 1, 0.6))
	print("[NET] connected to server")


func _on_connection_failed() -> void:
	_fail_connect()


func _fail_connect() -> void:
	connecting_t = -1.0
	_close_peer()
	if join_started >= 0.0 and _now() - join_started < JOIN_RETRY_WINDOW:
		_set_status("Хост пока не отвечает, пробуем ещё раз… (%d с)" % int(JOIN_RETRY_WINDOW - (_now() - join_started)), Color(1, 1, 0.6))
		print("[NET] retrying join")
		get_tree().create_timer(1.0).timeout.connect(func():
			if join_started >= 0.0 and multiplayer.multiplayer_peer == null:
				_start_client())
		return
	join_started = -1.0
	_set_menu_busy(false)
	_set_status("Не удалось подключиться к %s:%d. Сначала создайте игру в другом окне (тот же порт)." % [ADDRESS, _port()], Color(1, 0.3, 0.3))
	print("[NET] connection failed")


func _on_peer_connected(id: int) -> void:
	print("[NET] peer connected ", id)
	# Detect a vanished peer within ~10 s instead of ENet's default (up to 30 s), while tolerating
	# the multi-second stall of first-frame 3D shader compilation on slow machines.
	var pp := peer.get_peer(id) if peer else null
	if pp:
		pp.set_timeout(32, 5000, 10000)
	if not multiplayer.is_server():
		return
	if in_session:
		peer.disconnect_peer(id)  # only two players
		return
	in_session = true
	round_idx = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chapter="):
			round_idx = clampi(a.trim_prefix("--chapter=").to_int() - 1, 0, 99)
	saga = [0, 0]
	guard_is_host = true
	_host_begin_round()


func _on_peer_disconnected(id: int) -> void:
	print("[NET] peer disconnected ", id)
	if multiplayer.is_server() and in_session:
		_back_to_menu("Второй игрок отключился. Игра остановлена.")


func _on_server_disconnected() -> void:
	print("[NET] server disconnected")
	_back_to_menu("Соединение с хостом потеряно (хост закрыл игру или вышел в меню).")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close_peer()  # tell the other window right away


func _close_peer() -> void:
	if peer:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = null


func _leave_session() -> void:
	_back_to_menu("Вы вышли в меню.")


func _back_to_menu(msg: String) -> void:
	_close_peer()
	in_session = false
	connecting_t = -1.0
	join_started = -1.0
	game.phase = "idle"
	game.gp = {}
	game.build_map(CHAPTERS[0])
	results.visible = false
	results_shown = false
	menu.visible = true
	_set_menu_busy(false)
	print("[NET] back to menu: ", msg)
	var bad := msg.begins_with("Второй") or msg.begins_with("Соединение")
	_set_status(msg, Color(1, 0.3, 0.3) if bad else Color.WHITE)
	hud.queue_redraw()


func _chapter_for(idx: int) -> Dictionary:
	if idx < CHAPTERS.size():
		return CHAPTERS[idx]
	return BONUS[(idx - CHAPTERS.size()) % BONUS.size()]


func _host_begin_round() -> void:
	ready_flags = [false, false]
	_rpc_start_round.rpc(round_idx, guard_is_host)
	game.host_start_round(_chapter_for(round_idx))


@rpc("authority", "call_local", "reliable")
func _rpc_start_round(idx: int, guard_host: bool) -> void:
	round_idx = idx
	guard_is_host = guard_host
	in_session = true
	silence_t = 0.0
	var i_am_host := multiplayer.is_server()
	game.is_host = i_am_host
	game.local_role = "guard" if guard_host == i_am_host else "grandpa"
	if not i_am_host:
		game.build_map(_chapter_for(idx))
	game.gp = {}
	game.bubbles = []
	menu.visible = false
	results.visible = false
	results_shown = false
	print("[NET] round %d starts, local role = %s" % [idx, game.local_role])


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(packed: PackedByteArray, raw_size: int) -> void:
	if raw_size <= 0 or raw_size > 1 << 20:
		return
	var decoded: Variant = bytes_to_var(packed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE))
	if not decoded is Array or decoded.size() != 2:
		return
	var s: Dictionary = decoded[0]
	var meta: Dictionary = decoded[1]
	var first: bool = game.gp.is_empty()
	game.apply_snapshot(s)
	if first:
		game.gp_draw = game.gp["pos"]
		game.gd_draw = game.gd["pos"]
	saga = meta["saga"]
	ready_flags = meta["ready"]


@rpc("authority", "call_local", "reliable")
func _rpc_fx(d: Dictionary) -> void:
	game.apply_fx(d)
	if d.has("banner"):
		banner_text = d["banner"]
		banner_t = 2.5


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_ping() -> void:
	silence_t = 0.0


func _on_game_fx(d: Dictionary) -> void:
	if multiplayer.multiplayer_peer and multiplayer.is_server():
		_rpc_fx.rpc(d)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready() -> void:
	_host_mark_ready(multiplayer.get_remote_sender_id())


func _on_rematch_pressed() -> void:
	rematch_btn.disabled = true
	if multiplayer.is_server():
		_host_mark_ready(1)
	else:
		_rpc_ready.rpc_id(1)


func _host_mark_ready(sender: int) -> void:
	if game.phase != "over":
		return
	ready_flags[0 if sender == 1 else 1] = true
	print("[NET] ready flags ", ready_flags)
	if ready_flags[0] and ready_flags[1]:
		round_idx += 1
		guard_is_host = not guard_is_host
		_host_begin_round()


# ------------------------------------------------------------------ input

func _seat_pressed(keys: Array) -> bool:
	for k in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func _sample_input() -> Array:
	var data := []
	var focused := get_window().has_focus()
	for seat in 2:
		var s: Dictionary = SEATS[seat]
		var move := Vector2.ZERO
		var held := [false, false, false]
		if focused:
			move = Vector2(float(_seat_pressed(s["right"])) - float(_seat_pressed(s["left"])),
				float(_seat_pressed(s["down"])) - float(_seat_pressed(s["up"])))
			for k in 3:
				held[k] = _seat_pressed(s["act"][k])
		data.append_array([move.x, move.y, held[0], held[1], held[2], press_count[seat][0], press_count[seat][1], press_count[seat][2]])
	return data


func _host_receive_input(source: int, data: Array) -> void:
	if data.size() != 16:
		return
	if not host_last_counts.has(source):
		host_last_counts[source] = [[data[5], data[6], data[7]], [data[13], data[14], data[15]]]
	for seat in 2:
		var o := seat * 8
		var mv := Vector2(data[o], data[o + 1])
		host_inputs[seat] = {"move": mv.limit_length(1.0), "held": [bool(data[o + 2]), bool(data[o + 3]), bool(data[o + 4])]}
		for k in 3:
			var c: int = data[o + 5 + k]
			host_pending[seat][k] += maxi(0, c - host_last_counts[source][seat][k])
			host_last_counts[source][seat][k] = c


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_input(data: Array) -> void:
	_host_receive_input(multiplayer.get_remote_sender_id(), data)


func _role_input(seat: int) -> Dictionary:
	var i: Dictionary = host_inputs[seat]
	var d := {"move": i["move"], "h1": i["held"][0], "h2": i["held"][1], "h3": i["held"][2]}
	for k in 3:
		d["p%d" % (k + 1)] = host_pending[seat][k] > 0
		if host_pending[seat][k] > 0:
			host_pending[seat][k] -= 1
	return d


func _physics_process(dt: float) -> void:
	if connecting_t > 0.0 and _now() > connecting_t:
		_fail_connect()
	if not in_session or multiplayer.multiplayer_peer == null:
		return
	# Heartbeat: catches a crashed/killed peer even when ENet has not timed out yet.
	ping_t += dt
	silence_t += dt
	if ping_t >= 0.5:
		ping_t = 0.0
		_rpc_ping.rpc()
	if silence_t > PEER_SILENCE_LIMIT:
		_back_to_menu("Соединение потеряно: второе окно не отвечает больше %d секунд." % int(PEER_SILENCE_LIMIT))
		return
	var focused := get_window().has_focus()
	if focused or was_focused:
		var data := _sample_input()
		if multiplayer.is_server():
			_host_receive_input(1, data)
		else:
			_rpc_input.rpc_id(1, data)
	was_focused = focused
	if not multiplayer.is_server():
		if log_state:
			_log_state(dt)
		return
	if game.phase == "over":
		# Either player can ready up for the rematch with action key 1 (shared input, like gameplay).
		for seat_i in 2:
			if host_pending[seat_i][0] > 0 and not ready_flags[seat_i]:
				_host_mark_ready(1 if seat_i == 0 else -1)
	if game.phase != "play":
		host_pending = [[0, 0, 0], [0, 0, 0]]
	var guard_seat := 0 if guard_is_host else 1
	var in_gd := _role_input(guard_seat)
	var in_gp := _role_input(1 - guard_seat)
	game.host_step(dt, in_gp, in_gd)
	if game.phase == "over" and counted_round != round_idx:
		counted_round = round_idx
		var winner_is_host: bool = (game.winner == "guard") == guard_is_host
		saga[0 if winner_is_host else 1] += 1
	if multiplayer.get_peers().size() > 0:
		# Compressed so the snapshot always fits in one ENet packet.
		var raw := var_to_bytes([game.make_snapshot(), {"saga": saga, "ready": ready_flags}])
		_rpc_snapshot.rpc(raw.compress(FileAccess.COMPRESSION_DEFLATE), raw.size())
	if log_state:
		_log_state(dt)


## Debug aid (--log-state): prints the shared state once per second so both instances can be compared.
func _log_state(dt: float) -> void:
	log_t += dt
	if log_t < 1.0 or game.gp.is_empty():
		return
	log_t = 0.0
	print("[STATE] fps=%d %s role=%s phase=%s t=%.1f gp=(%d,%d) %s gd=(%d,%d) %s carry=%s order=%.2f home=%.2f esc=%.2f focus=%s stats=%s" % [
		Engine.get_frames_per_second(), "HOST" if multiplayer.is_server() else "CLIENT", game.local_role, game.phase, game.time_left,
		game.gp["pos"].x, game.gp["pos"].y, game.gp["state"], game.gd["pos"].x, game.gd["pos"].y, game.gd["state"],
		game.gd["carry"], game.order_progress, game.entrance_progress, game.gp["escape"], get_window().has_focus(),
		JSON.stringify(game.stats)])


## Presses are counted from key events (not polling) so even very short taps and fast mashing register.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	for seat in 2:
		for k in 3:
			if event.physical_keycode in SEATS[seat]["act"][k]:
				press_count[seat][k] += 1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and in_session:
		_leave_session()


func _process(dt: float) -> void:
	banner_t = maxf(0.0, banner_t - dt)
	if in_session and game.phase == "over" and not results_shown:
		_show_results()
	if results_shown:
		_update_rematch_info()
	hud.queue_redraw()


# ------------------------------------------------------------------ results

func _my_seat() -> int:
	return 0 if multiplayer.is_server() else 1


func _show_results() -> void:
	results_shown = true
	results.visible = true
	rematch_btn.disabled = false
	var won: bool = game.winner == game.local_role
	results_title.text = ("ПОБЕДА!" if won else "ПОРАЖЕНИЕ!") + "  " + ("ДЕД" if game.winner == "grandpa" else "ОХРАННИК") + " ПОБЕДИЛ"
	results_title.add_theme_color_override("font_color", Color(1, 0.85, 0.2) if won else Color(1, 0.45, 0.4))
	sfx.play("win" if won else "lose", -4.0)
	var s: Dictionary = game.stats
	var t: float = s.get("time", 0.0)
	var lines := [
		game.win_reason,
		"",
		"СТАТИСТИКА РАУНДА (%s)" % _chapter_for(round_idx)["title"],
		"Время раунда: %d:%02d" % [int(t) / 60, int(t) % 60],
		"Побеги деда из захвата: %d   (захватов: %d)" % [s["escapes"], s["grabs"]],
		"Подскользнулись на банане: дед — %d, охранник — %d" % [s["slips_gp"], s["slips_gd"]],
		"Удары тростью: %d" % s["cane_hits"],
		"Охранник врезался в препятствия: %d   (рывков: %d)" % [s["crashes"], s["dashes"]],
		"Брошено кожуры: %d   Позы статуи: %d   Переноски скамеек: %d" % [s["peels"], s["statues"], s["bench_moves"]],
		"",
		"СЧЁТ САГИ:  Игрок 1 (хост) %d : %d Игрок 2" % [saga[0], saga[1]],
	]
	if round_idx == CHAPTERS.size() - 1:
		var champion := "Игрок 1" if saga[0] > saga[1] else ("Игрок 2" if saga[1] > saga[0] else "дружба")
		lines.append("САГА ЗАВЕРШЕНА! Победитель: %s. Дальше — бонусные раунды." % champion)
		lines.append("Эпилог: " + ("Дед Семён съел шаурму и записался на танцы." if game.winner == "grandpa" else "Валера получил грамоту «Охранник года». Дед уже копает подкоп."))
	results_body.text = "\n".join(lines)


func _update_rematch_info() -> void:
	var mine: bool = ready_flags[_my_seat()]
	var theirs: bool = ready_flags[1 - _my_seat()]
	var next_role := "ДЕДА" if game.local_role == "guard" else "ОХРАННИКА"
	if mine and theirs:
		rematch_info.text = "Начинаем!"
	elif mine:
		rematch_info.text = "Вы готовы. Ждём соперника… (в реванше вы играете за %s)" % next_role
	elif theirs:
		rematch_info.text = "Соперник хочет реванш! В реванше вы играете за %s." % next_role
	else:
		rematch_info.text = "Следующий раунд: %s. Вы играете за %s.\nНажмите РЕВАНШ или клавишу [%s]." % [
			_chapter_for(round_idx + 1)["title"], next_role, SEATS[_my_seat()]["labels"][0]]


# ------------------------------------------------------------------ HUD

func _draw_hud() -> void:
	if not in_session or game.gp.is_empty():
		return
	var font := ThemeDB.fallback_font
	var vs := hud.size
	var role: String = game.local_role
	var seat: Dictionary = SEATS[_my_seat()]
	var keys: Array = seat["labels"]
	var dark := Color(0.1, 0.06, 0.1, 0.85)

	# Off-screen indicators (drawn first so panels stay on top).
	var other_pos: Vector2 = game.gd_draw if role == "grandpa" else game.gp_draw
	var other_label := "ОХРАННИК" if role == "grandpa" else "ДЕД"
	if role == "guard" and game.gp["state"] == "statue":
		other_pos = game.last_seen_gp
		other_label = "ДЕД?"
	_edge_arrow(view.to_screen(other_pos), other_label, Color(1, 0.3, 0.25), vs)
	_edge_arrow(view.to_screen(game.order_zone.get_center()), "ШАУРМА", Color(1, 0.6, 0.1), vs)
	_edge_arrow(view.to_screen(game.entrance_zone.get_center()), "ВХОД", Color(0.35, 0.6, 1), vs)

	# Timer.
	var tl: float = maxf(0.0, game.time_left)
	var tstr := "%d:%02d" % [int(ceil(tl)) / 60, int(ceil(tl)) % 60]
	_box(Rect2(vs.x * 0.5 - 70, 8, 140, 50), dark)
	hud.draw_string(font, Vector2(vs.x * 0.5 - 70, 46), tstr, HORIZONTAL_ALIGNMENT_CENTER, 140, 36,
		Color(1, 0.35, 0.3) if tl < 30.0 else Color.WHITE)

	# Role & goal.
	var role_text := "ТЫ — ДЕД СЕМЁН" if role == "grandpa" else "ТЫ — ОХРАННИК ВАЛЕРА"
	var goal := "Беги к шаурме и держи [%s] 3 сек!" % keys[2] if role == "grandpa" else "Схвати деда [%s] и отнеси к ВХОДУ!" % keys[0]
	_box(Rect2(8, 8, 330, 62), dark)
	hud.draw_string(font, Vector2(18, 34), role_text, HORIZONTAL_ALIGNMENT_LEFT, 320, 20,
		Color(0.6, 1, 0.5) if role == "grandpa" else Color(0.5, 0.75, 1))
	hud.draw_string(font, Vector2(18, 58), goal, HORIZONTAL_ALIGNMENT_LEFT, 320, 14, Color.WHITE)

	# Saga score.
	_box(Rect2(vs.x - 238, 8, 230, 62), dark)
	hud.draw_string(font, Vector2(vs.x - 228, 32), _chapter_for(round_idx)["title"], HORIZONTAL_ALIGNMENT_LEFT, 215, 14, Color(1, 0.85, 0.4))
	hud.draw_string(font, Vector2(vs.x - 228, 58), "Счёт: И1 %d : %d И2" % [saga[0], saga[1]], HORIZONTAL_ALIGNMENT_LEFT, 215, 18, Color.WHITE)

	# Both goal progress bars, visible to both players.
	_progress(Rect2(vs.x * 0.5 - 250, 64, 240, 22), game.order_progress, Color(1, 0.55, 0.1), "ЗАКАЗ ШАУРМЫ")
	_progress(Rect2(vs.x * 0.5 + 10, 64, 240, 22), game.entrance_progress, Color(0.3, 0.6, 1), "ДЕДА ВЕДУТ ДОМОЙ")
	if game.gp["state"] == "grabbed":
		var mash := "Жми [%s] быстро — вырывайся! [%s] — трость" % [keys[1], keys[0]] if role == "grandpa" else "Дед вырывается! Неси к входу!"
		_progress(Rect2(vs.x * 0.5 - 170, 92, 340, 26), game.gp["escape"], Color(1, 0.3, 0.3), mash)

	# Abilities.
	var abil := []
	if role == "grandpa":
		abil = [["Трость", game.gp["cane_cd"] / GameScript.CANE_CD],
			["Бросить кожуру" if game.gp["has_banana"] else "Взять кожуру", 0.0],
			["Заказ / Статуя", game.gp["statue_cd"] / GameScript.STATUE_CD]]
	else:
		abil = [["Схватить", 0.0], ["Рывок", game.gd["dash_cd"] / GameScript.DASH_CD],
			["Поставить скамейку" if game.gd["carry"] == "bench" else "Скамейка", game.gd["bench_cd"] / GameScript.BENCH_CD]]
	var bx := vs.x * 0.5 - 255.0
	for i in 3:
		var r := Rect2(bx + i * 172, vs.y - 58, 164, 50)
		_box(r, dark)
		var cd: float = abil[i][1]
		if cd > 0.0:
			hud.draw_rect(Rect2(r.position, Vector2(r.size.x * cd, r.size.y)), Color(0.6, 0.1, 0.1, 0.6), true)
		hud.draw_rect(Rect2(r.position + Vector2(8, 9), Vector2(32, 32)), Color(1, 0.85, 0.3) if cd <= 0.0 else Color(0.4, 0.4, 0.4), true)
		hud.draw_string(font, r.position + Vector2(8, 34), keys[i], HORIZONTAL_ALIGNMENT_CENTER, 32, 22, Color(0.1, 0.05, 0.1))
		hud.draw_string(font, r.position + Vector2(46, 31), abil[i][0], HORIZONTAL_ALIGNMENT_LEFT, 116, 14,
			Color.WHITE if cd <= 0.0 else Color(0.75, 0.75, 0.75))
	hud.draw_string(font, Vector2(8, vs.y - 12), "Движение: " + seat["move"], HORIZONTAL_ALIGNMENT_LEFT, 200, 14, Color(1, 1, 1, 0.8))

	# Intro story card and countdown.
	if game.phase == "intro":
		var ch := _chapter_for(round_idx)
		# Story on top, role reminder at the bottom: the characters in the middle stay visible.
		var card := Rect2(vs.x * 0.5 - 330, 94, 660, 160)
		_box(card, Color(0.15, 0.1, 0.25, 0.9))
		hud.draw_string(font, card.position + Vector2(0, 36), ch["title"], HORIZONTAL_ALIGNMENT_CENTER, card.size.x, 28, Color(1, 0.8, 0.25))
		var y := 70.0
		for line in ch["text"].split("\n"):
			hud.draw_string(font, card.position + Vector2(20, y), line, HORIZONTAL_ALIGNMENT_CENTER, card.size.x - 40, 16, Color.WHITE)
			y += 24.0
		var you := "В этом раунде ты — ДЕД. Движение: %s, действия: %s" % [seat["move"], "  ".join(keys)] if role == "grandpa" \
			else "В этом раунде ты — ОХРАННИК. Движение: %s, действия: %s" % [seat["move"], "  ".join(keys)]
		var rbox := Rect2(vs.x * 0.5 - 330, vs.y - 128, 660, 62)
		_box(rbox, Color(0.15, 0.1, 0.25, 0.9))
		hud.draw_string(font, rbox.position + Vector2(10, 26), you, HORIZONTAL_ALIGNMENT_CENTER, rbox.size.x - 20, 17,
			Color(0.6, 1, 0.5) if role == "grandpa" else Color(0.5, 0.75, 1))
		hud.draw_string(font, rbox.position + Vector2(10, 50), "Старт через %d…" % int(ceil(game.phase_t + GameScript.COUNTDOWN_TIME)),
			HORIZONTAL_ALIGNMENT_CENTER, rbox.size.x - 20, 14, Color(1, 1, 1, 0.75))
	elif game.phase == "countdown":
		hud.draw_string(font, Vector2(0, vs.y * 0.5 + 40), str(int(ceil(game.phase_t))), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 120, Color(1, 0.85, 0.2))
	if banner_t > 0.0:
		var a := clampf(banner_t, 0.0, 1.0)
		hud.draw_string_outline(font, Vector2(0, vs.y * 0.32), banner_text, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 40, 10, Color(0.1, 0.05, 0.1, a))
		hud.draw_string(font, Vector2(0, vs.y * 0.32), banner_text, HORIZONTAL_ALIGNMENT_CENTER, vs.x, 40, Color(1, 0.85, 0.2, a))


func _box(r: Rect2, c: Color) -> void:
	hud.draw_rect(r, c, true)
	hud.draw_rect(r, Color(0, 0, 0, 0.6), false, 2.0)


func _progress(r: Rect2, v: float, c: Color, text: String) -> void:
	_box(r, Color(0.1, 0.06, 0.1, 0.85))
	hud.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * clampf(v, 0.0, 1.0), r.size.y - 4)), c, true)
	hud.draw_string(ThemeDB.fallback_font, r.position + Vector2(0, r.size.y * 0.5 + 5), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, Color.WHITE)


func _edge_arrow(sp: Vector2, label: String, c: Color, vs: Vector2) -> void:
	var margin := 34.0
	var inner := Rect2(Vector2(margin, margin + 70), vs - Vector2(margin * 2, margin * 2 + 130))
	if inner.has_point(sp):
		return
	var centre := vs * 0.5
	var dir := (sp - centre).normalized()
	var p := Vector2(clampf(sp.x, inner.position.x, inner.end.x), clampf(sp.y, inner.position.y, inner.end.y))
	var tip := p + dir * 18.0
	var side := dir.orthogonal() * 12.0
	hud.draw_colored_polygon(PackedVector2Array([tip, p - dir * 6.0 + side, p - dir * 6.0 - side]), c)
	hud.draw_polyline(PackedVector2Array([tip, p - dir * 6.0 + side, p - dir * 6.0 - side, tip]), Color(0.1, 0.05, 0.1), 2.0)
	hud.draw_string_outline(ThemeDB.fallback_font, p - dir * 26.0 + Vector2(-50, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 100, 13, 4, Color(0.1, 0.05, 0.1))
	hud.draw_string(ThemeDB.fallback_font, p - dir * 26.0 + Vector2(-50, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 100, 13, c.lightened(0.3))
