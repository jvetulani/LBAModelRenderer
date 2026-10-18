class_name LBA1SailRepair
extends RefCounted

# BODY #49's two sail panels share vertices with the mast. Four of its five
# source actions rotate the free panel vertices around X, folding the panels
# through themselves. ANIM #231 (the sailing action) keeps the same panels
# open and supplies the intended small flutter. Keep all other source motion.
const BODY_INDEX := 49
const SAILING_ANIMATION := 231
const FOLDED_ANIMATIONS := [230, 232, 233, 234]
const SAIL_GROUPS := [3, 4]


static func needs_repair(body_index: int, body: Dictionary, animation_index: int) -> bool:
	if body_index != BODY_INDEX or not FOLDED_ANIMATIONS.has(animation_index):
		return false
	if body.get("game", "LBA1") != "LBA1" or body.get("group_count", 0) != 6 or body.get("points", PackedVector3Array()).size() != 69:
		return false
	var groups: Array = body["groups"]
	return groups[3]["pivot"] == 49 and groups[4]["pivot"] == 51


static func repair(animation: Dictionary, sailing_animation: Dictionary) -> Dictionary:
	if not animation.get("ok", false) or not sailing_animation.get("ok", false):
		return animation
	if animation["frame_count"] != sailing_animation["frame_count"] or animation["group_count"] < 5 or sailing_animation["group_count"] < 5:
		return animation
	var repaired := animation.duplicate(true)
	for frame_index in range(repaired["frame_count"]):
		for group_index in SAIL_GROUPS:
			repaired["frames"][frame_index]["transforms"][group_index] = sailing_animation["frames"][frame_index]["transforms"][group_index].duplicate(true)
	return repaired
