extends Node
## Postales coleccionables y notas de historia.

var found := {}
var notes_read := {}


func _ready() -> void:
	SaveManager.register("collectibles", self)


func reset() -> void:
	found.clear()
	notes_read.clear()


func is_found(id: String) -> bool:
	return found.get(id, false)


func collect(id: String) -> void:
	if found.get(id, false):
		return
	found[id] = true
	ProgressManager.set_stat("postcards", found.size())
	var card := postcard(id)
	EventBus.collectible_found.emit(id)
	EventBus.note_read.emit("Postal: " + card["title"], card["text"])
	AudioManager.play_ui("collect")
	HapticManager.pulse(80, 0.8)
	if found.size() >= GameData.POSTCARDS.size():
		ProgressManager.set_flag("copper_rake")
		EventBus.toast.emit("¡Colección completa!", "Desbloqueado: Rastrillo de cobre (aspecto)", "reward")
	SaveManager.request_save()


func read_note(id: String) -> void:
	notes_read[id] = true


func postcard(id: String) -> Dictionary:
	for p in GameData.POSTCARDS:
		if p["id"] == id:
			return p
	return {}


func to_save() -> Dictionary:
	return {"found": found, "notes": notes_read}


func from_save(d: Dictionary) -> void:
	found = d.get("found", {})
	notes_read = d.get("notes", {})
