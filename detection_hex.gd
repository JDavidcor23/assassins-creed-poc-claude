# PROTOTYPE - NOT FOR PRODUCTION
# Indicador de deteccion estilo Assassin's Creed: un hexagono que se llena de
# abajo hacia arriba y vira gris -> amarillo -> rojo. Main lo orbita alrededor
# del centro de la pantalla en la direccion del guardia, asi el jugador sabe
# DE DONDE lo estan detectando, no solo cuanto.
class_name DetectionHex
extends Control

const RADIO := 30.0
const GRIS := Color(0.78, 0.78, 0.76)
const AMARILLO := Color(1.0, 0.78, 0.15)
const ROJO := Color(0.93, 0.16, 0.11)

var ratio := 0.0:
	set(v):
		var nuevo := clampf(v, 0.0, 1.0)
		if is_equal_approx(nuevo, ratio):
			return
		ratio = nuevo
		queue_redraw()


func _draw() -> void:
	var hex := _hexagono(RADIO)
	draw_colored_polygon(hex, Color(0.0, 0.0, 0.0, 0.5))

	# El relleno sube de abajo hacia arriba: se recorta el hexagono contra un
	# rectangulo que crece. Geometry2D hace el corte exacto sin shaders.
	if ratio > 0.001:
		var alto := RADIO * 2.0 * ratio
		var corte := PackedVector2Array([
			Vector2(-RADIO, RADIO - alto),
			Vector2(RADIO, RADIO - alto),
			Vector2(RADIO, RADIO),
			Vector2(-RADIO, RADIO),
		])
		for pieza: PackedVector2Array in Geometry2D.intersect_polygons(hex, corte):
			draw_colored_polygon(pieza, color_actual())

	var borde := hex.duplicate()
	borde.append(hex[0])
	draw_polyline(borde, color_actual(), 2.5, true)


# Gris mientras duda, amarillo cuando sospecha, rojo cuando te tiene.
func color_actual() -> Color:
	if ratio < 0.5:
		return GRIS.lerp(AMARILLO, ratio / 0.5)
	return AMARILLO.lerp(ROJO, (ratio - 0.5) / 0.5)


func _hexagono(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in 6:
		var a := deg_to_rad(60.0 * float(i) - 90.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
