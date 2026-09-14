# PROTOTYPE - NOT FOR PRODUCTION
# Question: Does approaching a patrolling guard from behind and executing him feel tense and satisfying?
# Date: 2026-09-13
extends Node3D

const PLAYER_START := Vector3(0.0, 0.1, 12.0)
const PATROL: Array[Vector3] = [
	Vector3(-5.0, 0.0, -5.0),
	Vector3(5.0, 0.0, -5.0),
	Vector3(5.0, 0.0, 5.0),
	Vector3(-5.0, 0.0, 5.0),
]
const WINDUP_TIME := 0.35
const WINDUP_TIME_SCALE := 0.15
const SHAKE_TIME := 0.25
const SHAKE_STRENGTH := 0.12
const HITSTOP_TIME := 0.055
const ORBIT_RAD := 1.15
# Distancia en pixeles del hexagono al centro de la pantalla.
const HEX_ORBIT := 105.0
# Cuánto queda el subtítulo antes de desvanecerse.
const SUB_HOLD := 1.9
# Zona muerta de las palancas. Un stick gastado manda ruido y el personaje
# camina solo si esto queda en cero.
const STICK_DEADZONE := 0.22

const GROUND := Color(0.2, 0.28, 0.16)
const DIRT := Color(0.3, 0.24, 0.16)
const MOSS := Color(0.17, 0.25, 0.14)
const BARK := Color(0.26, 0.19, 0.12)
const LOG := Color(0.3, 0.22, 0.14)
const ROCK := Color(0.42, 0.42, 0.4)
const CANOPY: Array[Color] = [
	Color(0.2, 0.34, 0.18),
	Color(0.26, 0.38, 0.2),
	Color(0.18, 0.3, 0.17),
	Color(0.3, 0.4, 0.22),
]
const BUSH: Array[Color] = [
	Color(0.22, 0.36, 0.2),
	Color(0.28, 0.4, 0.22),
]
# Paja seca: se distingue del follaje verde para que el escondite se lea de
# lejos. Si no, corrés hacia un arbusto cualquiera y no pasa nada.
const STRAW: Array[Color] = [
	Color(0.62, 0.55, 0.26),
	Color(0.70, 0.62, 0.30),
	Color(0.54, 0.48, 0.22),
]
const THICKET_R := 1.45
const THICKET_H := 1.9

var _player: ProtoPlayer
var _guard: ProtoGuard
var _audio: ProtoAudio
var _prompt: Label
var _banner: Label
var _vignette: ColorRect
var _menu: Control
var _vol_value: Label
var _hex: DetectionHex
var _hint: Label
# Posiciones de los pastizales: se usan SOLO para avisar "agachate aca".
var _hideouts: Array[Vector3] = []
var _subs: Label
var _subs_tween: Tween
# Pantalla "click to play" (solo web). Null en escritorio.
var _gate: Control
# 0 = LIMPIO (sin cartel de controles) — el default, para grabar
# 1 = COMPLETO (con cartel) — para jugar y depurar
# 2 = CINE (nada de HUD ni conos de visión) — captura pura
var _hud_mode := 0
var _can_execute := false
var _done := false
var _shake_left := 0.0


func _ready() -> void:
	Engine.time_scale = 1.0
	# Con el arbol pausado, los nodos PAUSABLE dejan de recibir input: sin esto
	# se abre el menu y no hay forma de cerrarlo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_audio = ProtoAudio.new()
	add_child(_audio)
	_build_world()
	_spawn_player()
	_spawn_guard()
	_build_ui()
	_maybe_autoshot()


func _setup_input() -> void:
	_add_key(&"move_forward", KEY_W)
	_add_key(&"move_back", KEY_S)
	_add_key(&"move_left", KEY_A)
	_add_key(&"move_right", KEY_D)
	_add_key(&"execute", KEY_E)
	_add_key(&"restart", KEY_R)
	_add_key(&"crouch", KEY_CTRL)
	_add_key(&"crouch", KEY_C)
	_add_key(&"pause", KEY_ESCAPE)
	_add_key(&"jog", KEY_SHIFT)
	_add_key(&"hud", KEY_H)

	# --- Mando (layout Xbox) -------------------------------------------------
	# Palanca izquierda: mover. Palanca derecha: cámara. RT: trotar.
	# B agacharse, X ejecutar, Start menú, View reiniciar.
	_add_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis(&"move_back", JOY_AXIS_LEFT_Y, 1.0)

	_add_axis(&"look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_axis(&"look_down", JOY_AXIS_RIGHT_Y, 1.0)

	# RT es un eje analógico, no un botón: se dispara pasando el umbral.
	_add_axis(&"jog", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_pad(&"crouch", JOY_BUTTON_B)
	_add_pad(&"execute", JOY_BUTTON_X)
	_add_pad(&"pause", JOY_BUTTON_START)
	_add_pad(&"restart", JOY_BUTTON_BACK)
	_add_pad(&"hud", JOY_BUTTON_RIGHT_STICK)


func _add_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and (existing as InputEventKey).physical_keycode == key:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _add_pad(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton \
				and (existing as InputEventJoypadButton).button_index == button:
			return
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# Eje analógico como acción. El valor (-1 / +1) elige la mitad del recorrido:
# un stick da un solo eje para dos direcciones opuestas.
func _add_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# Zona muerta: sin esto un stick gastado camina solo.
	InputMap.action_set_deadzone(action, STICK_DEADZONE)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadMotion:
			var m := existing as InputEventJoypadMotion
			if m.axis == axis and signf(m.axis_value) == signf(value):
				return
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


# El renderer Compatibility (OpenGL/WebGL) no crea RenderingDevice: ésa es la
# forma confiable de detectarlo en runtime, sin leer ProjectSettings ni adivinar
# por plataforma.
func _compatibility() -> bool:
	# En headless NO hay GPU, así que get_rendering_device() siempre da null y
	# la detección diría "navegador" aunque estemos en Forward+. Sin ventana no
	# hay nada que degradar: los tests deben ver la config real.
	if DisplayServer.get_name() == "headless":
		return false
	return RenderingServer.get_rendering_device() == null


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m


func _build_world() -> void:
	_build_ground()

	_add_patch(Vector3(0.0, 0.0, 0.0), 6.5, DIRT)
	_add_patch(Vector3(-7.0, 0.0, 7.0), 3.0, MOSS)
	_add_patch(Vector3(6.0, 0.0, -8.0), 3.5, MOSS)
	_add_patch(Vector3(2.0, 0.0, 11.0), 2.5, DIRT)

	_add_log(Vector3(0.0, 0.0, -1.0), 0.0, 2.4)
	_add_log(Vector3(-2.5, 0.0, -8.5), 0.2, 3.2)
	_add_log(Vector3(8.0, 0.0, 0.5), PI * 0.5, 3.0)
	_add_log(Vector3(2.0, 0.0, 8.5), -0.15, 2.8)
	# Matorrales: los escondites. Repartidos lejos uno del otro para que elegir
	# a cuál corrés sea una decisión y no un reflejo.
	_add_thicket(Vector3(-6.0, 0.0, 6.5))
	_add_thicket(Vector3(7.0, 0.0, -6.0))
	_add_thicket(Vector3(-1.5, 0.0, -9.5))
	_add_rock(Vector3(-8.5, 0.0, 1.5), 1.3)
	_add_rock(Vector3(-7.6, 0.0, 2.6), 0.9)
	_add_rock(Vector3(6.5, 0.0, 5.5), 0.8)

	_add_bush(Vector3(-3.0, 0.0, 3.0), 1.0)
	_add_bush(Vector3(3.0, 0.0, -3.0), 1.0)
	_add_bush(Vector3(-6.5, 0.0, -2.0), 1.1)
	_add_bush(Vector3(6.5, 0.0, -2.5), 0.9)
	_add_bush(Vector3(-1.5, 0.0, 6.5), 1.1)
	_add_bush(Vector3(4.5, 0.0, 2.0), 0.9)
	_add_bush(Vector3(-4.5, 0.0, -6.5), 1.0)
	_add_bush(Vector3(0.5, 0.0, -6.0), 0.9)
	_add_bush(Vector3(-2.5, 0.0, 10.5), 1.0)
	_add_bush(Vector3(4.0, 0.0, 10.0), 0.9)

	_add_tree(Vector3(-4.0, 0.0, 9.5), 1.0)
	_add_tree(Vector3(6.0, 0.0, 8.0), 1.1)
	_add_tree(Vector3(8.5, 0.0, -7.5), 1.2)
	_add_tree(Vector3(-8.0, 0.0, -4.5), 1.0)
	_add_tree(Vector3(3.0, 0.0, -9.0), 0.9)
	_add_tree(Vector3(-9.5, 0.0, 6.5), 1.1)

	var ring := 18
	for i: int in ring:
		var a := TAU * float(i) / float(ring)
		var r := 14.5 + 2.5 * sin(float(i) * 2.3)
		_add_tree(Vector3(cos(a) * r, 0.0, sin(a) * r), 1.1 + 0.3 * sin(float(i) * 1.7))
	var ring2 := 14
	for i: int in ring2:
		var a := TAU * float(i) / float(ring2) + 0.2
		var r := 19.0 + 1.5 * cos(float(i) * 1.9)
		_add_tree(Vector3(cos(a) * r, 0.0, sin(a) * r), 1.3 + 0.2 * cos(float(i) * 2.1))
	for i: int in ring:
		var a := TAU * float(i) / float(ring) + 0.1
		var r := 12.0 + 1.0 * sin(float(i) * 3.1)
		_add_bush(Vector3(cos(a) * r, 0.0, sin(a) * r), 0.9 + 0.3 * cos(float(i) * 1.3))

	# Hora dorada: sol bajo y calido, sombras largas. Es lo que mas cambia la
	# imagen y no cuesta un solo asset.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, 47.0, 0.0)
	sun.light_color = Color(1.0, 0.83, 0.62)
	sun.light_energy = 3.4
	sun.light_angular_distance = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.27, 0.4, 0.55)
	sky_mat.sky_horizon_color = Color(0.78, 0.66, 0.48)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.12)
	sky_mat.ground_horizon_color = Color(0.6, 0.52, 0.4)
	sky_mat.sun_angle_max = 12.0
	sky_mat.energy_multiplier = 1.6
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 2.4

	# Tonemap cinematografico. En 4.7 el glow procesa ANTES del tonemap, asi que
	# la intensidad va baja o quema la imagen (ver docs/engine-reference).
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.55
	env.tonemap_white = 3.0

	# SSAO y niebla volumétrica NO existen en gl_compatibility (el único renderer
	# del navegador). En vez de dejar que se ignoren en silencio y perder la
	# atmósfera entera, se detecta y se COMPENSA: más niebla de profundidad —que
	# sí funciona— y más glow para no quedarse con una imagen plana.
	var rico := not _compatibility()

	env.ssao_enabled = rico
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.2
	env.ssao_power = 1.6

	env.glow_enabled = true
	env.glow_intensity = 0.35 if rico else 0.55
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.62, 0.56, 0.42)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.0
	# Sin niebla volumétrica la profundidad se aplana: la de profundidad arranca
	# antes y cierra más cerca para recuperar las capas entre los árboles.
	env.fog_depth_begin = 22.0 if rico else 14.0
	env.fog_depth_end = 58.0 if rico else 46.0
	env.fog_depth_curve = 1.4

	env.volumetric_fog_enabled = rico
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.72, 0.66, 0.52)
	env.volumetric_fog_emission = Color(0.05, 0.045, 0.035)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_gi_inject = 0.6

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	_add_dust()


# Polvo flotando en la luz. Es de las cosas mas baratas que existen y es la que
# hace que el mundo deje de parecer una foto fija.
func _add_dust() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.94, 0.8, 0.5)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true

	var quad := QuadMesh.new()
	quad.size = Vector2(0.035, 0.035)
	quad.material = mat

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16.0, 3.2, 16.0)
	pm.direction = Vector3(0.4, 0.1, 0.2)
	pm.spread = 55.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3(0.0, -0.012, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.color = Color(1.0, 0.95, 0.82, 0.45)

	var p := GPUParticles3D.new()
	p.amount = 420
	p.lifetime = 9.0
	p.preprocess = 6.0
	p.draw_pass_1 = quad
	p.process_material = pm
	p.position = Vector3(0.0, 2.6, 0.0)
	p.visibility_aabb = AABB(Vector3(-20.0, -4.0, -20.0), Vector3(40.0, 12.0, 40.0))
	add_child(p)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(60.0, 1.0, 60.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -0.5
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	mesh.mesh = plane
	mesh.material_override = _mat(GROUND)
	body.add_child(mesh)
	add_child(body)


func _add_patch(pos: Vector3, radius: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos + Vector3(0.0, 0.01, 0.0)
	mi.material_override = _mat(color)
	add_child(mi)


# Matorral de paja alto: el escondite. En una selva esto es lo que hay — un
# banco de plaza no existe acá y rompía la ambientación entera.
# Capa 8 como los demás arbustos: corta la línea de vista pero se puede
# atravesar caminando, así que te zambullís adentro.
func _add_thicket(pos: Vector3) -> void:
	var raiz := Node3D.new()
	raiz.position = pos
	add_child(raiz)

	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = Vector3(0.0, THICKET_H * 0.5, 0.0)
	var shape := SphereShape3D.new()
	shape.radius = THICKET_R
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	raiz.add_child(body)

	# Matas de paja: conos altos y finos, amarillentos, en dos anillos.
	_hideouts.append(pos)
	var seed := int(absf(pos.x) * 31.0 + absf(pos.z) * 17.0)
	for i: int in 16:
		var a := TAU * float(i) / 16.0 + float(seed % 7) * 0.2
		var anillo := THICKET_R * (0.35 if i % 2 == 0 else 0.78)
		var alto := THICKET_H * (0.82 + 0.28 * fmod(float(seed + i * 13) * 0.137, 1.0))
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = THICKET_R * 0.30
		mesh.height = alto
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _mat(STRAW[i % STRAW.size()])
		mi.position = Vector3(cos(a) * anillo, alto * 0.5, sin(a) * anillo)
		# Las matas se abren hacia afuera: un cono recto lee como carpa.
		mi.rotation = Vector3(sin(a) * 0.2, 0.0, -cos(a) * 0.2)
		raiz.add_child(mi)



func _add_log(pos: Vector3, yaw: float, length: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos + Vector3(0.0, 0.55, 0.0)
	body.rotation.y = yaw
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = length
	var col := CollisionShape3D.new()
	col.shape = shape
	col.rotation.z = PI * 0.5
	body.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.58
	mesh.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.rotation.z = PI * 0.5
	mi.material_override = _mat(LOG)
	body.add_child(mi)
	add_child(body)


func _add_rock(pos: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos + Vector3(0.0, radius * 0.45, 0.0)
	var shape := SphereShape3D.new()
	shape.radius = radius * 0.9
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3(1.0, 0.65, 1.2)
	mi.rotation.y = pos.x * 0.7
	mi.material_override = _mat(ROCK)
	body.add_child(mi)
	add_child(body)


func _add_bush(pos: Vector3, radius: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = pos + Vector3(0.0, radius * 0.6, 0.0)
	var shape := SphereShape3D.new()
	shape.radius = radius
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(radius * 0.55, -radius * 0.15, radius * 0.35),
		Vector3(-radius * 0.5, -radius * 0.2, -radius * 0.35),
	]
	for i: int in offsets.size():
		var mesh := CylinderMesh.new()
		var r := radius * (1.05 - 0.2 * float(i))
		mesh.top_radius = 0.0
		mesh.bottom_radius = r
		mesh.height = r * 1.6
		mesh.radial_segments = 6
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = offsets[i] + Vector3(0.0, r * 0.8 - radius * 0.6, 0.0)
		mi.rotation.y = float(i) * 0.9 + pos.z * 0.3
		mi.material_override = _mat(BUSH[i % BUSH.size()])
		body.add_child(mi)
	add_child(body)


func _add_tree(pos: Vector3, scale_factor: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	var trunk_h := 5.0 * scale_factor
	var shape := CylinderShape3D.new()
	shape.radius = 0.4 * scale_factor
	shape.height = trunk_h
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = trunk_h * 0.5
	body.add_child(col)

	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.26 * scale_factor
	trunk.bottom_radius = 0.5 * scale_factor
	trunk.height = trunk_h
	trunk.radial_segments = 7
	var trunk_mi := MeshInstance3D.new()
	trunk_mi.mesh = trunk
	trunk_mi.position.y = trunk_h * 0.5
	trunk_mi.material_override = _mat(BARK)
	body.add_child(trunk_mi)

	var seed_v := int(absf(pos.x * 7.0 + pos.z * 13.0))
	var tiers := 3
	var base_y := trunk_h * 0.55
	for i: int in tiers:
		var mesh := CylinderMesh.new()
		var r := (2.4 - 0.55 * float(i)) * scale_factor
		var h := (2.2 - 0.3 * float(i)) * scale_factor
		mesh.top_radius = 0.0
		mesh.bottom_radius = r
		mesh.height = h
		mesh.radial_segments = 7
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position.y = base_y + h * 0.5 + float(i) * h * 0.55
		mi.rotation.y = float(seed_v + i) * 0.7
		mi.material_override = _mat(CANOPY[(seed_v + i) % CANOPY.size()])
		body.add_child(mi)
	add_child(body)


func _spawn_player() -> void:
	_player = ProtoPlayer.new()
	_player.position = PLAYER_START
	_player.audio = _audio
	add_child(_player)
	_player.snap_camera()


func _spawn_guard() -> void:
	_guard = ProtoGuard.new()
	_guard.waypoints = PATROL.duplicate()
	_guard.position = PATROL[0]
	_guard.player = _player
	_guard.audio = _audio
	_guard.player_spotted.connect(_on_player_spotted)
	_guard.alerted.connect(_on_alerted)
	_guard.calmed.connect(_on_calmed)
	_guard.suspicion_changed.connect(_on_suspicion_changed)
	_guard.backstab_zone_changed.connect(_on_backstab_zone_changed)
	add_child(_guard)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_vignette = ColorRect.new()
	_vignette.color = Color(0.7, 0.0, 0.0, 0.0)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_vignette)

	_hint = Label.new()
	var hint := _hint
	hint.text = "KEYBOARD   WASD move  |  Mouse look  |  Shift jog  |  Ctrl/C crouch  |  E assassinate  |  R restart  |  Esc menu  |  H HUD
GAMEPAD    Left stick move  |  Right stick camera  |  RT jog  |  B crouch  |  X assassinate  |  View restart  |  Menu pause
Jogging gives you away. If spotted, crouch inside the tall grass — it breaks his line of sight"
	hint.add_theme_font_size_override("font_size", 15)
	hint.modulate = Color(1.0, 1.0, 1.0, 0.45)
	hint.position = Vector2(16.0, 12.0)
	layer.add_child(hint)

	_prompt = Label.new()
	_prompt.text = "[ E ]  ASSASSINATE"
	_prompt.add_theme_font_size_override("font_size", 32)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -200.0
	_prompt.offset_right = 200.0
	_prompt.offset_top = -120.0
	_prompt.offset_bottom = -70.0
	_prompt.visible = false
	layer.add_child(_prompt)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 64)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -400.0
	_banner.offset_right = 400.0
	_banner.offset_top = -100.0
	_banner.offset_bottom = 100.0
	_banner.visible = false
	layer.add_child(_banner)

	_hex = DetectionHex.new()
	_hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hex.visible = false
	layer.add_child(_hex)

	# Subtítulos: el guardia habla en castellano peninsular contra el criollo del
	# jugador. Eso es narrativa, no decoración — y sin traducir se pierde.
	_subs = Label.new()
	_subs.add_theme_font_size_override("font_size", 26)
	_subs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subs.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subs.offset_left = -500.0
	_subs.offset_right = 500.0
	_subs.offset_top = -62.0
	_subs.offset_bottom = -20.0
	_subs.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_subs.add_theme_constant_override("outline_size", 6)
	_subs.modulate.a = 0.0
	layer.add_child(_subs)
	if _audio != null:
		_audio.said.connect(_on_said)

	_build_menu(layer)
	_build_start_gate(layer)
	_apply_hud_mode()


# Puerta de entrada SOLO EN WEB. El navegador bloquea dos cosas hasta que el
# usuario hace un gesto:
#   - el audio (politica de autoplay: si no, cada pagina te gritaria al abrirla)
#   - los mandos (la Gamepad API los esconde hasta que se aprieta un boton,
#     porque un mando identifica tu equipo y sirve para rastrear)
# Sin esta pantalla el juego PARECE roto: no suena y el mando no responde.
# En escritorio no hace falta y solo estorbaria.
func _build_start_gate(layer: CanvasLayer) -> void:
	# `-- --gate` fuerza la pantalla en escritorio para poder MIRARLA sin tener
	# que desplegar. Sin esto, la unica forma de ver como quedo era subirla.
	if not OS.has_feature("web") and not OS.get_cmdline_user_args().has("--gate"):
		return

	_gate = Control.new()
	_gate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gate.process_mode = Node.PROCESS_MODE_ALWAYS
	_gate.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_gate)

	var fondo := ColorRect.new()
	fondo.color = Color(0.05, 0.04, 0.03, 0.92)
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gate.add_child(fondo)

	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate.add_child(centro)

	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 22)
	caja.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centro.add_child(caja)

	# El aviso va ARRIBA del titulo: tiene que leerse antes que nada. Solo
	# aparece en web, que es el link publico — la version de escritorio queda
	# limpia para mostrarla en persona.
	var aviso_ia := Label.new()
	aviso_ia.text = "BUILT WITH CLAUDE CODE"
	aviso_ia.add_theme_font_size_override("font_size", 40)
	aviso_ia.add_theme_color_override("font_color", Color(0.96, 0.94, 0.90))
	aviso_ia.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(aviso_ia)

	var aviso_ia2 := Label.new()
	aviso_ia2.text = "An experiment — not a product, and not a replacement for game developers."
	aviso_ia2.add_theme_font_size_override("font_size", 21)
	aviso_ia2.add_theme_color_override("font_color", Color(0.90, 0.72, 0.20))
	aviso_ia2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(aviso_ia2)

	var linea := ColorRect.new()
	linea.color = Color(0.45, 0.40, 0.32, 0.8)
	linea.custom_minimum_size = Vector2(0.0, 2.0)
	caja.add_child(linea)

	var titulo := Label.new()
	titulo.text = "RUANA Y PÓLVORA"
	titulo.add_theme_font_size_override("font_size", 40)
	titulo.add_theme_color_override("font_color", Color(0.90, 0.72, 0.20))
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(titulo)

	var sub := Label.new()
	sub.text = "a stealth prototype"
	sub.add_theme_font_size_override("font_size", 19)
	sub.add_theme_color_override("font_color", Color(0.72, 0.68, 0.60))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(sub)

	var jugar := Button.new()
	jugar.text = "  CLICK TO PLAY  "
	jugar.add_theme_font_size_override("font_size", 30)
	jugar.custom_minimum_size = Vector2(0.0, 62.0)
	jugar.pressed.connect(_open_gate)
	caja.add_child(jugar)

	var aviso := Label.new()
	aviso.text = "Sound starts after you click — your browser blocks audio until then.
Using a gamepad? Press any button once the game starts."
	aviso.add_theme_font_size_override("font_size", 16)
	aviso.add_theme_color_override("font_color", Color(0.66, 0.62, 0.55))
	aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caja.add_child(aviso)

	# El mundo queda congelado hasta el clic: si no, el guardia patrulla (y te
	# detecta) mientras el jugador todavia esta leyendo la pantalla.
	get_tree().paused = true


func _open_gate() -> void:
	if _gate == null:
		return
	_gate.queue_free()
	_gate = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_said(texto: String) -> void:
	if _subs == null or _hud_mode == 2:
		return
	_subs.text = texto
	if _subs_tween != null and _subs_tween.is_valid():
		_subs_tween.kill()
	_subs.modulate.a = 1.0
	_subs_tween = create_tween()
	_subs_tween.tween_interval(SUB_HOLD)
	_subs_tween.tween_property(_subs, "modulate:a", 0.0, 0.45)


# Tres niveles de HUD. No se borra nada: se apaga. Grabás limpio y volvés a
# tener los controles con una tecla.
func _apply_hud_mode() -> void:
	var completo := _hud_mode == 1
	var cine := _hud_mode == 2
	if _hint != null:
		_hint.visible = completo
	if _hex != null and cine:
		_hex.visible = false
	if _vignette != null:
		_vignette.visible = not cine
	if _guard != null:
		_guard.show_cones(not cine)
	if cine:
		_prompt.visible = false
		_banner.visible = false


func _cycle_hud() -> void:
	_hud_mode = (_hud_mode + 1) % 3
	_apply_hud_mode()


# El hexagono orbita el centro de la pantalla apuntando al guardia: decirte
# CUANTO te detectan sin decirte DE DONDE es la mitad de la informacion.
func _update_hex() -> void:
	if _hex == null or _player == null or _guard == null or _player.cam == null:
		return
	if not _hex.visible:
		return
	var centro := get_viewport().get_visible_rect().size * 0.5
	var blanco := _guard.global_position + Vector3(0.0, 1.2, 0.0)
	var cam := _player.cam
	var plano := cam.unproject_position(blanco) - centro
	# Detras de la camara unproject espeja el punto: hay que invertirlo o el
	# indicador apunta justo al lado opuesto del guardia.
	if cam.is_position_behind(blanco):
		plano = -plano
	if plano.length() < 1.0:
		plano = Vector2.UP
	_hex.position = centro + plano.normalized() * HEX_ORBIT


# El menu vive en PROCESS_MODE_ALWAYS: tiene que responder con el arbol pausado.
func _build_menu(layer: CanvasLayer) -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu.visible = false
	layer.add_child(_menu)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(360.0, 0.0)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)

	var vol_label := Label.new()
	vol_label.text = "Volume"
	vol_label.add_theme_font_size_override("font_size", 20)
	row.add_child(vol_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	# El bus Master sobrevive al reload_current_scene: el slider lee el valor
	# real en vez de resetear a tope en cada reinicio.
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(_on_volume_changed)
	row.add_child(slider)

	_vol_value = Label.new()
	_vol_value.add_theme_font_size_override("font_size", 20)
	_vol_value.custom_minimum_size = Vector2(56.0, 0.0)
	_vol_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_vol_value)

	_menu_button(box, "RESUME", _close_menu)
	_menu_button(box, "RESTART", _restart)
	_menu_button(box, "QUIT", _quit)

	_on_volume_changed(slider.value)


func _menu_button(box: VBoxContainer, text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(0.0, 44.0)
	b.pressed.connect(handler)
	box.add_child(b)


func _on_volume_changed(value: float) -> void:
	# Master (bus 0), NUNCA Mundo: ProtoAudio reescribe Mundo en cada frame
	# para el ducking y se comeria el valor del slider.
	# -80 dB en vez de set_bus_mute: es silencio igual, y asi db_to_linear
	# devuelve el mismo valor al reconstruir el slider tras un reinicio.
	AudioServer.set_bus_volume_db(0, -80.0 if value <= 0.001 else linear_to_db(value))
	if _vol_value != null:
		_vol_value.text = "%d%%" % roundi(value * 100.0)


func _quit() -> void:
	get_tree().quit()


func _toggle_menu() -> void:
	var opening := not _menu.visible
	_menu.visible = opening
	get_tree().paused = opening
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if opening else Input.MOUSE_MODE_CAPTURED


func _close_menu() -> void:
	if _menu.visible:
		_toggle_menu()


func _restart() -> void:
	# Despausar ANTES del reload: la escena nueva hereda el arbol pausado.
	# Y resetear time_scale, si no reiniciar durante el slow-mo de la ejecucion
	# arranca la partida en camara lenta.
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	# Antes del early-return del shake: el hexagono tiene que seguir al guardia
	# todos los frames, no solo cuando la camara tiembla.
	_update_hex()
	_update_prompt()
	if _shake_left <= 0.0:
		return
	_shake_left -= delta
	var cam := _player.cam
	if _shake_left <= 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		return
	var k := _shake_left / SHAKE_TIME * SHAKE_STRENGTH
	cam.h_offset = randf_range(-k, k)
	cam.v_offset = randf_range(-k, k)


func _unhandled_input(event: InputEvent) -> void:
	# Con la puerta abierta nada mas responde: el menu de pausa encima de la
	# pantalla de inicio deja el arbol pausado de una forma que no se puede
	# deshacer.
	if _gate != null:
		return
	if event.is_action_pressed(&"pause"):
		_toggle_menu()
	elif event.is_action_pressed(&"restart"):
		_restart()
	elif event.is_action_pressed(&"hud"):
		_cycle_hud()
	elif event.is_action_pressed(&"execute") and _can_execute and not _done:
		# main es PROCESS_MODE_ALWAYS y sigue recibiendo input pausado:
		# sin este guard se puede ejecutar al guardia desde el menu.
		if not _menu.visible:
			_execute()


# Esconderse no tiene boton: te metes en un matorral y te agachas. El follaje
# ya corta la linea de vista (capa 8) y agachado los ojos bajan a 0.7 m, asi
# que la fisica hace el trabajo. Una mecanica menos que explicar.
func _update_prompt() -> void:
	if _player == null or _done or _hud_mode == 2:
		if _prompt != null:
			_prompt.visible = false
		return

	# Matar gana sobre esconderse: si tenes al guardia a tiro, esa es LA decision.
	if _can_execute:
		_prompt.text = "[ E ]  ASSASSINATE"
		_prompt.visible = true
		return

	# Dentro del pastizal y de pie: avisar que agacharse te oculta. Un escondite
	# que no se anuncia no existe para el jugador.
	if not _player.crouching and _dentro_del_pastizal():
		_prompt.text = "[ C ]  CROUCH TO HIDE"
		_prompt.visible = true
		return

	_prompt.visible = false


func _dentro_del_pastizal() -> bool:
	for h: Vector3 in _hideouts:
		var d := Vector2(_player.global_position.x - h.x, _player.global_position.z - h.z)
		if d.length() <= THICKET_R + 0.3:
			return true
	return false


func _on_suspicion_changed(ratio: float) -> void:
	_vignette.color.a = ratio * 0.35
	if _hex != null:
		_hex.ratio = ratio
		# Solo aparece cuando algo esta pasando: un HUD siempre encendido deja
		# de comunicar.
		_hex.visible = ratio > 0.01 and not _done and _hud_mode != 2
	if _audio != null:
		_audio.set_suspicion(ratio)


func _on_backstab_zone_changed(inside: bool) -> void:
	# Escondido no se ejecuta: estás sentado.
	_can_execute = inside and not _done
	# La visibilidad del prompt la decide _update_hideout(), que es el único que
	# conoce las tres opciones (ejecutar / esconderse / salir) y su prioridad.


# Te vio: NO perdiste. Te senala, grita y sale a buscarte. Podes romper la
# linea de vista, esconderte en un arbusto y volver a intentarlo.
# (Pilar 1: ser descubierto ENCARECE el asesinato, no lo anula.)
func _on_alerted() -> void:
	if _done:
		return
	_flash("SPOTTED!
find cover", Color(1.0, 0.55, 0.15), 1.5)


func _on_calmed() -> void:
	if _done:
		return
	_flash("you lost him", Color(0.85, 0.85, 0.78), 1.2)


func _flash(text: String, color: Color, seconds: float) -> void:
	_banner.text = text
	_banner.modulate = color
	_banner.visible = true
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)
	await tw.finished
	if not _done:
		_banner.visible = false
		_banner.modulate.a = 1.0


# Esto SI es perder: te agarro.
func _on_player_spotted() -> void:
	if _done:
		return
	_done = true
	_can_execute = false
	_prompt.visible = false
	_player.frozen = true
	_vignette.color.a = 0.5
	_banner.modulate = Color(0.95, 0.12, 0.12)
	_banner.modulate.a = 1.0
	_banner.text = "CAUGHT"
	_banner.visible = true
	await get_tree().create_timer(1.4).timeout
	get_tree().reload_current_scene()


func _execute() -> void:
	_done = true
	_can_execute = false
	_prompt.visible = false
	_player.frozen = true
	_guard.frozen = true

	var cam := _player.cam

	# --- TIEMPO 1: el mundo se apaga y todo se frena -----------------------
	if _audio != null:
		_audio.duck_world(1.0)
	_player.crouching = false
	_player.face_toward(_guard.global_position)
	_player.play_stab(WINDUP_TIME)
	Engine.time_scale = WINDUP_TIME_SCALE

	var anchor := _guard.backstab_anchor()
	anchor.y = _player.global_position.y

	var windup := create_tween()
	windup.set_ignore_time_scale(true)
	windup.set_parallel(true)
	windup.tween_property(_player, "global_position", anchor, WINDUP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# La camara orbita hacia el frente del guardia: dejas de ver una espalda y
	# pasas a ver una ejecucion.
	windup.tween_property(_player, "view_yaw", _player.view_yaw + ORBIT_RAD, WINDUP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	windup.tween_property(_player, "view_pitch", -0.14, WINDUP_TIME).set_trans(Tween.TRANS_SINE)
	windup.tween_property(_player.arm, "spring_length", 2.4, WINDUP_TIME).set_trans(Tween.TRANS_SINE)
	windup.tween_property(cam, "fov", 52.0, WINDUP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(WINDUP_TIME, true, false, true).timeout

	# --- TIEMPO 2: el impacto ---------------------------------------------
	if _audio != null:
		_audio.play_at(_audio.impacto, _guard.chest_position(), 4.0)
	_guard.die()
	cam.fov = 44.0
	_shake_left = SHAKE_TIME

	# Hit-stop: unos frames congelados. Es lo que hace que el golpe se sienta.
	Engine.time_scale = 0.04
	await get_tree().create_timer(HITSTOP_TIME, true, false, true).timeout
	Engine.time_scale = 1.0

	var punch := create_tween()
	punch.set_parallel(true)
	punch.tween_property(cam, "fov", ProtoPlayer.FOV_BASE, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	punch.tween_property(_player.arm, "spring_length", ProtoPlayer.CAM_DIST, 0.8).set_trans(Tween.TRANS_SINE)

	# --- TIEMPO 3: un segundo de silencio, y recien ahi vuelve el mundo ----
	await get_tree().create_timer(0.9).timeout
	_player.end_stab()
	if _audio != null:
		var back := create_tween()
		back.tween_method(_audio.duck_world, 1.0, 0.0, 1.6).set_trans(Tween.TRANS_SINE)
	_player.frozen = false
	_banner.text = "CLEAN KILL\nR to restart"
	_banner.modulate = Color(0.92, 0.86, 0.7)
	_banner.visible = true


# --- Modo captura ---------------------------------------------------------
# `godot --path . -- --shot [segundos] [carpeta]`
# Orbita al jugador, se acerca al guardia, guarda PNGs y cierra.
# Sirve para revisar el look sin depender de que alguien mire la pantalla.

func _maybe_autoshot() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--shot"):
		return
	var delay := 2.0
	var out_dir := OS.get_user_data_dir()
	var i := args.find("--shot")
	if i + 1 < args.size():
		delay = float(args[i + 1])
	if i + 2 < args.size():
		out_dir = args[i + 2]
	_autoshot(delay, out_dir)


func _autoshot(delay: float, out_dir: String) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().create_timer(delay).timeout
	print("ALTURA jugador=%.2f m  guardia=%.2f m" % [_player.rig.model_height(), _guard.rig.model_height()])
	print("ZANCADA jugador walk=%.2f m/s crouch=%.2f m/s  |  guardia walk=%.2f m/s" % [
		_player.rig.ground_speed.get("walk", 0.0),
		_player.rig.ground_speed.get("crouch_walk", 0.0),
		_guard.rig.ground_speed.get("walk", 0.0)])
	print("CLIPS guardia: ", _guard.rig.anim.get_animation_list())

	for i: int in 4:
		_player.view_yaw = TAU * float(i) / 4.0
		_player.snap_camera()
		await get_tree().create_timer(0.35).timeout
		await _shoot(out_dir, "player_%d" % (i * 90))

	_guard.frozen = true
	var gfwd := -_guard.global_transform.basis.z
	await _look_at_guard(gfwd * -3.6, out_dir, "guardia_espalda")
	await _look_at_guard(gfwd * 3.6, out_dir, "guardia_frente")

	get_tree().quit()


# Coloca al jugador en un offset alrededor del guardia y apunta la camara a el.
func _look_at_guard(offset: Vector3, out_dir: String, tag: String) -> void:
	_player.global_position = _guard.global_position + offset + Vector3(0.0, 0.1, 0.0)
	var d := (_guard.global_position - _player.global_position).normalized()
	_player.view_yaw = atan2(-d.x, -d.z)
	_player.view_pitch = -0.12
	_player.snap_camera()
	await get_tree().create_timer(0.5).timeout
	await _shoot(out_dir, tag)


func _shoot(out_dir: String, tag: String) -> void:
	for n: int in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("%s.png" % tag)
	print("SHOT ", path, " err=", img.save_png(path))
