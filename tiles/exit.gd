extends Area2D

export(String) var map: String
export(String) var player_position: String
export(String) var entrance: String

func _ready() -> void:
	connect("body_entered", self, "body_entered")

func body_entered(body) -> void:
	if body.is_in_group("player") && body.is_network_master():
		body.state = "interact"
		screenfx.play("fadewhite")
		yield(screenfx, "animation_finished")
		
		global.get_player_state()
		global.next_entrance = entrance
		
		var old_map = get_parent()
		var root = old_map.get_parent()
		
		for peer in network.map_peers:
			get_tree().rpc_id(peer, "player_exiting_scene")
		
		if get_tree().is_network_server():
			network.remove_player_from_map(1)
		else:
			rpc_id(1, "remove_player_from_map", get_tree().get_network_unique_id())
		
		var new_map_path = "res://maps/" + map + ".tmx"
		var new_map = load(new_map_path).instance()
		root.call_deferred("add_child", new_map)
		
		old_map.call_deferred("queue_free")
