class_name AvatarDriver
extends Node3D
## Loads Saint.vrm (or any .vrm in user://models) at runtime and drives it from tracking data.

const MODEL_RES := "res://models/Saint.vrm"
const MODEL_DIR := "user://models"
const ORDER := [
	"hips", "spine", "chest", "upperChest", "leftShoulder", "rightShoulder", "neck", "head",
	"leftUpperArm", "leftLowerArm", "leftHand", "rightUpperArm", "rightLowerArm", "rightHand",
	"leftUpperLeg", "leftLowerLeg", "leftFoot", "rightUpperLeg", "rightLowerLeg", "rightFoot",
]
const FINGERS := [
	["Index", ["Proximal", "Intermediate", "Distal"]],
	["Middle", ["Proximal", "Intermediate", "Distal"]],
	["Ring", ["Proximal", "Intermediate", "Distal"]],
	["Little", ["Proximal", "Intermediate", "Distal"]],
	["Thumb", ["Metacarpal", "Proximal", "Distal"]],
]

var load_status := "Loading avatar..."
var ready_ok := false

var _s: AppSettings
var _tracking: TrackingService
var _env: EnvironmentCtl
var _model: VrmModel
var _rig: AvatarRig
var _pose: PoseSolver
var _face: FaceSolver
var _springs: SpringBones
var _facing_local := Vector3(0, 0, 1)   # avatar facing, expressed in this holder's space

var _cur := {}
var _last_arrival := 0.0
var _last_frame_t := 0.0
var _idle_accum := 0.0
var _next_blink := 3.0
var _blink_t := -1.0

# smoothed face outputs
var _bl := 0.0
var _br := 0.0
var _aa := 0.0
var _ih := 0.0
var _ou := 0.0
var _ee := 0.0
var _oh := 0.0
var _hp := 0.0
var _an := 0.0
var _sa := 0.0
var _su := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _morph := {}


func facing_world() -> Vector3:
	return global_transform.basis * _facing_local


func init_driver(s: AppSettings, tracking: TrackingService, env: EnvironmentCtl) -> void:
	_s = s
	_tracking = tracking
	_env = env
	_load()


# ------------------------------------------------------------------ loading

func _load() -> void:
	await get_tree().process_frame
	await get_tree().process_frame   # let "Loading..." render before the one-time import hitch
	var bytes := _read_model_bytes()
	if bytes.is_empty():
		load_status = "Avatar file not found"
		return
	load_status = "Parsing VRM..."
	_model = VrmModel.from_bytes(bytes, _s.toon_shader)
	if _model.error != "":
		load_status = "Avatar load failed: " + _model.error
		push_error(load_status)
		return

	add_child(_model.root)
	_rig = AvatarRig.new(_model.skeleton, _model.humanoid)
	_pose = PoseSolver.new(_rig, _s)
	_face = FaceSolver.new(_s)
	_springs = SpringBones.new()
	_springs.setup(_model.skeleton, _model.json, Callable(_model, "bone_for_node"))

	# facing direction (skeleton space -> holder space), measured before any yaw is applied
	var to_holder := global_transform.basis.inverse() * _model.skeleton.global_transform.basis
	_facing_local = (to_holder * _rig.forward_skel).normalized()

	load_status = "Ready"
	ready_ok = true


func _read_model_bytes() -> PackedByteArray:
	if DirAccess.dir_exists_absolute(MODEL_DIR):
		var files := Array(DirAccess.get_files_at(MODEL_DIR)).filter(func(n): return String(n).to_lower().ends_with(".vrm"))
		files.sort()
		if not files.is_empty():
			load_status = "Loading " + String(files[0])
			return FileAccess.get_file_as_bytes(MODEL_DIR + "/" + String(files[0]))
	load_status = "Loading Saint.vrm"
	return FileAccess.get_file_as_bytes(MODEL_RES)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not ready_ok:
		return
	scale = Vector3.ONE * _s.avatar_scale
	_model.root.rotation_degrees.y = _s.avatar_yaw

	if _tracking.consume_new():
		var now := Time.get_ticks_msec() / 1000.0
		var dt := clampf(now - _last_arrival, 0.008, 0.25)
		_last_arrival = now
		_last_frame_t = now
		_face.solve(_tracking.frame, dt)
		_pose.solve(_tracking.frame, dt, _face.state.valid, _face.state.head_local)
	elif Time.get_ticks_msec() / 1000.0 - _last_frame_t > 0.5:
		# tracking lost / camera off: relax to an idle pose
		_idle_accum += delta
		if _idle_accum >= 1.0 / 30.0:
			_face.relax(_idle_accum)
			_pose.solve(null, _idle_accum, false, Quaternion.IDENTITY)
			_idle_accum = 0.0

	_apply_bones(delta)
	_apply_face(delta)
	if _s.spring_bones:
		_springs.step(_model.skeleton, delta, _s.spring_collisions)
	else:
		_springs.reset()
	_env.frame(global_position, facing_world())


func _apply_bones(delta: float) -> void:
	var a := 1.0 - exp(-_s.follow_speed * delta)
	for n in ORDER:
		if not _rig.bones.has(n) or not _pose.targets.has(n):
			continue
		var tgt: Quaternion = _pose.targets[n]
		var cur: Quaternion = _cur.get(n, tgt)
		cur = cur.slerp(tgt, a)
		_cur[n] = cur
		_rig.apply_global(_rig.bones[n].idx, cur)
	_apply_fingers()
	_apply_eyes()


## Relaxed finger curl (the pose model does not track fingers).
func _apply_fingers() -> void:
	var rad := deg_to_rad(_s.finger_curl_deg)
	for side in ["left", "right"]:
		for f in FINGERS:
			var k := 0.5 if f[0] == "Thumb" else 1.0
			for part in f[1]:
				var n: String = side + f[0] + part
				if not _rig.bones.has(n):
					continue
				var b: AvatarRig.Bone = _rig.bones[n]
				if not b.has_dir:
					continue
				var axis := b.rest_dir.cross(Vector3.DOWN)
				if axis.length_squared() < 1e-6:
					continue
				var angle := minf(rad * k, b.rest_dir.angle_to(Vector3.DOWN))
				_rig.apply_relative_world(b, Quaternion(axis.normalized(), angle))


func _apply_eyes() -> void:
	var yaw := clampf(_yaw * 0.3, -_model.eye_limit_h, _model.eye_limit_h)
	var pitch := clampf(_pitch * 0.3, -_model.eye_limit_v, _model.eye_limit_v)
	# local frame: looking right = rotate forward (-z) toward +x = rotation about +y by -yaw; looking up = about +x by +pitch
	var d := Quaternion(Vector3.UP, -deg_to_rad(yaw)) * Quaternion(Vector3.RIGHT, deg_to_rad(pitch))
	for n in ["leftEye", "rightEye"]:
		if _rig.bones.has(n):
			_rig.apply_relative_local(_rig.bones[n], d)


func _apply_face(delta: float) -> void:
	var st := _face.state
	var a := 1.0 - exp(-(_s.follow_speed * 1.6) * delta)

	var blink_l := st.blink_l
	var blink_r := st.blink_r
	if not st.valid and _s.idle_blink:
		_next_blink -= delta
		if _next_blink <= 0.0:
			_blink_t = 0.0
			_next_blink = randf_range(2.5, 5.5)
		if _blink_t >= 0.0:
			_blink_t += delta
			var v := sin(clampf(_blink_t / 0.16, 0.0, 1.0) * PI)
			blink_l = v
			blink_r = v
			if _blink_t > 0.16:
				_blink_t = -1.0

	var ab := maxf(a, 0.6)
	_bl = lerpf(_bl, blink_l, ab)
	_br = lerpf(_br, blink_r, ab)
	_aa = lerpf(_aa, st.aa, a)
	_ih = lerpf(_ih, st.ih, a)
	_ou = lerpf(_ou, st.ou, a)
	_ee = lerpf(_ee, st.ee, a)
	_oh = lerpf(_oh, st.oh, a)
	_hp = lerpf(_hp, st.happy, a)
	_an = lerpf(_an, st.angry, a)
	_sa = lerpf(_sa, st.sad, a)
	_su = lerpf(_su, st.surprised, a)
	_yaw = lerpf(_yaw, st.gaze_yaw, a)
	_pitch = lerpf(_pitch, st.gaze_pitch, a)

	_model.begin_morphs()
	_model.add_expression("blinkLeft", _bl)
	_model.add_expression("blinkRight", _br)
	_model.add_expression("aa", _aa)
	_model.add_expression("ih", _ih)
	_model.add_expression("ou", _ou)
	_model.add_expression("ee", _ee)
	_model.add_expression("oh", _oh)
	_model.add_expression("happy", _hp)
	_model.add_expression("angry", _an)
	_model.add_expression("sad", _sa)
	_model.add_expression("surprised", _su)

	# direct VRoid morph targets: brows, and a smile shape that does not close the eyes
	var targets := {
		"Fcl_BRW_Angry": st.brow_angry, "Fcl_BRW_Surprised": st.brow_surprised,
		"Fcl_BRW_Sorrow": st.brow_sorrow, "Fcl_BRW_Joy": st.brow_joy,
		"Fcl_BRW_Fun": st.brow_fun, "Fcl_MTH_Joy": st.mth_joy,
	}
	for k in targets:
		_morph[k] = lerpf(float(_morph.get(k, 0.0)), float(targets[k]), a)
		_model.add_morph_named(k, _morph[k])
	_model.end_morphs()
