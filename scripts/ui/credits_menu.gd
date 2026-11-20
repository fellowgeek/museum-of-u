extends RefCounted
## Offline notices from the running engine and the museum's bundled assets.

const TITLE := "Credits & Licenses"
const CONTRIBUTORS := "Museum contributors"
const ENGINE := "Godot Engine"
const COMPONENTS := "Third-party components"
const LICENSES := "License texts"
const XR := "Godot XR Tools"
const MUSEUM_NOTICE := "res://assets/ui/museum-contributors.txt"
const XR_HANDS := "res://assets/models/xr_hands/LICENSE.md"
const XR_TOOLKIT := "res://assets/models/xr_hands/TOOLKIT_LICENSE.txt"

var return_to: Callable
var history: Array[String] = []
var components: Dictionary = {}
var licenses: Dictionary = {}

func open(app: Node, origin: Callable) -> void:
	return_to = origin
	if components.is_empty():
		for component in Engine.get_copyright_info():
			components[component.name] = component
		licenses = Engine.get_license_info()
	history.assign([TITLE])
	app.screen = "credits"
	show_page(app)

func back(app: Node) -> void:
	var previous := history.pop_back() as String
	if history.is_empty():
		return_to.call()
		focus_entry(app, TITLE)
	else:
		show_page(app, previous)

func enter(app: Node, entry: String) -> void:
	history.append(entry)
	show_page(app)

func show_page(app: Node, selected := "") -> void:
	var title := history.back() as String
	var parent := history[-2] if history.size() > 1 else ""
	app.page(title)
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(back.bind(app))
	app.navigation.add_child(back_button)
	app.navigation.show()
	if parent == COMPONENTS:
		show_document(app, component_text(components[title]))
	elif parent == LICENSES:
		show_document(app, licenses[title])
	else:
		match title:
			TITLE:
				app.text("Explore the artists, tools and software behind Museum of U.")
				add_entries(app, [CONTRIBUTORS, ENGINE, COMPONENTS, LICENSES, XR])
			CONTRIBUTORS: show_document(app, FileAccess.get_file_as_string(MUSEUM_NOTICE))
			ENGINE: show_document(app, Engine.get_license_text())
			COMPONENTS: add_entries(app, sorted_names(components))
			LICENSES: add_entries(app, sorted_names(licenses))
			XR:
				var toolkit := FileAccess.get_file_as_string(XR_TOOLKIT)
				var hands := FileAccess.get_file_as_string(XR_HANDS)
				show_document(app, "Hand calibration\n\n" + toolkit + "\nHand models and poses\n\n" + hands)
	if not selected.is_empty(): focus_entry(app, selected)

func add_entries(app: Node, entries: Array) -> void:
	for entry in entries:
		var entry_button: Button = app.button(entry, enter.bind(app, entry))
		entry_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry_button.clip_text = false

func focus_entry(app: Node, title: String) -> void:
	for child in app.content.get_children():
		if child is Button and child.text == title:
			app.first_button = child
			app._focus(child)
			return

static func sorted_names(items: Dictionary) -> Array:
	var names := items.keys()
	names.sort_custom(func(a: String, b: String): return a.naturalnocasecmp_to(b) < 0)
	return names

func component_text(component: Dictionary) -> String:
	var sections := PackedStringArray()
	var applicable := PackedStringArray()
	for part in component.parts:
		sections.append("\n".join(part.files) + "\n\n" + "\n".join(part.copyright) + "\n\n" + part.license)
		for word in part.license.split(" ", false):
			var key: String = word.strip_edges().trim_prefix("(").trim_suffix(")")
			if licenses.has(key) and not applicable.has(key): applicable.append(key)
	for key in applicable:
		sections.append(key + "\n\n" + licenses[key])
	return "\n\n".join(sections)

func show_document(app: Node, body: String) -> void:
	var reader := RichTextLabel.new()
	reader.accessibility_name = history.back()
	reader.selection_enabled = true
	reader.focus_mode = Control.FOCUS_ALL
	reader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reader.add_theme_color_override("default_color", Color("eee6d5"))
	reader.add_theme_constant_override("line_separation", 5)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("24221c")
	paper.set_content_margin_all(18)
	reader.add_theme_stylebox_override("normal", paper)
	var focus := app.surface.theme.get_stylebox("focus", "Button") as StyleBoxFlat
	reader.add_theme_stylebox_override("focus", focus)
	reader.text = body
	app.content.add_child(reader)
	reader.gui_input.connect(scroll_document.bind(reader))
	app.first_button = reader
	app._focus(reader)

func scroll_document(event: InputEvent, reader: RichTextLabel) -> void:
	var bar := reader.get_v_scroll_bar()
	var line := reader.get_theme_font_size("normal_font_size") + reader.get_theme_constant("line_separation")
	if event.is_action_pressed("ui_up", true): bar.value -= line
	elif event.is_action_pressed("ui_down", true): bar.value += line
	elif event.is_action_pressed("ui_page_up", true): bar.value -= maxf(line, bar.page - line)
	elif event.is_action_pressed("ui_page_down", true): bar.value += maxf(line, bar.page - line)
	else: return
	reader.accept_event()
