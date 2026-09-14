# PROTOTYPE - NOT FOR PRODUCTION
# Verifica el mapeo del mando (layout Xbox) sin necesidad de tener uno conectado:
# lo que se comprueba es que cada accion tenga su evento de joypad registrado.
extends SceneTree

var _fails := 0


func _init() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var m := packed.instantiate()
	root.add_child(m)
	current_scene = m
	await process_frame

	print("=== palancas")
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)

	print("=== gatillo y botones")
	_axis("jog", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_boton("crouch", JOY_BUTTON_B)
	_boton("execute", JOY_BUTTON_X)
	_boton("pause", JOY_BUTTON_START)
	_boton("restart", JOY_BUTTON_BACK)

	print("=== zona muerta")
	for a: String in ["move_left", "move_right", "move_forward", "move_back",
			"look_left", "look_right", "look_up", "look_down"]:
		var dz := InputMap.action_get_deadzone(StringName(a))
		_check("%s tiene zona muerta (%.2f)" % [a, dz], dz > 0.05)

	print("=== el teclado sigue funcionando")
	# El mando SUMA, no reemplaza: un mapeo que pisa el teclado rompe la demo.
	_tecla("move_forward", KEY_W)
	_tecla("execute", KEY_E)
	_tecla("crouch", KEY_C)
	_tecla("jog", KEY_SHIFT)

	print("\nfallos=", _fails)
	quit(1 if _fails > 0 else 0)


func _axis(accion: String, eje: JoyAxis, valor: float) -> void:
	for e: InputEvent in InputMap.action_get_events(StringName(accion)):
		if e is InputEventJoypadMotion:
			var mo := e as InputEventJoypadMotion
			if mo.axis == eje and signf(mo.axis_value) == signf(valor):
				_check("%s -> eje %d (%+.0f)" % [accion, eje, valor], true)
				return
	_check("%s -> eje %d (%+.0f)" % [accion, eje, valor], false)


func _boton(accion: String, boton: JoyButton) -> void:
	for e: InputEvent in InputMap.action_get_events(StringName(accion)):
		if e is InputEventJoypadButton \
				and (e as InputEventJoypadButton).button_index == boton:
			_check("%s -> boton %d" % [accion, boton], true)
			return
	_check("%s -> boton %d" % [accion, boton], false)


func _tecla(accion: String, key: Key) -> void:
	for e: InputEvent in InputMap.action_get_events(StringName(accion)):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == key:
			_check("%s sigue en el teclado" % accion, true)
			return
	_check("%s sigue en el teclado" % accion, false)


func _check(nombre: String, ok: bool) -> void:
	print(("  OK    " if ok else "  FALLA ") + nombre)
	if not ok:
		_fails += 1
