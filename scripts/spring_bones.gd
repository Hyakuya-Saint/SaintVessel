class_name SpringBones
extends RefCounted
## VRMC_springBone (VRM 1.0) simulated in GDScript, in skeleton space (hair, skirt, sleeves, bust ...).
## Verlet integration per segment: inertia (drag) + stiffness toward the animated pose + gravity, fixed segment length,
## sphere/capsule collider push-out. The last joint of a chain is only an end point (spec: it is not rotated).

class Joint extends RefCounted:
	var bone := -1
	var child := -1
	var hit_radius := 0.0
	var stiffness := 1.0
	var drag := 0.4
	var gravity_power := 0.0
	var gravity_dir := Vector3.DOWN   # world space as authored
	var rest_local_q := Quaternion.IDENTITY
	var rest_local_origin := Vector3.ZERO
	var axis_local := Vector3.DOWN
	var length := 0.05
	var cur := Vector3.ZERO
	var prev := Vector3.ZERO

class Collider extends RefCounted:
	var bone := -1
	var capsule := false
	var offset := Vector3.ZERO
	var tail := Vector3.ZERO
	var radius := 0.0
	var w0 := Vector3.ZERO
	var w1 := Vector3.ZERO

class Chain extends RefCounted:
	var joints: Array = []
	var colliders: Array = []   # Collider objects

var chains: Array = []
var colliders: Array = []
var _primed := false


func setup(skel: Skeleton3D, json: Dictionary, bone_for_node: Callable) -> void:
	var sb: Dictionary = json.get("extensions", {}).get("VRMC_springBone", {})
	if sb.is_empty():
		return

	for c in sb.get("colliders", []):
		var col := Collider.new()
		col.bone = bone_for_node.call(int(c.get("node", -1)))
		var shape: Dictionary = c.get("shape", {})
		if shape.has("sphere"):
			col.offset = _v3(shape["sphere"].get("offset", [0, 0, 0]))
			col.radius = float(shape["sphere"].get("radius", 0.0))
		elif shape.has("capsule"):
			col.capsule = true
			col.offset = _v3(shape["capsule"].get("offset", [0, 0, 0]))
			col.tail = _v3(shape["capsule"].get("tail", [0, 0, 0]))
			col.radius = float(shape["capsule"].get("radius", 0.0))
		colliders.append(col)

	var groups: Array = sb.get("colliderGroups", [])
	for sp in sb.get("springs", []):
		var chain := Chain.new()
		var jl: Array = sp.get("joints", [])
		for gi in sp.get("colliderGroups", []):
			if int(gi) < groups.size():
				for ci in groups[int(gi)].get("colliders", []):
					if int(ci) < colliders.size():
						chain.colliders.append(colliders[int(ci)])
		for k in range(jl.size() - 1):
			var jj: Dictionary = jl[k]
			var j := Joint.new()
			j.bone = bone_for_node.call(int(jj.get("node", -1)))
			j.child = bone_for_node.call(int(jl[k + 1].get("node", -1)))
			if j.bone < 0 or j.child < 0:
				continue
			j.hit_radius = float(jj.get("hitRadius", 0.0))
			j.stiffness = float(jj.get("stiffness", 1.0))
			j.drag = float(jj.get("dragForce", 0.5))
			j.gravity_power = float(jj.get("gravityPower", 0.0))
			j.gravity_dir = _v3(jj.get("gravityDir", [0, -1, 0]))
			var gj := skel.get_bone_global_rest(j.bone)
			var gc := skel.get_bone_global_rest(j.child)
			var d: Vector3 = gj.basis.orthonormalized().inverse() * (gc.origin - gj.origin)
			j.length = d.length()
			if j.length < 1e-5:
				continue
			j.axis_local = d / j.length
			var rest := skel.get_bone_rest(j.bone)
			j.rest_local_q = rest.basis.orthonormalized().get_rotation_quaternion()
			j.rest_local_origin = rest.origin
			chain.joints.append(j)
		if not chain.joints.is_empty():
			chains.append(chain)


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func reset() -> void:
	_primed = false


func step(skel: Skeleton3D, dt: float, use_collisions: bool) -> void:
	if chains.is_empty():
		return
	dt = clampf(dt, 0.001, 1.0 / 30.0)
	var g_basis := skel.global_transform.basis.orthonormalized().inverse()

	if use_collisions:
		for c in colliders:
			if c.bone < 0:
				continue
			var gp := skel.get_bone_global_pose(c.bone)
			c.w0 = gp * c.offset
			c.w1 = gp * c.tail

	for chain in chains:
		for j in chain.joints:
			var parent := skel.get_bone_parent(j.bone)
			var pg := skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
			var pq := pg.basis.orthonormalized().get_rotation_quaternion()
			var head: Vector3 = pg * j.rest_local_origin
			var base_q: Quaternion = pq * j.rest_local_q
			var axis_world: Vector3 = base_q * j.axis_local

			if not _primed:
				j.cur = head + axis_world * j.length
				j.prev = j.cur

			var grav: Vector3 = g_basis * j.gravity_dir
			var nxt: Vector3 = j.cur + (j.cur - j.prev) * (1.0 - j.drag) \
					+ axis_world * (j.stiffness * dt) + grav * (j.gravity_power * dt)
			nxt = head + (nxt - head).normalized() * j.length

			if use_collisions:
				for c in chain.colliders:
					var r: float = c.radius + j.hit_radius
					var center: Vector3 = c.w0
					if c.capsule:
						center = Geometry3D.get_closest_point_to_segment(nxt, c.w0, c.w1)
					var d: Vector3 = nxt - center
					var dist := d.length()
					if dist < r:
						nxt = center + d / maxf(dist, 1e-6) * r
						nxt = head + (nxt - head).normalized() * j.length

			j.prev = j.cur
			j.cur = nxt
			var dir := (nxt - head).normalized()
			var q := Quaternion(axis_world, dir) * base_q
			skel.set_bone_pose_rotation(j.bone, pq.inverse() * q)
	_primed = true
