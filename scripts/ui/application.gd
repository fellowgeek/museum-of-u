extends Node
## Application owner; desktop developer launches bypass it, VR retains menu ownership.
const Model=preload("res://scripts/settings/menu_settings.gd")
const Store=preload("res://scripts/saves/save_store.gd")
const Bookmark=preload("res://scripts/saves/run_bookmark.gd")
const Thumbnail=preload("res://scripts/ui/menu_thumbnail.gd")
const Validator=preload("res://scripts/session/playable_spawn.gd")
const CreditsMenu = preload("res://scripts/ui/credits_menu.gd")
const PhotoFolders = preload("res://scripts/museum/photo_folders.gd")
var photo_setup_task := -1
var photos_path := ""
var saves:=Store.new()
var credits := CreditsMenu.new()
var world: Node3D
var backdrop: TextureRect
var canvas: CanvasLayer
var surface: PanelContainer
var navigation: HFlowContainer
var scroll: ScrollContainer
var content: VBoxContainer
var status: Label
var screen: String=""
var preferences: Dictionary={}
var run: Dictionary={}
var draft: Dictionary={}
var new_setup: Dictionary={}
var settings_category: String="Display"
var settings_previous: Dictionary={}
var validator: RefCounted
var loading:=false
var autosave_elapsed:=0.0
var display_remaining:=0.0
var display_previous: Dictionary={}
var display_window: Dictionary={}
var pending_settings: Dictionary={}
var modal: ConfirmationDialog
var after_back: Callable
var memory: Node
var game_input: Node
var first_button: Control
var pending_focus: WeakRef
var focus_wait:=0
var preferences_path: String="user://preferences.json"
var reload_previous_preferences: Dictionary={}
var reload_pending:=false
var run_name: String=""
var advanced:=false
var observed_draft: Dictionary={}
var autosettings_delay:=0.0
var paused_thumbnail: String=""
var vr_menu: Node3D
var xr_events_connected := false
var vr_disconnect_notice := ""
var vr_tracking_lost := 0.0
var auto_vr_pending := true
var auto_vr_wait := 0.0
var vr_defaults_applied := false


func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	memory=get_node("/root/RunMemory")
	game_input=get_node("/root/GameInput")
	if developer_launch():
		get_tree().change_scene_to_file.call_deferred("res://scenes/museum/museum.tscn")
		return
	if photos_path.is_empty(): photos_path = PhotoFolders.photo_directory()
	photo_setup_task = WorkerThreadPool.add_task(PhotoFolders.prepare.bind(photos_path), false, "Prepare museum photos")
	get_tree().auto_accept_quit=false
	game_input.set_meta("menu_context",true)
	canvas=CanvasLayer.new()
	canvas.layer=150
	add_child(canvas)
	backdrop=TextureRect.new()
	backdrop.texture=load("res://assets/ui/museum_backdrop.png")
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	canvas.add_child(backdrop)
	surface=PanelContainer.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.theme=menu_theme()
	canvas.add_child(surface)
	var margins:=MarginContainer.new()
	for side in ["left","right"]: margins.add_theme_constant_override("margin_"+side,48)
	for side in ["top","bottom"]: margins.add_theme_constant_override("margin_"+side,28)
	surface.add_child(margins)
	scroll=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	var layout:=VBoxContainer.new()
	margins.add_child(layout)
	navigation=HFlowContainer.new()
	layout.add_child(navigation)
	layout.add_child(scroll)
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	content=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",12)
	scroll.add_child(content)
	var loaded: Variant=Store.read_json(preferences_path,262144)
	if loaded is Dictionary:
		var compatible := Model.select(loaded, Model.GALLERY_TABS)
		if Model.strict(compatible, false).is_empty(): preferences = compatible
	# Unconfirmed display settings are never persisted; a crash restores the prior file.
	var xr := XRServer.find_interface("OpenXR")
	var use_vr := "--vr" in OS.get_cmdline_user_args() and xr != null and xr.is_initialized()
	get_viewport().use_xr = false
	if not use_vr: GameSettings.presentation(preferences)
	GameSettings.apply_viewport(get_window())
	if use_vr:
		attach_vr_menu()
		start_vr_launch()
	else: main_menu()

static func developer_launch() -> bool:
	if "--vr" in OS.get_cmdline_user_args():
		return false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--"): return true
	return false

func menu_theme() -> Theme:
	var theme:=Theme.new()
	theme.default_font_size=20
	var background:=StyleBoxFlat.new()
	background.bg_color=Color(0.075,0.07,0.055,0.88)
	theme.set_stylebox("panel","PanelContainer",background)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("373226") if state in ["hover","pressed"] else Color("24221c")
		style.content_margin_left=18; style.content_margin_right=18
		style.content_margin_top=10; style.content_margin_bottom=10
		if state=="focus":
			style.bg_color=Color.TRANSPARENT
			style.set_border_width_all(2)
			style.border_color=Color("e7bb67")
		theme.set_stylebox(state,"Button",style)
	theme.set_color("font_color","Label",Color("eee6d5"))
	theme.set_color("font_color","Button",Color("eee6d5"))
	theme.set_color("font_disabled_color","Button",Color("aaa08c"))
	return theme

func page(title: String, description: String="") -> void:
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var desktop_title := screen == "main" and vr_menu == null
	surface.custom_minimum_size.x = 360 if desktop_title else 0
	if desktop_title: surface.anchor_right = .34
	var panel:=surface.theme.get_stylebox("panel","PanelContainer").duplicate() as StyleBoxFlat
	panel.bg_color.a=0.98 if is_instance_valid(world) else 0.88
	surface.add_theme_stylebox_override("panel",panel)
	for child in navigation.get_children(): navigation.remove_child(child); child.queue_free()
	navigation.hide()
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	first_button=null
	content.custom_maximum_size.x = 860 if screen == "credits" else -1
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL if screen == "credits" else Control.SIZE_FILL
	scroll.scroll_vertical=0
	surface.show()
	backdrop.visible=not is_instance_valid(world)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	game_input.set_meta("menu_context",true)
	if screen == "main":
		var logo := TextureRect.new()
		logo.texture = preload("res://assets/ui/museum-logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size.y = 68
		logo.accessibility_name = title
		content.add_child(logo)
	else:
		var heading := Label.new()
		heading.text = title
		if screen == "credits": heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.add_theme_font_size_override("font_size", 44)
		content.add_child(heading)
	if not description.is_empty(): text(description)
	if vr_menu != null: vr_menu.show_panel()
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color",Color("e7bb67"))
	content.add_child(status)
	status.visible = screen != "credits"

func text(message: String) -> Label:
	var label:=Label.new()
	label.text=message
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)
	return label

func button(label: String, action: Callable, disabled:=false) -> Button:
	var node:=Button.new()
	node.text=label
	node.clip_text=true
	node.alignment=HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size=Vector2(0,48)
	node.disabled=disabled
	content.add_child(node)
	node.pressed.connect(action)
	if first_button==null and not disabled:
		first_button=node
		_focus.call_deferred(node)
	return node

func notice(message: String) -> void:
	if is_instance_valid(status): status.text=message

func main_menu() -> void:
	screen="main"
	page("Museum of U")
	accent(button("New visit",new_game),false)
	button("Open photos folder", open_photos_folder)
	button("Settings",func(): open_settings(main_menu))
	button(CreditsMenu.TITLE, func(): credits.open(self, main_menu))
	vr_mode_button()
	button("Quit to Desktop",func(): get_tree().quit())

func open_photos_folder() -> void:
	var problem := DirAccess.make_dir_recursive_absolute(photos_path)
	if problem == OK: problem = OS.shell_open(photos_path)
	if problem != OK: notice("Could not open the photos folder at %s (%s)." % [photos_path, error_string(problem)])

func _exit_tree() -> void:
	if photo_setup_task >= 0: WorkerThreadPool.wait_for_task_completion(photo_setup_task)

func new_game() -> void:
	new_setup=SettingsSchema.new_exploration_defaults()
	if vr_menu != null: new_setup=Model.overlay(new_setup,preferences,["Graphics"])
	run_name=Time.get_datetime_string_from_system().substr(0,16).replace("T","_")
	new_game_page()

func new_game_page() -> void:
	screen="new"
	page("New visit")
	accent(button("Start",start_new))
	button("Back",main_menu)

func start_new() -> void:
	if not Store.valid_name(run_name): notice("Enter a run name of 1–80 characters."); return
	var problem:=Model.strict(new_setup)
	if not problem.is_empty(): notice(problem); return
	var rng:=RandomNumberGenerator.new(); rng.randomize()
	var seed_value: int=rng.randi_range(-2147483648,2147483647)
	new_setup.world.seed_mode="fixed"; new_setup.world.seed=seed_value
	var data: Dictionary={"version":1,"settings_version":1,"interaction_version":1,"generator":GameSettings.GENERATOR_VERSION,"slot":Store.identifier(),"name":run_name.strip_edges(),"settings":new_setup.duplicate(true),"seed":seed_value,"original_seed":seed_value,"transitions":0,"created":Time.get_datetime_string_from_system(),"journal":{"clock":0.0,"records":{},"trimmed":false}}
	await start_run(data,true)

func start_saved(data: Dictionary) -> void:
	var problem:=Store.validate(data)
	if not problem.is_empty(): notice(problem); return
	if is_instance_valid(world):
		confirm("Load "+data.name+"?", "Save the current exploration before replacing it?",func():
			if save_current(): start_run(data),func(): start_run(data))
	else: start_run(data)

func start_run(data: Dictionary, fresh:=false) -> void:
	if loading: return
	loading=true
	screen="loading"
	page("Preparing your visit")
	validator=Validator.new()
	button("Cancel",func(): validator.cancelled=true)
	get_tree().paused=true
	if vr_menu != null:
		vr_menu.show_loading("Preparing your visit")
		await preload("res://scripts/vr/vr_loading.gd").present(get_tree())
	else: await get_tree().process_frame
	if is_instance_valid(world): world.free()
	memory.end()
	if get_tree().has_meta("door_states"): get_tree().remove_meta("door_states")
	run=data.duplicate(true)
	var configuration: Dictionary=SettingsLoader.new().validate(run.settings)
	if not fresh and Model.get_value(run.settings, "display.resolution") == null:
		configuration.display.resolution = "native"
	configuration.world.seed=int(run.seed); configuration.world.seed_mode="fixed"
	var problem:=GameSettings.begin_run(configuration)
	if not problem.is_empty(): fail_load(problem,data); return
	# Fresh visits inherit the device's display and audio preferences.
	GameSettings.presentation(Model.overlay(Model.select(configuration,["Graphics","Display","Audio"]),preferences,["Display","Audio"]) if fresh else preferences)
	get_node("/root/LaunchSettings")._setup_audio_buses()
	GameSettings.apply_frame_pacing(vr_menu != null)
	GameSettings.apply_render_quality(get_window(),vr_menu != null)
	paused_thumbnail=""
	if run.settings.get("schema_version") == 1:
		var previous_id: String = run.get("generation_id", "")
		var current_id := GameSettings.active_generation_id()
		var records: Dictionary = run.journal.records
		for key: String in records.keys():
			var record: Dictionary = records[key]
			if record.state.world == previous_id:
				record.state.world = current_id
				records[current_id + key.trim_prefix(previous_id)] = record
				records.erase(key)
	memory.begin(run.journal)
	world=load("res://scenes/museum/museum.tscn").instantiate()
	world.get_node("ChunkManager").photo_directory_override = photos_path
	world.get_node("ChunkManager").origin_wing=maxi(0,int(run.get("pose",{}).get("museum_origin_wing",0)))
	world.process_mode=Node.PROCESS_MODE_PAUSABLE
	world.get_node("ChunkManager").spread_preparation = vr_menu != null
	var desired:=Vector3(4.5,0.1,4.5)
	if run.has("pose"): desired=memory.vec(run.pose.position)
	# A save can occur between crossing a rebase threshold and the next process
	# tick. Normalize before _ready so the spawn request and physical origin agree.
	var museum_manager:=world.get_node("ChunkManager")
	if absf(desired.z)>=museum_manager.Builder.STRIDE*4:
		var shift:=maxi(-museum_manager.origin_wing,floori(desired.z/museum_manager.Builder.STRIDE))
		museum_manager.origin_wing+=shift
		desired.z-=shift*museum_manager.Builder.STRIDE
	world.get_node("Player").position=desired
	add_child(world)
	if world.get_node("ChunkManager").spread_preparation:
		await finish_vr_preparation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	world.get_node("Player")._cursor_locked=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	notice("Finding a safe start…")
	if vr_menu != null: vr_menu.loading_indicator.begin("Finding a safe start")
	var found: Dictionary=await validator.find(world.get_node("ChunkManager"),world.get_node("Player"),desired)
	if found.is_empty(): fail_load("Loading cancelled." if validator.cancelled else "No safe starting area with a verified exit was found. Please try again.",data); return
	var player=world.get_node("Player")
	player.global_position=found.position
	player.velocity=Vector3.ZERO
	if run.has("pose"):
		Bookmark.restore_pose(player, run.pose)
	if vr_menu != null: activate_vr_player(player)
	if player.vr != null:
		player.vr.global_position = player.global_position
		player.vr.rotation.y = player.neck.global_rotation.y
	player.reset_physics_interpolation()
	run["spawn_check"]=validator.details
	loading=false
	autosave_elapsed=0.0
	apply_live(GameSettings.snapshot())
	if reload_pending:
		var preference_error:=Store.write_json(preferences_path+".tmp",preferences)
		if preference_error.is_empty() and DirAccess.rename_absolute(preferences_path+".tmp",preferences_path)==OK:
			reload_pending=false
		else:
			fail_load("Could not save the new preferences. Previous preferences were retained.",data)
			return
	if not save_current("auto"):
		page("Exploration is not saved",saves.error)
		button("Retry save",func():
			if save_current("auto"): resume())
		button("Continue unsaved",resume)
		button("Return to Main Menu",return_main)
		return
	resume()
	initial_thumbnail.call_deferred(run.slot)

func finish_vr_preparation() -> void:
	# The desktop player exists during loading, before the XR adapter takes over.
	if vr_menu != null:
		world.get_node("Player/UI").hide()
		var effects = world.get_node("VisualEffects")
		if is_instance_valid(effects.screen_layer): effects.screen_layer.hide()
	await world.get_node("ChunkManager").finish_preparation()

func fail_load(problem: String, data: Dictionary) -> void:
	if reload_pending:
		preferences=reload_previous_preferences
		reload_pending=false
	if is_instance_valid(world): world.free()
	world=null
	memory.end()
	loading=false
	get_tree().paused=false
	page("Could not enter the museum",problem)
	button("Retry visit",func(): start_run(data))
	button("Return to Main Menu",return_main)

func bookmark() -> Dictionary:
	return Bookmark.pose_for(world.get_node("Player"))

func snapshot() -> Dictionary:
	return Bookmark.capture(run, world, memory)

func save_current(kind: String="manual") -> bool:
	if not is_instance_valid(world): return false
	var data:=snapshot()
	if not saves.save(data,kind): notice(saves.error); return false
	run=data
	var thumbnail:=capture_play() if screen=="playing" else paused_thumbnail
	write_save_thumbnail(data.slot,kind,thumbnail)
	notice("Saved "+run.name+". Older areas may reset when revisited.")
	return true

func pause_menu() -> void:
	if loading or not is_instance_valid(world): return
	if vr_menu != null and world.get_node("Player").vr != null: world.get_node("Player").vr.suspend_input()
	if screen=="playing": paused_thumbnail=capture_play()
	get_tree().paused=true
	world.get_node("Player")._cursor_locked=false
	screen="pause"
	page("Paused")
	button("Resume",resume)
	button("Settings",func(): open_settings(pause_menu))
	button(CreditsMenu.TITLE, func(): credits.open(self, pause_menu))
	vr_mode_button()
	button("Exit",exit_menu)

func resume() -> void:
	if loading or not is_instance_valid(world): return
	screen="playing"
	surface.hide()
	backdrop.hide()
	game_input.set_meta("menu_context",false)
	game_input.armed=false
	world.get_node("Player")._cursor_locked=true
	world.get_node("Player")._controller_jump=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if vr_menu != null else Input.MOUSE_MODE_CAPTURED
	if vr_menu != null: vr_menu.hide_panel()
	get_tree().paused=false
	if not vr_disconnect_notice.is_empty():
		pause_menu()
		notice(vr_disconnect_notice)
		vr_disconnect_notice = ""

func exit_menu() -> void:
	screen="exit"
	page("Exit","Leave this museum visit. You can start a fresh visit from the main menu.")
	button("Return to Main Menu",return_main)
	button("Quit to Desktop",func(): get_tree().quit())
	button("Back",pause_menu)

func load_menu() -> void:
	screen="load"
	page("Saved Games","Choose a saved exploration to resume or manage.")
	var slots:=saves.list_slots()
	text("%d / %d save slots occupied" % [slots.size(),Store.MAX_SLOTS])
	if is_instance_valid(world): button("Save current game",func():
		if save_current(): load_menu(); notice("Current game saved."))
	var gallery:=gallery_grid()
	if slots.is_empty(): text("No saved explorations yet. Start a New Game to create one.")
	for slot in slots:
		gallery_card(gallery,save_display_name(slot.name)+("" if slot.error.is_empty() else "\n"+slot.error),save_thumbnail(slot.slot,"auto" if "-auto-" in slot.get("revision","") else "manual"),func(): slot_menu(slot))
	button("Back",pause_menu if is_instance_valid(world) else main_menu)

func save_display_name(value: String) -> String:
	# Normalize legacy automatic names for display without rewriting saved data.
	var legacy:=RegEx.new()
	legacy.compile("^Exploration ([0-9]{4}-[0-9]{2}-[0-9]{2})[ T]([0-9]{2}:[0-9]{2}):[0-9]{2}$")
	var matched:=legacy.search(value)
	return matched.get_string(1)+"_"+matched.get_string(2) if matched!=null else value

func slot_menu(slot: Dictionary) -> void:
	page(save_display_name(slot.name),"Resume your latest saved progress.")
	var latest: Dictionary={}
	for entry in saves.revisions(slot.slot):
		if entry.error.is_empty():
			latest=entry.data
			break
	var load_button:=button("Load & Play",func(): start_saved(latest),latest.is_empty())
	if not latest.is_empty(): accent(load_button)
	if latest.is_empty(): notice("No compatible save is available for this game.")
	button("Delete",func(): confirm("Delete "+save_display_name(slot.name)+"?","Permanently removes only this run and its revisions.",func():
		if saves.delete(slot.slot): load_menu()
		else: notice("Could not delete this run. It may be locked by a writer.")))
	button("Back",load_menu)

func confirm(title: String, message: String, accepted: Callable, without_save: Callable=Callable()) -> void:
	modal=ConfirmationDialog.new()
	modal.title=title; modal.dialog_text=message
	modal.ok_button_text=("Apply" if title=="Unsaved settings" else "Save and continue") if without_save.is_valid() else "Confirm"
	modal.cancel_button_text="Cancel"
	modal.process_mode=Node.PROCESS_MODE_ALWAYS
	if vr_menu != null: modal.theme = surface.theme
	(vr_menu.ui if vr_menu != null else self).add_child(modal)
	modal.confirmed.connect(func(): modal.queue_free(); accepted.call())
	modal.canceled.connect(func(): modal.queue_free())
	if without_save.is_valid():
		modal.add_button("Discard" if title=="Unsaved settings" else "Continue without saving",false,"discard")
		modal.custom_action.connect(func(_action): modal.hide(); modal.queue_free(); without_save.call())
	modal.popup_centered(Vector2i(800,300) if vr_menu != null else Vector2i(600,220))

func return_main() -> void:
	if is_instance_valid(world): world.free()
	world=null
	memory.end()
	if get_tree().has_meta("door_states"): get_tree().remove_meta("door_states")
	GameSettings.end_run()
	GameSettings.presentation(preferences)
	get_tree().paused=false
	run.clear()
	main_menu()

func open_settings(back: Callable) -> void:
	after_back=back
	settings_previous=GameSettings.snapshot() if is_instance_valid(world) else Model.overlay(GameSettings.launch_snapshot(),preferences,Model.GALLERY_TABS)
	if vr_menu == null and DisplayServer.get_name()!="headless":
		settings_previous.display.window_mode={Window.MODE_FULLSCREEN:"fullscreen",Window.MODE_EXCLUSIVE_FULLSCREEN:"exclusive_fullscreen"}.get(get_window().mode,"windowed")
		var backing_scale:=DisplayServer.screen_get_max_scale() if OS.get_name()=="macOS" else 1.0
		settings_previous.display.width=clampi(roundi(get_window().size.x/backing_scale),640,7680)
		settings_previous.display.height=clampi(roundi(get_window().size.y/backing_scale),360,4320)
	draft=settings_previous.duplicate(true)
	advanced=false
	observed_draft=draft.duplicate(true)
	settings_category="Display"
	settings_page()

func settings_page() -> void:
	if vr_menu != null:
		vr_settings_page()
		return
	screen="settings"
	page("Settings","Adjustments preview and save automatically. Apply & Back finishes graphics and display changes. " + ("Point at tabs to switch sections; right stick scrolls." if vr_menu != null else "L1 / R1 switches sections."))
	var tabs:=navigation; tabs.show()
	for category in Model.GALLERY_TABS:
		var tab:=Button.new(); tab.text=category; tabs.add_child(tab)
		tab.toggle_mode=true; tab.button_pressed=category==settings_category
		if tab.button_pressed: accent(tab,false)
		tab.pressed.connect(func(): settings_category=category; settings_page())
		if category==settings_category: first_button=tab; _focus.call_deferred(tab)
	text(settings_category)
	if settings_category == "Audio":
		for path in Model.GALLERY_AUDIO: setting_row(path)
		button("Apply & Back", finish_settings)
		return
	if settings_category=="Display":
		text("Lower resolutions soften the image and reduce rendering work in windowed or fullscreen play. Display changes apply when you leave Settings; choose Keep within 15 seconds.")
	if settings_category=="Graphics":
		text("Quality: "+Model.quality_label(draft))
		var quality:=OptionButton.new()
		for tier in ["Choose quality…","Low","Medium","High"]: quality.add_item(tier)
		content.add_child(quality)
		quality.item_selected.connect(func(index):
			if index>0: Model.quality(draft,["low","medium","high"][index-1]); settings_page())
	for path in SettingsSchema.RULES:
		if Model.category(path)!=settings_category or path=="render.quality" or (settings_category=="Audio" and path.ends_with(".muted")): continue
		if not advanced and not Model.basic(path): continue
		setting_row(path)
	button("Hide Advanced" if advanced else "Advanced settings",func(): advanced=not advanced; settings_page())
	button("Apply & Back",finish_settings)

func vr_settings_page() -> void:
	screen = "settings"
	page("VR Settings", "Choose performance or detail. Audio changes save automatically.")
	text("Quality: " + ("Max Frames" if draft.render.quality == "low" else "Balanced" if draft.render.quality == "medium" else "Custom"))
	button("Max Frames", func(): Model.quality(draft, "low"); finish_settings())
	button("Balanced", func(): Model.quality(draft, "medium"); finish_settings())
	for path in Model.GALLERY_AUDIO:
		setting_row(path)
	button("Back", finish_settings)

func setting_row(path: String) -> void:
	var row:=HBoxContainer.new()
	row.set_meta("setting_path",path)
	content.add_child(row)
	var label:=Label.new(); label.text=Model.label(path)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x=240
	row.add_child(label)
	var rule: Array=SettingsSchema.RULES[path]
	var value: Variant=Model.get_value(draft,path)
	if path.ends_with(".gain_db"):
		label.text=path.get_slice(".",1).capitalize()+" volume (%)"
		var mute_path:=path.trim_suffix("gain_db")+"muted"
		numeric_slider(row,0 if Model.get_value(draft,mute_path) else roundf(db_to_linear(value)*100),0,100,1,func(amount):
			SettingsSchema.put(draft,mute_path,amount==0)
			if amount>0: SettingsSchema.put(draft,path,clampf(linear_to_db(amount/100.0),-60,0))
			GameSettings.set_channel_volume(path.get_slice(".",1), Model.get_value(draft,path), amount==0))
	elif value is bool:
		var toggle:=CheckButton.new(); toggle.button_pressed=value; toggle.text="On" if value else "Off"
		row.add_child(toggle)
		toggle.toggled.connect(func(on): SettingsSchema.put(draft,path,on); toggle.text="On" if on else "Off")
	elif rule.size()==2 and rule[1] is Array:
		var select:=OptionButton.new(); row.add_child(select)
		for option in rule[1]:
			select.add_item(("Native (current display)" if option=="native" else str(option).replace("x"," × ")) if path=="display.resolution" else str(option).capitalize())
		select.selected=rule[1].find(value)
		select.item_selected.connect(func(index): SettingsSchema.put(draft,path,rule[1][index]))
	else:
		var step_size:=1.0 if rule[0] is int else (0.0001 if path.ends_with("sensitivity") else 0.001 if rule[2]<=0.2 else 0.01)
		numeric_slider(row,value,rule[1],rule[2],step_size,func(chosen): SettingsSchema.put(draft,path,int(chosen) if rule[0] is int else chosen))
	row.tooltip_text="Default: %s. %s" % [str(rule[0]),"Reload Run Required" if settings_category=="Graphics" else "Saves automatically"]

func apply_live(settings: Dictionary) -> void:
	GameSettings.presentation(settings)
	get_node("/root/LaunchSettings")._setup_audio_buses()
	if not is_instance_valid(world): return
	var player=world.get_node("Player")
	player.mouse_sensitivity=settings.player.camera.sensitivity
	player.invert_y=settings.player.camera.invert_y
	player.bob_amplitude=settings.player.camera.bob_amplitude
	player.bob_frequency=settings.player.camera.bob_frequency
	player.camera.fov=settings.player.camera.fov_degrees
	player.get_node("UI/HintLabel")._refresh()
	var effects=world.get_node("VisualEffects")
	effects.configure(world.get_node("WorldEnvironment").environment)

func apply_settings() -> void:
	var problem:=Model.strict(draft)
	if not problem.is_empty(): notice(problem); return
	if Model.select(draft,["Display"])!=Model.select(settings_previous,["Display"]):
		display_previous=settings_previous.duplicate(true)
		display_window={"mode":get_window().mode,"size":get_window().size,"position":get_window().position}
		pending_settings=draft.duplicate(true)
		GameSettings.presentation(draft)
		GameSettings.apply_viewport(get_window())
		display_remaining=15.0
		page("Keep these display settings?","The previous display settings return automatically in 15 seconds.")
		button("Keep",func(): display_remaining=0; commit_settings(pending_settings))
		button("Revert",revert_display)
		return
	commit_settings(draft)

func revert_display() -> void:
	display_remaining=0
	GameSettings.presentation(display_previous)
	GameSettings.apply_viewport(get_window())
	if not display_window.is_empty():
		get_window().mode=display_window.mode
		get_window().size=display_window.size
		get_window().position=display_window.position
	draft=Model.overlay(draft,display_previous,["Display"])
	settings_page()
	notice("Display settings reverted.")

func commit_settings(settings: Dictionary) -> void:
	var next:=Model.select(settings,Model.GALLERY_TABS)
	var reload_run:=is_instance_valid(world) and Model.select(settings,["Graphics"])!=Model.select(settings_previous,["Graphics"])
	if reload_run:
		if not save_current(): return
		reload_previous_preferences=preferences.duplicate(true)
		reload_pending=true
		preferences=next
		var saved:=snapshot()
		start_run(saved)
		return
	var problem:=Store.write_json(preferences_path+".tmp",next)
	if not problem.is_empty():
		apply_live(settings_previous); GameSettings.apply_viewport(get_window()); notice(problem); return
	if DirAccess.rename_absolute(preferences_path+".tmp",preferences_path)!=OK:
		apply_live(settings_previous); GameSettings.apply_viewport(get_window()); notice("Could not publish preferences; previous settings restored."); return
	preferences=next
	apply_live(settings)
	GameSettings.apply_viewport(get_window())
	after_back.call()

func file_dialog(saving: bool, selected: Callable) -> void:
	var dialog:=FileDialog.new()
	dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters=PackedStringArray(["*.json ; JSON preset"])
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	if vr_menu != null: dialog.theme = surface.theme
	(vr_menu.ui if vr_menu != null else self).add_child(dialog)
	dialog.file_selected.connect(func(path): selected.call(path); dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered_ratio(0.75)

func _process(delta: float) -> void:
	if auto_vr_pending:
		auto_vr_wait -= delta
		if auto_vr_wait <= 0.0:
			auto_vr_wait = 0.5
			try_auto_vr()
	if vr_menu != null and not vr_menu.synthetic:
		var tracker := XRServer.get_tracker("head") as XRPositionalTracker
		var pose := tracker.get_pose("default") if tracker != null else null
		check_vr_tracking(pose != null and pose.has_tracking_data, delta)
	if pending_focus!=null:
		if focus_wait>0: focus_wait-=1
		else:
			_focus_after_layout(pending_focus)
			pending_focus=null
	if screen=="settings" and draft!=observed_draft:
		observed_draft=draft.duplicate(true)
		autosettings_delay=0.25
	if autosettings_delay>0:
		autosettings_delay-=delta
		if autosettings_delay<=0 and screen=="settings": autosave_settings()
	if display_remaining>0:
		display_remaining-=delta
		notice("Reverting in %d seconds…" % ceili(display_remaining))
		if display_remaining<=0: revert_display()
	if screen=="playing" and not get_tree().paused:
		autosave_elapsed+=delta
		if autosave_elapsed>=300:
			autosave_elapsed=0
			if not save_current("auto"): pause_menu(); notice("Autosave failed: "+saves.error)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(surface): return
	# Circle/B remains crouch during play; Options/Start owns controller pause.
	if screen=="playing" and event is InputEventJoypadButton: return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		menu_back()
		get_viewport().set_input_as_handled()

func menu_back() -> void:
	if is_instance_valid(modal) and modal.visible:
		modal.hide(); modal.canceled.emit(); return
	if vr_menu != null:
		var windows: Array[Window] = vr_menu.ui.get_embedded_subwindows()
		windows.reverse()
		for window in windows:
			if window.visible:
				window.close_requested.emit()
				window.hide()
				return
	if loading:
		if validator != null: validator.cancelled=true
	elif display_remaining>0: revert_display()
	elif screen=="playing": pause_menu()
	elif screen=="pause": resume()
	elif screen=="settings": finish_settings()
	elif screen=="credits": credits.back(self)
	else:
		if is_instance_valid(world): pause_menu()
		else: main_menu()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(surface):
		if display_remaining>0: revert_display()
		if screen == "settings" and not draft.is_empty(): autosave_settings()
		if is_instance_valid(world): pause_menu(); exit_menu()
		else: get_tree().quit()

func _focus(node: Variant) -> void:
	if not is_instance_valid(node) or node!=first_button: return
	pending_focus=weakref(node)
	focus_wait=1

func _focus_after_layout(reference: WeakRef) -> void:
	var node: Control=reference.get_ref()
	if is_instance_valid(node) and node.is_inside_tree():
		node.grab_focus()
		if node==first_button and screen!="credits": scroll.set_deferred("scroll_vertical",0)

func accent(node: Button, focus:=true) -> void:
	for state in ["normal","hover","pressed"]:
		var style:=node.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.bg_color=Color("315e54") if state=="normal" else Color("42796b")
		style.set_border_width_all(2)
		style.border_color=Color("81b6a4")
		node.add_theme_stylebox_override(state,style)
	if focus:
		first_button=node
		_focus.call_deferred(node)

func numeric_slider(parent: Control, value: float, minimum: float, maximum: float, increment: float, changed: Callable) -> HSlider:
	var box:=HBoxContainer.new(); parent.add_child(box)
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var slider:=HSlider.new(); box.add_child(slider)
	slider.min_value=0; slider.max_value=100; slider.step=1
	slider.value=(value-minimum)/(maximum-minimum)*100
	slider.custom_minimum_size=Vector2(170,44); slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var readout:=Label.new(); box.add_child(readout); readout.custom_minimum_size.x=78
	readout.text=String.num(value,4)
	slider.value_changed.connect(func(percent):
		var amount:=lerpf(minimum,maximum,percent/100.0)
		if increment==1: amount=roundf(amount)
		readout.text=String.num(amount,4); changed.call(amount))
	return slider

func switch_tab(direction: int) -> bool:
	if screen!="settings" or not navigation.visible or (is_instance_valid(modal) and modal.visible): return false
	autosave_settings()
	var categories := Model.GALLERY_TABS
	settings_category=categories[posmod(categories.find(settings_category)+direction,categories.size())]
	settings_page()
	return true

func autosave_settings() -> bool:
	autosettings_delay=0
	if draft.is_empty(): return true
	# Window changes wait for the timed confirmation; graphics reconstruction occurs on exit.
	var next:=Model.overlay(draft,settings_previous,["Display"])
	var selected:=Model.select(next,Model.GALLERY_TABS)
	var problem:=Store.write_json(preferences_path+".tmp",selected)
	if problem.is_empty() and DirAccess.rename_absolute(preferences_path+".tmp",preferences_path)!=OK: problem="Could not save settings"
	if not problem.is_empty(): notice(problem); return false
	preferences=selected
	apply_live(next)
	GameSettings.apply_render_quality(get_window(),vr_menu != null)
	observed_draft=draft.duplicate(true)
	return true

func finish_settings() -> void:
	if not autosave_settings(): return
	apply_settings()

func capture_play() -> String:
	if DisplayServer.get_name()=="headless": return ""
	return Thumbnail.encode(get_viewport().get_texture().get_image())

func write_save_thumbnail(slot: String, kind: String, encoded: String) -> void:
	if encoded.is_empty() or not Store.valid_id(slot): return
	var path:=saves.root.path_join(slot).path_join(kind+".jpg")
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null: return
	file.store_buffer(Marshalls.base64_to_raw(encoded)); file.close()
	DirAccess.rename_absolute(path+".tmp",path)

func save_thumbnail(slot: String, kind: String) -> String:
	if not Store.valid_id(slot): return ""
	var path:=saves.root.path_join(slot).path_join(kind+".jpg")
	if not FileAccess.file_exists(path): return ""
	return Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(path))

func initial_thumbnail(slot: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if screen=="playing" and run.get("slot","")==slot:
		write_save_thumbnail(slot,"auto",capture_play())

func gallery_grid() -> HFlowContainer:
	var grid:=HFlowContainer.new()
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",16)
	content.add_child(grid)
	return grid

func gallery_card(grid: HFlowContainer, title: String, encoded: String, action: Callable) -> void:
	var card:=button("",action)
	content.remove_child(card); grid.add_child(card)
	card.custom_minimum_size=Vector2(272,240)
	card.tooltip_text=title
	var layout:=VBoxContainer.new()
	card.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left=10; layout.offset_right=-10; layout.offset_top=10; layout.offset_bottom=-10
	layout.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var preview:=TextureRect.new(); layout.add_child(preview)
	preview.custom_minimum_size=Vector2(252,142)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.texture=Thumbnail.texture(encoded)
	preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if preview.texture==null:
		var placeholder:=Label.new(); preview.add_child(placeholder)
		placeholder.text="No preview yet"; placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		placeholder.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		placeholder.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var label:=Label.new(); layout.add_child(label)
	label.text=title; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible=3; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size",18)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE

func attach_vr_menu(source_test := false) -> void:
	if vr_menu != null: return
	auto_vr_pending = false
	if not vr_defaults_applied:
		# First VR entry uses Max Frames.
		Model.quality(preferences, "low")
		GameSettings.presentation(Model.overlay(GameSettings.snapshot(), preferences, ["Graphics", "Audio"]))
		vr_defaults_applied = true
	vr_menu = preload("res://scripts/vr/vr_menu.gd").new()
	add_child(vr_menu)
	vr_menu.configure(self, source_test)
	if not source_test:
		var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
		if not xr_events_connected:
			for event in [xr.session_stopping, xr.session_loss_pending, xr.instance_exiting]:
				event.connect(on_vr_session_ended)
			xr_events_connected = true

func vr_mode_button() -> void:
	if vr_menu != null: button("Exit VR", exit_vr)
	else: button("Enter VR", enter_vr)

func enter_vr() -> void:
	if loading or vr_menu != null: return
	auto_vr_pending = false
	if not initialize_vr():
		notice("VR is unavailable. Connect your headset and start SteamVR / Quest Link, then try Enter VR again. If the runtime still cannot connect, restart the game with the headset connected.")
		return
	vr_tracking_lost = 0.0
	attach_vr_menu()
	GameSettings.apply_frame_pacing(true)
	GameSettings.apply_render_quality(get_viewport(), true)
	if is_instance_valid(world):
		# Rebuild the same snapshot so default shadows/material quality also applies.
		await start_run(snapshot())
		if not is_instance_valid(world) or vr_menu == null: return
		if world.get_node("Player").vr == null:
			exit_vr("Could not enter VR. Desktop controls are ready.")
			return
		pause_menu()
	else: main_menu()

func headset_ready() -> bool:
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr == null or not xr.is_initialized(): return false
	var state := xr.get_session_state()
	return state >= OpenXRInterface.SESSION_STATE_READY and state <= OpenXRInterface.SESSION_STATE_FOCUSED and (not xr.is_user_presence_supported() or xr.is_user_present())

func try_auto_vr() -> void:
	if not auto_vr_pending or vr_menu != null or loading: return
	if screen not in ["main", "pause", "playing"] or is_instance_valid(modal): return
	if headset_ready():
		auto_vr_pending = false
		enter_vr.call_deferred()

func initialize_vr() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	return xr != null and (xr.is_initialized() or xr.initialize())

func activate_vr_player(player: Node) -> void:
	player._start_vr()

func check_vr_tracking(available: bool, delta: float) -> void:
	vr_tracking_lost = 0.0 if available else vr_tracking_lost + delta
	if vr_tracking_lost >= 5.0: on_vr_session_ended()

func on_vr_session_ended() -> void:
	exit_vr.call_deferred("VR disconnected. Desktop controls are ready.")

func exit_vr(message: String = "") -> void:
	auto_vr_pending = false
	if vr_menu == null: return
	var menu := vr_menu
	menu.reset_input()
	# The menu viewport owns the canvas, but never the application's lifetime.
	canvas.reparent(self)
	vr_menu = null
	get_viewport().use_xr = false
	if is_instance_valid(modal): modal.queue_free()
	modal = null
	if is_instance_valid(world):
		var player = world.get_node("Player")
		if player.vr != null: player.vr.restore_desktop()
		else:
			player.get_node("UI").show()
			player.camera.current = true
		world.get_node("VisualEffects").configure(world.get_node("WorldEnvironment").environment)
	menu.queue_free()
	GameSettings.apply_frame_pacing(false)
	GameSettings.apply_render_quality(get_viewport(), false)
	if loading:
		vr_disconnect_notice = message
		return
	if is_instance_valid(world): pause_menu()
	else: main_menu()
	notice(message)

func start_vr_launch() -> void:
	# Preserve CLI configuration while keeping pause, settings and save ownership.
	loading = true
	validator = null
	screen = "loading"
	page("Preparing world")
	get_tree().paused = true
	vr_menu.show_loading("Preparing your visit")
	await preload("res://scripts/vr/vr_loading.gd").present(get_tree())
	var configuration := GameSettings.snapshot()
	var seed_value := GameSettings.resolved_seed
	configuration.world.seed = seed_value
	configuration.world.seed_mode = "fixed"
	run = {"version":1,"settings_version":1,"interaction_version":1,"generator":GameSettings.GENERATOR_VERSION,"slot":Store.identifier(),"name":"VR exploration", "settings":configuration,"seed":seed_value,"original_seed":seed_value,"transitions":0,"created":Time.get_datetime_string_from_system(),"journal":{"clock":0.0,"records":{},"trimmed":false}}
	var problem := GameSettings.begin_run(configuration)
	if not problem.is_empty(): loading = false; get_tree().paused = false; main_menu(); notice(problem); return
	memory.begin(run.journal)
	world = load("res://scenes/museum/museum.tscn").instantiate()
	world.get_node("ChunkManager").photo_directory_override = photos_path
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.get_node("ChunkManager").spread_preparation = true
	add_child(world)
	await finish_vr_preparation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if vr_menu != null: activate_vr_player(world.get_node("Player"))
	loading = false
	resume()
