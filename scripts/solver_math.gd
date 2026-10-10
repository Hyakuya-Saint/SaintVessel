class_name SolverMath
extends RefCounted
## Shared helpers. The avatar-local frame used by the solvers is Godot-native:
##   x = avatar's right, y = up, z = BACK  (so forward = -z, and (x, y, z) is a proper right-handed rotation basis).

## Reflect across the avatar's own left/right plane.
static func mirror(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## Orientation from a "right" and an "up" hint, expressed in the avatar-local frame.
static func frame_q(right: Vector3, up: Vector3) -> Quaternion:
	if up.length_squared() < 1e-8:
		return Quaternion.IDENTITY
	up = up.normalized()
	right = right - up * right.dot(up)
	if right.length_squared() < 1e-8:
		return Quaternion.IDENTITY
	right = right.normalized()
	var back := right.cross(up)   # x cross y = z (back)
	return Basis(right, up, back).orthonormalized().get_rotation_quaternion()


static func clamp_q(q: Quaternion, max_deg: float) -> Quaternion:
	var ang := Quaternion.IDENTITY.angle_to(q)
	var lim := deg_to_rad(max_deg)
	if ang <= lim or ang < 1e-5:
		return q
	return Quaternion.IDENTITY.slerp(q, lim / ang)


## MediaPipe pose index of the opposite body side (nose stays; eyes unused).
static func swap_side(i: int) -> int:
	if i < 7:
		return i
	return i + 1 if (i & 1) == 1 else i - 1
