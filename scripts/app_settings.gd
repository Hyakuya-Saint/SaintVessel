class_name AppSettings
extends RefCounted
## All user-tweakable settings, persisted as JSON in user://settings.json.

enum Bg { NEUTRAL, GRADIENT, IMAGE, GREEN, TRANSPARENT }

const PATH := "user://settings.json"
const KEYS := [
	"use_front_camera", "flip_camera_image", "use_gpu_delegate", "track_body", "track_face", "track_legs", "mirror",
	"body_min_cutoff", "body_beta", "face_min_cutoff", "face_beta", "follow_speed",
	"pose_depth_scale", "finger_curl_deg", "mouth_gain", "emotion_strength", "brow_gain", "gaze_gain",
	"swap_eyes", "invert_gaze_yaw", "invert_gaze_pitch", "idle_blink", "spring_bones", "spring_collisions", "toon_shader",
	"background", "gradient_top", "gradient_bottom", "avatar_scale", "avatar_yaw",
	"camera_distance", "camera_height", "camera_look_height", "camera_fov", "show_debug",
]

# ---- tracking input
var use_front_camera := true
var flip_camera_image := false   # only if your device delivers a mirrored analysis frame
var use_gpu_delegate := false    # MediaPipe GPU delegate (experimental, falls back to CPU)
var track_body := true
var track_face := true
var track_legs := false          # off by default: most desk/webcam setups don't show legs
var mirror := true               # true = avatar acts like a mirror, false = avatar copies you

# ---- smoothing (One Euro): lower min_cutoff = smoother, higher beta = less lag on fast moves
var body_min_cutoff := 1.5
var body_beta := 1.0
var face_min_cutoff := 2.5
var face_beta := 2.0
var follow_speed := 28.0         # render-rate interpolation toward the filtered target

# ---- retargeting
var pose_depth_scale := 1.0      # <1 damps noisy monocular depth
var finger_curl_deg := 22.0
var mouth_gain := 1.2
var emotion_strength := 0.35
var brow_gain := 1.0
var gaze_gain := 110.0
var swap_eyes := false           # flip if a left wink drives the right eye
var invert_gaze_yaw := false
var invert_gaze_pitch := false
var idle_blink := true
var spring_bones := true
var spring_collisions := true
var toon_shader := true          # false = keep Godot's imported unlit materials

# ---- view
var background := 0
var gradient_top := Color(0.16, 0.20, 0.32)
var gradient_bottom := Color(0.55, 0.40, 0.60)
var avatar_scale := 1.0
var avatar_yaw := 0.0
var camera_distance := 2.4
var camera_height := 1.1
var camera_look_height := 1.05
var camera_fov := 28.0
var show_debug := false


static func load_settings() -> AppSettings:
	var s := AppSettings.new()
	if FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			s.from_dict(parsed)
	return s


func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "\t"))


func to_dict() -> Dictionary:
	var d := {}
	for k in KEYS:
		var v = get(k)
		d[k] = v.to_html() if v is Color else v
	return d


func from_dict(d: Dictionary) -> void:
	for k in KEYS:
		if not d.has(k):
			continue
		var cur = get(k)
		match typeof(cur):
			TYPE_BOOL:
				set(k, bool(d[k]))
			TYPE_INT:
				set(k, int(d[k]))
			TYPE_FLOAT:
				set(k, float(d[k]))
			TYPE_COLOR:
				set(k, Color.html(str(d[k])))


func reset_defaults() -> void:
	from_dict(AppSettings.new().to_dict())
