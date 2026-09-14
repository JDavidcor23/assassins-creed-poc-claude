# PROTOTYPE - NOT FOR PRODUCTION
# Verifica el oído del guardia y el indicador de detección.
# El caso que motivó todo: trotar pegado a la ESPALDA del guardia tiene que
# alertarlo. Antes no pasaba nada, porque sólo existía la visión.
extends SceneTree

var _fails := 0


func _init() -> void:
	var packed := load("res://main.tscn") as PackedScene
	var m := packed.instantiate()
	root.add_child(m)
	current_scene = m
	await process_frame
	await process_frame

	var p := m.get("_player") as ProtoPlayer
	var g := m.get("_guard") as ProtoGuard

	print("=== radio de ruido por estado")
	p.frozen = false
	p.crouching = false
	p.jogging = false
	p.velocity = Vector3.ZERO
	_eq("quieto no hace ruido", p.noise_radius(), 0.0)
	p.velocity = Vector3(ProtoPlayer.WALK_SPEED, 0.0, 0.0)
	_eq("caminando", p.noise_radius(), ProtoPlayer.NOISE_WALK)
	p.velocity = Vector3(ProtoPlayer.JOG_SPEED, 0.0, 0.0)
	_eq("trotando", p.noise_radius(), ProtoPlayer.NOISE_JOG)
	p.crouching = true
	p.velocity = Vector3(ProtoPlayer.CROUCH_SPEED, 0.0, 0.0)
	_eq("agachado", p.noise_radius(), ProtoPlayer.NOISE_CROUCH)
	p.crouching = false

	print("=== EL BUG: trotar detrás del guardia")
	# Detrás = opuesto al frente del guardia. La visión no llega nunca ahí.
	var atras := g.global_position - (-g.global_transform.basis.z) * 3.0
	atras.y = p.global_position.y
	p.global_position = atras
	await process_frame

	p.velocity = Vector3.ZERO
	_check("quieto detrás: NO lo oye", not g.call("_can_hear_player"))
	_check("quieto detrás: NO lo ve", not g.call("_can_see_player"))

	p.velocity = (g.global_position - p.global_position).normalized() * ProtoPlayer.JOG_SPEED
	_check("TROTANDO detrás a 3 m: LO OYE", g.call("_can_hear_player"))
	_check("trotando detrás: sigue sin verlo (es oído, no vista)",
		not g.call("_can_see_player"))

	p.crouching = true
	p.velocity = p.velocity.normalized() * ProtoPlayer.CROUCH_SPEED
	_check("agachado detrás a 3 m: NO lo oye", not g.call("_can_hear_player"))
	p.crouching = false

	print("=== el oído no tiene cono: mismo ruido, cualquier ángulo")
	var radio := 3.0
	var oidos := 0
	for i: int in 8:
		var a := TAU * float(i) / 8.0
		var pos := g.global_position + Vector3(cos(a), 0.0, sin(a)) * radio
		pos.y = p.global_position.y
		p.global_position = pos
		p.velocity = Vector3(ProtoPlayer.JOG_SPEED, 0.0, 0.0)
		if g.call("_can_hear_player"):
			oidos += 1
	_check("trotando a 3 m lo oye desde los 8 ángulos (oyó %d/8)" % oidos, oidos == 8)

	print("=== alcance del oído")
	var lejos := g.global_position + Vector3(ProtoPlayer.NOISE_JOG + 2.0, 0.0, 0.0)
	lejos.y = p.global_position.y
	p.global_position = lejos
	p.velocity = Vector3(ProtoPlayer.JOG_SPEED, 0.0, 0.0)
	_check("trotando más lejos que NOISE_JOG: no lo oye", not g.call("_can_hear_player"))

	print("=== indicador de detección")
	var hex := m.get("_hex") as DetectionHex
	_check("el hexágono existe", hex != null)
	if hex != null:
		hex.ratio = 0.0
		var gris := hex.color_actual()
		hex.ratio = 0.5
		var amarillo := hex.color_actual()
		hex.ratio = 1.0
		var rojo := hex.color_actual()
		_check("en 0 es gris", gris.is_equal_approx(DetectionHex.GRIS))
		_check("en 0.5 es amarillo", amarillo.is_equal_approx(DetectionHex.AMARILLO))
		_check("en 1.0 es rojo", rojo.is_equal_approx(DetectionHex.ROJO))
		# Lo que de verdad importa: que el rojo se distinga del gris de un vistazo.
		_check("rojo y gris son claramente distintos",
			absf(rojo.r - gris.r) + absf(rojo.g - gris.g) + absf(rojo.b - gris.b) > 0.5)
		hex.ratio = 2.0
		_eq("el ratio se clampea a 1", hex.ratio, 1.0)
		hex.ratio = -1.0
		_eq("el ratio se clampea a 0", hex.ratio, 0.0)

	print("=== esconderse SIN boton: agacharse en el pastizal")
	var matorrales: Array = m.get("_hideouts") if m.get("_hideouts") != null else []
	print("  (matorrales registrados: %d — ya no se usan como lista)" % matorrales.size())
	# El pastizal es capa 8: corta el raycast de vision pero se atraviesa
	# caminando. Agachado los ojos bajan a 0.7 m y quedan por debajo del follaje.
	var pasto := Vector3(-6.0, 0.0, 6.5)   # mismo lugar que _add_thicket
	# TEARDOWN: hay que devolver al guardia a su sitio o los tests siguientes
	# miden con el pastizal en el medio. Paso de verdad: dos fallos fantasma.
	var g_pos := g.global_position
	var g_yaw := g.rotation.y
	g.frozen = true
	g.global_position = pasto + Vector3(0.0, 0.0, 5.0)
	g.rotation.y = g.call("_yaw_toward", pasto - g.global_position)
	p.global_position = Vector3(pasto.x, p.global_position.y, pasto.z)
	p.velocity = Vector3.ZERO
	p.crouching = true
	for i: int in 8:
		await process_frame
	_check("agachado dentro del pastizal: NO lo ve", not g.call("_can_see_player"))
	_check("agachado quieto no hace ruido audible",
		p.noise_radius() <= ProtoPlayer.NOISE_CROUCH)
	p.crouching = false
	g.global_position = g_pos
	g.rotation.y = g_yaw
	g.frozen = false
	await process_frame

	print("=== zona de ejecución (era demasiado exigente)")
	var rango: float = ProtoGuard.BACKSTAB_RANGE
	var radios := 0.35 + 0.35
	_check("queda separación real entre cuerpos (%.2f m)" % (rango - radios),
		rango - radios > 1.0)
	var arco := 2.0 * ProtoGuard.BACKSTAB_HALF_ANGLE_DEG
	_check("el arco por detrás es usable (%.0f grados)" % arco, arco >= 140.0)
	# Pero no tanto como para ejecutar de frente: eso rompería la fantasía.
	_check("no se puede ejecutar de frente", arco < 200.0)

	print("=== de frente NO se puede ser invisible")
	# Posiciones FIJAS, no las del guardia patrullando: segun donde estuviera
	# quedaba un arbusto en el medio y el test fallaba una de cada dos corridas.
	# Origen mirando +X: tramo despejado verificado contra el layout del mapa.
	g.frozen = true
	g.global_position = Vector3(0.0, 0.0, 0.0)
	g.rotation.y = g.call("_yaw_toward", Vector3(1.0, 0.0, 0.0))
	await physics_frame
	var frente := -g.global_transform.basis.z
	for modo: String in ["quieto", "agachado"]:
		p.global_position = g.global_position + frente * 5.5
		p.crouching = (modo == "agachado")
		p.velocity = Vector3.ZERO
		# physics_frame, NO process_frame: _can_see_player() hace un raycast y el
		# espacio fisico se actualiza en el tick de fisica. Con process_frame se
		# consultaba el estado viejo y el test fallaba de forma intermitente.
		await physics_frame
		await physics_frame
		_check("%s, de frente, a 5.5 m: LO VE" % modo, g.call("_can_see_player"))
	# Pero el sigilo tiene que seguir sirviendo LEJOS, si no agacharse sobra.
	p.global_position = g.global_position + frente * 7.5
	p.crouching = true
	await physics_frame
	await physics_frame
	_check("agachado a 7.5 m: no lo ve (el sigilo sirve de lejos)",
		not g.call("_can_see_player"))
	p.crouching = false
	g.frozen = false

	print("=== subtítulos del guardia")
	# Congelado: si patrulla, suelta su murmullo en medio del test y aparecen
	# 4 subtitulos donde se esperaban 3.
	g.frozen = true
	var vistos: Array[String] = []
	var audio := m.get("_audio") as ProtoAudio
	audio.said.connect(func(t: String) -> void: vistos.append(t))
	for tipo: StringName in [&"sospecha", &"alerta", &"murmullo"]:
		audio.speak(tipo, Vector3.ZERO, -40.0)
	await process_frame
	_check("cada línea hablada emite subtítulo (%d de 3)" % vistos.size(), vistos.size() == 3)
	# El subtítulo tiene que ser el de la línea que SONÓ, no uno al azar.
	for t: String in vistos:
		var existe := false
		for tipo: Variant in ProtoAudio.VOZ_LINEAS:
			for par: Array in ProtoAudio.VOZ_LINEAS[tipo]:
				if String(par[1]) == t:
					existe = true
		_check("\"%s\" sale de la tabla de líneas" % t, existe)
	g.frozen = false

	print("=== INVARIANTES DE DISEÑO: el juego tiene que ser jugable")
	_invariantes_de_aproximacion()

	print("\nfallos=", _fails)
	quit(1 if _fails > 0 else 0)


# Se rompió en vivo: CROUCH_SPEED quedó en 1.25, EXACTAMENTE la velocidad de
# patrulla del guardia, y acercarse por detrás pasó a ser imposible — no
# difícil, imposible. Ningún test lo vio porque todos miraban piezas sueltas.
# Estas reglas miran el juego entero.
func _invariantes_de_aproximacion() -> void:
	var vg: float = ProtoGuard.MOVE_SPEED
	var rango: float = ProtoGuard.BACKSTAB_RANGE
	var limite: float = ProtoGuard.DETECT_TIME / ProtoGuard.HEAR_RATE

	_check("agachado le gana al guardia (%.2f vs %.2f, +%.2f m/s)" % [
		ProtoPlayer.CROUCH_SPEED, vg, ProtoPlayer.CROUCH_SPEED - vg],
		ProtoPlayer.CROUCH_SPEED - vg >= 0.15)
	_check("caminando le gana al guardia (+%.2f m/s)" % [ProtoPlayer.WALK_SPEED - vg],
		ProtoPlayer.WALK_SPEED - vg >= 0.15)
	_check("agachado llega a rango SIN ser oído (ruido %.1f < rango %.1f)" % [
		ProtoPlayer.NOISE_CROUCH, rango],
		ProtoPlayer.NOISE_CROUCH < rango)
	var exp_walk := _tiempo_expuesto(ProtoPlayer.WALK_SPEED, ProtoPlayer.NOISE_WALK)
	_check("caminando alcanza a cruzar (%.1fs <= %.1fs)" % [exp_walk, limite],
		exp_walk <= limite)
	# El que faltaba: "llega" no alcanza, tiene que COSTARLE. Con exposición 0
	# caminar es tan seguro como agacharse y más rápido — y agacharse sobra.
	# Pasó de verdad al subir BACKSTAB_RANGE por encima de NOISE_WALK.
	_check("pero caminar NO es gratis: está expuesto %.1fs" % exp_walk, exp_walk >= 0.5)
	_check("el ruido al caminar supera el rango de ejecución (%.1f > %.1f)" % [
		ProtoPlayer.NOISE_WALK, rango], ProtoPlayer.NOISE_WALK > rango)
	# Si trotar también funcionara, nadie se agacharía nunca y el sigilo sobra.
	_check("trotando NO alcanza a cruzar (%.1fs > %.1fs) — el costo existe" % [
		_tiempo_expuesto(ProtoPlayer.JOG_SPEED, ProtoPlayer.NOISE_JOG), limite],
		_tiempo_expuesto(ProtoPlayer.JOG_SPEED, ProtoPlayer.NOISE_JOG) > limite)
	_check("los tres modos hacen ruido distinto",
		ProtoPlayer.NOISE_CROUCH < ProtoPlayer.NOISE_WALK
		and ProtoPlayer.NOISE_WALK < ProtoPlayer.NOISE_JOG)


# Segundos dentro del radio de ruido antes de llegar a rango de ejecución.
func _tiempo_expuesto(vel: float, ruido: float) -> float:
	var gana: float = vel - ProtoGuard.MOVE_SPEED
	if gana <= 0.0:
		return INF
	return maxf(ruido - ProtoGuard.BACKSTAB_RANGE, 0.0) / gana


func _eq(nombre: String, valor: float, esperado: float) -> void:
	_check("%s = %.3f" % [nombre, valor], absf(valor - esperado) < 0.001)


func _check(nombre: String, ok: bool) -> void:
	print(("  OK    " if ok else "  FALLA ") + nombre)
	if not ok:
		_fails += 1
