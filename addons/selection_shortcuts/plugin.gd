tool
extends EditorPlugin

# ******************************************************************************

const settings_prefix = "interface/selection_shortcuts/"
var move_selection_shortcut = 'Control+F'
var shortcut_setting_name = 'move_selection_keybind'

var numbers := ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']
var save_keybind_prefix = 'Control+'
var find_keybind_prefix = 'Shift+'
var save_find_keybind_prefix = 'Control+Shift+'
var target_node_paths = {}

var active := false

# ******************************************************************************

func get_plugin_name():
	return 'SelectionShortcuts'

func _enter_tree():
	name = 'SelectionShortcuts'

	add_setting(shortcut_setting_name, TYPE_STRING, move_selection_shortcut)
	add_setting('save_keybind_prefix', TYPE_STRING, save_keybind_prefix)
	add_setting('find_keybind_prefix', TYPE_STRING, find_keybind_prefix)
	add_setting('save_find_keybind_prefix', TYPE_STRING, save_find_keybind_prefix)
	for n in numbers:
		target_node_paths[n] = ''
		add_setting('target_node_path' + n, TYPE_STRING, '')

	settings_changed()
	saved_paths = load_json('selection_shortcuts.json', {})
	var settings = get_editor_interface().get_editor_settings()
	settings.connect('settings_changed', self, 'settings_changed')
	
	connect('main_screen_changed', self, '_main_screen_changed')

func _main_screen_changed(screen_name):
	active = screen_name == '2D'

func settings_changed():
	move_selection_shortcut = get_setting(shortcut_setting_name)
	save_keybind_prefix = get_setting('save_keybind_prefix')
	find_keybind_prefix = get_setting('find_keybind_prefix')
	save_find_keybind_prefix = get_setting('save_find_keybind_prefix')
	for n in numbers:
		target_node_paths[n] = get_setting('target_node_path' + n)

	build_keybinds()

func get_selected_nodes():
	return get_editor_interface().get_selection().get_selected_nodes()

func get_scene():
	return get_editor_interface().get_edited_scene_root()

func get_selected_node_paths():
	var scene = get_scene()
	var selection = get_selected_nodes()
	var paths = []
	for node in selection:
		paths.append(scene.get_path_to(node))
	return paths

# ******************************************************************************

var just_went = false
var saved_paths = {'scenes':{}, 'target_node_paths':{}}
var select_keybinds := []
var save_keybinds := []
var find_keybinds := []
var save_find_keybinds := []

func build_keybinds():
	select_keybinds.clear()
	save_keybinds.clear()
	find_keybinds.clear()
	save_find_keybinds.clear()
	for n in numbers:
		select_keybinds.append(n)
		save_keybinds.append(save_keybind_prefix + n)
		find_keybinds.append(find_keybind_prefix + n)
		save_find_keybinds.append(save_find_keybind_prefix + n)

func _input(event):
	if !active:
		return

	if !(event is InputEventKey):
		return

	if event.as_text() == move_selection_shortcut:
		if event.pressed:
			if just_went:
				return
			move_object_to_cursor()
			just_went = true
		else:
			just_went = false
		return

	if !event.pressed:
		return

	var focused = get_editor_interface().get_inspector().get_focus_owner()
	if focused is TextEdit or focused is LineEdit:
		return

	var scene = get_scene()
	var n = event.as_text()
	n = n[len(n) -1]

	if event.as_text() in select_keybinds:
		get_tree().set_input_as_handled()
		if scene.filename in saved_paths and n in saved_paths[scene.filename]:
			var selected = get_selected_node_paths()
			if selected.hash() == saved_paths[scene.filename][n].hash():
				return
			
			get_editor_interface().get_selection().clear()
			for path in saved_paths[scene.filename][n]:
				var node = scene.get_node_or_null(path)
				if node:
					get_editor_interface().get_selection().add_node(node)
		return

	if event.as_text() in save_keybinds:
		get_tree().set_input_as_handled()
		if !(scene.filename in saved_paths):
			saved_paths[scene.filename] = {}
		saved_paths[scene.filename][n] = get_selected_node_paths()
		save_json('selection_shortcuts.json', saved_paths)
		return

	if event.as_text() in find_keybinds:
		get_tree().set_input_as_handled()
		if n in target_node_paths:
			var root = get_editor_interface().get_edited_scene_root()
			var nodes = []
			var paths = target_node_paths[n]
			if ', ' in paths:
				for path in paths.split(', '):
					nodes.append(root.get_node_or_null(path))
			else:
				nodes = [root.get_node_or_null(paths)]
			if nodes:
				get_editor_interface().get_selection().clear()
				for node in nodes:
					if node:
						get_editor_interface().get_selection().add_node(node)
		return

	if event.as_text() in save_find_keybinds:
		get_tree().set_input_as_handled()
		var selected = get_selected_node_paths()
		var paths = PoolStringArray(selected).join(', ')
		target_node_paths[n] = paths
		set_setting('target_node_path' + n, paths)
		return

# ******************************************************************************

func move_object_to_cursor():
	var selection = get_selected_nodes()

	var targets = []
	for node in selection:
		if node is CanvasItem:
			targets.append(node)
	
	if targets.size() == 0:
		return

	var undo = get_undo_redo()
	if targets.size() == 1:
		var target = targets[0]

		undo.create_action('Move "%s" to %s' % [target.name, str(target.global_position)])
		undo.add_undo_property(target, 'global_position', target.global_position)
		target.global_position = target.get_viewport().get_mouse_position()
		undo.add_do_property(target, 'global_position', target.global_position)
		undo.commit_action()

	if targets.size() > 1:
		var center = Vector2()
		for target in targets:
			center += target.global_position

		center /= targets.size()
		var destination = targets[0].get_viewport().get_mouse_position()

		undo.create_action('Move selection to %s' % [str(destination)])
		var offset = destination - center
		for target in targets:
			undo.add_undo_property(target, 'global_position', target.global_position)
			target.global_position += offset
			undo.add_do_property(target, 'global_position', target.global_position)
		undo.commit_action()

# ******************************************************************************

func add_setting(_name:String, type, value):
	var name = settings_prefix + _name
	var settings = get_editor_interface().get_editor_settings()
	if settings.has_setting(name):
		return
	settings.set(name, value)
	var property_info = {
		"name": name,
		"type": type
	}
	settings.add_property_info(property_info)

func set_setting(_name:String, value):
	var name = settings_prefix + _name
	var settings = get_editor_interface().get_editor_settings()
	settings.set_setting(name, value)

func get_setting(_name:String):
	var name = settings_prefix + _name
	var settings = get_editor_interface().get_editor_settings()
	return settings.get_setting(name)

# ******************************************************************************

func save_json(path, data):
	var f = File.new()
	f.open('user://' + path, File.WRITE)
	f.store_string(JSON.print(data, "\t"))
	f.close()

func load_json(path, default=null):
	var result = default
	var f = File.new()
	if f.file_exists('user://' + path):
		f.open('user://' + path, File.READ)
		var text = f.get_as_text()
		f.close()
		var parse = JSON.parse(text)
		if parse.result is Dictionary:
			result = parse.result
	return result
