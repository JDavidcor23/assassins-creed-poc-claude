extends SceneTree

func _walk(n: Node, depth: int, out: Array) -> void:
	out.append("  ".repeat(depth) + n.name + " [" + n.get_class() + "]")
	for c in n.get_children():
		_walk(c, depth + 1, out)

func _init() -> void:
	var files := [
		"res://assets/characters/asesino/mixamo/asesino_tpose.fbx",
		"res://assets/characters/asesino/mixamo/idle.fbx",
		"res://assets/characters/asesino/mixamo/stab.fbx",
		"res://assets/characters/realista/mixamo/realista_tpose.fbx",
		"res://assets/characters/realista/mixamo/dying.fbx",
	]
	for f in files:
		print("=== ", f.get_file())
		var ps := ResourceLoader.load(f)
		if ps == null:
			print("  !! LOAD FAILED")
			continue
		var root: Node = ps.instantiate()
		var skels := root.find_children("*", "Skeleton3D", true, false)
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		var players := root.find_children("*", "AnimationPlayer", true, false)
		print("  root=", root.name, " (", root.get_class(), ")")
		print("  Skeleton3D=", skels.size(), "  MeshInstance3D=", meshes.size(), "  AnimationPlayer=", players.size())
		for s in skels:
			var sk := s as Skeleton3D
			print("    bones=", sk.get_bone_count(), "  first5=", range(mini(5, sk.get_bone_count())).map(func(i): return sk.get_bone_name(i)))
		for p in players:
			var ap := p as AnimationPlayer
			for a in ap.get_animation_list():
				var anim := ap.get_animation(a)
				print("    anim '", a, "' len=", "%.2f" % anim.length, "s tracks=", anim.get_track_count(), " loop=", anim.loop_mode)
		for m in meshes:
			var mi := m as MeshInstance3D
			var surf := mi.mesh.get_surface_count() if mi.mesh else 0
			print("    mesh '", mi.name, "' surfaces=", surf, " skin=", mi.skin != null)
			for i in surf:
				var mat := mi.mesh.surface_get_material(i)
				print("      surface ", i, " material=", mat.resource_name if mat else "<none>", " tris=", mi.mesh.surface_get_array_len(i) / 3)
		root.free()
	quit()
