extends Node
## Audio: efectos (2D y 3D), bucles de herramientas, ambiente y música con fundidos.
## Todos los sonidos son originales y se generan con tools/gen_audio.py.

const DIR := "res://assets/audio/"
const LOOPS := ["rake_loop", "blower_loop", "vacuum_loop", "industrial_loop", "wind_loop", "suburb_loop", "duct_loop"]
const MUSIC := ["music_1", "music_2"]

var _streams := {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _next2d := 0
var _next3d := 0
var _loops := {}        # nombre -> {"player": AudioStreamPlayer, "target": float, "pitch": float}
var _music_player: AudioStreamPlayer
var _music_index := 0
var _music_gap := 6.0
var _bird_timer := 5.0
var _ambient_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool2d.append(p)
	for i in 10:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 6.0
		p3.max_distance = 45.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool3d.append(p3)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)


func stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path := DIR + sound + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if s is AudioStreamWAV and (LOOPS.has(sound)):
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
	_streams[sound] = s
	return s


## Variante aleatoria: "step" -> step_1..step_n si existen.
func _variant(base: String, count: int) -> String:
	if count <= 1:
		return base
	return "%s_%d" % [base, randi_range(1, count)]


func play_ui(sound: String, volume_db: float = 0.0) -> void:
	play_sfx("ui_" + sound, Vector3.INF, volume_db, 0.0)


func play_sfx(sound: String, pos: Vector3 = Vector3.INF, volume_db: float = 0.0, pitch_rand: float = 0.08, variants: int = 1) -> void:
	var s := stream(_variant(sound, variants))
	if s == null:
		return
	var pitch := 1.0 + randf_range(-pitch_rand, pitch_rand)
	if pos == Vector3.INF:
		var p := _pool2d[_next2d]
		_next2d = (_next2d + 1) % _pool2d.size()
		p.stream = s
		p.volume_db = volume_db
		p.pitch_scale = pitch
		p.play()
	else:
		var p3 := _pool3d[_next3d]
		_next3d = (_next3d + 1) % _pool3d.size()
		p3.stream = s
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.global_position = pos
		p3.play()


## Controla un bucle continuo (herramientas, viento...). volume en lineal 0..1.
func set_loop(sound: String, volume: float, pitch: float = 1.0, bus: String = "SFX") -> void:
	if not _loops.has(sound):
		if volume <= 0.001:
			return
		var s := stream(sound)
		if s == null:
			return
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.stream = s
		p.volume_db = -60.0
		add_child(p)
		p.play()
		_loops[sound] = {"player": p, "target": volume, "pitch": pitch, "current": 0.0}
	var l: Dictionary = _loops[sound]
	l["target"] = volume
	l["pitch"] = pitch


func start_ambience() -> void:
	_ambient_on = true
	set_loop("wind_loop", 0.55, 1.0, "Ambient")
	set_loop("suburb_loop", 0.35, 1.0, "Ambient")
	if not _music_player.playing:
		_music_gap = 3.0


func stop_all_tool_loops() -> void:
	for k in ["rake_loop", "blower_loop", "vacuum_loop", "industrial_loop"]:
		if _loops.has(k):
			_loops[k]["target"] = 0.0


func _process(delta: float) -> void:
	var paused := get_tree().paused
	for k in _loops:
		var l: Dictionary = _loops[k]
		var target: float = 0.0 if (paused and not (k in ["wind_loop", "suburb_loop"])) else l["target"]
		var cur: float = l["current"]
		var rate := 4.0 if target > cur else 3.0
		cur = move_toward(cur, target, rate * delta)
		l["current"] = cur
		var p: AudioStreamPlayer = l["player"]
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		p.pitch_scale = lerpf(p.pitch_scale, float(l["pitch"]), minf(delta * 5.0, 1.0))
		if cur <= 0.0005 and p.playing and target <= 0.0:
			p.stream_paused = true
		elif cur > 0.0005 and p.stream_paused:
			p.stream_paused = false
	if not _ambient_on:
		return
	# Pájaros esporádicos.
	_bird_timer -= delta
	if _bird_timer <= 0.0 and not paused:
		_bird_timer = randf_range(4.0, 11.0)
		play_sfx("bird", Vector3.INF, randf_range(-14.0, -7.0), 0.12, 3)
	# Música suave con silencios entre pistas.
	if not _music_player.playing:
		_music_gap -= delta
		if _music_gap <= 0.0:
			var s := stream(MUSIC[_music_index % MUSIC.size()])
			_music_index += 1
			if s != null:
				_music_player.stream = s
				_music_player.volume_db = -4.0
				_music_player.play()
			_music_gap = 9999.0


func _on_music_finished() -> void:
	_music_gap = randf_range(20.0, 45.0)
