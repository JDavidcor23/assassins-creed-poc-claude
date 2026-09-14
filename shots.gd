# PROTOTYPE - NOT FOR PRODUCTION
# Capturas para el README. A diferencia de _autoshot() (que saca fotos de
# diagnostico desde 4 angulos planos), esto COMPONE escenas: elige posiciones,
# estados y encuadre para que cada imagen cuente una mecanica.
#
# Uso:  godot --path . --script shots.gd
# Necesita VENTANA: en headless no hay nada que renderizar.
extends SceneTree

const OUT := "res://docs/img"

var _m: Node
var _p: ProtoPlayer
var _g: ProtoGuard


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var packed := load("res://main.tscn") as PackedScene
	_m = packed.instantiate()
	root.add_child(_m)
	current_scene = _m
	await process_frame
	await process_frame
	_p = _m.get("_player") as ProtoPlayer
	_g = _m.get("_guard") as ProtoGuard
	_g.frozen = true
	_p.frozen = true

	# 1. HERO — el acercamiento por la espalda, sin HUD ni conos. Es la foto
	#    que tiene que vender el juego: hora dorada, niebla, silueta.
	_m.set("_hud_mode", 2)
	_m.call("_apply_hud_mode")
	await _encuadre(_detras(3.2), -0.10, 4.2)
	await _foto("01-hero")

	# 2. DETECCION — el cono sale hacia ADELANTE del guardia: desde atras no se
	#    ve nada. Hay que pararse en diagonal y mirar desde arriba.
	_m.set("_hud_mode", 0)
	_m.call("_apply_hud_mode")
	var lado := _g.global_transform.basis.x
	var frente := -_g.global_transform.basis.z
	await _encuadre(_g.global_position + lado * 6.5 + frente * 4.0 + Vector3(0.0, 0.1, 0.0),
		-0.52, 9.0)
	await _foto("02-vision-cone")

	# 3. EJECUTAR — dentro del arco, con el prompt en pantalla.
	_m.set("_can_execute", true)
	_m.call("_update_prompt")
	await _encuadre(_detras(2.0), -0.14, 3.2)
	await _foto("03-assassinate")
	_m.set("_can_execute", false)

	# 4. PASTIZAL — agachado dentro del matorral, con el aviso.
	var pasto := Vector3(-6.0, 0.0, 6.5)
	_p.global_position = Vector3(pasto.x, _p.global_position.y, pasto.z)
	_p.crouching = true
	_p.rig.play_state("crouch_idle", 0.0, 1.0)
	_g.global_position = pasto + Vector3(0.5, 0.0, 7.0)
	_g.rotation.y = _g.call("_yaw_toward", pasto - _g.global_position)
	_m.call("_update_prompt")
	_p.view_yaw = _p.view_yaw + PI
	_p.view_pitch = -0.42
	_p.arm.spring_length = 4.6
	_p.snap_camera()
	for i: int in 30:
		await process_frame
	await _foto("04-tall-grass")

	print("\nListo: 4 capturas en ", OUT)
	quit(0)


# Coloca al jugador y apunta la camara hacia el guardia.
func _encuadre(pos: Vector3, pitch: float, dist: float) -> void:
	_p.global_position = pos
	var d := (_g.global_position - _p.global_position).normalized()
	_p.view_yaw = atan2(-d.x, -d.z)
	_p.view_pitch = pitch
	_p.arm.spring_length = dist
	_p.snap_camera()
	# El SpringArm y el lag de camara necesitan varios frames para asentarse;
	# con menos, la foto sale con la camara todavia viajando.
	for i: int in 30:
		await process_frame


func _detras(metros: float) -> Vector3:
	var atras := -(-_g.global_transform.basis.z)
	return _g.global_position + atras * metros + Vector3(0.0, 0.1, 0.0)


func _foto(nombre: String) -> void:
	# frame_post_draw: sin esperar el dibujado la imagen sale del frame anterior.
	for n: int in 4:
		await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var ruta := ProjectSettings.globalize_path(OUT.path_join(nombre + ".png"))
	var err := img.save_png(ruta)
	print("  %s -> %s" % [nombre, "OK" if err == OK else "ERROR %d" % err])
