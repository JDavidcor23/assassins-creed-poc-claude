# PROTOTYPE - NOT FOR PRODUCTION
# Las 5 capas del brief: ambiente en loop, pasos por material, latido que sube
# con la sospecha, impacto del verbo central, y la voz del guardia.
# Archivos generados con ElevenLabs, ya normalizados a -3 dBFS.
class_name ProtoAudio
extends Node

const DIR := "res://assets/audio/"

# El bus "Mundo" existe para poder apagar el mundo de un golpe durante la
# ejecucion y dejar solo la hoja. El silencio es parte del momento.
const BUS_MUNDO := &"Mundo"

# Cada línea del guardia con su traducción. El acento peninsular contra el
# criollo del jugador es narrativa, no decoración — el subtítulo la hace legible
# para quien no habla español.
# Se elige el clip Y el texto juntos: con un AudioStreamRandomizer el audio sale
# al azar y el subtítulo diría otra cosa que la que se escucha.
const VOZ_LINEAS := {
	&"sospecha": [
		["voz/guardia_sospecha_01", "Who goes there?"],
		["voz/guardia_sospecha_02", "What was that?"],
	],
	&"alerta": [
		["voz/guardia_alerta_01", "Halt! Stop right there!"],
		["voz/guardia_alerta_02", "To arms! An insurgent!"],
	],
	&"murmullo": [["voz/guardia_murmullo_01", "Damned jungle..."]],
	&"muerte": [["voz/guardia_muerte_01", ""]],
}

signal said(texto: String)

# Atado al rango de caza del guardia (11.5 m) con un margen chico: se lo oye
# justo un poco mas lejos de lo que ve, no cuatro veces mas.
const VOZ_ALCANCE := 14.0
const VOZ_UNIDAD := 3.5

const AMB_DB := -14.0
const LATIDO_MAX_DB := -6.0
const LATIDO_MIN_DB := -34.0

var _ambiente: AudioStreamPlayer
var _latido: AudioStreamPlayer
var _mundo_idx := 0
var _suspicion := 0.0
var _duck := 0.0

var pasos_hojas: AudioStreamRandomizer
var pasos_tierra: AudioStreamRandomizer
var impacto: AudioStreamRandomizer
var desenfunda: AudioStream
var cuerpo_cae: AudioStream
var voz_sospecha: AudioStreamRandomizer
var voz_alerta: AudioStreamRandomizer
var voz_murmullo: AudioStream
var voz_muerte: AudioStream


func _ready() -> void:
	_setup_bus()

	pasos_hojas = _randomizer(["sfx/paso_hojas_01", "sfx/paso_hojas_02", "sfx/paso_hojas_03"], 0.12, 0.9)
	pasos_tierra = _randomizer(["sfx/paso_tierra_01", "sfx/paso_tierra_02", "sfx/paso_tierra_03"], 0.12, 0.9)
	impacto = _randomizer(["sfx/hoja_impacto_01", "sfx/hoja_impacto_02"], 0.05, 1.0)
	desenfunda = _stream("sfx/hoja_desenfunda_01")
	cuerpo_cae = _stream("sfx/cuerpo_cae_01")
	voz_sospecha = _randomizer(["voz/guardia_sospecha_01", "voz/guardia_sospecha_02"], 0.0, 1.0)
	voz_alerta = _randomizer(["voz/guardia_alerta_01", "voz/guardia_alerta_02"], 0.0, 1.0)
	voz_murmullo = _stream("voz/guardia_murmullo_01")
	voz_muerte = _stream("voz/guardia_muerte_01")

	_ambiente = AudioStreamPlayer.new()
	_ambiente.stream = _stream("ambiente/ambiente_selva")
	_ambiente.bus = BUS_MUNDO
	_ambiente.volume_db = AMB_DB
	add_child(_ambiente)
	if _ambiente.stream != null:
		_ambiente.play()

	_latido = AudioStreamPlayer.new()
	_latido.stream = _stream("ambiente/latido")
	_latido.bus = BUS_MUNDO
	_latido.volume_db = LATIDO_MIN_DB
	add_child(_latido)
	if _latido.stream != null:
		_latido.play()


func _setup_bus() -> void:
	_mundo_idx = AudioServer.get_bus_index(BUS_MUNDO)
	if _mundo_idx == -1:
		AudioServer.add_bus()
		_mundo_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_mundo_idx, BUS_MUNDO)
		AudioServer.set_bus_send(_mundo_idx, &"Master")


func _stream(rel: String) -> AudioStream:
	for ext: String in [".ogg", ".mp3", ".wav"]:
		var p := DIR + rel + ext
		if ResourceLoader.exists(p):
			return load(p) as AudioStream
	push_warning("ProtoAudio: falta " + rel)
	return null


func _randomizer(rels: Array, pitch: float, vol_scale: float) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	r.random_pitch = 1.0 + pitch
	r.random_volume_offset_db = 2.0
	for rel: Variant in rels:
		var s := _stream(String(rel))
		if s != null:
			r.add_stream(r.streams_count, s, vol_scale)
	return r


# El latido sube con la sospecha. No es un numero en pantalla: se siente.
func set_suspicion(ratio: float) -> void:
	_suspicion = clampf(ratio, 0.0, 1.0)


func duck_world(amount: float) -> void:
	_duck = clampf(amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if _latido != null:
		var target := lerpf(LATIDO_MIN_DB, LATIDO_MAX_DB, pow(_suspicion, 0.7))
		_latido.volume_db = lerpf(_latido.volume_db, target, minf(1.0, 8.0 * delta))
		_latido.pitch_scale = lerpf(0.85, 1.35, _suspicion)
	AudioServer.set_bus_volume_db(_mundo_idx, lerpf(0.0, -40.0, _duck))


# --- helpers posicionales -------------------------------------------------

func play_at(stream: AudioStream, pos: Vector3, db: float = 0.0, pitch: float = 1.0, bus: StringName = &"Master", alcance: float = 40.0, unidad: float = 6.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = bus
	p.unit_size = unidad
	p.max_distance = alcance
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	# global_position solo existe dentro del arbol: primero add_child, despues mover.
	add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func play_2d(stream: AudioStream, db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# Habla y avisa QUÉ dijo, para que el subtítulo coincida con el audio.
func speak(tipo: StringName, pos: Vector3, db: float = 0.0) -> void:
	var opciones: Array = VOZ_LINEAS.get(tipo, [])
	if opciones.is_empty():
		return
	var elegida: Array = opciones[randi() % opciones.size()]
	var stream := _stream(String(elegida[0]))
	if stream == null:
		return
	# La voz no puede viajar mas lejos de lo que el guardia VE. A 40 m (el
	# default) lo escuchabas gritar desde la otra punta del mapa: rompia la
	# lectura de "donde esta el peligro", que es la unica info que importa.
	play_at(stream, pos, db, 1.0, &"Master", VOZ_ALCANCE, VOZ_UNIDAD)
	var texto := String(elegida[1])
	if texto != "":
		said.emit(texto)


func step(pos: Vector3, on_leaves: bool, db: float) -> void:
	play_at(pasos_hojas if on_leaves else pasos_tierra, pos, db, 1.0, BUS_MUNDO)
