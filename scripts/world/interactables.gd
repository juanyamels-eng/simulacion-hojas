class_name Interactable
extends StaticBody3D
## Base de todo lo que se puede usar con el botón INTERACTUAR.
## Capa de colisión 2 = rayo de interacción. Añade la capa 1 si además bloquea al jugador.

const LAYER_WORLD := 1
const LAYER_INTERACT := 2
const LAYER_BAG := 4


func get_prompt(_player: Node) -> String:
	return ""


func is_available(_player: Node) -> bool:
	return true


## Segundos que hay que mantener pulsado (0 = pulsación simple).
func hold_time(_player: Node) -> float:
	return 0.0


func interact(_player: Node) -> void:
	pass


static func make_shape(body: CollisionObject3D, size: Vector3, offset: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = offset
	body.add_child(cs)
	return cs
