
extends RefCounted

const TYPE_PROPERTY_CHANGE = "PROPERTY_CHANGE"
const TYPE_NODE_CREATE = "NODE_CREATE"
const TYPE_NODE_REMOVE = "NODE_REMOVE"
const TYPE_NODE_RENAME = "NODE_RENAME"

var action_id: String
var timestamp: int
var client_id: int
var target_path: String
var type: String
var payload: Dictionary
var inverse_payload: Dictionary

func _init(p_client_id: int, p_target_path: String, p_type: String, p_payload: Dictionary, p_inverse_payload: Dictionary = {}):
    action_id = str(p_client_id) + "_" + str(Time.get_ticks_usec()) + "_" + str(randi())
    timestamp = Time.get_ticks_usec()
    client_id = p_client_id
    target_path = p_target_path
    type = p_type
    payload = p_payload
    inverse_payload = p_inverse_payload

func to_dict() -> Dictionary:
    return {
        "action_id": action_id,
        "timestamp": timestamp,
        "client_id": client_id,
        "target_path": target_path,
        "type": type,
        "payload": payload,
        "inverse_payload": inverse_payload
    }

static func from_dict(dict: Dictionary) -> RefCounted:
    var action = TeamCreateAction.new(
        dict.get("client_id", 0),
        dict.get("target_path", ""),
        dict.get("type", ""),
        dict.get("payload", {}),
        dict.get("inverse_payload", {})
    )
    action.action_id = dict.get("action_id", "")
    action.timestamp = dict.get("timestamp", 0)
    return action
