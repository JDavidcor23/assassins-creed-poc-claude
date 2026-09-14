# PROTOTYPE - NOT FOR PRODUCTION
# Carga un personaje de Mixamo (T-pose con piel) y le pega los clips descargados
# aparte, todos dentro de un unico AnimationPlayer.
#
# Por que esto funciona sin BoneMap ni SkeletonProfileHumanoid: los clips se
# bajaron de Mixamo PARA este personaje, asi que los tracks ya apuntan a
# "Skeleton3D:mixamorig_*", exactamente el mismo path que tiene el T-pose.
# Verificado con probe.gd el 2026-09-13.
class_name MixamoRig
extends Node3D

const HEAD_BONE := "mixamorig_Head"
const HIPS_BONE := "mixamorig_Hips"

var anim: AnimationPlayer
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var model: Node3D

var _current := ""
# Velocidad real de avance de cada clip, en m/s. Medida del desplazamiento de
# cadera ANTES de anularlo. Con esto los pies no patinan a ninguna velocidad.
var ground_speed: Dictionary = {}


# clips: { "idle": "res://.../idle.fbx", ... }
# in_place: nombres de clips a los que hay que anular el desplazamiento de cadera
# target_head_y: altura deseada del hueso de la cabeza, en metros
func setup(tpose_path: String, clips: Dictionary, in_place: Array[String], target_head_y: float) -> void:
	var packed := load(tpose_path) as PackedScene
	if packed == null:
		push_error("MixamoRig: no pude cargar " + tpose_path)
		return
	model = packed.instantiate() as Node3D
	add_child(model)

	var skels := model.find_children("*", "Skeleton3D", true, false)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if skels.is_empty() or players.is_empty():
		push_error("MixamoRig: el FBX no trae Skeleton3D o AnimationPlayer")
		return
	skeleton = skels[0] as Skeleton3D
	mesh = (meshes[0] as MeshInstance3D) if not meshes.is_empty() else null
	anim = players[0] as AnimationPlayer

	_normalize_scale(target_head_y)

	var lib := anim.get_animation_library("")
	if lib == null:
		lib = AnimationLibrary.new()
		anim.add_animation_library("", lib)
	# El clip que viene dentro del T-pose no sirve (0.03 s o basura "Take 001").
	for junk: StringName in lib.get_animation_list():
		lib.remove_animation(junk)

	for clip_name: String in clips.keys():
		var path := String(clips[clip_name])
		# Un clip que todavia no se bajo es un estado esperado, no un error:
		# quien lo pide consulta has_clip() y degrada. Fallar ruidoso aca
		# llenaba la consola de rojo por un archivo opcional.
		if not ResourceLoader.exists(path):
			print("MixamoRig: falta el clip '", clip_name, "' (", path, ") — se omite")
			continue
		var a := _load_clip(path)
		if a == null:
			push_error("MixamoRig: no pude extraer animacion de " + path)
			continue
		_normalize_clip_units(a, clip_name)
		if in_place.has(clip_name):
			ground_speed[clip_name] = _strip_horizontal_root_motion(a)
		a.loop_mode = Animation.LOOP_LINEAR if in_place.has(clip_name) else Animation.LOOP_NONE
		lib.add_animation(StringName(clip_name), a)


# Mixamo/Meshy exporta con unidades inconsistentes: el asesino venia ~92x mas
# chico que el guardia. Medimos la ALTURA REAL DE LA MALLA (un hecho fisico) en
# vez de un hueso, y escalamos para que los dos midan lo mismo.
func _normalize_scale(target_height: float) -> void:
	if target_height <= 0.0 or mesh == null or mesh.mesh == null or model == null:
		return
	var h := mesh.mesh.get_aabb().size.y
	if h < 0.000001:
		return
	model.scale = Vector3.ONE * (target_height / h)


# Altura del personaje en metros, ya escalado. Para verificar, no para adivinar.
func model_height() -> float:
	if mesh == null or mesh.mesh == null or model == null:
		return 0.0
	return mesh.mesh.get_aabb().size.y * model.scale.y


func _load_clip(path: String) -> Animation:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var players := inst.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		inst.free()
		return null
	var ap := players[0] as AnimationPlayer
	var names := ap.get_animation_list()
	var best: Animation = null
	# Todos los clips de Mixamo se llaman "mixamo_com" adentro del FBX; el T-pose
	# del guardia ademas trae un "Take 001". Nos quedamos con el mas largo.
	for n: StringName in names:
		var a := ap.get_animation(n)
		if best == null or a.length > best.length:
			best = a
	var copy: Animation = best.duplicate(true) if best != null else null
	inst.free()
	return copy


# Un clip bajado de Mixamo con OTRO personaje viene en las unidades de ESE
# personaje. El asesino sale del pipeline Meshy ~93x mas chico que un Mixamo
# estandar: medido, la cadera de su walking.fbx esta a 0.010 y la de un clip de
# libreria a 0.932. Sin normalizar, la cadera aterriza 93x mas arriba y el
# modelo sale volando; ademas _strip_horizontal_root_motion devuelve una
# velocidad absurda (239 m/s).
# Se compara la altura inicial de la cadera contra el rest pose del esqueleto
# destino y se reescalan todas las claves. Un clip del propio personaje da
# factor ~1.0 y no se toca.
func _normalize_clip_units(a: Animation, clip_name: String) -> void:
	# El rest pose NO sirve de referencia: medido, la cadera del asesino tiene
	# rest.origin.y = 0.000028 (casi el origen). Mixamo no guarda la pose en el
	# rest, la guarda en la animacion. La referencia buena es la altura de la
	# MALLA en unidades locales: la cadera de un humano cae a ~0.53 de su
	# altura, y eso se cumple venga el clip del personaje que venga.
	if mesh == null or mesh.mesh == null:
		return
	var altura_local := mesh.mesh.get_aabb().size.y
	if altura_local <= 0.000001:
		return
	var cadera_esperada := altura_local * HIP_HEIGHT_RATIO
	for t: int in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if not String(a.track_get_path(t)).ends_with(":" + HIPS_BONE):
			continue
		var count := a.track_get_key_count(t)
		if count < 1:
			return
		var first: Vector3 = a.track_get_key_value(t, 0)
		if absf(first.y) <= 0.000001:
			return
		var factor := cadera_esperada / first.y
		# Solo se corrige un desajuste GRUESO de unidades (el caso real es 93x).
		# Dentro de esta banda el clip es del propio personaje y no se toca:
		# reescalar por diferencias anatomicas chicas rompe mas de lo que arregla.
		if factor > UNIT_FIX_MIN and factor < UNIT_FIX_MAX:
			return
		for k: int in count:
			a.track_set_key_value(t, k, (a.track_get_key_value(t, k) as Vector3) * factor)
		print("MixamoRig: '", clip_name, "' venia en otra escala, normalizado x%.5f" % factor)
		return


# Convierte una animacion con desplazamiento de raiz en una "in place":
# congela X/Z de la cadera en su valor inicial y deja Y (el rebote del paso).
# Devuelve la velocidad de avance que TENIA el clip, en m/s ya escalados.
func _strip_horizontal_root_motion(a: Animation) -> float:
	var scale_factor := model.scale.y if model != null else 1.0
	for t: int in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var p := String(a.track_get_path(t))
		if not p.ends_with(":" + HIPS_BONE):
			continue
		var count := a.track_get_key_count(t)
		if count < 2:
			return 0.0
		var first: Vector3 = a.track_get_key_value(t, 0)
		var last: Vector3 = a.track_get_key_value(t, count - 1)
		var travelled := Vector2(last.x - first.x, last.z - first.z).length() * scale_factor
		for k: int in count:
			var v: Vector3 = a.track_get_key_value(t, k)
			a.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))
		if a.length <= 0.001:
			return 0.0
		return travelled / a.length
	return 0.0


# Cuanto se puede estirar un clip antes de que el paso deje de vender el avance.
# Mas alla de esto los pies patinan: el personaje cubre menos metros de los que
# recorre. Es el techo real de cada clip, no un gusto.
const STRETCH_MIN := 0.5
const STRETCH_MAX := 1.8

# Proporcion humana: la cadera cae a ~0.53 de la altura total. Se usa para
# detectar un clip que viene en las unidades de OTRO personaje.
const HIP_HEIGHT_RATIO := 0.53
# Banda de "esta bien": fuera de esto hay un desajuste grueso de unidades.
const UNIT_FIX_MIN := 0.5
const UNIT_FIX_MAX := 2.0


# Velocidad de reproduccion para que el paso coincida con el avance real.
func speed_for(clip_name: String, world_speed: float) -> float:
	var natural: float = ground_speed.get(clip_name, 0.0)
	if natural <= 0.05:
		return 1.0
	return clampf(world_speed / natural, STRETCH_MIN, STRETCH_MAX)


# Velocidad maxima que este clip puede sostener sin patinar. 0.0 si el clip
# no existe o no tiene avance medible (un idle, por ejemplo).
func max_world_speed(clip_name: String) -> float:
	return ground_speed.get(clip_name, 0.0) * STRETCH_MAX


func has_clip(clip_name: String) -> bool:
	return anim != null and anim.has_animation(clip_name)


func play_state(clip_name: String, blend: float = 0.22, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation(clip_name):
		return
	anim.speed_scale = speed
	if _current == clip_name:
		return
	_current = clip_name
	anim.play(clip_name, blend)


func play_once(clip_name: String, blend: float = 0.10, speed: float = 1.0) -> void:
	if anim == null or not anim.has_animation(clip_name):
		return
	_current = clip_name
	anim.speed_scale = speed
	anim.play(clip_name, blend)


func set_speed(speed: float) -> void:
	if anim != null:
		anim.speed_scale = speed


func clip_length(clip_name: String) -> float:
	if anim == null or not anim.has_animation(clip_name):
		return 0.0
	return anim.get_animation(clip_name).length


func tint(color: Color) -> void:
	if mesh == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mesh.material_override = m


# Multiplica la textura original por un color en vez de taparla. Conserva todo
# el detalle del atlas y solo desplaza el tono: es la unica forma de recolorear
# un personaje que trae UNA sola superficie y UN solo material.
func tint_albedo(color: Color) -> void:
	if mesh == null or mesh.mesh == null:
		return
	for s: int in mesh.mesh.get_surface_count():
		var src := mesh.get_active_material(s)
		var m: StandardMaterial3D
		if src is StandardMaterial3D:
			m = (src as StandardMaterial3D).duplicate() as StandardMaterial3D
		else:
			m = StandardMaterial3D.new()
		m.albedo_color = color
		mesh.set_surface_override_material(s, m)


# Devuelve la posicion global de un hueso (para colgar la hoja, la sangre, etc).
func bone_global_position(bone_name: String) -> Vector3:
	if skeleton == null:
		return global_position
	var i := skeleton.find_bone(bone_name)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
