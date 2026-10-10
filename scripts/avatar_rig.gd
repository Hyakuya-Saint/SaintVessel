class_name AvatarRig
extends RefCounted
## Rest-pose data for driving a VRM 1.0 humanoid inside a Godot Skeleton3D.
##
## VRoid exports bones whose local axes are NOT aligned (Saint's hips carry ~7 deg on X, arms/shoulders carry small
## Z/Y rotations). So we never assume "identity = T-pose". For every humanoid bone we store its GLOBAL rest rotation
## and its rest direction (bone -> child), and always express targets as
##     target_global = delta_in_skeleton_space * rest_global
## then convert to a local pose using the parent's current global rotation. This is the same trick as UniVRM's
## "normalized rig", done by hand.
##
## Everything lives in SKELETON space. The avatar-local frame (x right, y up, z back) is mapped into it by frame_q,
## which is measured from the leg layout, so we never have to guess whether the model faces +Z or -Z.

class Bone extends RefCounted:
	var name := ""
	var idx := -1
	var rest_rot := Quaternion.IDENTITY     # global rest rotation, skeleton space
	var rest_local := Quaternion.IDENTITY   # local rest rotation
	var rest_dir := Vector3.ZERO            # bone -> child, skeleton space
	var has_dir := false

# bone -> bones whose position defines its rest direction (first existing candidate wins)
const CHILD := {
	"spine": ["chest"],
	"chest": ["upperChest", "neck"],
	"upperChest": ["neck"],
	"neck": ["head"],
	"leftShoulder": ["leftUpperArm"], "rightShoulder": ["rightUpperArm"],
	"leftUpperArm": ["leftLowerArm"], "leftLowerArm": ["leftHand"],
	"leftHand": ["leftMiddleProximal", "leftIndexProximal"],
	"rightUpperArm": ["rightLowerArm"], "rightLowerArm": ["rightHand"],
	"rightHand": ["rightMiddleProximal", "rightIndexProximal"],
	"leftUpperLeg": ["leftLowerLeg"], "leftLowerLeg": ["leftFoot"], "leftFoot": ["leftToes"],
	"rightUpperLeg": ["rightLowerLeg"], "rightLowerLeg": ["rightFoot"], "rightFoot": ["rightToes"],
	"leftThumbMetacarpal": ["leftThumbProximal"], "leftThumbProximal": ["leftThumbDistal"],
	"leftIndexProximal": ["leftIndexIntermediate"], "leftIndexIntermediate": ["leftIndexDistal"],
	"leftMiddleProximal": ["leftMiddleIntermediate"], "leftMiddleIntermediate": ["leftMiddleDistal"],
	"leftRingProximal": ["leftRingIntermediate"], "leftRingIntermediate": ["leftRingDistal"],
	"leftLittleProximal": ["leftLittleIntermediate"], "leftLittleIntermediate": ["leftLittleDistal"],
	"rightThumbMetacarpal": ["rightThumbProximal"], "rightThumbProximal": ["rightThumbDistal"],
	"rightIndexProximal": ["rightIndexIntermediate"], "rightIndexIntermediate": ["rightIndexDistal"],
	"rightMiddleProximal": ["rightMiddleIntermediate"], "rightMiddleIntermediate": ["rightMiddleDistal"],
	"rightRingProximal": ["rightRingIntermediate"], "rightRingIntermediate": ["rightRingDistal"],
	"rightLittleProximal": ["rightLittleIntermediate"], "rightLittleIntermediate": ["rightLittleDistal"],
}
# distal bones have no child: reuse the parent's direction
const DISTAL_PARENT := {
	"leftThumbDistal": "leftThumbProximal", "rightThumbDistal": "rightThumbProximal",
	"leftIndexDistal": "leftIndexIntermediate", "rightIndexDistal": "rightIndexIntermediate",
	"leftMiddleDistal": "leftMiddleIntermediate", "rightMiddleDistal": "rightMiddleIntermediate",
	"leftRingDistal": "leftRingIntermediate", "rightRingDistal": "rightRingIntermediate",
	"leftLittleDistal": "leftLittleIntermediate", "rightLittleDistal": "rightLittleIntermediate",
}

var skel: Skeleton3D
var bones := {}                        # vrm humanoid name -> Bone
var frame_q := Quaternion.IDENTITY     # avatar-local frame -> skeleton space (proper rotation)
var forward_skel := Vector3(0, 0, -1)  # direction the avatar faces, skeleton space


func _init(p_skel: Skeleton3D, humanoid: Dictionary) -> void:
	skel = p_skel
	for n in humanoid:
		var b := Bone.new()
		b.name = n
		b.idx = int(humanoid[n])
		var g := skel.get_bone_global_rest(b.idx)
		b.rest_rot = g.basis.orthonormalized().get_rotation_quaternion()
		b.rest_local = skel.get_bone_rest(b.idx).basis.orthonormalized().get_rotation_quaternion()
		bones[n] = b

	for n in CHILD:
		if not bones.has(n):
			continue
		var b: Bone = bones[n]
		for c in CHILD[n]:
			if not bones.has(c):
				continue
			var d: Vector3 = skel.get_bone_global_rest(bones[c].idx).origin - skel.get_bone_global_rest(b.idx).origin
			if d.length_squared() < 1e-10:
				continue
			b.rest_dir = d.normalized()
			b.has_dir = true
			break
	for n in DISTAL_PARENT:
		if bones.has(n) and bones.has(DISTAL_PARENT[n]) and bones[DISTAL_PARENT[n]].has_dir:
			bones[n].rest_dir = bones[DISTAL_PARENT[n]].rest_dir
			bones[n].has_dir = true

	# Facing from the leg layout. avatar right = right leg - left leg; Godot basis (right, up, back) is proper.
	if bones.has("leftUpperLeg") and bones.has("rightUpperLeg"):
		var r: Vector3 = skel.get_bone_global_rest(bones["rightUpperLeg"].idx).origin \
				- skel.get_bone_global_rest(bones["leftUpperLeg"].idx).origin
		r.y = 0.0
		if r.length_squared() > 1e-8:
			r = r.normalized()
			var back := r.cross(Vector3.UP)
			frame_q = Basis(r, Vector3.UP, back).orthonormalized().get_rotation_quaternion()
			forward_skel = -back


## Rotation (skeleton space) aiming the bone's rest direction at an avatar-local direction.
func aim_local(b: Bone, dir_local: Vector3) -> Quaternion:
	return Quaternion(b.rest_dir, frame_q * dir_local) * b.rest_rot


## Rotation (skeleton space) for a delta expressed in the avatar-local frame.
func delta_local(b: Bone, delta: Quaternion) -> Quaternion:
	return frame_q * delta * frame_q.inverse() * b.rest_rot


## Writes a bone pose so its GLOBAL rotation equals target (uses the parent's current global pose).
func apply_global(bone_idx: int, target: Quaternion) -> void:
	var parent := skel.get_bone_parent(bone_idx)
	var pg := Quaternion.IDENTITY
	if parent >= 0:
		pg = skel.get_bone_global_pose(parent).basis.orthonormalized().get_rotation_quaternion()
	skel.set_bone_pose_rotation(bone_idx, pg.inverse() * target)


## Relative rotation on top of the rest pose (follows the parent). delta is in the avatar-local frame.
func apply_relative_local(b: Bone, delta: Quaternion) -> void:
	var world_delta := frame_q * delta * frame_q.inverse()
	skel.set_bone_pose_rotation(b.idx, b.rest_local * (b.rest_rot.inverse() * world_delta * b.rest_rot))


## Same, but the delta is already in skeleton space.
func apply_relative_world(b: Bone, world_delta: Quaternion) -> void:
	skel.set_bone_pose_rotation(b.idx, b.rest_local * (b.rest_rot.inverse() * world_delta * b.rest_rot))
