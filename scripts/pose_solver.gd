class_name PoseSolver
extends RefCounted
## MediaPipe pose (world landmarks) -> target rotations (skeleton space) for the VRM humanoid.
##
## Conventions
##  * Landmarks are converted to the AVATAR-LOCAL frame (x right, y up, z back):
##        local = (-mp.x, -mp.y, +mp.z)     (MediaPipe: x image-right, y down, z away; image is NOT mirrored)
##  * Mirror mode reflects x and swaps left/right landmarks, so the avatar behaves like a mirror.
##    Non-mirror mode keeps anatomy: the avatar's right arm follows the performer's right arm.
##  * Limbs are aimed with swing-only rotations from their rest direction (scale independent, no twist).
##    Torso / hips are solved from orthonormal frames, so they get yaw, pitch and roll.
##  * Segments that are not visible fade toward a relaxed idle pose instead of snapping.

# segment ids: 0 LUpperArm 1 LLowerArm 2 LHand 3 RUpperArm 4 RLowerArm 5 RHand
#              6 LUpperLeg 7 LLowerLeg 8 LFoot  9 RUpperLeg 10 RLowerLeg 11 RFoot
const SEG_COUNT := 12

var targets := {}   # vrm bone name -> Quaternion (global, skeleton space)

var _rig: AvatarRig
var _s: AppSettings
var _seg_f: Array = []
var _seg_w: Array = []
var _hips_f := OneEuro.Q.new()
var _sh_f := OneEuro.Q.new()
var _torso_w := 0.0
var _f: TrackingFrame
var _mirror := false
var _mc := 1.5
var _bt := 1.0


func _init(rig: AvatarRig, s: AppSettings) -> void:
	_rig = rig
	_s = s
	for i in SEG_COUNT:
		var f := OneEuro.V3.new()
		f.reset(_idle_dir(i))
		_seg_f.append(f)
		_seg_w.append(0.0)


static func _side(i: int) -> float:
	return -1.0 if (i < 3 or (i >= 6 and i < 9)) else 1.0


## Relaxed standing pose in avatar-local space (arms down, legs straight; forward = -z).
static func _idle_dir(i: int) -> Vector3:
	var k := _side(i)
	var t := i % 3
	if i < 6:
		if t == 0:
			return Vector3(k * 0.18, -0.98, -0.05).normalized()
		return Vector3(k * 0.10, -0.97, -0.20).normalized()
	if t == 0:
		return Vector3(k * 0.02, -1.0, 0.0).normalized()
	if t == 1:
		return Vector3(k * 0.01, -1.0, -0.02).normalized()
	return Vector3(0.0, -0.25, -0.97).normalized()


# ---- landmark access in avatar-local space ------------------------------------------------

func _idx(i: int) -> int:
	return SolverMath.swap_side(i) if _mirror else i


func _v(i: int) -> bool:
	return _f.pose_vis[_idx(i)] > 0.5


func _p(i: int) -> Vector3:
	var w: Vector3 = _f.pose_world[_idx(i)]
	var u := Vector3(-w.x, -w.y, w.z * _s.pose_depth_scale)
	if _mirror:
		u = SolverMath.mirror(u)
	return u


func _seg(id: int, ok: bool, measured: Vector3, idle: Vector3, dt: float) -> Vector3:
	var sf: OneEuro.V3 = _seg_f[id]
	if ok and measured.length_squared() > 1e-8:
		sf.filter(measured.normalized(), dt, _mc, _bt)
	_seg_w[id] = move_toward(float(_seg_w[id]), 1.0 if ok else 0.0, dt * 3.0)
	var last := sf.last()
	if last.length_squared() < 1e-6:
		last = idle
	return idle.normalized().slerp(last.normalized(), float(_seg_w[id])).normalized()


# ---- main entry ---------------------------------------------------------------------------

## f may be null (idle). head_local = absolute head orientation in the avatar-local frame from the face solver.
func solve(f: TrackingFrame, dt: float, head_valid: bool, head_local: Quaternion) -> void:
	dt = clampf(dt, 0.005, 0.25)
	_f = f
	_mirror = _s.mirror
	_mc = _s.body_min_cutoff
	_bt = _s.body_beta
	var body := f != null and f.pose_valid and _s.track_body

	# ---------------- torso ----------------
	var sh_ok := body and _v(11) and _v(12)
	var hip_ok := sh_ok and _v(23) and _v(24)
	var hips_l := Quaternion.IDENTITY
	var sh_l := Quaternion.IDENTITY
	if sh_ok:
		var up := Vector3.UP
		if hip_ok:
			up = (_p(11) + _p(12)) * 0.5 - (_p(23) + _p(24)) * 0.5
		sh_l = SolverMath.clamp_q(SolverMath.frame_q(_p(12) - _p(11), up), 70.0)
		if hip_ok:
			var hips_up := Vector3.UP.slerp(up.normalized(), 0.35)
			hips_l = SolverMath.clamp_q(SolverMath.frame_q(_p(24) - _p(23), hips_up), 60.0)
		sh_l = _sh_f.filter(sh_l, dt, _mc, _bt)
		hips_l = _hips_f.filter(hips_l, dt, _mc, _bt)
	_torso_w = move_toward(_torso_w, 1.0 if sh_ok else 0.0, dt * 2.5)
	var d_h := Quaternion.IDENTITY.slerp(hips_l, _torso_w)
	var d_s := Quaternion.IDENTITY.slerp(sh_l, _torso_w)

	_set("hips", d_h)
	_set("spine", d_h.slerp(d_s, 0.33))
	_set("chest", d_h.slerp(d_s, 0.66))
	_set("upperChest", d_s)

	# ---------------- head / neck ----------------
	var d_head := head_local if head_valid else d_s
	_set("neck", d_s.slerp(d_head, 0.4))
	_set("head", d_head)

	# ---------------- arms / legs ----------------
	_solve_arm(true, body, dt, d_s)
	_solve_arm(false, body, dt, d_s)
	var legs := body and _s.track_legs
	_solve_leg(true, legs, dt)
	_solve_leg(false, legs, dt)


func _solve_arm(left: bool, body: bool, dt: float, d_s: Quaternion) -> void:
	var sh := 11 if left else 12
	var el := sh + 2
	var wr := sh + 4
	var pk := sh + 6
	var ix := sh + 8
	var base := 0 if left else 3

	var ok_u := body and _v(sh) and _v(el)
	var ok_l := ok_u and _v(wr)
	var ok_h := ok_l and _v(pk) and _v(ix)

	var d_u := _seg(base, ok_u, (_p(el) - _p(sh)) if ok_u else Vector3.ZERO, _idle_dir(base), dt)
	var d_l := _seg(base + 1, ok_l, (_p(wr) - _p(el)) if ok_l else Vector3.ZERO, _idle_dir(base + 1), dt)
	var hm := ((_p(pk) + _p(ix)) * 0.5 - _p(wr)) if ok_h else Vector3.ZERO
	var d_h := _seg(base + 2, ok_h, hm, d_l, dt)

	var pre := "left" if left else "right"
	_aim(pre + "UpperArm", d_u)
	_aim(pre + "LowerArm", d_l)
	_aim(pre + "Hand", d_h)

	# raise the shoulder a little when the arm goes above horizontal
	var sname := pre + "Shoulder"
	if _rig.bones.has(sname) and _rig.bones[sname].has_dir:
		var sb: AvatarRig.Bone = _rig.bones[sname]
		var base_rot := _rig.delta_local(sb, d_s)
		var rest_now: Vector3 = _rig.frame_q * d_s * _rig.frame_q.inverse() * sb.rest_dir
		var w := clampf(d_u.y, 0.0, 1.0) * 0.35
		var lift_dir := rest_now.slerp(_rig.frame_q * d_u, w)
		targets[sname] = Quaternion(rest_now, lift_dir) * base_rot


func _solve_leg(left: bool, legs: bool, dt: float) -> void:
	var hp := 23 if left else 24
	var kn := hp + 2
	var an := hp + 4
	var ft := hp + 8
	var base := 6 if left else 9

	var ok_u := legs and _v(hp) and _v(kn)
	var ok_l := ok_u and _v(an)
	var ok_f := ok_l and _v(ft)

	var d_u := _seg(base, ok_u, (_p(kn) - _p(hp)) if ok_u else Vector3.ZERO, _idle_dir(base), dt)
	var d_l := _seg(base + 1, ok_l, (_p(an) - _p(kn)) if ok_l else Vector3.ZERO, _idle_dir(base + 1), dt)
	var d_f := _seg(base + 2, ok_f, (_p(ft) - _p(an)) if ok_f else Vector3.ZERO, _idle_dir(base + 2), dt)

	var pre := "left" if left else "right"
	_aim(pre + "UpperLeg", d_u)
	_aim(pre + "LowerLeg", d_l)
	_aim(pre + "Foot", d_f)


func _aim(bone_name: String, dir_local: Vector3) -> void:
	if _rig.bones.has(bone_name) and _rig.bones[bone_name].has_dir:
		targets[bone_name] = _rig.aim_local(_rig.bones[bone_name], dir_local)


func _set(bone_name: String, delta_local: Quaternion) -> void:
	if _rig.bones.has(bone_name):
		targets[bone_name] = _rig.delta_local(_rig.bones[bone_name], delta_local)
