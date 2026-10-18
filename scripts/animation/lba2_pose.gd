class_name LBA2Pose
extends RefCounted

const POSE = preload("res://scripts/animation/character_pose.gd")

const ANGLE_SCALE := TAU / 4096.0


static func sample(body: Dictionary, animation: Dictionary, source_frame: int, target_frame: int, weight: float) -> Dictionary:
	return POSE.sample(body, animation, source_frame, target_frame, weight, 4096.0)
