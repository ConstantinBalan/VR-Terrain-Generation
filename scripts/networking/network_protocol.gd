class_name NetworkProtocol
extends RefCounted

const PROTOCOL_VERSION: String = "1.0"
const DEFAULT_PORT: int = 4242
const HEARTBEAT_INTERVAL: float = 5.0

enum MessageType {
	HANDSHAKE,
	HANDSHAKE_ACK,
	TERRAIN_CHUNK,
	CHUNK_ACK,
	DISCONNECT
}

static func create_handshake() -> Dictionary:
	return {
		"type": MessageType.HANDSHAKE,
		"version": PROTOCOL_VERSION
	}

static func create_handshake_ack() -> Dictionary:
	return {
		"type": MessageType.HANDSHAKE_ACK,
		"version": PROTOCOL_VERSION
	}

static func create_terrain_chunk_message(grid_pos: Vector2i, params_dict: Dictionary) -> Dictionary:
	return {
		"type": MessageType.TERRAIN_CHUNK,
		"grid_position": {"x": grid_pos.x, "y": grid_pos.y},
		"parameters": params_dict
	}

static func create_chunk_ack(grid_pos: Vector2i) -> Dictionary:
	return {
		"type": MessageType.CHUNK_ACK,
		"grid_position": {"x": grid_pos.x, "y": grid_pos.y}
	}

static func create_disconnect() -> Dictionary:
	return {
		"type": MessageType.DISCONNECT
	}

static func parse_grid_position(data: Dictionary) -> Vector2i:
	var pos = data.get("grid_position", {"x": 0, "y": 0})
	return Vector2i(pos.x, pos.y)
