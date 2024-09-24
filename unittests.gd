
extends SceneTree

const TestRunner:= preload("res://glecs_test_runner.tscn")

func _initialize():
	change_scene_to_packed(TestRunner)
	await process_frame
	await process_frame
	current_scene.run_tests()