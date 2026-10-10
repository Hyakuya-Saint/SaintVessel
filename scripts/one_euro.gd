class_name OneEuro
extends RefCounted
## One Euro filter (Casiez et al.): strong smoothing when still, low lag when moving fast.

static func alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (2.0 * PI * maxf(cutoff, 0.001))
	return 1.0 / (1.0 + tau / dt)


class F1 extends RefCounted:
	var x := 0.0
	var dx := 0.0
	var primed := false

	func reset(v: float) -> void:
		x = v
		dx = 0.0
		primed = true

	func filter(v: float, dt: float, min_cutoff: float, beta: float) -> float:
		dt = maxf(dt, 0.0001)
		if not primed:
			reset(v)
			return v
		var d := (v - x) / dt
		dx = lerpf(dx, d, OneEuro.alpha(1.0, dt))
		var cutoff := min_cutoff + beta * absf(dx)
		x = lerpf(x, v, OneEuro.alpha(cutoff, dt))
		return x


class V3 extends RefCounted:
	var fx := OneEuro.F1.new()
	var fy := OneEuro.F1.new()
	var fz := OneEuro.F1.new()

	func reset(v: Vector3) -> void:
		fx.reset(v.x)
		fy.reset(v.y)
		fz.reset(v.z)

	func last() -> Vector3:
		return Vector3(fx.x, fy.x, fz.x)

	func filter(v: Vector3, dt: float, min_cutoff: float, beta: float) -> Vector3:
		return Vector3(fx.filter(v.x, dt, min_cutoff, beta),
				fy.filter(v.y, dt, min_cutoff, beta),
				fz.filter(v.z, dt, min_cutoff, beta))


## Angular-speed driven smoothing for rotations.
class Q extends RefCounted:
	var q := Quaternion.IDENTITY
	var speed := 0.0
	var primed := false

	func filter(target: Quaternion, dt: float, min_cutoff: float, beta: float) -> Quaternion:
		dt = maxf(dt, 0.0001)
		if not primed:
			primed = true
			q = target
			return q
		var sp := q.angle_to(target) / dt
		speed = lerpf(speed, sp, OneEuro.alpha(1.0, dt))
		var cutoff := min_cutoff + beta * speed
		q = q.slerp(target, OneEuro.alpha(cutoff, dt))
		return q
