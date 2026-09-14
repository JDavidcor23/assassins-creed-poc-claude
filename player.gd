# PROTOTYPE - NOT FOR PRODUCTION
# Asesino: modelo de Meshy rigueado en Mixamo + clips de Mixamo.
class_name ProtoPlayer
extends CharacterBody3D

const WALK_SPEED := 1.45
# El clip agachado avanza 1.25 m/s natural (techo 2.26). A 1.25 se reproduce a
# 1.0x — exacto — y agacharse deja de ser una condena: antes, a 0.92, el guardia
# terminaba la ronda antes de que pudieras llegarle.
const CROUCH_SPEED := 1.25
# El trote existe porque caminar tiene techo: el clip de caminata avanza
# ~0.96 m/s y estirarlo mas alla de rig.STRETCH_MAX hace patinar los pies.
# Trotar no es "caminar mas rapido", es otro clip con otra postura.
# Medido: el clip de trote avanza 2.59 m/s natural, techo 4.67 m/s. A 3.9 se
# reproduce a 1.5x — rapido de verdad y todavia lejos de patinar.
const JOG_SPEED := 3.9
const ACCEL := 9.0
const JOG_ACCEL := 7.0
const DECEL := 12.0

# Costo de sigilo: multiplica la distancia a la que el guardia te ve.
# Agachado te acerca mas, trotar te delata antes. Sin este costo el trote
# seria gratis y no volverias a caminar nunca — y esperar la ventana es
# justo lo que el prototipo quiere medir.
# 0.85 y no 0.65: agacharse NO te hace invisible en campo abierto. Su trabajo
# real es bajarte los ojos a 0.7 m para que troncos y rocas te tapen — eso ya lo
# hace el raycast. A 0.65 el guardia te miraba de frente a 5.5 m y no te
# registraba, y eso no se lo cree nadie.
const STEALTH_CROUCH := 0.85
const STEALTH_WALK := 1.0
const STEALTH_JOG := 1.35

# Radio en metros al que el guardia TE OYE. El oído no tiene cono: por eso
# trotar pegado a su espalda lo alerta.
#
# Estos tres números le dan un ROL a cada modo, que es lo que faltaba:
#  - agachado  (0.9 m): por debajo de BACKSTAB_RANGE (1.6) -> llegás a rango de
#              ejecución sin que te oiga NUNCA. Lento, pero seguro.
#  - caminando (2.2 m): quedan 0.6 m para cruzar oyéndote; a +0.50 m/s son 1.2 s
#              contra un límite de 1.5 s. Llegás, pero JUSTO. Esa es la tensión.
#  - trotando  (8.0 m): cruzar tarda 2.2 s contra 1.5 s -> te delata siempre.
#              Sirve para reposicionarte lejos o para escapar, no para matar.
const NOISE_CROUCH := 0.9
# 3.0 y no 2.2: tiene que ser MAYOR que BACKSTAB_RANGE (2.4), si no caminando
# llegás a rango antes de entrar en su oído y agacharse deja de servir otra vez.
const NOISE_WALK := 3.0
const NOISE_JOG := 8.0
const MOUSE_SENS := 0.0025
# Sensibilidad de la palanca derecha, en radianes por segundo a tope.
const PAD_SENS := 3.0
# El pitch se mueve más lento que el yaw: su recorrido útil es mucho más corto.
const PAD_PITCH_SCALE := 0.55
const PITCH_MIN := -1.15
const PITCH_MAX := 0.12
const FACE_TURN_SPEED := 11.0
const EYE_STANDING := 1.45
const EYE_CROUCHED := 0.7

# Altura del hueso de la cabeza en metros. El asesino viene ~92x chico del
# pipeline Meshy -> Mixamo; el rig lo reescala midiendo este hueso.
const BODY_HEIGHT := 1.82
# Si el modelo mira al reves, esto pasa a PI.
const MODEL_YAW_OFFSET := PI

const CAM_LAG := 7.0
const CAM_DIST := 4.4
const CAM_DIST_CROUCH := 3.4
const CAM_PIVOT_Y := 1.74
const CAM_PIVOT_Y_CROUCH := 1.22
const FOV_BASE := 68.0
const FOV_MOVE := 73.0

# Hoja oculta, en metros. El antebrazo mide 0.251 m: la hoja arranca a media
# caña y la punta termina ~9 cm más allá de la muñeca.
const BLADE_LENGTH := 0.28
const BLADE_WIDTH := 0.020
const BLADE_THICK := 0.042
const BLADE_OFFSET_Y := 0.205
const BLADE_OFFSET_Z := -0.028

const STEP_DIST := 0.82
const STEP_DIST_JOG := 1.15
const STEP_DB_JOG := 3.0
const FOV_JOG := 82.0

var frozen := false
var crouching := false
var jogging := false
var cam: Camera3D
var audio: ProtoAudio
var rig: MixamoRig

var view_yaw := 0.0
var view_pitch := -0.16
var _pivot: Node3D
var arm: SpringArm3D
var _crouch_amount := 0.0
var _move_amount := 0.0
var _stabbing := false
var _step_accum := 0.0
var _blade: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4

	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)

	rig = MixamoRig.new()
	add_child(rig)
	var base := "res://assets/characters/asesino/mixamo/"
	rig.setup(base + "asesino_tpose.fbx", {
		"idle": base + "idle.fbx",
		"walk": base + "walking.fbx",
		"crouch_idle": base + "crouch_idle.fbx",
		"crouch_walk": base + "crouched_walking.fbx",
		"jog": base + "jog.fbx",
		"stab": base + "stab.fbx",
	}, ["idle", "walk", "crouch_idle", "crouch_walk", "jog"], BODY_HEIGHT)
	rig.rotation.y = MODEL_YAW_OFFSET
	rig.play_state("idle", 0.0)
	_attach_blade()

	_pivot = Node3D.new()
	_pivot.top_level = true
	add_child(_pivot)
	_pivot.global_position = global_position + Vector3(0.0, CAM_PIVOT_Y, 0.0)
	_pivot.rotation = Vector3(view_pitch, view_yaw, 0.0)

	arm = SpringArm3D.new()
	arm.spring_length = CAM_DIST
	arm.margin = 0.5
	arm.collision_mask = 1
	arm.add_excluded_object(get_rid())
	arm.position = Vector3(0.62, 0.12, 0.0)
	_pivot.add_child(arm)

	cam = Camera3D.new()
	cam.fov = FOV_BASE
	cam.current = true
	arm.add_child(cam)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# La hoja oculta va montada en el ANTEBRAZO, no en la mano: sale por debajo de
# la muñeca y la punta pasa los nudillos. Esa es la silueta de Assassin's Creed
# y es lo que la distingue de "un tipo con un cuchillo".
#
# Medido: el antebrazo mide 0.251 m y su hueso corre a lo largo de +Y local
# (hacia la mano). La hoja se extiende sobre ese mismo eje.
func _attach_blade() -> void:
	if rig.skeleton == null:
		return
	# El antebrazo PRIMERO. Antes se buscaba la mano primero y el rig de Mixamo
	# siempre la tiene, así que el fallback al antebrazo no corría nunca.
	var idx := rig.skeleton.find_bone("mixamorig_RightForeArm")
	if idx < 0:
		idx = rig.skeleton.find_bone("mixamorig_RightHand")
	if idx < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = idx
	rig.skeleton.add_child(att)

	# Prisma en vez de caja: se afila hacia +Y y lee como hoja, no como barra.
	var mesh := PrismMesh.new()
	mesh.size = Vector3(BLADE_WIDTH, BLADE_LENGTH, BLADE_THICK)
	_blade = MeshInstance3D.new()
	_blade.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.80, 0.81, 0.84)
	m.metallic = 0.95
	m.roughness = 0.18
	_blade.material_override = m
	_blade.visible = false

	# EL BUG QUE LA MANDABA A 15 METROS: el BoneAttachment vive en el espacio
	# del esqueleto, donde el antebrazo entero mide 0.00262. La escala del mesh
	# se compensaba con 1/s, pero la POSICIÓN no — así que -0.16 no eran 16 cm,
	# eran 61 antebrazos. Hay que dividir la posición por la misma escala.
	var s := rig.model.scale.x if rig.model != null else 1.0
	if s > 0.0001:
		_blade.scale = Vector3.ONE / s
		_blade.position = Vector3(0.0, BLADE_OFFSET_Y, BLADE_OFFSET_Z) / s
	else:
		_blade.position = Vector3(0.0, BLADE_OFFSET_Y, BLADE_OFFSET_Z)
	att.add_child(_blade)


func eye_height() -> float:
	return lerpf(EYE_STANDING, EYE_CROUCHED, _crouch_amount)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		view_yaw -= motion.relative.x * MOUSE_SENS
		view_pitch = clampf(view_pitch - motion.relative.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed(&"crouch") and not frozen:
		crouching = not crouching
	# Escape ya no alterna el mouse: lo toma el menu de pausa en main.gd, que
	# libera y recaptura el cursor por su cuenta.


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var target := Vector3.ZERO
	# Trotar se mantiene apretado, no se togglea: soltar y volver a caminar
	# tiene que ser inmediato cuando ves al guardia darse vuelta.
	jogging = not frozen and Input.is_action_pressed(&"jog")
	if not frozen:
		var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		var dir := (Basis(Vector3.UP, view_yaw) * Vector3(input.x, 0.0, input.y)).normalized()
		target = dir * current_speed()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := DECEL
	if target.length_squared() > 0.001:
		# Arrancar a trotar pesa mas que arrancar a caminar: el cuerpo tiene
		# que vencer su propia inercia antes de lanzarse.
		rate = JOG_ACCEL if is_jogging() else ACCEL
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()

	if horizontal.length_squared() > 0.05 and not _stabbing:
		var target_yaw := atan2(-horizontal.x, -horizontal.z) + MODEL_YAW_OFFSET
		rig.rotation.y = lerp_angle(rig.rotation.y, target_yaw, minf(1.0, FACE_TURN_SPEED * delta))


func _process(delta: float) -> void:
	_update_pad_look(delta)
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	_move_amount = lerpf(_move_amount, clampf(horizontal_speed / WALK_SPEED, 0.0, 1.0), minf(1.0, 10.0 * delta))
	_crouch_amount = lerpf(_crouch_amount, 1.0 if crouching else 0.0, minf(1.0, 8.0 * delta))

	_update_animation(horizontal_speed)
	_update_steps(horizontal_speed, delta)
	_update_camera(delta, horizontal_speed)


# Trotar pedido por input. Agachado no se trota: son intenciones opuestas.
func is_jogging() -> bool:
	return jogging and not crouching and not frozen


func has_jog_clip() -> bool:
	return rig != null and rig.has_clip("jog")


func current_speed() -> float:
	if crouching:
		return CROUCH_SPEED
	if not is_jogging():
		return WALK_SPEED
	if has_jog_clip():
		return JOG_SPEED
	# Sin jog.fbx todavia: en vez de patinar, el trote se limita a lo maximo
	# que la caminata puede sostener. Se siente corto, pero no miente.
	return maxf(WALK_SPEED, rig.max_world_speed("walk") if rig != null else WALK_SPEED)


# Multiplicador de la distancia a la que el guardia te ve. Se calcula sobre la
# velocidad REAL, no sobre la tecla: quedarte quieto con Shift no te delata, y
# el costo entra de a poco mientras acelerás.
func stealth_factor() -> float:
	if crouching:
		return STEALTH_CROUCH
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed <= WALK_SPEED + 0.15:
		return STEALTH_WALK
	var t := clampf((speed - WALK_SPEED) / maxf(JOG_SPEED - WALK_SPEED, 0.01), 0.0, 1.0)
	return lerpf(STEALTH_WALK, STEALTH_JOG, t)


# Cuánto ruido hacés, en metros. Quieto no suena; agachado casi nada; trotando
# se oye a 9 m. Sin ángulo y sin línea de vista: el sonido no necesita que te
# miren, y ese era justo el agujero — correr detrás del guardia era gratis.
func noise_radius() -> float:
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed < 0.25 or frozen:
		return 0.0
	if crouching:
		return NOISE_CROUCH
	var t := clampf((speed - WALK_SPEED) / maxf(JOG_SPEED - WALK_SPEED, 0.01), 0.0, 1.0)
	return lerpf(NOISE_WALK, NOISE_JOG, t)


# Cámara con la palanca derecha. El mouse manda deltas por evento; un stick da
# una POSICIÓN sostenida, así que hay que integrarlo por frame o no se mueve.
func _update_pad_look(delta: float) -> void:
	if frozen:
		return
	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look.length_squared() < 0.0001:
		return
	# Curva cuadrática: precisión cerca del centro, velocidad en el borde.
	# Lineal se siente resbaloso para apuntar y lento para girar.
	var curva := look * look.length()
	view_yaw -= curva.x * PAD_SENS * delta
	view_pitch = clampf(view_pitch - curva.y * PAD_SENS * delta * PAD_PITCH_SCALE,
		PITCH_MIN, PITCH_MAX)


func _update_animation(speed: float) -> void:
	if _stabbing:
		return
	var moving := speed > 0.25
	if crouching:
		if moving:
			rig.play_state("crouch_walk", 0.2, rig.speed_for("crouch_walk", speed))
		else:
			rig.play_state("crouch_idle", 0.25, 1.0)
	elif not moving:
		rig.play_state("idle", 0.3, 1.0)
	elif speed > WALK_SPEED + 0.2 and has_jog_clip():
		# Blend mas corto que el de caminar: lanzarse a trotar es un cambio
		# de intencion, no una transicion suave.
		rig.play_state("jog", 0.18, rig.speed_for("jog", speed))
	else:
		rig.play_state("walk", 0.2, rig.speed_for("walk", speed))


func _update_steps(speed: float, delta: float) -> void:
	if speed < 0.3 or audio == null:
		return
	_step_accum += speed * delta
	# La zancada se alarga al trotar. Con la zancada de caminata, 3.2 m/s
	# dispararia casi 4 pasos por segundo: suena a ametralladora, no a alguien
	# corriendo.
	var t := clampf((speed - WALK_SPEED) / maxf(JOG_SPEED - WALK_SPEED, 0.01), 0.0, 1.0)
	var stride := STEP_DIST if crouching else lerpf(STEP_DIST, STEP_DIST_JOG, t)
	if _step_accum < stride:
		return
	_step_accum = 0.0
	var db := -8.0 if crouching else lerpf(-2.0, STEP_DB_JOG, t)
	audio.step(global_position, true, db)


func _update_camera(delta: float, speed: float) -> void:
	var pivot_y := lerpf(CAM_PIVOT_Y, CAM_PIVOT_Y_CROUCH, _crouch_amount)
	var want := global_position + Vector3(0.0, pivot_y, 0.0)
	# Lag de camara: la camara persigue, no va pegada. Es lo que da peso.
	_pivot.global_position = _pivot.global_position.lerp(want, minf(1.0, CAM_LAG * delta))
	_pivot.rotation = Vector3(view_pitch, view_yaw, 0.0)
	arm.spring_length = lerpf(CAM_DIST, CAM_DIST_CROUCH, _crouch_amount)
	if not _stabbing:
		var want_fov := lerpf(FOV_BASE, FOV_MOVE, _move_amount)
		# El FOV se sigue abriendo pasando la velocidad de caminata: es el
		# aviso visual de que dejaste de ser sigiloso.
		var extra := clampf((speed - WALK_SPEED) / maxf(JOG_SPEED - WALK_SPEED, 0.01), 0.0, 1.0)
		want_fov = lerpf(want_fov, FOV_JOG, extra)
		cam.fov = lerpf(cam.fov, want_fov, minf(1.0, 4.0 * delta))


func snap_camera() -> void:
	_pivot.global_position = global_position + Vector3(0.0, CAM_PIVOT_Y, 0.0)


func blade_position() -> Vector3:
	if _blade != null and _blade.is_inside_tree():
		return _blade.global_position
	return global_position + Vector3(0.0, 1.2, 0.0)


func show_blade(visible_now: bool) -> void:
	if _blade != null:
		_blade.visible = visible_now


func play_stab(windup_real_time: float) -> void:
	_stabbing = true
	show_blade(true)
	if audio != null:
		audio.play_at(audio.desenfunda, global_position + Vector3(0.0, 1.2, 0.0), -4.0)
	# El clip de Mixamo dura ~2.6 s; lo estiramos para cubrir el windup en
	# camara lenta y despues corre a velocidad normal.
	var total := rig.clip_length("stab")
	var speed := 1.0
	if total > 0.0:
		speed = clampf(total / maxf(windup_real_time * 3.0, 0.2), 0.6, 2.0)
	rig.play_once("stab", 0.06, speed)


func end_stab() -> void:
	_stabbing = false
	show_blade(false)
	rig.play_state("idle", 0.3, 1.0)


func face_toward(target: Vector3) -> void:
	var d := target - global_position
	rig.rotation.y = atan2(-d.x, -d.z) + MODEL_YAW_OFFSET
