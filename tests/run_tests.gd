extends Node
## Minimal headless test runner (no plugins needed). From the project folder:
##   godot --headless --fixed-fps 60 res://tests/TestRunner.tscn
## Exits with code 0 when everything passes, 1 otherwise. SUITE=test_police
## (an environment variable) runs just that suite.

const SUITES: Array[String] = [
	"res://tests/test_road_geo.gd",
	"res://tests/test_road_manager.gd",
	"res://tests/test_driving.gd",
	"res://tests/test_contacts.gd",
	"res://tests/test_route.gd",
	"res://tests/test_traffic.gd",
	"res://tests/test_race_flow.gd",
	"res://tests/test_cars.gd",
	"res://tests/test_props.gd",
	"res://tests/test_garage.gd",
	"res://tests/test_sites.gd",
	"res://tests/test_audio.gd",
	"res://tests/test_police.gd",
]


func _ready() -> void:
	await get_tree().process_frame
	var passed := 0
	var failed := 0
	var only := OS.get_environment("SUITE")
	for path in SUITES:
		if only != "" and path.get_file().get_basename() != only:
			continue
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("  FAIL  %s: doesn't compile (see the errors above)" % path.get_file())
			continue
		var suite: TestSuite = script.new()
		suite.name = path.get_file().get_basename()
		add_child(suite)
		for method in suite.get_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			suite.failures.clear()
			await suite.call(method_name)
			if suite.failures.is_empty():
				passed += 1
				print("  PASS  %s.%s" % [suite.name, method_name])
			else:
				failed += 1
				print("  FAIL  %s.%s" % [suite.name, method_name])
				for failure in suite.failures:
					print("          - " + failure)
		suite.queue_free()
		await get_tree().process_frame
	print("\n%d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
