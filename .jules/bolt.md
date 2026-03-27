## 2024-03-27 - [Avoid find_children for dynamic indicators]
**Learning:** Using `find_children("*", "Node", true, false)` on every tick or selection change to find previously instantiated networked indicators is O(N) where N is the total number of nodes in the scene. In a large project, this causes a major CPU spike when deselecting or receiving selection updates.
**Action:** Use Godot's built-in grouping system (`add_to_group("TeamCreateSelectionOutlines")` and `get_tree().get_nodes_in_group(...)`) for O(1) lookup of dynamic UI/networking indicators scattered throughout the scene tree.
