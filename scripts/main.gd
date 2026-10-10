extends Node
## Builds the whole app from code, so the scene file stays trivial.

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.screen_set_keep_on(true)

	var settings := AppSettings.load_settings()

	var env := EnvironmentCtl.new()
	add_child(env)
	env.init_env(settings)

	var tracking := TrackingService.new()
	add_child(tracking)

	var driver := AvatarDriver.new()
	add_child(driver)
	driver.init_driver(settings, tracking, env)

	var ui := SettingsUi.new()
	add_child(ui)
	ui.init_ui(settings, tracking, driver, env)

	tracking.init_service(settings)
