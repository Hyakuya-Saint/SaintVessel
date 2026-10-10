class_name SettingsUi
extends CanvasLayer
## Touch-friendly settings panel built from Control nodes. Tap the top-right corner to bring the UI back after "Hide UI".

var _s: AppSettings
var _tracking: TrackingService
var _driver: AvatarDriver
var _env: EnvironmentCtl

var _root: Control
var _menu_btn: Button
var _panel: PanelContainer
var _debug: Label
var _info: Label
var _hidden := false
var _dirty := false
var _scale := 1.0
var _fps := 0.0


func init_ui(s: AppSettings, tracking: TrackingService, driver: AvatarDriver, env: EnvironmentCtl) -> void:
	_s = s
	_tracking = tracking
	_driver = driver
	_env = env
	layer = 10

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_debug = Label.new()
	_debug.position = Vector2(8, 4)
	_debug.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_debug)

	_menu_btn = Button.new()
	_menu_btn.text = "Menu"
	_menu_btn.custom_minimum_size = Vector2(64, 36)
	_menu_btn.pressed.connect(_toggle_panel)
	_root.add_child(_menu_btn)

	_panel = PanelContainer.new()
	_panel.visible = false
	_root.add_child(_panel)
	var tabs := TabContainer.new()
	_panel.add_child(tabs)

	var t_track := _tab(tabs, "Tracking")
	_button(t_track, "Start / restart camera", func(): _tracking.start_tracking())
	_button(t_track, "Stop camera", func(): _tracking.stop_tracking())
	_check(t_track, "Mirror mode (avatar acts like a mirror)", "mirror")
	_check(t_track, "Track body", "track_body")
	_check(t_track, "Track face", "track_face")
	_check(t_track, "Track legs (stand back so legs are visible)", "track_legs")
	_check(t_track, "Front camera (restart camera to apply)", "use_front_camera")
	_check(t_track, "Flip camera image (if left/right is wrong)", "flip_camera_image")
	_check(t_track, "GPU delegate (experimental, restart camera)", "use_gpu_delegate")
	_slider(t_track, "Body smoothing", "body_min_cutoff", 0.2, 5.0)
	_slider(t_track, "Body responsiveness", "body_beta", 0.0, 5.0)
	_slider(t_track, "Face smoothing", "face_min_cutoff", 0.5, 8.0)
	_slider(t_track, "Face responsiveness", "face_beta", 0.0, 8.0)
	_slider(t_track, "Follow speed", "follow_speed", 8.0, 60.0)

	var t_face := _tab(tabs, "Face")
	_slider(t_face, "Mouth gain", "mouth_gain", 0.5, 2.5)
	_slider(t_face, "Emotion strength", "emotion_strength", 0.0, 1.0)
	_slider(t_face, "Eyebrow gain", "brow_gain", 0.0, 2.0)
	_slider(t_face, "Gaze gain", "gaze_gain", 0.0, 250.0)
	_check(t_face, "Swap left/right eye (wink test)", "swap_eyes")
	_check(t_face, "Invert gaze horizontal", "invert_gaze_yaw")
	_check(t_face, "Invert gaze vertical", "invert_gaze_pitch")
	_check(t_face, "Auto-blink when face is lost", "idle_blink")
	_slider(t_face, "Body depth scale", "pose_depth_scale", 0.3, 1.2)
	_slider(t_face, "Relaxed finger curl", "finger_curl_deg", 0.0, 50.0)

	var t_view := _tab(tabs, "View")
	var bg := OptionButton.new()
	for n in ["Neutral", "Gradient", "Image", "Green screen", "Transparent"]:
		bg.add_item(n)
	bg.select(_s.background)
	bg.item_selected.connect(_on_bg)
	t_view.add_child(bg)
	_button(t_view, "Reload background image", func(): _env.reload_background_image())
	_color(t_view, "Gradient top", "gradient_top")
	_color(t_view, "Gradient bottom", "gradient_bottom")
	_slider(t_view, "Avatar scale", "avatar_scale", 0.5, 1.5)
	_slider(t_view, "Avatar turn", "avatar_yaw", -60.0, 60.0)
	_slider(t_view, "Camera distance", "camera_distance", 0.8, 6.0)
	_slider(t_view, "Camera height", "camera_height", 0.2, 2.0)
	_slider(t_view, "Look-at height", "camera_look_height", 0.2, 1.8)
	_slider(t_view, "Field of view", "camera_fov", 15.0, 60.0)
	_check(t_view, "Spring bones (hair/clothes physics)", "spring_bones")
	_check(t_view, "Spring bone collisions", "spring_collisions")
	_button(t_view, "Hide UI (tap top-right corner to restore)", func(): _hide_ui())

	var t_info := _tab(tabs, "Info")
	_check(t_info, "Show debug overlay", "show_debug")
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t_info.add_child(_info)
	_button(t_info, "Reset all settings", _on_reset)


# ---------------------------------------------------------------- widget helpers

func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	tabs.add_child(sc)
	return box


func _check(parent: Control, text: String, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = bool(_s.get(key))
	cb.toggled.connect(_on_check.bind(key))
	parent.add_child(cb)


func _slider(parent: Control, text: String, key: String, mn: float, mx: float) -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = text
	lab.custom_minimum_size = Vector2(150, 0)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = (mx - mn) / 200.0
	sl.value = float(_s.get(key))
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 28)
	var val := Label.new()
	val.text = "%.2f" % sl.value
	val.custom_minimum_size = Vector2(46, 0)
	sl.value_changed.connect(_on_slider.bind(key, val))
	row.add_child(lab)
	row.add_child(sl)
	row.add_child(val)
	parent.add_child(row)


func _color(parent: Control, text: String, key: String) -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = text
	lab.custom_minimum_size = Vector2(150, 0)
	var cp := ColorPickerButton.new()
	cp.color = _s.get(key)
	cp.custom_minimum_size = Vector2(80, 30)
	cp.color_changed.connect(_on_color.bind(key))
	row.add_child(lab)
	row.add_child(cp)
	parent.add_child(row)


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	parent.add_child(b)


# ---------------------------------------------------------------- behaviour

func _on_bg(i: int) -> void:
	_s.background = i
	_dirty = true


func _on_reset() -> void:
	_s.reset_defaults()
	_dirty = true


func _on_check(v: bool, key: String) -> void:
	_s.set(key, v)
	_dirty = true


func _on_slider(v: float, key: String, val: Label) -> void:
	_s.set(key, v)
	val.text = "%.2f" % v
	_dirty = true


func _on_color(c: Color, key: String) -> void:
	_s.set(key, c)
	_dirty = true


func _toggle_panel() -> void:
	_panel.visible = not _panel.visible
	_menu_btn.text = "Close" if _panel.visible else "Menu"
	if not _panel.visible and _dirty:
		_save()


func _hide_ui() -> void:
	_hidden = true
	_root.visible = false
	_panel.visible = false
	_menu_btn.text = "Menu"
	_save()


func _save() -> void:
	_s.save()
	_dirty = false


func _process(delta: float) -> void:
	_fps = lerpf(_fps, 1.0 / maxf(delta, 0.0001), 0.1)
	var vp := get_viewport().get_visible_rect().size
	_scale = maxf(1.0, minf(vp.x, vp.y) / 420.0)
	_root.scale = Vector2(_scale, _scale)
	var sz := vp / _scale
	_root.size = sz
	_menu_btn.position = Vector2(sz.x - 70, 6)
	_panel.position = Vector2(6, 46)
	_panel.size = Vector2(sz.x - 12, minf(sz.y - 54, 440))

	_debug.visible = _s.show_debug
	if _s.show_debug:
		_debug.text = "render %.0f fps | tracking %.0f fps\n%s\n%s %s" % [
			_fps, _tracking.fps, _tracking.status, _driver.load_status, _env.note]
	if _info:
		_info.text = "Tracking: %s\nAvatar: %s\nCustom models: put a .vrm in\n%s/models\nBackground image: background.png in\n%s" % [
			_tracking.status, _driver.load_status, OS.get_user_data_dir(), OS.get_user_data_dir()]


func _input(event: InputEvent) -> void:
	if _hidden and event is InputEventMouseButton and event.pressed:
		var vp := get_viewport().get_visible_rect().size
		if event.position.x > vp.x - 140 and event.position.y < 140:
			_hidden = false
			_root.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and _dirty:
		_save()
