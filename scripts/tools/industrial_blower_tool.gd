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
	_air.amount = 64
	_air.spread = 18.0


func _model_id() -> String:
	return "industrial_model"


## Soplador industrial: carcasa amarilla con bandas de aviso, doble toma de aire, motor grande,
## tubo ancho con boquilla abocinada.
func _model_parts() -> Array:
	var yellow := MeshFactory.pc(Color(0.84, 0.64, 0.12), MeshFactory.PAT_METAL)
	var grey := MeshFactory.pc(Color(0.22, 0.23, 0.25), MeshFactory.PAT_METAL)
	var black := MeshFactory.pc(Color(0.07, 0.07, 0.08), MeshFactory.PAT_PLAIN)
	var steel := MeshFactory.pc(Color(0.62, 0.64, 0.67), MeshFactory.PAT_METAL)
	var side := Basis(Vector3.BACK, PI * 0.5)
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	var p := []
	p.append(MeshFactory.part("box", Vector3(0, 0, 0.08), Vector3(0.19, 0.17, 0.32), yellow))
	p.append(MeshFactory.part("sph", Vector3(0, 0.075, 0.08), Vector3(0.19, 0.11, 0.32), yellow))
	for k in 3:
		p.append(MeshFactory.part("box", Vector3(0, 0.0, -0.04 + k * 0.09), Vector3(0.196, 0.176, 0.03), black))
	for sx in [-1.0, 1.0]:
		p.append(MeshFactory.part("cyl", Vector3(sx * 0.12, -0.01, 0.08), Vector3(0.24, 0.09, 0.24), grey, side))
		p.append(MeshFactory.part("cyl", Vector3(sx * 0.168, -0.01, 0.08), Vector3(0.18, 0.012, 0.18), black, side))
		for k in 4:
			p.append(MeshFactory.part("box", Vector3(sx * 0.174, -0.01, 0.08), Vector3(0.008, 0.18, 0.014), steel, Basis(Vector3.RIGHT, k * PI / 4.0)))
	p.append(MeshFactory.part("box", Vector3(0.0, -0.12, 0.15), Vector3(0.16, 0.1, 0.17), grey))
	for k in 4:
		p.append(MeshFactory.part("box", Vector3(0.0, -0.12, 0.08 + k * 0.045), Vector3(0.17, 0.11, 0.012), black))
	p.append(MeshFactory.part("box", Vector3(0, -0.17, 0.2), Vector3(0.045, 0.16, 0.055), black, Basis(Vector3.RIGHT, 0.25)))
	p.append(MeshFactory.part("box", Vector3(0, -0.12, 0.15), Vector3(0.02, 0.05, 0.03), MeshFactory.pc(Color(0.85, 0.2, 0.15), MeshFactory.PAT_PLAIN)))
	p.append(MeshFactory.part("box", Vector3(0, 0.13, 0.08), Vector3(0.035, 0.014, 0.22), black))
	p.append(MeshFactory.part("cyl", Vector3(0, -0.02, -0.28), Vector3(0.11, 0.52, 0.11), grey, along))
	for k in 4:
		p.append(MeshFactory.part("cyl", Vector3(0, -0.02, -0.08 - k * 0.04), Vector3(0.118, 0.02, 0.118), yellow if k % 2 == 0 else black, along))
	p.append([MeshFactory.cyl(0.055, 0.078, 0.1, 12), Transform3D(along, Vector3(0, -0.02, -0.58)), steel])
	p.append(MeshFactory.part("cyl", Vector3(0, -0.02, -0.635), Vector3(0.158, 0.02, 0.158), black, along))
	return p


func _power() -> float:
	return float(UpgradeManager.get_value("blower_power")) * 2.0 * float(UpgradeManager.get_value("industrial_power"))
