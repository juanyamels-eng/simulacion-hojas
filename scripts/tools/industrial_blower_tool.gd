class_name IndustrialBlowerTool
extends BlowerTool
## Soplador industrial: cono enorme y empuje masivo de cientos de hojas sin física individual.


func _init() -> void:
	tool_id = "industrial"
	range_mult = 1.6
	angle_mult = 1.5
	shove = true
	loop_name = "industrial_loop"


func build_model() -> void:
	super.build_model()
	model.scale = Vector3.ONE * 1.35
	for c in model.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is BoxMesh and ((c as MeshInstance3D).mesh as BoxMesh).size.x > 0.15:
			(c as MeshInstance3D).material_override = MeshFactory.mat(Color(0.85, 0.75, 0.15))
	_air.amount = 64
	_air.spread = 18.0


func _power() -> float:
	return float(UpgradeManager.get_value("blower_power")) * 2.0 * float(UpgradeManager.get_value("industrial_power"))
