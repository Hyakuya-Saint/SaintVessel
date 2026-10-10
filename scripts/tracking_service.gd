class_name TrackingService
extends Node
## Owns the camera/tracking pipeline. On Android it talks to the SaintTracking plugin (CameraX + MediaPipe).
## On desktop it plays a synthetic performance so the avatar can be tested without a phone.

const CAMERA_PERMISSION := "android.permission.CAMERA"

var frame := TrackingFrame.new()
var status := "idle"
var fps := 0.0
var running := false

var _s: AppSettings
var _plugin = null
var _has_new := false
var _fps_count := 0
var _fps_t := 0.0
var _status_t := 0.0
var _sim_t := 0.0


func init_service(s: AppSettings) -> void:
	_s = s
	start_tracking()


func consume_new() -> bool:
	var n := _has_new
	_has_new = false
	return n


func start_tracking() -> void:
	running = false
	if OS.get_name() != "Android":
		running = true
		status = "simulated tracking (desktop)"
		return
	if not (CAMERA_PERMISSION in OS.get_granted_permissions()):
		status = "requesting camera permission"
		if not get_tree().on_request_permissions_result.is_connected(_on_permission):
			get_tree().on_request_permissions_result.connect(_on_permission)
		OS.request_permissions()
		return
	_start_plugin()


func stop_tracking() -> void:
	if _plugin:
		_plugin.stop()
	running = false
	status = "stopped"


func _on_permission(permission: String, granted: bool) -> void:
	if permission != CAMERA_PERMISSION:
		return
	if granted:
		_start_plugin()
	else:
		status = "camera permission denied (enable it in Android settings)"


func _start_plugin() -> void:
	if not Engine.has_singleton("SaintTracking"):
		status = "SaintTracking plugin missing from this build"
		return
	_plugin = Engine.get_singleton("SaintTracking")
	_plugin.start(_s.use_front_camera, _s.flip_camera_image, _s.use_gpu_delegate)
	running = true
	status = "starting camera"


func _process(delta: float) -> void:
	if not running:
		return
	_fps_t += delta
	if _fps_t >= 1.0:
		fps = _fps_count / _fps_t
		_fps_count = 0
		_fps_t = 0.0

	if _plugin:
		var packet: PackedFloat32Array = _plugin.poll()
		if packet.size() == TrackingFrame.PACKET_SIZE and frame.parse(packet):
			_has_new = true
			_fps_count += 1
		_status_t += delta
		if _status_t > 1.0:
			_status_t = 0.0
			status = String(_plugin.getStatus())
	else:
		_sim_t += delta
		if _sim_t >= 1.0 / 30.0:
			_sim_t = 0.0
			SimTracking.fill(frame, Time.get_ticks_msec() / 1000.0)
			_has_new = true
			_fps_count += 1


func _notification(what: int) -> void:
	if _s == null or OS.get_name() != "Android":
		return
	if what == NOTIFICATION_APPLICATION_PAUSED and running:
		stop_tracking()
	elif what == NOTIFICATION_APPLICATION_RESUMED and _plugin != null and not running:
		start_tracking()
