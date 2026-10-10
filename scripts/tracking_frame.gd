class_name TrackingFrame
extends RefCounted
## Decoded tracking packet. Layout must match SaintTrackingPlugin.java.
## Pose: MediaPipe WORLD space (meters, hip-centred; x = image right, y = image down, z = away from camera).
## Face: normalized image coords (x,y in 0..1, z on the same scale as x, smaller = closer to camera).

const POSE_COUNT := 33
const FACE_COUNT := 478
const BLEND_COUNT := 52
const HEADER := 8
const PACKET_SIZE := HEADER + POSE_COUNT * 4 + FACE_COUNT * 3 + BLEND_COUNT

const BLEND_NAMES := [
	"_neutral", "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
	"cheekPuff", "cheekSquintLeft", "cheekSquintRight", "eyeBlinkLeft", "eyeBlinkRight",
	"eyeLookDownLeft", "eyeLookDownRight", "eyeLookInLeft", "eyeLookInRight", "eyeLookOutLeft",
	"eyeLookOutRight", "eyeLookUpLeft", "eyeLookUpRight", "eyeSquintLeft", "eyeSquintRight",
	"eyeWideLeft", "eyeWideRight", "jawForward", "jawLeft", "jawOpen", "jawRight", "mouthClose",
	"mouthDimpleLeft", "mouthDimpleRight", "mouthFrownLeft", "mouthFrownRight", "mouthFunnel",
	"mouthLeft", "mouthLowerDownLeft", "mouthLowerDownRight", "mouthPressLeft", "mouthPressRight",
	"mouthPucker", "mouthRight", "mouthRollLower", "mouthRollUpper", "mouthShrugLower",
	"mouthShrugUpper", "mouthSmileLeft", "mouthSmileRight", "mouthStretchLeft", "mouthStretchRight",
	"mouthUpperUpLeft", "mouthUpperUpRight", "noseSneerLeft", "noseSneerRight",
]

var pose_valid := false
var face_valid := false
var img_w := 480.0
var img_h := 640.0
var pose_world := PackedVector3Array()
var pose_vis := PackedFloat32Array()
var face := PackedVector3Array()
var blend := PackedFloat32Array()


func _init() -> void:
	pose_world.resize(POSE_COUNT)
	pose_vis.resize(POSE_COUNT)
	face.resize(FACE_COUNT)
	blend.resize(BLEND_COUNT)


static func blend_index(n: String) -> int:
	return BLEND_NAMES.find(n)


func parse(d: PackedFloat32Array) -> bool:
	if d.size() != PACKET_SIZE:
		return false
	pose_valid = d[3] > 0.5
	face_valid = d[4] > 0.5
	img_w = maxf(1.0, d[5])
	img_h = maxf(1.0, d[6])
	var o := HEADER
	for i in POSE_COUNT:
		pose_world[i] = Vector3(d[o], d[o + 1], d[o + 2])
		pose_vis[i] = d[o + 3]
		o += 4
	for i in FACE_COUNT:
		face[i] = Vector3(d[o], d[o + 1], d[o + 2])
		o += 3
	for i in BLEND_COUNT:
		blend[i] = d[o + i]
	return true
