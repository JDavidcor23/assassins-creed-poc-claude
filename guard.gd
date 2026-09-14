# PROTOTYPE - NOT FOR PRODUCTION
# Guardia realista: Castle Guard 01 (libreria gratis de Mixamo) + clips de Mixamo.
#
# PILAR 1 DEL DISENO: "ser descubierto ENCARECE el asesinato, no lo anula."
# Por eso que te vean NO es perder. Te senala, grita, y sale a buscarte. Podes
# romper la linea de vista, esconderte, y volver a intentarlo — contra un
# guardia que ahora mira para todos lados. Perder es que te AGARRE.
class_name ProtoGuard
extends Node3D

signal player_spotted          # te agarro -> perdiste
signal alerted                 # te vio -> ahora te busca
signal calmed                  # te perdio y volvio a la patrulla
signal suspicion_changed(ratio: float)
signal backstab_zone_changed(inside: bool)

# Patrulla, no marcha. A 1.25 iba EXACTAMENTE a la velocidad del jugador
# agachado: acercarse por detrás era imposible, no difícil. Y de paso su clip
# de caminata avanza 0.90 m/s natural, así que a 0.95 se reproduce a 1.06x —
# antes iba a 1.39x, acelerado y feo.
const MOVE_SPEED := 0.95
const HUNT_SPEED := 1.62
const TURN_TIME := 0.7
const LOOK_SWEEP_DEG := 70.0
const LOOK_SWEEP_TIME := 0.9
const LOOK_HOLD_TIME := 0.4

const VIEW_DIST := 8.0
const VIEW_HALF_ANGLE_DEG := 40.0
const HUNT_VIEW_DIST := 11.5
const HUNT_VIEW_HALF_ANGLE_DEG := 55.0
const VIEW_DIST_CROUCH_FACTOR := 0.65
# Radio en el que la vista NO se negocia: si estás en el cono y con línea de
# vista, te ve, estés agachado o quieto. Sin esto, agachado a 5.5 m de frente
# el guardia miraba a través tuyo.
const SURE_SIGHT_DIST := 6.0

const DETECT_TIME := 0.9
# Oir llena la sospecha mas lento que ver. Un ruido te delata, no te identifica.
const HEAR_RATE := 0.6
const SUSPICION_DECAY := 0.8
const SUSPICIOUS_TURN_SPEED := 3.0
const LINGER_TIME := 1.2

# Cuanto aguanta viendote antes de agarrarte. Esa es tu ventana para huir.
const CAUGHT_TIME := 2.2
const CAUGHT_RANGE := 1.8
const SEARCH_TIME := 5.5
const HUNT_TURN_SPEED := 4.5

# Se mide de CENTRO A CENTRO y cada cápsula tiene 0.35 m de radio: a 1.6 había
# que pegarse a 0.90 m de su espalda con el tipo caminando, y el área útil era
# de 2.68 m2. Ahora 2.4 m -> 1.70 m de separación real.
# El lunge del windup ya cubre la distancia (el tween a backstab_anchor), así
# que exigir que llegues pegado era pedir dos veces lo mismo.
const BACKSTAB_RANGE := 2.4
# 75 de semiángulo = arco de 150 grados. "Casi detrás" ahora cuenta; de frente y
# de costado puro, no — eso rompería la fantasía.
const BACKSTAB_HALF_ANGLE_DEG := 75.0
const EYE_HEIGHT := 1.6
const SIGHT_MASK := 1 | 2 | 8

const BODY_HEIGHT := 1.80
const MODEL_YAW_OFFSET := PI
const STEP_DIST := 0.85

# El usuario tenia razon: un guardia entero de rojo parece un juguete.
# La REGLA es "si algo es rojo, es peligro" — y el peligro es el CONO, no el
# hombre. El guardia conserva su textura; el unico rojo de la escena es su vision.
const COAT_TINT := Color(1.0, 0.97, 0.94)
const DEAD_TINT := Color(0.55, 0.5, 0.48)

enum State { LOOK, TURN, MOVE, SUSPICIOUS, LINGER, ALERT, HUNT, SEARCH }

var waypoints: Array[Vector3] = []
var player: ProtoPlayer
var frozen := false
var audio: ProtoAudio
var rig: MixamoRig

var _state := State.LOOK
var _target_index := 0
var _base_yaw := 0.0
var _look_t := 0.0
var _turn_from := 0.0
var _turn_to := 0.0
var _turn_t := 0.0
var _linger_left := 0.0
var _suspicion := 0.0
var _in_zone := false
var _cone_calm: MeshInstance3D
var _cone_hunt: MeshInstance3D
var _mat_calm: StandardMaterial3D
var _mat_hunt: StandardMaterial3D
var _body: StaticBody3D
var _moved_this_frame := 0.0
var _dying := false
var _step_accum := 0.0
var _murmur_cd := 6.0
var _was_suspicious := false

var _alert_left := 0.0
var _caught_t := 0.0
var _search_left := 0.0
var _last_known := Vector3.ZERO
var _hunting := false
var _cones_allowed := true


func _ready() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 4
	_body.collision_mask = 0
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	_body.add_child(col)
	add_child(_body)

	rig = MixamoRig.new()
	add_child(rig)
	var base := "res://assets/characters/realista/mixamo/"
	rig.setup(base + "realista_tpose.fbx", {
		"idle": base + "idle.fbx",
		"walk": base + "walking.fbx",
		"look": base + "looking_around.fbx",
		"alerta": base + "alerta.fbx",
		"die": base + "dying.fbx",
	}, ["idle", "walk", "look"], BODY_HEIGHT)
	rig.rotation.y = MODEL_YAW_OFFSET
	rig.tint_albedo(COAT_TINT)
	rig.play_state("idle", 0.0)

	_mat_calm = _cone_material(Color(0.9, 0.1, 0.1, 0.13))
	_mat_hunt = _cone_material(Color(1.0, 0.1, 0.05, 0.42))
	_cone_calm = _build_cone(VIEW_DIST, VIEW_HALF_ANGLE_DEG, _mat_calm)
	_cone_hunt = _build_cone(HUNT_VIEW_DIST, HUNT_VIEW_HALF_ANGLE_DEG, _mat_hunt)
	_cone_hunt.visible = false
	add_child(_cone_calm)
	add_child(_cone_hunt)

	if waypoints.size() >= 2:
		_base_yaw = _yaw_toward(waypoints[1] - position)
		rotation.y = _base_yaw
		_target_index = 0
		_look_t = 0.0


func _cone_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	return m


func _build_cone(dist: float, half_deg: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(half_deg)
	var segments := 28
	for i: int in segments:
		var a0 := -half + (2.0 * half) * float(i) / float(segments)
		var a1 := -half + (2.0 * half) * float(i + 1) / float(segments)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0), 0.0, -cos(a0)) * dist)
		st.add_vertex(Vector3(sin(a1), 0.0, -cos(a1)) * dist)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position.y = 0.05
	mi.material_override = mat
	return mi


func _yaw_toward(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


# Los conos de visión son una ayuda de lectura, no parte de la ficción: en modo
# cine se apagan para que la captura quede limpia.
func show_cones(on: bool) -> void:
	_cones_allowed = on
	if not on:
		_cone_calm.visible = false
		_cone_hunt.visible = false
	else:
		_cone_calm.visible = not _hunting and not _dying
		_cone_hunt.visible = _hunting and not _dying


func is_hunting() -> bool:
	return _hunting


func _physics_process(delta: float) -> void:
	_moved_this_frame = 0.0
	if frozen:
		return
	var can_see := _can_see_player()
	var can_hear := _can_hear_player()
	if _hunting:
		_update_hunt(can_see or can_hear, delta)
	else:
		_update_suspicion(can_see, can_hear, delta)
	if frozen:
		return
	_patrol(delta)
	_update_backstab_zone()


func _process(delta: float) -> void:
	if _dying:
		return
	var speed := _moved_this_frame / maxf(delta, 0.0001)
	_update_animation(speed)
	_update_steps(speed, delta)
	_update_murmur(delta)


func _update_animation(speed: float) -> void:
	match _state:
		State.ALERT:
			pass  # el clip de senalar se lanza una sola vez al entrar
		State.MOVE, State.HUNT:
			if speed > 0.1:
				rig.play_state("walk", 0.2, rig.speed_for("walk", speed))
			else:
				rig.play_state("idle", 0.3, 1.0)
		State.LINGER, State.SEARCH:
			# Aca SI puede mirar alrededor con el cuerpo: ya te perdio y el cono
			# no esta prometiendo nada. Durante LOOK el barrido lo maneja el
			# codigo, para que el cono nunca mienta sobre hacia donde mira.
			rig.play_state("look", 0.3, 1.0)
		_:
			rig.play_state("idle", 0.3, 1.0)


func _update_steps(speed: float, delta: float) -> void:
	if speed < 0.2 or audio == null:
		return
	_step_accum += speed * delta
	if _step_accum < STEP_DIST:
		return
	_step_accum = 0.0
	audio.step(global_position, true, 0.0 if _hunting else -3.0)


func _update_murmur(delta: float) -> void:
	if audio == null or _state != State.MOVE:
		return
	_murmur_cd -= delta
	if _murmur_cd <= 0.0:
		_murmur_cd = randf_range(14.0, 24.0)
		audio.speak(&"murmullo", global_position + Vector3(0.0, 1.6, 0.0), -10.0)


# --- Maquina de estados ---------------------------------------------------

func _patrol(delta: float) -> void:
	match _state:
		State.LOOK:
			_look_t += delta
			rotation.y = _base_yaw + deg_to_rad(LOOK_SWEEP_DEG) * _sweep_curve(_look_t)
			if _look_t >= _sweep_total():
				_target_index = (_target_index + 1) % waypoints.size()
				_begin_turn(_yaw_toward(waypoints[_target_index] - global_position))
		State.TURN:
			_turn_t += delta / TURN_TIME
			rotation.y = lerp_angle(_turn_from, _turn_to, minf(_turn_t, 1.0))
			if _turn_t >= 1.0:
				_state = State.MOVE
		State.MOVE:
			_walk_toward(waypoints[_target_index], MOVE_SPEED, delta, true)
		State.SUSPICIOUS:
			var to_player := player.global_position - global_position
			rotation.y = lerp_angle(rotation.y, _yaw_toward(to_player), minf(1.0, SUSPICIOUS_TURN_SPEED * delta))
			if _suspicion <= 0.0:
				_linger_left = LINGER_TIME
				_state = State.LINGER
		State.LINGER:
			_linger_left -= delta
			if _linger_left <= 0.0:
				_begin_turn(_yaw_toward(waypoints[_target_index] - global_position))
		State.ALERT:
			# Te esta senalando. Clavado en el lugar, mirandote a los ojos.
			var d := player.global_position - global_position
			rotation.y = lerp_angle(rotation.y, _yaw_toward(d), minf(1.0, HUNT_TURN_SPEED * delta))
			_alert_left -= delta
			if _alert_left <= 0.0:
				_state = State.HUNT
		State.HUNT:
			if _walk_toward(_last_known, HUNT_SPEED, delta, false):
				_search_left = SEARCH_TIME
				_state = State.SEARCH
		State.SEARCH:
			_search_left -= delta
			if _search_left <= 0.0:
				_calm_down()


func _walk_toward(target: Vector3, speed: float, delta: float, arrive_look: bool) -> bool:
	var to_target := target - global_position
	to_target.y = 0.0
	var step := speed * delta
	if to_target.length() <= step:
		_moved_this_frame = to_target.length()
		global_position = Vector3(target.x, global_position.y, target.z)
		if arrive_look:
			_base_yaw = rotation.y
			_look_t = 0.0
			_state = State.LOOK
		return true
	_moved_this_frame = step
	global_position += to_target.normalized() * step
	rotation.y = lerp_angle(rotation.y, _yaw_toward(to_target), minf(1.0, HUNT_TURN_SPEED * delta))
	return false


func _sweep_total() -> float:
	return LOOK_SWEEP_TIME * 2.0 + LOOK_HOLD_TIME * 2.0


func _sweep_curve(t: float) -> float:
	var s := LOOK_SWEEP_TIME
	var h := LOOK_HOLD_TIME
	if t < s:
		return sin((t / s) * PI * 0.5)
	if t < s + h:
		return 1.0
	if t < s + h + s:
		var u := (t - s - h) / s
		return cos(u * PI)
	return -1.0


func _begin_turn(to_yaw: float) -> void:
	_turn_from = rotation.y
	_turn_to = to_yaw
	_turn_t = 0.0
	_state = State.TURN


# --- Vision ---------------------------------------------------------------

func _can_see_player() -> bool:
	# Sentado en un banco sos uno más del paisaje. El guardia sigue yendo al
	# último lugar donde te vio, no te encuentra, busca y se calma — esa
	# máquina de estados ya existía (SEARCH -> _calm_down).
	if player == null:
		return false
	var forward := -global_transform.basis.z
	var eye := global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var target := player.global_position + Vector3(0.0, player.eye_height(), 0.0)
	var to_player := target - eye
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	var base_dist := HUNT_VIEW_DIST if _hunting else VIEW_DIST
	var half_deg := HUNT_VIEW_HALF_ANGLE_DEG if _hunting else VIEW_HALF_ANGLE_DEG
	# El jugador decide cuanto se expone: agachado 0.65x, caminando 1.0x,
	# trotando 1.35x. El factor sale de su velocidad real, no de la tecla.
	# Piso de visión: dentro de este radio, si estás en el cono y sin nada en el
	# medio, te ve — te agaches o no. El sigilo recorta la distancia a la que te
	# descubren, no te borra de delante de sus narices.
	var view_dist := maxf(base_dist * player.stealth_factor(), SURE_SIGHT_DIST)
	if flat.length() > view_dist or flat.length() <= 0.01:
		return false
	if forward.angle_to(flat.normalized()) > deg_to_rad(half_deg):
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target, SIGHT_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


# El oido NO tiene cono ni linea de vista: si hacés ruido lo suficientemente
# cerca, te escucha aunque esté de espaldas. Los arbustos tapan la vista, no el
# sonido.
func _can_hear_player() -> bool:
	if player == null or _dying:
		return false
	var radio := player.noise_radius()
	if radio <= 0.0:
		return false
	return global_position.distance_to(player.global_position) <= radio


func _update_suspicion(can_see: bool, can_hear: bool, delta: float) -> void:
	if can_see or can_hear:
		# Oir levanta sospecha mas lento que ver: un ruido te hace girar a
		# mirar, no te identifica.
		_suspicion = minf(_suspicion + delta * (1.0 if can_see else HEAR_RATE), DETECT_TIME)
		# Si te oye sin verte, se da vuelta hacia el ruido. Ahi te ve — o no.
		if not can_see:
			var hacia := _yaw_toward(player.global_position - global_position)
			rotation.y = lerp_angle(rotation.y, hacia, minf(1.0, SUSPICIOUS_TURN_SPEED * delta))
		if _state != State.SUSPICIOUS:
			_state = State.SUSPICIOUS
			if not _was_suspicious:
				_was_suspicious = true
				if audio != null:
					audio.speak(&"sospecha", global_position + Vector3(0.0, 1.6, 0.0), -2.0)
	else:
		_suspicion = maxf(_suspicion - delta * SUSPICION_DECAY, 0.0)
		if _suspicion <= 0.0:
			_was_suspicious = false

	var ratio := _suspicion / DETECT_TIME
	_mat_calm.albedo_color.a = lerpf(0.13, 0.6, ratio)
	suspicion_changed.emit(ratio)

	if _suspicion >= DETECT_TIME:
		_begin_alert()


# Te vio. NO perdiste: te senala, grita, y sale a buscarte.
func _begin_alert() -> void:
	_hunting = true
	_suspicion = DETECT_TIME
	_caught_t = 0.0
	_last_known = player.global_position
	_state = State.ALERT
	_cone_calm.visible = false
	_cone_hunt.visible = _cones_allowed
	rotation.y = _yaw_toward(player.global_position - global_position)
	_alert_left = maxf(rig.clip_length("alerta"), 0.8)
	rig.play_once("alerta", 0.08, 1.0)
	if audio != null:
		audio.speak(&"alerta", global_position + Vector3(0.0, 1.6, 0.0), 3.0)
	suspicion_changed.emit(1.0)
	alerted.emit()


func _update_hunt(can_see: bool, delta: float) -> void:
	if can_see:
		_last_known = player.global_position
		var close := global_position.distance_to(player.global_position) <= CAUGHT_RANGE
		_caught_t += delta * (2.0 if close else 1.0)
		if _state == State.SEARCH:
			_state = State.HUNT
		if _caught_t >= CAUGHT_TIME:
			frozen = true
			player_spotted.emit()
			return
	else:
		_caught_t = maxf(_caught_t - delta * 0.7, 0.0)
	_mat_hunt.albedo_color.a = lerpf(0.42, 0.78, clampf(_caught_t / CAUGHT_TIME, 0.0, 1.0))
	suspicion_changed.emit(clampf(0.55 + 0.45 * (_caught_t / CAUGHT_TIME), 0.0, 1.0))


func _calm_down() -> void:
	_hunting = false
	_caught_t = 0.0
	_suspicion = 0.0
	_was_suspicious = false
	_cone_hunt.visible = false
	_cone_calm.visible = _cones_allowed
	_mat_calm.albedo_color.a = 0.13
	suspicion_changed.emit(0.0)
	_target_index = _nearest_waypoint()
	_begin_turn(_yaw_toward(waypoints[_target_index] - global_position))
	calmed.emit()


func _nearest_waypoint() -> int:
	var best := 0
	var best_d := INF
	for i: int in waypoints.size():
		var d := global_position.distance_squared_to(waypoints[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func _update_backstab_zone() -> void:
	var forward := -global_transform.basis.z
	var rel := player.global_position - global_position
	rel.y = 0.0
	var behind := forward.dot(rel.normalized()) < -cos(deg_to_rad(BACKSTAB_HALF_ANGLE_DEG))
	var inside := rel.length() <= BACKSTAB_RANGE and behind
	if inside != _in_zone:
		_in_zone = inside
		backstab_zone_changed.emit(inside)


func backstab_anchor() -> Vector3:
	var forward := -global_transform.basis.z
	return global_position + forward * -0.95


func chest_position() -> Vector3:
	return global_position + Vector3(0.0, 1.25, 0.0)


func die() -> void:
	frozen = true
	_dying = true
	_hunting = false
	_cone_calm.visible = false
	_cone_hunt.visible = false
	_body.collision_layer = 0
	if _in_zone:
		_in_zone = false
		backstab_zone_changed.emit(false)
	suspicion_changed.emit(0.0)
	rig.tint_albedo(DEAD_TINT)
	rig.play_once("die", 0.05, 1.0)
	if audio != null:
		audio.speak(&"muerte", global_position + Vector3(0.0, 1.5, 0.0), -1.0)
		await get_tree().create_timer(0.45).timeout
		audio.play_at(audio.cuerpo_cae, global_position, 0.0)
