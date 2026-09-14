# PROTOTYPE - NOT FOR PRODUCTION
# Verifica el menu de pausa sin abrir ventana: visibilidad, pausa del arbol,
# process_mode, el slider sobre Master, y que el bus Mundo quede intacto.
extends SceneTree

var _fails := 0
# El DisplayServer headless IGNORA Input.mouse_mode: siempre lee 0 (VISIBLE)
# le mandes lo que le mandes. Afirmar sobre el cursor aca da falsos positivos
# tanto como falsos negativos, asi que se marca como no verificable.
var _sin_cursor := DisplayServer.get_name() == "headless"


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

	print("=== construccion")
	var menu := m.get("_menu") as Control
	_check("el menu se construyo", menu != null)
	if menu == null:
		quit(1)
		return
	_check("arranca oculto", not menu.visible)
	_check("menu es PROCESS_MODE_ALWAYS", menu.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("main es PROCESS_MODE_ALWAYS", m.process_mode == Node.PROCESS_MODE_ALWAYS)
	_check("el arbol arranca despausado", not paused)
	_check("la accion pause existe", InputMap.has_action(&"pause"))

	print("=== abrir")
	m.call("_toggle_menu")
	await process_frame
	_check("se hace visible", menu.visible)
	_check("pausa el arbol", paused)
	_check_cursor("libera el mouse", Input.MOUSE_MODE_VISIBLE)

	print("=== volumen (bus Master)")
	var mundo_idx := AudioServer.get_bus_index(&"Mundo")
	_check("el bus Mundo existe", mundo_idx > 0)
	var mundo_antes := AudioServer.get_bus_volume_db(mundo_idx)

	m.call("_on_volume_changed", 0.5)
	var db := AudioServer.get_bus_volume_db(0)
	_check("50%% -> Master en %.2f dB" % db, absf(db - linear_to_db(0.5)) < 0.01)
	_check("round-trip 50% sobrevive al reload", absf(db_to_linear(db) - 0.5) < 0.001)

	var etiqueta := m.get("_vol_value") as Label
	_check("la etiqueta dice 50%% (dice '%s')" % etiqueta.text, etiqueta.text == "50%")

	m.call("_on_volume_changed", 0.0)
	_check("0% -> -80 dB (silencio)", AudioServer.get_bus_volume_db(0) <= -79.9)
	_check("round-trip 0% vuelve a 0", db_to_linear(AudioServer.get_bus_volume_db(0)) < 0.01)

	m.call("_on_volume_changed", 1.0)
	_check("100% -> Master en 0 dB", absf(AudioServer.get_bus_volume_db(0)) < 0.01)
	_check("el bus Mundo quedo intacto", absf(AudioServer.get_bus_volume_db(mundo_idx) - mundo_antes) < 0.01)

	print("=== cerrar")
	m.call("_close_menu")
	await process_frame
	_check("se oculta", not menu.visible)
	_check("despausa el arbol", not paused)
	_check_cursor("recaptura el mouse", Input.MOUSE_MODE_CAPTURED)

	print("=== reiniciar desde el menu (el caso peligroso)")
	# El escenario real: pausar en mitad del slow-mo de la ejecucion y reiniciar.
	m.call("_toggle_menu")
	Engine.time_scale = 0.15
	await process_frame
	m.call("_restart")
	await process_frame
	await process_frame
	_check("el reinicio despausa", not paused)
	_check("el reinicio resetea time_scale", is_equal_approx(Engine.time_scale, 1.0))
	_check("la escena se recargo", current_scene != null and current_scene != m)

	print("\nfallos=", _fails)
	quit(1 if _fails > 0 else 0)


func _check(nombre: String, ok: bool) -> void:
	print(("  OK    " if ok else "  FALLA ") + nombre)
	if not ok:
		_fails += 1


func _check_cursor(nombre: String, esperado: Input.MouseMode) -> void:
	if _sin_cursor:
		print("  N/A   " + nombre + "  (headless no aplica mouse_mode - probar con ventana)")
		return
	_check(nombre, Input.mouse_mode == esperado)
