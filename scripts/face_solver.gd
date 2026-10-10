class_name FaceSolver
extends RefCounted
## MediaPipe face landmarks + ARKit-style blendshapes -> VRM expressions, head orientation and gaze.
## Head pose and gaze use mesh landmarks (side-agnostic: eyes are classified by image x),
## mouth / brows / blink use the 52 blendshapes.

## Everything the face tracker drives, already smoothed. Left/Right refer to the AVATAR's sides.
class State extends RefCounted:
	var valid := false
	var head_local := Quaternion.IDENTITY     # absolute, avatar-local frame
	var blink_l := 0.0
	var blink_r := 0.0
	var aa := 0.0
	var ih := 0.0
	var ou := 0.0
	var ee := 0.0
	var oh := 0.0
	var happy := 0.0
	var angry := 0.0
	var sad := 0.0
	var surprised := 0.0
	var brow_angry := 0.0
	var brow_surprised := 0.0
	var brow_sorrow := 0.0
	var brow_joy := 0.0
	var brow_fun := 0.0
	var mth_joy := 0.0
	var gaze_yaw := 0.0     # degrees, + = avatar's right
	var gaze_pitch := 0.0   # degrees, + = up

var state := State.new()

# landmark groups: outer corner, inner corner, upper lid, lower lid, iris centre
const EYE_A := [33, 133, 159, 145, 468]
const EYE_B := [263, 362, 386, 374, 473]
const FOREHEAD := 10
const CHIN := 152
const NAMES := ["jawOpen", "mouthFunnel", "mouthPucker", "mouthSmileLeft", "mouthSmileRight", "mouthStretchLeft",
		"mouthStretchRight", "mouthFrownLeft", "mouthFrownRight", "eyeBlinkLeft", "eyeBlinkRight", "eyeWideLeft",
		"eyeWideRight", "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
		"noseSneerLeft", "noseSneerRight", "cheekSquintLeft", "cheekSquintRight"]

var _s: AppSettings
var _f: TrackingFrame
var _ix := {}
var _c: Array = []
var _head_f := OneEuro.Q.new()
var _yaw := 0.0
var _pitch := 0.0


func _init(s: AppSettings) -> void:
	_s = s
	for n in NAMES:
		_ix[n] = TrackingFrame.blend_index(n)
	for i in 24:
		_c.append(OneEuro.F1.new())


func _b(n: String) -> float:
	return _f.blend[_ix[n]]


func _fl(c: int, v: float, dt: float, k := 1.0) -> float:
	return _c[c].filter(v, dt, _s.face_min_cutoff * k, _s.face_beta * k)


## Face lost: fade everything back to neutral.
func relax(dt: float) -> void:
	state.valid = false
	var d := exp(-6.0 * dt)
	state.blink_l *= d
	state.blink_r *= d
	state.aa *= d
	state.ih *= d
	state.ou *= d
	state.ee *= d
	state.oh *= d
	state.happy *= d
	state.angry *= d
	state.sad *= d
	state.surprised *= d
	state.brow_angry *= d
	state.brow_surprised *= d
	state.brow_sorrow *= d
	state.brow_joy *= d
	state.brow_fun *= d
	state.mth_joy *= d
	state.gaze_yaw *= d
	state.gaze_pitch *= d


func solve(f: TrackingFrame, dt: float) -> void:
	if f == null or not f.face_valid or not _s.track_face:
		relax(dt)
		return
	dt = clampf(dt, 0.005, 0.25)
	_f = f
	state.valid = true
	var mirror := _s.mirror
	var W := f.img_w
	var H := f.img_h

	# ---------------- head orientation from the mesh ----------------
	# local frame: x = performer's right (= -image x), y = up (= -image y), z = back (= +depth)
	var raw := func(i: int) -> Vector3:
		var p: Vector3 = f.face[i]
		return Vector3(p.x * W, p.y * H, p.z * W)
	var user := func(i: int) -> Vector3:
		var r: Vector3 = raw.call(i)
		return Vector3(-r.x, -r.y, r.z)

	# In the unmirrored camera image the performer's RIGHT eye is on the image's left (smaller x).
	var a_x: float = raw.call(EYE_A[0]).x + raw.call(EYE_A[1]).x
	var b_x: float = raw.call(EYE_B[0]).x + raw.call(EYE_B[1]).x
	var right_eye: Array = EYE_A if a_x < b_x else EYE_B
	var left_eye: Array = EYE_B if a_x < b_x else EYE_A

	var r_pt: Vector3 = user.call(right_eye[0])
	var l_pt: Vector3 = user.call(left_eye[0])
	var fore: Vector3 = user.call(FOREHEAD)
	var chin: Vector3 = user.call(CHIN)
	if mirror:
		var r2 := SolverMath.mirror(l_pt)
		var l2 := SolverMath.mirror(r_pt)
		r_pt = r2
		l_pt = l2
		fore = SolverMath.mirror(fore)
		chin = SolverMath.mirror(chin)
	var head := SolverMath.clamp_q(SolverMath.frame_q(r_pt - l_pt, fore - chin), 75.0)
	state.head_local = _head_f.filter(head, dt, _s.face_min_cutoff, _s.face_beta)

	# ---------------- blink ----------------
	var b_user_l := inverse_lerp(0.15, 0.60, _b("eyeBlinkLeft"))
	var b_user_r := inverse_lerp(0.15, 0.60, _b("eyeBlinkRight"))
	var b_l := b_user_r if mirror else b_user_l   # avatar's left eye
	var b_r := b_user_l if mirror else b_user_r
	if _s.swap_eyes:
		var t := b_l
		b_l = b_r
		b_r = t
	state.blink_l = _fl(0, clampf(b_l, 0.0, 1.0), dt, 4.0)
	state.blink_r = _fl(1, clampf(b_r, 0.0, 1.0), dt, 4.0)

	# ---------------- mouth visemes (heuristic mapping tuned for VRoid's A/I/U/E/O) ----------------
	var jaw := _b("jawOpen")
	var fun := _b("mouthFunnel")
	var puck := _b("mouthPucker")
	var smile := (_b("mouthSmileLeft") + _b("mouthSmileRight")) * 0.5
	var stretch := (_b("mouthStretchLeft") + _b("mouthStretchRight")) * 0.5
	var open := clampf(jaw * 1.5 * _s.mouth_gain, 0.0, 1.0)
	var rounded := maxf(fun, puck)

	var aa := open * (1.0 - 0.8 * rounded) * (1.0 - 0.4 * smile)
	var oh := clampf(fun * 1.6 * _s.mouth_gain, 0.0, 1.0) * lerpf(0.5, 1.0, open)
	var ou := clampf(puck * 1.6 * _s.mouth_gain, 0.0, 1.0) * lerpf(0.5, 1.0, open)
	var ee := clampf(smile * 1.2 + stretch * 1.2, 0.0, 1.0) * (1.0 - 0.5 * open) * (1.0 - rounded)
	var ih := clampf(stretch * 1.5 - smile * 0.3, 0.0, 1.0) * lerpf(0.4, 1.0, open) * (1.0 - rounded)
	var total := aa + ih + ou + ee + oh
	if total > 1.0:
		aa /= total
		ih /= total
		ou /= total
		ee /= total
		oh /= total
	state.aa = _fl(2, aa, dt, 2.0)
	state.ih = _fl(3, ih, dt, 2.0)
	state.ou = _fl(4, ou, dt, 2.0)
	state.ee = _fl(5, ee, dt, 2.0)
	state.oh = _fl(6, oh, dt, 2.0)

	# ---------------- brows / emotions ----------------
	var brow_down := (_b("browDownLeft") + _b("browDownRight")) * 0.5
	var brow_outer := (_b("browOuterUpLeft") + _b("browOuterUpRight")) * 0.5
	var inner := _b("browInnerUp")
	var wide := (_b("eyeWideLeft") + _b("eyeWideRight")) * 0.5
	var frown := (_b("mouthFrownLeft") + _b("mouthFrownRight")) * 0.5
	var sneer := (_b("noseSneerLeft") + _b("noseSneerRight")) * 0.5
	var cheek := (_b("cheekSquintLeft") + _b("cheekSquintRight")) * 0.5
	var g := _s.brow_gain
	var e := _s.emotion_strength

	state.brow_angry = _fl(7, clampf((brow_down * 1.6 - inner * 0.5) * g, 0.0, 1.0), dt)
	state.brow_surprised = _fl(8, clampf((brow_outer * 1.6 + wide * 0.6) * g, 0.0, 1.0), dt)
	state.brow_sorrow = _fl(9, clampf((inner * 1.5 - brow_outer) * g, 0.0, 1.0), dt)
	state.brow_joy = _fl(10, clampf(smile * 0.6 * g, 0.0, 1.0), dt)
	state.brow_fun = _fl(11, 0.0, dt)
	state.mth_joy = _fl(12, clampf((smile - 0.1) * 1.5, 0.0, 1.0), dt)

	state.happy = _fl(13, clampf((smile - 0.55) * 3.0 + cheek * 0.2, 0.0, 1.0) * e, dt)
	state.surprised = _fl(14, clampf((brow_outer * 0.6 + wide * 0.8 + jaw * 0.5 - 0.6) * 2.2, 0.0, 1.0) * e, dt)
	state.angry = _fl(15, clampf((brow_down + sneer * 0.5 - 0.5) * 2.5, 0.0, 1.0) * e, dt)
	state.sad = _fl(16, clampf((inner * 0.8 + frown - 0.55) * 2.5, 0.0, 1.0) * e, dt)

	# ---------------- gaze from the iris landmarks ----------------
	if maxf(state.blink_l, state.blink_r) < 0.5:
		var o := (_eye_offset(EYE_A) + _eye_offset(EYE_B)) * 0.5   # image coords, +x right, +y down
		var yaw_user := -o.x * _s.gaze_gain                          # image-left = performer's right
		var pitch_up := -o.y * _s.gaze_gain
		if mirror:
			yaw_user = -yaw_user
		if _s.invert_gaze_yaw:
			yaw_user = -yaw_user
		if _s.invert_gaze_pitch:
			pitch_up = -pitch_up
		_yaw = _fl(17, clampf(yaw_user, -45.0, 45.0), dt)
		_pitch = _fl(18, clampf(pitch_up, -30.0, 30.0), dt)
	state.gaze_yaw = _yaw
	state.gaze_pitch = _pitch


func _eye_offset(e: Array) -> Vector2:
	var px := func(i: int) -> Vector2:
		return Vector2(_f.face[i].x * _f.img_w, _f.face[i].y * _f.img_h)
	var outer: Vector2 = px.call(e[0])
	var inner: Vector2 = px.call(e[1])
	var up: Vector2 = px.call(e[2])
	var lo: Vector2 = px.call(e[3])
	var iris: Vector2 = px.call(e[4])
	var w := outer.distance_to(inner)
	if w < 0.001:
		return Vector2.ZERO
	var c := (outer + inner) * 0.5
	return Vector2((iris.x - c.x) / w, (iris.y - (up.y + lo.y) * 0.5) / w)
