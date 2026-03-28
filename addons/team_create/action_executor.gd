

extends RefCounted
const TeamCreateAction = preload("res://addons/team_create/action.gd")

static func execute(action, current_scene: Node, network: Node, scene_path: String) -> bool:
    if current_scene.scene_file_path != scene_path and scene_path != "":
        return false

    match action.type:
        TeamCreateAction.TYPE_PROPERTY_CHANGE:
            var node = network.get_node_by_unique_id(current_scene, action.target_path)
            if not node: return false
            var prop_name = action.payload.get("property", "")
            var value = action.payload.get("value")

            if prop_name.begins_with("metadata/"):
                return false

            if typeof(value) == TYPE_STRING and (value as String).begins_with("res://"):
                if ".." in (value as String): return false
                var is_downloading = network and network.file_sync and value in network.file_sync.downloading_files
                if not is_downloading and ResourceLoader.exists(value):
                    var res = load(value)
                    if res: node.set(prop_name, res)
                else:
                    return false # Should be queued for later in scene_sync
            elif typeof(value) == TYPE_DICTIONARY and value.has("sub_resource_bytes"):
                var res = bytes_to_var_with_objects(value["sub_resource_bytes"])
                if res is Resource:
                    var path = value.get("resource_path", "")
                    if path != "":
                        var existing_res = null
                        if ResourceLoader.has_cached(path):
                            existing_res = load(path)
                        if existing_res and existing_res.get_class() == res.get_class():
                            var props = res.get_property_list()
                            for p in props:
                                var p_name = p.name
                                if p.usage & PROPERTY_USAGE_STORAGE or p.usage & PROPERTY_USAGE_EDITOR:
                                    if p_name != "resource_path" and p_name != "resource_local_to_scene" and p_name != "resource_name":
                                        existing_res.set(p_name, res.get(p_name))
                            res = existing_res
                        else:
                            res.take_over_path(path)
                    node.set(prop_name, res)
            else:
                node.set(prop_name, value)
            return true

        TeamCreateAction.TYPE_NODE_CREATE:
            var parent = network.get_node_by_unique_id(current_scene, action.target_path)
            if not parent: return false
            var new_name = action.payload.get("name", "")
            var type = action.payload.get("type", "")
            if parent.has_node(new_name): return true # Already exists
            var new_node = ClassDB.instantiate(type) as Node
            if new_node:
                new_node.name = new_name
                parent.add_child(new_node)
                new_node.owner = current_scene
                return true
            return false

        TeamCreateAction.TYPE_NODE_REMOVE:
            var node = network.get_node_by_unique_id(current_scene, action.target_path)
            if not node or node == current_scene: return false
            var parent = node.get_parent()
            if is_instance_valid(parent):
                parent.remove_child(node)
            node.queue_free()
            return true

        TeamCreateAction.TYPE_NODE_RENAME:
            var parent = network.get_node_by_unique_id(current_scene, action.target_path)
            if not parent: return false
            var old_name = action.payload.get("old_name", "")
            var new_name = action.payload.get("new_name", "")
            var node = parent.get_node_or_null(old_name)
            if node:
                node.name = new_name
                return true
            return false
    return false

static func undo(action, current_scene: Node, network: Node, scene_path: String) -> bool:
    if current_scene.scene_file_path != scene_path and scene_path != "":
        return false

    match action.type:
        TeamCreateAction.TYPE_PROPERTY_CHANGE:
            var node = network.get_node_by_unique_id(current_scene, action.target_path)
            if not node: return false
            var prop_name = action.payload.get("property", "")
            if action.inverse_payload.has("value"):
                node.set(prop_name, action.inverse_payload["value"])
            return true

        TeamCreateAction.TYPE_NODE_CREATE:
            # Undo create is remove
            var parent = network.get_node_by_unique_id(current_scene, action.target_path)
            if not parent: return false
            var new_name = action.payload.get("name", "")
            var node = parent.get_node_or_null(new_name)
            if node:
                parent.remove_child(node)
                node.queue_free()
                return true
            return false

        TeamCreateAction.TYPE_NODE_REMOVE:
            # Undo remove is create
            var parent = network.get_node_by_unique_id(current_scene, action.inverse_payload.get("parent_path", ""))
            if not parent: return false
            var new_name = action.payload.get("name", "")
            var type = action.payload.get("type", "")
            var new_node = ClassDB.instantiate(type) as Node
            if new_node:
                new_node.name = new_name
                parent.add_child(new_node)
                new_node.owner = current_scene
                # Restore properties
                var props = action.inverse_payload.get("properties", {})
                for prop_name in props:
                    new_node.set(prop_name, props[prop_name])
                return true
            return false

        TeamCreateAction.TYPE_NODE_RENAME:
            var parent = network.get_node_by_unique_id(current_scene, action.target_path)
            if not parent: return false
            var old_name = action.payload.get("old_name", "")
            var new_name = action.payload.get("new_name", "")
            var node = parent.get_node_or_null(new_name)
            if node:
                node.name = old_name
                return true
            return false
    return false
