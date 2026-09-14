extends SceneTree

func _init() -> void:
	var dirs: Array[String] = ["voz", "sfx", "ambiente"]
	var total := 0
	var bad := 0
	for d: String in dirs:
		var base: String = "res://assets/audio/" + d
		var da := DirAccess.open(base)
		if da == null:
			print("!! no such dir: ", base)
			continue
		print("=== ", d)
		for f: String in da.get_files():
			if f.ends_with(".import"):
				continue
			var path: String = base + "/" + f
			var st := ResourceLoader.load(path)
			total += 1
			if st == null:
				print("  !! FALLO al cargar ", f)
				bad += 1
				continue
			var loops := "-"
			if st is AudioStreamWAV:
				loops = "loop=" + str((st as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED)
			elif st is AudioStreamMP3:
				loops = "loop=" + str((st as AudioStreamMP3).loop)
			elif st is AudioStreamOggVorbis:
				loops = "loop=" + str((st as AudioStreamOggVorbis).loop)
			print("  %-26s %-18s %6.2fs  %s" % [f, st.get_class(), (st as AudioStream).get_length(), loops])
	print("\ntotal=", total, "  fallos=", bad)
	quit(1 if bad > 0 else 0)
