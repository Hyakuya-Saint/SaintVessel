class_name SimTracking
extends RefCounted
## Synthetic performer for desktop testing: waves the performer's right arm, talks, blinks, turns the head.
## Built in the avatar-local convention (x right, y up, z back) and converted to MediaPipe space.

static func _to_mp(u: Vector3) -> Vector3:
	return Vector3(-u.x, -u.y, u.z)


static func fill(f: TrackingFrame, t: float) -> void:
	f.pose_valid = true
	f.face_valid = true
	f.img_w = 480.0
	f.img_h = 640.0

	var u := PackedVector3Array()
	u.resize(TrackingFrame.POSE_COUNT)
	var tw := Quaternion.from_euler(Vector3(0.0, deg_to_rad(sin(t * 0.7) * 18.0), 0.0))
	u[23] = Vector3(-0.10, 0.0, 0.0)
	u[24] = Vector3(0.10, 0.0, 0.0)
	u[11] = tw * Vector3(-0.20, 0.50, 0.0)
	u[12] = tw * Vector3(0.20, 0.50, 0.0)

	var wave := sin(t * 3.0)
	var l_el := Vector3(-0.15, -1.0, -0.05).normalized() * 0.28
	var l_wr := Vector3(-0.05, -1.0, -0.25).normalized() * 0.25
	var r_el := Vector3(0.7, 0.45, -0.15).normalized() * 0.28
	var r_wr := Vector3(0.15 + 0.35 * wave, 1.0, -0.1).normalized() * 0.25
	u[13] = u[11] + l_el
	u[15] = u[13] + l_wr
	u[14] = u[12] + r_el
	u[16] = u[14] + r_wr
	u[17] = u[15] + l_wr.normalized() * 0.07
	u[19] = u[15] + l_wr.normalized() * 0.08
	u[18] = u[16] + r_wr.normalized() * 0.07
	u[20] = u[16] + r_wr.normalized() * 0.08
	for side in 2:
		var x := -0.10 if side == 0 else 0.10
		var hip := 23 if side == 0 else 24
		u[hip + 2] = Vector3(x, -0.45, 0.0)
		u[hip + 4] = Vector3(x, -0.90, 0.0)
		u[hip + 8] = Vector3(x, -0.95, -0.12)
	for i in TrackingFrame.POSE_COUNT:
		f.pose_world[i] = _to_mp(u[i])
		f.pose_vis[i] = 0.0 if (i >= 25 and i <= 32) else 1.0   # legs "not visible"

	# ---- face mesh: canonical points rotated by a head pose, projected into image space
	var head := Quaternion.from_euler(Vector3(deg_to_rad(sin(t * 0.5) * 8.0),
			deg_to_rad(sin(t * 0.9) * 25.0), deg_to_rad(sin(t * 0.6) * 8.0)))
	var scale := 1600.0   # meters -> pixels
	var gx := sin(t * 0.8) * 0.004
	var blink_h := 0.0 if absf(sin(t * 1.3)) > 0.97 else 0.006
	var put := func(idx: int, local: Vector3) -> void:
		var raw: Vector3 = _to_mp(head * local) * scale
		f.face[idx] = Vector3(0.5 + raw.x / f.img_w, 0.4 + raw.y / f.img_h, raw.z / f.img_w)
	# eye group A (33/133/159/145/468) = performer's right, group B = left
	put.call(33, Vector3(0.045, 0.03, 0.0))
	put.call(133, Vector3(0.015, 0.03, 0.0))
	put.call(159, Vector3(0.030, 0.03 + blink_h, 0.0))
	put.call(145, Vector3(0.030, 0.03 - blink_h, 0.0))
	put.call(468, Vector3(0.030 + gx, 0.03, 0.0))
	put.call(263, Vector3(-0.045, 0.03, 0.0))
	put.call(362, Vector3(-0.015, 0.03, 0.0))
	put.call(386, Vector3(-0.030, 0.03 + blink_h, 0.0))
	put.call(374, Vector3(-0.030, 0.03 - blink_h, 0.0))
	put.call(473, Vector3(-0.030 + gx, 0.03, 0.0))
	put.call(10, Vector3(0.0, 0.09, 0.0))
	put.call(152, Vector3(0.0, -0.07, 0.0))

	f.blend.fill(0.0)
	var set_b := func(n: String, v: float) -> void:
		f.blend[TrackingFrame.blend_index(n)] = clampf(v, 0.0, 1.0)
	set_b.call("jawOpen", 0.35 + 0.35 * sin(t * 5.0))
	var smile := 0.5 + 0.5 * sin(t * 0.5)
	set_b.call("mouthSmileLeft", smile)
	set_b.call("mouthSmileRight", smile)
	var blink := 1.0 if blink_h == 0.0 else 0.0
	set_b.call("eyeBlinkLeft", blink)
	set_b.call("eyeBlinkRight", blink)
	set_b.call("browInnerUp", 0.3 + 0.3 * sin(t * 0.4))
