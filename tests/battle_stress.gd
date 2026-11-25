extends SceneTree

const Game = preload("res://game.tscn")
const Benchmark = preload("res://scripts/benchmark/fleet_benchmark.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = Game.instantiate()
	game.test_profile = true
	root.add_child(game)
	var benchmark := Benchmark.new()
	await benchmark.run(game)
