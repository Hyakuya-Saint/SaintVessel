class_name EnvironmentCtl
extends Node3D
## Camera, background (neutral / gradient / image / green screen / transparent).

var camera: Camera3D
var note := ""

var _s: AppSettings
var _world: WorldEnvironment
var _env: Environment
var _bg_layer: CanvasLayer
var _bg_rect: TextureRect
var _grad_tex: GradientTexture2D
var _last_key := ""
var _reload := false


func init_env(s: AppSettings) -> void:
	_s = s
	camera = Camera3D.new()
	camera.current = true
	camera.near = 0.05
	camera.far = 60.0
	add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 25, 0)
	light.shadow_enabled = false
	add_child(light)

	_env = Environment.new()
	_world = WorldEnvironment.new()
	_world.environment = _env
	add_child(_world)

	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = -2
	add_child(_bg_layer)
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(_bg_rect)

	_grad_tex = GradientTexture2D.new()
	_grad_tex.gradient = Gradient.new()
	_grad_tex.fill_from = Vector2(0, 0)
	_grad_tex.fill_to = Vector2(0, 1)
	_grad_tex.width = 8
	_grad_tex.height = 256


func reload_background_image() -> void:
	_reload = true


## Place the camera in front of the avatar, looking at it.
func frame(avatar_pos: Vector3, facing: Vector3) -> void:
	facing.y = 0.0
	if facing.length_squared() < 1e-4:
		facing = Vector3(0, 0, 1)
	facing = facing.normalized()
	var pos := avatar_pos + facing * _s.camera_distance + Vector3.UP * _s.camera_height
	camera.global_position = pos
	camera.look_at(avatar_pos + Vector3.UP * _s.camera_look_height, Vector3.UP)
	camera.fov = _s.camera_fov


func _process(_delta: float) -> void:
	if _s == null:
		return
	var key := "%d|%s|%s" % [_s.background, _s.gradient_top.to_html(), _s.gradient_bottom.to_html()]
	if key == _last_key and not _reload:
		return
	_last_key = key
	_reload = false
	_apply_background()


func _apply_background() -> void:
	note = ""
	var transparent := _s.background == AppSettings.Bg.TRANSPARENT
	get_viewport().transparent_bg = transparent
	get_window().transparent = transparent
	_bg_rect.visible = false
	_env.background_mode = Environment.BG_COLOR

	match _s.background:
		AppSettings.Bg.NEUTRAL:
			_env.background_color = Color(0.22, 0.22, 0.24)
		AppSettings.Bg.GREEN:
			_env.background_color = Color(0.0, 0.694, 0.251)   # #00B140 chroma green
		AppSettings.Bg.TRANSPARENT:
			_env.background_mode = Environment.BG_CLEAR_COLOR
			RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
			note = "Alpha 0 output (needs a capture path that keeps alpha)"
		AppSettings.Bg.GRADIENT:
			_grad_tex.gradient.set_color(0, _s.gradient_top)
			_grad_tex.gradient.set_color(1, _s.gradient_bottom)
			_bg_rect.texture = _grad_tex
			_show_canvas_background()
		AppSettings.Bg.IMAGE:
			var tex := _load_image()
			if tex != null:
				_bg_rect.texture = tex
				_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				_show_canvas_background()
			else:
				_env.background_color = Color(0.22, 0.22, 0.24)
				note = "Put background.png/.jpg in " + OS.get_user_data_dir()
	if _s.background != AppSettings.Bg.IMAGE:
		_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE


func _show_canvas_background() -> void:
	_env.background_mode = Environment.BG_CANVAS
	_env.canvas_max_layer = -1
	_bg_rect.visible = true


func _load_image() -> Texture2D:
	for n in ["background.png", "background.jpg", "background.jpeg"]:
		var p := "user://" + n
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img != null and not img.is_empty():
				return ImageTexture.create_from_image(img)
	return null
