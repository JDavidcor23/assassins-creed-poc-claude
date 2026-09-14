extends SceneTree

func _tree(n: Node, d: int, out: Array) -> void:
	out.append("  ".repeat(d) + n.name + " [" + n.get_class() + "]")
	for c in n.get_children():
		_tree(c, d + 1, out)

func _init() -> void:
	for who: String in ["asesino", "realista"]:
		var tp: String = "res://assets/characters/%s/mixamo/%s_tpose.fbx" % [who, who]
		var root: Node = (load(tp) as PackedScene).instantiate()
		var out: Array = []
		_tree(root, 0, out)
		print("=== ", who, " T-POSE ===")
		for l: String in out:
			print(l)
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var mi: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		print("  skeleton path from root: ", root.get_path_to(sk))
		print("  mesh AABB size: ", mi.get_aabb().size, "  mesh scale: ", mi.global_transform.basis.get_scale())
		print("  root xform scale: ", root.transform.basis.get_scale())
		print("  hips rest origin: ", sk.get_bone_rest(0).origin)
		root.free()

		var clip: Node = (load("res://assets/characters/%s/mixamo/idle.fbx" % who) as PackedScene).instantiate()
		var ap: AnimationPlayer = clip.find_children("*", "AnimationPlayer", true, false)[0]
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0])
		print("  --- idle.fbx: AnimationPlayer root_node=", ap.root_node, " parent=", ap.get_parent().name)
		for i: int in mini(4, anim.get_track_count()):
			print("      track %d  type=%d  path=%s" % [i, anim.track_get_type(i), str(anim.track_get_path(i))])
		clip.free()
	quit()
