extends Node
## Guardado automático robusto: escritura atómica, suma de verificación y copia de seguridad.
## Cada sistema registra un "proveedor" con to_save()/from_save(). Las hojas usan un binario aparte.

const VERSION := 1
const AUTOSAVE_INTERVAL := 120.0

var slot := "campaign"
var _providers := {}          # nombre -> Object con to_save()/from_save(dict)
var _leaf_provider: Object = null
var _autosave_timer := 0.0
var _dirty_request := false
var enabled := true
var _loaded := {}             # últimos datos cargados (para proveedores que se registran tarde)


func register(name: String, provider: Object) -> void:
	_providers[name] = provider
	if _loaded.has(name):
		provider.from_save(_loaded[name])


## Elimina proveedores cuyos nodos ya no existen (p. ej. tras recargar la escena).
func _prune() -> void:
	for k in _providers.keys():
		if not is_instance_valid(_providers[k]):
			_providers.erase(k)


func clear_loaded() -> void:
	_loaded.clear()


func register_leaf_provider(provider: Object) -> void:
	_leaf_provider = provider


func unregister_leaf_provider(provider: Object) -> void:
	if _leaf_provider == provider:
		_leaf_provider = null


func _process(delta: float) -> void:
	if not enabled or not GameManager.in_game:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL or _dirty_request:
		_dirty_request = false
		save_game()


## Pide un guardado en el siguiente frame (agrupa varias peticiones).
func request_save() -> void:
	_dirty_request = true


func _path(kind: String) -> String:
	return "user://%s_%s" % [slot, kind]


func has_save(for_slot: String = "") -> bool:
	var s := for_slot if for_slot != "" else slot
	return FileAccess.file_exists("user://%s_state.json" % s) or FileAccess.file_exists("user://%s_state.json.bak" % s)


func save_game() -> bool:
	if not enabled or not GameManager.in_game:
		return false
	_autosave_timer = 0.0
	var data := {}
	_prune()
	for k in _providers:
		data[k] = _providers[k].to_save()
	var body := JSON.stringify(data)
	var wrapper := {"v": VERSION, "sum": body.md5_text(), "time": Time.get_unix_time_from_system(), "data": body}
	var ok := _write_atomic(_path("state.json"), JSON.stringify(wrapper).to_utf8_buffer())
	if _leaf_provider != null and is_instance_valid(_leaf_provider):
		var leaf_bytes: PackedByteArray = _leaf_provider.save_leaf_state()
		if leaf_bytes.size() > 0:
			var packed := PackedByteArray()
			packed.append_array("VHL1".to_utf8_buffer())
			var raw_size := leaf_bytes.size()
			var comp := leaf_bytes.compress(FileAccess.COMPRESSION_ZSTD)
			var header := PackedByteArray()
			header.resize(8)
			header.encode_u32(0, raw_size)
			header.encode_u32(4, _crc(leaf_bytes))
			packed.append_array(header)
			packed.append_array(comp)
			ok = _write_atomic(_path("leaves.bin"), packed) and ok
	if ok:
		EventBus.game_saved.emit()
	return ok


func load_game() -> bool:
	var data := _read_state(_path("state.json"))
	if data.is_empty():
		data = _read_state(_path("state.json") + ".bak")
		if data.is_empty():
			return false
		push_warning("Guardado principal dañado: se usa la copia de seguridad.")
	_loaded = data
	_prune()
	for k in _providers:
		if data.has(k):
			_providers[k].from_save(data[k])
	return true


## Devuelve el estado binario de las hojas (o vacío si no hay o está dañado).
func load_leaf_state() -> PackedByteArray:
	var res := _read_leaves(_path("leaves.bin"))
	if res.is_empty():
		res = _read_leaves(_path("leaves.bin") + ".bak")
	return res


func delete_slot(for_slot: String) -> void:
	for kind in ["state.json", "leaves.bin"]:
		for suffix in ["", ".bak", ".tmp"]:
			var p := "user://%s_%s%s" % [for_slot, kind, suffix]
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)


func _read_state(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var wrapper: Variant = JSON.parse_string(txt)
	if typeof(wrapper) != TYPE_DICTIONARY or not wrapper.has("data") or not wrapper.has("sum"):
		return {}
	var body: String = wrapper["data"]
	if body.md5_text() != wrapper["sum"]:
		return {}
	var data: Variant = JSON.parse_string(body)
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return data


func _read_leaves(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_utf8() != "VHL1":
		return PackedByteArray()
	var raw_size := bytes.decode_u32(4)
	var crc := bytes.decode_u32(8)
	var raw := bytes.slice(12).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size or _crc(raw) != crc:
		return PackedByteArray()
	return raw


func _write_atomic(path: String, bytes: PackedByteArray) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("No se pudo escribir " + tmp)
		return false
	f.store_buffer(bytes)
	f.close()
	# Verificación: lo que hay en disco debe coincidir exactamente.
	if FileAccess.get_file_as_bytes(tmp) != bytes:
		push_error("Verificación de guardado fallida: " + path)
		return false
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	return DirAccess.rename_absolute(tmp, path) == OK


func _crc(bytes: PackedByteArray) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().decode_u32(0)
