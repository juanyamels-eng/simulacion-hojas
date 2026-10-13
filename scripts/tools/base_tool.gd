class_name BaseTool
extends Node3D
## Base de las herramientas. Cada herramienta tiene un modelo visible y su lógica sobre las hojas.

var tool_id := ""
var player: PlayerController
var lm: LeafManager
var active := false
var using := false
var _equip_t := 0.0
var model: Node3D


func setup(p: PlayerController) -> void:
	player = p
	lm = p.leaf_manager
	model = Node3D.new()
	build_model()
	visible = false


## Las herramientas de mano cuelgan de la cámara; las de suelo, del cuerpo.
func attach_parent() -> Node3D:
	return player.cam.camera


func build_model() -> void:
	pass


func equip() -> void:
	active = true
	visible = true
	_equip_t = 0.0


func unequip() -> void:
	active = false
	visible = false
	stop_use()


func stop_use() -> void:
	using = false


## held: botón de herramienta mantenido; pressed: flanco de pulsación.
func process_tool(_delta: float, _held: bool, _pressed: bool) -> void:
	pass


func speed_factor() -> float:
	return 1.0


func status_text() -> String:
	return ""


func equip_offset(delta: float) -> float:
	_equip_t = minf(_equip_t + delta * 4.0, 1.0)
	return (1.0 - ease(_equip_t, 0.4)) * 0.5


func part(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D = null, rough: float = 0.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = MeshFactory.mat(color, rough)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else model).add_child(mi)
	return mi


func zone_id() -> String:
	return AreaManager.current_zone
