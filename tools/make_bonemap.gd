extends SceneTree
## Crée assets/mixamo/mixamo_bonemap.tres : correspondance os Mixamo -> profil humanoïde Godot.
func _init() -> void:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	var m := {"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head"}
	for side in ["Left", "Right"]:
		m[side + "Shoulder"] = side + "Shoulder"
		m[side + "UpperArm"] = side + "Arm"
		m[side + "LowerArm"] = side + "ForeArm"
		m[side + "Hand"] = side + "Hand"
		m[side + "UpperLeg"] = side + "UpLeg"
		m[side + "LowerLeg"] = side + "Leg"
		m[side + "Foot"] = side + "Foot"
		m[side + "Toes"] = side + "ToeBase"
		m[side + "ThumbMetacarpal"] = side + "HandThumb1"
		m[side + "ThumbProximal"] = side + "HandThumb2"
		m[side + "ThumbDistal"] = side + "HandThumb3"
		for f in [["Index", "Index"], ["Middle", "Middle"], ["Ring", "Ring"], ["Little", "Pinky"]]:
			m[side + f[0] + "Proximal"] = side + "Hand" + f[1] + "1"
			m[side + f[0] + "Intermediate"] = side + "Hand" + f[1] + "2"
			m[side + f[0] + "Distal"] = side + "Hand" + f[1] + "3"
	for k in m:
		bm.set_skeleton_bone_name(k, "mixamorig_" + m[k])
	print(ResourceSaver.save(bm, "res://assets/mixamo/mixamo_bonemap.tres"))
	quit()
