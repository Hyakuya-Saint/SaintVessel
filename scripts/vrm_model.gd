class_name VrmModel
extends RefCounted
## Loads a VRM 1.0 (.vrm = binary glTF) at runtime with Godot's GLTFDocument and reads the VRMC_* extensions
## from the JSON chunk ourselves (humanoid map, expressions, look-at limits, spring bones, MToon parameters).
## No addon needed. Godot ignores the VRM extensions during import, so this class re-attaches them.

const TOON_SHADER := preload("res://shaders/mtoon_lite.gdshader")
const OUTLINE_SHADER := preload("res://shaders/mtoon_outline.gdshader")

var root: Node3D
var skeleton: Skeleton3D
var json: Dictionary = {}
var state: GLTFState
var humanoid := {}       # VRM humanoid bone name -> skeleton bone index
var expr_binds := {}     # preset name -> Array of {mesh, idx, weight}
var morph_lookup := {}   # blend-shape name -> Array of {mesh, idx}
var eye_limit_h := 12.0
var eye_limit_v := 10.0
var error := ""

var _acc := {}           # MeshInstance3D -> Array[float] accumulators


static func from_bytes(bytes: PackedByteArray, toon: bool) -> VrmModel:
	var m := VrmModel.new()
	m.json = _read_json(bytes)
	if m.json.is_empty():
		m.error = "Not a GLB/VRM file"
		return m
	if not m.json.get("extensions", {}).has("VRMC_vrm"):
		m.error = "Not a VRM 1.0 file (VRMC_vrm extension missing)"
		return m

	m.state = GLTFState.new()
	var doc := GLTFDocument.new()
	var err := doc.append_from_buffer(bytes, "", m.state)
	if err != OK:
		m.error = "glTF import failed (error %d)" % err
		return m
	var scene := doc.generate_scene(m.state)
	if scene == null or not (scene is Node3D):
		m.error = "glTF scene generation failed"
		return m
	m.root = scene as Node3D
	m._build(toon)
	return m


static func _read_json(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 20 or bytes.decode_u32(0) != 0x46546C67:   # "glTF"
		return {}
	var chunk_len := bytes.decode_u32(12)
	if bytes.decode_u32(16) != 0x4E4F534A:                       # "JSON"
		return {}
	var parsed = JSON.parse_string(bytes.slice(20, 20 + chunk_len).get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


func _build(toon: bool) -> void:
	var vrm: Dictionary = json["extensions"]["VRMC_vrm"]
	var nodes: Array = json.get("nodes", [])
	var hb: Dictionary = vrm.get("humanoid", {}).get("humanBones", {})

	# the skeleton that owns the hips
	var hips_name := ""
	if hb.has("hips"):
		hips_name = String(nodes[int(hb["hips"]["node"])].get("name", ""))
	skeleton = _find_skeleton(root, hips_name)
	if skeleton == null:
		error = "No Skeleton3D found in the imported VRM"
		return

	for key in hb:
		var bi := bone_for_node(int(hb[key]["node"]))
		if bi >= 0:
			humanoid[key] = bi

	# ---- blend shapes by name (glTF extras.targetNames) and VRM expression binds
	for i in nodes.size():
		if not nodes[i].has("mesh"):
			continue
		var mi := state.get_scene_node(i) as MeshInstance3D
		if mi == null:
			continue
		var names: Array = json["meshes"][int(nodes[i]["mesh"])].get("extras", {}).get("targetNames", [])
		for k in names.size():
			var key := String(names[k])
			if not morph_lookup.has(key):
				morph_lookup[key] = []
			morph_lookup[key].append({"mesh": mi, "idx": k})
			_ensure(mi)

	var preset: Dictionary = vrm.get("expressions", {}).get("preset", {})
	for pname in preset:
		var list := []
		for b in preset[pname].get("morphTargetBinds", []):
			var mi := state.get_scene_node(int(b["node"])) as MeshInstance3D
			if mi == null:
				continue
			list.append({"mesh": mi, "idx": int(b["index"]), "weight": float(b.get("weight", 1.0))})
			_ensure(mi)
		expr_binds[pname] = list

	var la: Dictionary = vrm.get("lookAt", {})
	if la.has("rangeMapHorizontalOuter"):
		eye_limit_h = float(la["rangeMapHorizontalOuter"].get("outputScale", 12.0))
	if la.has("rangeMapVerticalUp"):
		eye_limit_v = float(la["rangeMapVerticalUp"].get("outputScale", 10.0))

	if toon:
		_apply_toon()


func bone_for_node(node_index: int) -> int:
	var nodes: Array = json.get("nodes", [])
	if node_index < 0 or node_index >= nodes.size() or skeleton == null:
		return -1
	return skeleton.find_bone(String(nodes[node_index].get("name", "")))


static func _find_skeleton(n: Node, hips_name: String) -> Skeleton3D:
	if n is Skeleton3D and (hips_name == "" or (n as Skeleton3D).find_bone(hips_name) >= 0):
		return n
	for c in n.get_children():
		var r := _find_skeleton(c, hips_name)
		if r != null:
			return r
	return null


# ------------------------------------------------------------------ morph accumulation

func _ensure(mi: MeshInstance3D) -> void:
	if _acc.has(mi):
		return
	var a := []
	a.resize(maxi(mi.get_blend_shape_count(), 1))
	a.fill(0.0)
	_acc[mi] = a


func begin_morphs() -> void:
	for mi in _acc:
		_acc[mi].fill(0.0)


func add_expression(preset: String, w: float) -> void:
	if w <= 0.0001 or not expr_binds.has(preset):
		return
	for b in expr_binds[preset]:
		var a: Array = _acc[b["mesh"]]
		if b["idx"] < a.size():
			a[b["idx"]] += w * b["weight"]


func add_morph_named(morph: String, w: float) -> void:
	if w <= 0.0001 or not morph_lookup.has(morph):
		return
	for e in morph_lookup[morph]:
		var a: Array = _acc[e["mesh"]]
		if e["idx"] < a.size():
			a[e["idx"]] += w


func end_morphs() -> void:
	for mi in _acc:
		var a: Array = _acc[mi]
		for i in a.size():
			mi.set_blend_shape_value(i, clampf(a[i], 0.0, 1.0))


# ------------------------------------------------------------------ materials

func _mesh_instances(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_mesh_instances(c, out)


func _apply_toon() -> void:
	var by_name := {}
	var first := {}
	for jm in json.get("materials", []):
		if first.is_empty():
			first = jm
		by_name[String(jm.get("name", ""))] = jm
	var meshes := []
	_mesh_instances(root, meshes)
	for mi in meshes:
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(si)
			if src == null:
				continue
			var jm: Dictionary = by_name.get(src.resource_name, first)
			mi.set_surface_override_material(si, _make_toon(src, jm))


func _texture_by_index(tex_index: int) -> Texture2D:
	var texs: Array = state.get_textures()
	var imgs: Array = state.get_images()
	if tex_index < 0 or tex_index >= texs.size():
		return null
	var si: int = texs[tex_index].get_src_image()
	if si < 0 or si >= imgs.size():
		return null
	return imgs[si] as Texture2D


func _make_toon(src: Material, jm: Dictionary) -> Material:
	var mt: Dictionary = jm.get("extensions", {}).get("VRMC_materials_mtoon", {})
	var sm := ShaderMaterial.new()
	sm.shader = TOON_SHADER

	var base := Color.WHITE
	if src is BaseMaterial3D:
		sm.set_shader_parameter("albedo_tex", src.albedo_texture)
		base = src.albedo_color
	sm.set_shader_parameter("base_color", base)

	var sc: Array = mt.get("shadeColorFactor", [0.78, 0.74, 0.80])
	var shade := Color(float(sc[0]), float(sc[1]), float(sc[2])).linear_to_srgb()
	sm.set_shader_parameter("shade_color", shade)
	var st: Dictionary = mt.get("shadeMultiplyTexture", {})
	if st.has("index"):
		var tex := _texture_by_index(int(st["index"]))
		if tex != null:
			sm.set_shader_parameter("shade_tex", tex)
			sm.set_shader_parameter("use_shade_tex", true)
	sm.set_shader_parameter("shading_shift", float(mt.get("shadingShiftFactor", -0.05)))
	sm.set_shader_parameter("shading_toony", float(mt.get("shadingToonyFactor", 0.9)))
	var cutoff := float(jm.get("alphaCutoff", 0.5)) if String(jm.get("alphaMode", "OPAQUE")) != "OPAQUE" else 0.0
	sm.set_shader_parameter("alpha_cutoff", cutoff)

	var mode := String(mt.get("outlineWidthMode", "none"))
	var width := float(mt.get("outlineWidthFactor", 0.0))
	if mode != "none" and width > 0.0:
		var om := ShaderMaterial.new()
		om.shader = OUTLINE_SHADER
		om.set_shader_parameter("albedo_tex", sm.get_shader_parameter("albedo_tex"))
		om.set_shader_parameter("base_color", base)
		om.set_shader_parameter("alpha_cutoff", cutoff)
		om.set_shader_parameter("outline_width", maxf(width * 1.5, 0.0006))
		var oc: Array = mt.get("outlineColorFactor", [0.1, 0.08, 0.1])
		om.set_shader_parameter("outline_color", Color(float(oc[0]), float(oc[1]), float(oc[2])).linear_to_srgb())
		sm.next_pass = om
	return sm
