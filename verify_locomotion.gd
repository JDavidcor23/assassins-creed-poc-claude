# PROTOTYPE - NOT FOR PRODUCTION
# Verifica la locomocion: velocidades por estado, costo de sigilo, y el
# invariante que importa — ningun estado puede pedir mas velocidad de la que
# su clip de animacion puede sostener sin que los pies patinen.
extends SceneTree

var _fails := 0


func _init() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		print("!! no se pudo cargar main.tscn")
		quit(1)
		return

	var m := packed.instantiate()
	root.add_child(m)
	current_scene = m
	await process_frame
	await process_frame

	var p := m.get("_player") as ProtoPlayer
	if p == null:
		print("!! no hay player")
		quit(1)
		return
	var rig := p.rig
	var hay_jog := p.has_jog_clip()

	print("=== clips disponibles")
	for clip: String in ["idle", "walk", "crouch_walk", "jog", "stab"]:
		var nat := rig.ground_speed.get(clip, 0.0) as float
		var techo := rig.max_world_speed(clip)
		if rig.has_clip(clip):
			print("  OK    %-12s natural=%5.2f m/s  techo=%5.2f m/s" % [clip, nat, techo])
		else:
			print("  FALTA %-12s" % clip)

	print("=== input")
	_check("la accion jog existe", InputMap.has_action(&"jog"))

	print("=== velocidad por estado")
	p.frozen = false
	p.crouching = false
	p.jogging = false
	_eq("caminar", p.current_speed(), ProtoPlayer.WALK_SPEED)
	p.crouching = true
	_eq("agachado", p.current_speed(), ProtoPlayer.CROUCH_SPEED)
	p.crouching = false
	p.jogging = true
	if hay_jog:
		_eq("trotar", p.current_speed(), ProtoPlayer.JOG_SPEED)
	else:
		var techo_walk := rig.max_world_speed("walk")
		_check("sin clip, el trote cae al techo de la caminata (%.2f m/s)" % p.current_speed(),
			absf(p.current_speed() - techo_walk) < 0.01)

	print("=== intenciones opuestas")
	p.crouching = true
	p.jogging = true
	_check("agachado no trota", not p.is_jogging())
	p.crouching = false
	p.frozen = true
	_check("congelado no trota", not p.is_jogging())
	p.frozen = false

	print("=== costo de sigilo (sale de la velocidad real, no de la tecla)")
	p.crouching = true
	p.jogging = false
	_eq("agachado", p.stealth_factor(), ProtoPlayer.STEALTH_CROUCH)
	p.crouching = false
	p.velocity = Vector3.ZERO
	_eq("quieto", p.stealth_factor(), ProtoPlayer.STEALTH_WALK)
	p.velocity = Vector3(ProtoPlayer.WALK_SPEED, 0.0, 0.0)
	_eq("caminando", p.stealth_factor(), ProtoPlayer.STEALTH_WALK)
	p.velocity = Vector3(ProtoPlayer.JOG_SPEED, 0.0, 0.0)
	_eq("trotando", p.stealth_factor(), ProtoPlayer.STEALTH_JOG)
	# El caso que se escapa si el factor sale de la tecla en vez de la velocidad.
	p.jogging = true
	p.velocity = Vector3.ZERO
	_eq("quieto con Shift apretado NO delata", p.stealth_factor(), ProtoPlayer.STEALTH_WALK)
	p.jogging = false
	# Y a mitad de aceleracion el costo tiene que ser intermedio, no un escalon.
	p.velocity = Vector3((ProtoPlayer.WALK_SPEED + ProtoPlayer.JOG_SPEED) * 0.5, 0.0, 0.0)
	var medio := p.stealth_factor()
	_check("a media aceleracion el costo es intermedio (%.3f)" % medio,
		medio > ProtoPlayer.STEALTH_WALK and medio < ProtoPlayer.STEALTH_JOG)

	print("=== INVARIANTE: ningun estado patina")
	_no_patina(rig, "walk", ProtoPlayer.WALK_SPEED)
	_no_patina(rig, "crouch_walk", ProtoPlayer.CROUCH_SPEED)
	if hay_jog:
		_no_patina(rig, "jog", ProtoPlayer.JOG_SPEED)
	else:
		print("  PEND  jog: falta jog.fbx — bajar 'Jog Forward' de Mixamo sin In Place")

	print("=== hoja oculta (se escapó a 15 m por un bug de escala)")
	p.show_blade(true)
	await process_frame
	var hoja := p.get("_blade") as MeshInstance3D
	_check("la hoja existe", hoja != null)
	if hoja != null:
		var mano := rig.bone_global_position("mixamorig_RightHand")
		var d := hoja.global_position.distance_to(mano)
		# El BoneAttachment vive en unidades de esqueleto: si alguien escribe la
		# posición en metros sin dividir por la escala, la hoja sale volando.
		_check("la hoja está en la muñeca, no en órbita (%.3f m de la mano)" % d, d < 0.25)
		var largo := (hoja.get_aabb().size * hoja.global_basis.get_scale()).y
		_check("mide como una hoja, no como una espada (%.2f m)" % largo,
			largo > 0.15 and largo < 0.35)
	p.show_blade(false)

	print("\nfallos=", _fails)
	if not hay_jog:
		print("NOTA: sin jog.fbx el trote corre en modo degradado (no patina, pero es corto).")
	quit(1 if _fails > 0 else 0)


# El clip solo puede estirarse hasta rig.STRETCH_MAX. Pedirle mas metros por
# segundo que eso significa que el personaje se desliza sobre el piso.
func _no_patina(rig: MixamoRig, clip: String, world: float) -> void:
	if not rig.has_clip(clip):
		print("  PEND  %s: clip ausente" % clip)
		return
	var techo := rig.max_world_speed(clip)
	_check("%-12s pide %.2f m/s, el clip sostiene %.2f m/s" % [clip, world, techo],
		world <= techo + 0.001)


func _eq(nombre: String, valor: float, esperado: float) -> void:
	_check("%s = %.3f" % [nombre, valor], absf(valor - esperado) < 0.001)


func _check(nombre: String, ok: bool) -> void:
	print(("  OK    " if ok else "  FALLA ") + nombre)
	if not ok:
		_fails += 1
