extends SceneTree

const Audio = preload("res://audio.gd")
var failed := false

func check(ok: bool, label: String) -> void:
	if not ok:
		failed = true
		printerr("FAIL ",label)

func _initialize() -> void:
	var ambient := Audio.synth_ambient(4.0)
	check(ambient.data.size()/2 == 88200 and ambient.loop_end == 88199,"four-second opening ambience ends at its last PCM frame")
	for stream in [ambient,Audio.synth_layer(false),Audio.synth_layer(true)]:
		var frames: int = stream.data.size()/2
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == frames-1,"every generated loop has an in-bounds endpoint")
	var click := Audio.synth_tone(0.04,640.0,420.0,0.14,0.02,"sine")
	check(click.loop_mode == AudioStreamWAV.LOOP_DISABLED,"one-shot effects still finish")
	for samples in [PackedFloat32Array(),PackedFloat32Array([0.5])]:
		check(Audio.pack_pcm(samples,true).loop_mode == AudioStreamWAV.LOOP_DISABLED,"degenerate loops are not submitted to the mixer")
	print("Audio loop checks ", "failed" if failed else "passed")
	quit(1 if failed else 0)
