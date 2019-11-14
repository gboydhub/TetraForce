extends Node

var current_map = null

var active_maps: Dictionary = {}
var current_players: Array = []
var map_owners: Dictionary = {}
var map_peers: Array = []

var player_data: Dictionary = {}

var server_object_data = {}

var my_player_data: Dictionary = {
	skin ="res://player/player.png",
	name = "", 
	}

var clock: Timer


var rooms: Dictionary = {}

func _ready() -> void:
	set_process(false)
	get_tree().connect("network_peer_connected", self, "_player_connected")
	get_tree().connect("network_peer_disconnected", self, "_player_disconnected")

func initialize() -> void:
	clock = Timer.new()
	clock.wait_time = 0.1
	clock.one_shot = false
	clock.owner = self
	add_child(clock)
	#clock.start()
	clock.connect("timeout", self, "clock_update")
	
	if get_tree().is_network_server():
		player_data[1] = my_player_data
	
	rpc_id(1, "_receive_my_player_data", get_tree().get_network_unique_id(), my_player_data)

remote func _receive_my_player_data(id, new_player_data) -> void:
	
	var collision_count: int = 0
	var player_name: String = new_player_data.name
	
	while check_dupe_name(player_name):
		collision_count += 1
		player_name = get_player_name(new_player_data.name, collision_count)
		
	new_player_data.name = player_name
	player_data[id] = new_player_data
	
	rpc("_receive_player_data", player_data)
	
func get_player_name(player_name, collision_count) -> String:
	if collision_count == 0:
		return player_name
	else:
		return player_name + "%d" % collision_count
	
func clear() -> void:
	if is_instance_valid(current_map):
		current_map.free()
	if is_instance_valid(clock):
		clock.stop()
	active_maps.clear()
	current_players.clear()
	map_owners.clear()
	map_peers.clear()
	player_data.clear()

func check_dupe_name(player_name: String) -> bool:
	for value in player_data.values():
		if player_name == value.name:
			return true
			
	return false

remote func _receive_player_data(received_player_data: Dictionary) -> void:
	player_data = received_player_data

func clock_update() -> void:
	update_maps()
	update_current_players()

remote func add_player_to_map(player_id, map):
	active_maps[player_id] = map
	map_peers.append(player_id)
	update_current_players()
	rpc("_receive_active_maps", active_maps)
	_update_map_owners()
	current_map.update_players()
	
remote func remove_player_from_map(player_id):
	active_maps.erase(player_id)
	update_current_players()
	rpc("_receive_active_maps", active_maps)
	_update_map_owners()
	current_map.update_players()
	
remotesync func player_exiting_scene() -> void:
	var peer_id = network.get_rpc_sender_id()
	if map_peers.has(peer_id):
		map_peers.remove(peer_id)
	if active_maps.has(peer_id):
		active_maps.erase(peer_id)
	
	get_tree().root.find_node(peer_id).call_deferred("queue_free")
	current_map.update_players()
	
func update_maps() -> void:
	if get_tree().is_network_server():
		active_maps[1] = current_map.name
		
		rpc("_receive_active_maps", active_maps)
		_update_map_owners()
	else:
		_send_current_map()
	
	update_current_players()
	current_map.update_players()

func update_current_players() -> void:
	var new_current_players: Array = []
	for peer in active_maps:
		if active_maps.get(peer) == current_map.name:
			new_current_players.append(peer)
	var other_players: Array = new_current_players
	other_players.erase(get_tree().get_network_unique_id())
	map_peers = other_players
	current_players = new_current_players

func _update_map_owners() -> void:
	
	for map in active_maps.values():
		if !map_owners.keys().has(map):
			map_owners[map] = active_maps.keys()[active_maps.values().find(map)]
	
	# remove old maps
	var owner_keys = map_owners.keys()
	for map in owner_keys:
		if !active_maps.values().has(map):
			map_owners.erase(map)
	
	# reassign owners
	for map in map_owners.keys():
		var map_owner = map_owners.get(map) # gets player id of map
		if active_maps[map_owner] != map: # if player id is not in that map...
			map_owners[map] = active_maps.keys()[active_maps.values().find(map)] # change owner to a player in that map
	
	rpc("_receive_map_owners", map_owners)

# client only, sends current_map to server
func _send_current_map() -> void:
	rpc_id(1, "_receive_current_map", get_tree().get_network_unique_id(), current_map.name)

# server only, updates active_maps
remote func _receive_current_map(id: int, map) -> void:
	active_maps[id] = map
	rpc_id(id, "_receive_active_maps", active_maps)

# received by clients
remote func _receive_active_maps(maps: Dictionary) -> void:
	active_maps = maps

remote func _receive_map_owners(owners: Dictionary) -> void:
	map_owners = owners

func _player_connected(id) -> void:
	update_current_players()

func _player_disconnected(id) -> void:
	if get_tree().is_network_server():
		active_maps.erase(id)
	update_maps()

func _send_flags_to_map(map_name):
	for pid in active_maps.keys():
		if active_maps[pid] == map_name:
			_send_flags_to_player(pid)
			
remote func _request_map_flags(player_id):
	_send_flags_to_player(player_id)

func _send_flags_to_player(player_id):
	var p_map = active_maps[player_id]
	var map_flag_data = server_object_data.get(p_map, {})

	for obj in map_flag_data.keys():
		for flag in map_flag_data[obj].keys():
			print_debug("SSF: ", p_map + "|" + obj)
			rpc_id(player_id, "update_object_flag", p_map + "|" + obj, flag, server_object_data[p_map][obj][flag])

master func update_server_object_flag(object_id, flag_name, flag_val):
	print_debug("SDOF")
	var split_pos = object_id.find("|")
	var obj_map = object_id.left(split_pos)
	var obj_id = object_id.right(split_pos+1)
	
	if !server_object_data.has(obj_map):
		server_object_data[obj_map] = {}
	
	if !server_object_data[obj_map].has(obj_id):
		server_object_data[obj_map][obj_id] = {}
		
	server_object_data[obj_map][obj_id][flag_name] = flag_val
	
	_send_flags_to_map(obj_map)
	
	
remotesync func update_object_flag(object_id, flag_name, flag_val):
	var obj = get_tree().get_root().find_node(object_id, true, false)
	if obj:
		obj._received_flag_update(flag_name, flag_val)
		obj.flag_list[flag_name] = flag_val
	else:
		print_debug("Could not find ", object_id)

func get_room_screen(pos: Vector2) -> Vector2:
	return Vector2(floor(pos.x / 16 / 16), floor(pos.y / 9 / 16))

func get_room(pos):
	var screen: Vector2 = get_room_screen(pos)
	if rooms.has(screen) :
		return rooms[screen]
	
	else :
		# create room
		var r = Room.new()
		r.tile_rect.position = screen * Vector2(16, 9)
		
		r.connect("player_entered", self, "_on_room_player_entered", [r])
		r.connect("player_exited", self, "_on_room_player_exited", [r])
		r.connect("enemies_defeated", self, "_on_room_enemies_defeated", [r])
		r.connect("empty", self, "_on_room_empty", [r])
		
		rooms[screen] = r
		return r

func _on_room_player_entered(room: Room) -> void:
	print(room, "player_entered")

func _on_room_player_exited(room: Room) -> void:
	print(room, "player_exited")

func _on_room_enemies_defeated(room: Room) -> void:
	print(room, "enemies_defeated")

func _on_room_empty(room: Room) -> void:
	# free the room once it's clear
	print(room.get_class())
	rooms.erase(room)

func is_scene_owner() -> bool:
	if map_owners.keys().has(current_map.name):
		return false
	if map_owners[current_map.name] == get_tree().get_network_unique_id():
		return true
	return false
