extends Node

signal lobby_changed()
signal lobbies_changed()
signal connection_status_changed(message: String)
signal network_game_requested(mode_id: String)

const GAME_PORT := 24567
const DISCOVERY_PORT := 24568
const MAX_PLAYERS := 8
const BEACON_INTERVAL := 0.8
const LOBBY_TIMEOUT := 2.4

var profile_name := "Player"
var selected_mode := "ring_duel"
var status_message := "Offline"
var player_profiles: Dictionary = {}
var discovered_lobbies: Array[Dictionary] = []
var network_match_active := false

var peer: ENetMultiplayerPeer
var discovery_socket: PacketPeerUDP
var beacon_timer := 0.0

func _ready() -> void:
	_load_profile()
	_start_discovery_listener()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta: float) -> void:
	_update_discovery(delta)
	if is_hosting():
		beacon_timer -= delta
		if beacon_timer <= 0.0:
			_send_lobby_beacon()
			beacon_timer = BEACON_INTERVAL

func set_profile_name(new_name: String) -> void:
	profile_name = new_name.strip_edges()
	if profile_name == "":
		profile_name = "Player"
	_save_profile()
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			player_profiles[str(multiplayer.get_unique_id())] = profile_name
			_broadcast_lobby_state()
		else:
			_submit_profile.rpc_id(1, profile_name)
	lobby_changed.emit()

func set_selected_mode(mode_id: String) -> void:
	selected_mode = mode_id
	if is_hosting():
		_broadcast_lobby_state()
	lobby_changed.emit()

func host_lobby(mode_id: String) -> void:
	close_lobby()
	selected_mode = mode_id
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, MAX_PLAYERS)
	if error != OK:
		_set_status("Could not host lobby on port %d" % GAME_PORT)
		return
	multiplayer.multiplayer_peer = peer
	player_profiles = {str(multiplayer.get_unique_id()): profile_name}
	beacon_timer = 0.0
	_set_status("Hosting LAN lobby on port %d" % GAME_PORT)
	lobby_changed.emit()

func join_lobby(address: String) -> void:
	close_lobby()
	var target := address.strip_edges()
	if target == "":
		_set_status("Enter a host IP first")
		return
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(target, GAME_PORT)
	if error != OK:
		_set_status("Could not connect to %s" % target)
		return
	multiplayer.multiplayer_peer = peer
	_set_status("Connecting to %s..." % target)
	lobby_changed.emit()

func join_discovered_lobby(index: int) -> void:
	if index < 0 or index >= discovered_lobbies.size():
		return
	join_lobby(str(discovered_lobbies[index].get("address", "")))

func close_lobby(message: String = "Offline") -> void:
	network_match_active = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	if peer != null:
		peer.close()
		peer = null
	player_profiles.clear()
	_set_status(message)
	lobby_changed.emit()

func start_game() -> void:
	if not is_hosting():
		_set_status("Only the host can start the lobby")
		return
	_start_network_game.rpc(selected_mode)

func is_hosting() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()

func is_connected_to_lobby() -> bool:
	return multiplayer.multiplayer_peer != null

func is_network_match() -> bool:
	return network_match_active and multiplayer.multiplayer_peer != null

func local_player_id() -> int:
	if not is_network_match():
		return 0
	return 1 if multiplayer.get_unique_id() == 1 else 2

func peer_player_id(peer_id: int) -> int:
	if peer_id == 1:
		return 1
	return 2

@rpc("any_peer", "reliable")
func _submit_profile(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	player_profiles[str(sender_id)] = display_name.strip_edges()
	_broadcast_lobby_state()

@rpc("authority", "call_local", "reliable")
func _sync_lobby_state(profiles: Dictionary, mode_id: String) -> void:
	player_profiles = profiles
	selected_mode = mode_id
	lobby_changed.emit()

@rpc("authority", "call_local", "reliable")
func _start_network_game(mode_id: String) -> void:
	selected_mode = mode_id
	network_match_active = true
	network_game_requested.emit(mode_id)

func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		player_profiles[str(peer_id)] = "Player %d" % peer_id
		_broadcast_lobby_state()

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		player_profiles.erase(str(peer_id))
		_broadcast_lobby_state()

func _on_connected_to_server() -> void:
	_set_status("Connected to lobby")
	_submit_profile.rpc_id(1, profile_name)

func _on_connection_failed() -> void:
	close_lobby("Connection failed")

func _on_server_disconnected() -> void:
	close_lobby("Host disconnected")

func _broadcast_lobby_state() -> void:
	_sync_lobby_state.rpc(player_profiles, selected_mode)
	lobby_changed.emit()

func _start_discovery_listener() -> void:
	discovery_socket = PacketPeerUDP.new()
	discovery_socket.set_broadcast_enabled(true)
	var error := discovery_socket.bind(DISCOVERY_PORT)
	if error != OK:
		_set_status("LAN discovery unavailable on port %d" % DISCOVERY_PORT)

func _update_discovery(delta: float) -> void:
	if discovery_socket == null:
		return
	var previous_lobby_count := discovered_lobbies.size()
	for lobby in discovered_lobbies:
		lobby["age"] = float(lobby.get("age", 0.0)) + delta
	discovered_lobbies = discovered_lobbies.filter(func(lobby: Dictionary) -> bool:
		return float(lobby.get("age", 0.0)) <= LOBBY_TIMEOUT
	)
	var changed := discovered_lobbies.size() != previous_lobby_count
	while discovery_socket.get_available_packet_count() > 0:
		var packet := discovery_socket.get_packet()
		var text := packet.get_string_from_utf8()
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var lobby_data: Dictionary = data
		if lobby_data.get("type", "") != "leduel_lobby":
			continue
		_upsert_discovered_lobby(lobby_data, discovery_socket.get_packet_ip())
		changed = true
	if changed:
		lobbies_changed.emit()

func _send_lobby_beacon() -> void:
	if discovery_socket == null:
		return
	var data := {
		"type": "leduel_lobby",
		"name": "%s's Lobby" % profile_name,
		"host": profile_name,
		"mode": selected_mode,
		"players": player_profiles.size(),
		"max_players": MAX_PLAYERS
	}
	discovery_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	discovery_socket.put_packet(JSON.stringify(data).to_utf8_buffer())

func _upsert_discovered_lobby(data: Dictionary, address: String) -> void:
	if address == "" or address == "127.0.0.1":
		return
	for lobby in discovered_lobbies:
		if lobby.get("address", "") == address:
			lobby["name"] = data.get("name", "LAN Lobby")
			lobby["host"] = data.get("host", "Host")
			lobby["mode"] = data.get("mode", "ring_duel")
			lobby["players"] = data.get("players", 1)
			lobby["max_players"] = data.get("max_players", MAX_PLAYERS)
			lobby["age"] = 0.0
			return
	discovered_lobbies.append({
		"address": address,
		"name": data.get("name", "LAN Lobby"),
		"host": data.get("host", "Host"),
		"mode": data.get("mode", "ring_duel"),
		"players": data.get("players", 1),
		"max_players": data.get("max_players", MAX_PLAYERS),
		"age": 0.0
	})

func _set_status(message: String) -> void:
	status_message = message
	connection_status_changed.emit(message)

func _load_profile() -> void:
	var config := ConfigFile.new()
	if config.load("user://profile.cfg") == OK:
		profile_name = str(config.get_value("profile", "name", profile_name))

func _save_profile() -> void:
	var config := ConfigFile.new()
	config.set_value("profile", "name", profile_name)
	config.save("user://profile.cfg")
