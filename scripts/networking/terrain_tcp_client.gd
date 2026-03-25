class_name TerrainTCPClient
extends Node

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	HANDSHAKE,
	CONNECTED,
	ERROR
}

var state: ConnectionState = ConnectionState.DISCONNECTED
var tcp: StreamPeerTCP = StreamPeerTCP.new()
var send_queue: Array[Dictionary] = []
var waiting_for_ack: bool = false
var chunks_sent: int = 0
var total_to_send: int = 0

signal connected_to_editor
signal disconnected_from_editor
signal chunk_sent(grid_pos: Vector2i)
signal chunk_acknowledged(grid_pos: Vector2i)
signal export_completed(total_sent: int)
signal connection_failed(reason: String)

func connect_to_editor(host: String = "127.0.0.1", port: int = NetworkProtocol.DEFAULT_PORT) -> void:
	if state != ConnectionState.DISCONNECTED and state != ConnectionState.ERROR:
		push_warning("TerrainTCPClient: Already connected or connecting")
		return

	print("TerrainTCPClient: Connecting to ", host, ":", port)
	tcp = StreamPeerTCP.new()
	tcp.connect_to_host(host, port)
	state = ConnectionState.CONNECTING
	waiting_for_ack = false
	send_queue.clear()
	chunks_sent = 0
	total_to_send = 0

func disconnect_from_editor() -> void:
	if state == ConnectionState.CONNECTED:
		_send_message(NetworkProtocol.create_disconnect())
	_cleanup_connection()
	print("TerrainTCPClient: Disconnected")

func send_terrain_chunk(grid_pos: Vector2i, params: TerrainParameters, height_data: PackedFloat32Array = PackedFloat32Array()) -> void:
	var message = NetworkProtocol.create_terrain_chunk_message(grid_pos, params.to_dictionary(), height_data)
	send_queue.append(message)
	total_to_send += 1

func export_all_chunks() -> void:
	var all_params = GridManager.chunk_parameters
	if all_params.is_empty():
		push_warning("TerrainTCPClient: No chunks to export")
		export_completed.emit(0)
		return

	chunks_sent = 0
	total_to_send = 0

	for grid_pos in all_params:
		var params: TerrainParameters = all_params[grid_pos]
		var height_data: PackedFloat32Array = GridManager.chunk_height_data.get(grid_pos, PackedFloat32Array())
		send_terrain_chunk(grid_pos, params, height_data)

	print("TerrainTCPClient: Queued ", total_to_send, " chunks for export")

func _process(_delta: float) -> void:
	match state:
		ConnectionState.CONNECTING:
			_poll_connecting()
		ConnectionState.HANDSHAKE:
			_poll_handshake()
		ConnectionState.CONNECTED:
			_poll_connected()

func _poll_connecting() -> void:
	tcp.poll()
	var status = tcp.get_status()

	match status:
		StreamPeerTCP.STATUS_CONNECTED:
			print("TerrainTCPClient: TCP connected, sending handshake")
			_send_message(NetworkProtocol.create_handshake())
			state = ConnectionState.HANDSHAKE
		StreamPeerTCP.STATUS_ERROR:
			print("TerrainTCPClient: Connection failed")
			state = ConnectionState.ERROR
			connection_failed.emit("Failed to connect to editor")
		# STATUS_CONNECTING — keep waiting

func _poll_handshake() -> void:
	tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		state = ConnectionState.ERROR
		connection_failed.emit("Lost connection during handshake")
		return

	if tcp.get_available_bytes() > 0:
		var response = tcp.get_var()
		if response is Dictionary and response.get("type") == NetworkProtocol.MessageType.HANDSHAKE_ACK:
			print("TerrainTCPClient: Handshake complete, connected to editor v", response.get("version"))
			state = ConnectionState.CONNECTED
			connected_to_editor.emit()
		else:
			print("TerrainTCPClient: Invalid handshake response")
			state = ConnectionState.ERROR
			connection_failed.emit("Invalid handshake response from editor")

func _poll_connected() -> void:
	tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_cleanup_connection()
		return

	# Check for incoming acks
	if tcp.get_available_bytes() > 0:
		var response = tcp.get_var()
		if response is Dictionary:
			_handle_message(response)

	# Send next chunk from queue if not waiting for ack
	if not waiting_for_ack and not send_queue.is_empty():
		var message = send_queue.pop_front()
		_send_message(message)
		waiting_for_ack = true
		var grid_pos = NetworkProtocol.parse_grid_position(message)
		chunk_sent.emit(grid_pos)
		print("TerrainTCPClient: Sent chunk at ", grid_pos, " (", chunks_sent + 1, "/", total_to_send, ")")

func _handle_message(data: Dictionary) -> void:
	var msg_type = data.get("type", -1)

	match msg_type:
		NetworkProtocol.MessageType.CHUNK_ACK:
			var grid_pos = NetworkProtocol.parse_grid_position(data)
			waiting_for_ack = false
			chunks_sent += 1
			chunk_acknowledged.emit(grid_pos)
			print("TerrainTCPClient: Chunk acknowledged at ", grid_pos)

			if send_queue.is_empty() and total_to_send > 0:
				print("TerrainTCPClient: Export complete - ", chunks_sent, " chunks sent")
				export_completed.emit(chunks_sent)
		NetworkProtocol.MessageType.DISCONNECT:
			print("TerrainTCPClient: Editor requested disconnect")
			_cleanup_connection()

func _send_message(message: Dictionary) -> void:
	tcp.put_var(message)

func _cleanup_connection() -> void:
	tcp.disconnect_from_host()
	state = ConnectionState.DISCONNECTED
	waiting_for_ack = false
	send_queue.clear()
	disconnected_from_editor.emit()

func get_connection_state_name() -> String:
	match state:
		ConnectionState.DISCONNECTED: return "Disconnected"
		ConnectionState.CONNECTING: return "Connecting"
		ConnectionState.HANDSHAKE: return "Handshake"
		ConnectionState.CONNECTED: return "Connected"
		ConnectionState.ERROR: return "Error"
	return "Unknown"
