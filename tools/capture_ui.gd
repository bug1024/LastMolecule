extends SceneTree
## Desktop visual smoke capture. All persistence is disabled before scenes are created.
var main: Control
var output := "res://.godot/lab-review"
func _initialize() -> void:
	call_deferred("run")
func shot(name: String) -> void:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Company.default_save_path = ""
	RunSave.save_path = ""
	GameSettings.save_path = ""
	root.size = Vector2i(1280, 800 if OS.get_cmdline_user_args().has("--tall") else 720)
	root.gui_disable_input = true # Captures must not react to incidental mouse clicks.
	if OS.get_cmdline_user_args().has("--english"):
		GameSettings.locale = "en"
		TranslationServer.set_locale("en")
	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await create_timer(1.4).timeout
	await shot("title")
	title._project_select.open()
	await shot("projects")
	title._project_select.close()
	title._archive.open()
	await shot("archive")
	title._archive.close()
	title._credits.open()
	await shot("credits")
	title._credits.close()
	title.queue_free()
	await process_frame
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._battle_view.set_process_unhandled_input(false)
	var game = main.get_node("GameLogic")
	if String(game._current_event.get("id", "")) == "disease":
		game.resolve_event_choice("disease", 0)
	main._mol_editor._work.apply_preset("balanced")
	main._mol_editor._refresh_all()
	await shot("editor")
	if game.is_designing():
		game.submit_molecule(main._mol_editor._work.sites.duplicate())
	main._mol_editor.visible = false
	main._event_popup.visible = false
	await shot("hub")
	main._map_screen.show_map()
	await shot("map")
	main._map_screen.visible = false
	game._start_battle("fight")
	await create_timer(2).timeout
	if is_instance_valid(main._battle_view._tip):
		main._battle_view._tip.get_parent().get_parent().queue_free()
		main._battle_view._tip = null
	await shot("battle")
	# Regression composition: boss pressure, three different mechanisms and low-HP warning.
	game.battles_fought = 1
	game._start_battle("boss")
	await create_timer(5).timeout
	while main._battle_view._busy:
		await process_frame
	var battle = main._battle_view
	var manager = battle._manager
	manager.hand.clear()
	for id in ["exp_assay", "exp_counter", "sig_balance"]:
		manager.hand.append(ResearchCard.from_dict(game.get_card_by_id(id)))
	manager.energy = 1
	manager.player.hp = 77
	battle._shown_player_hp = 77
	battle._refresh_all(true)
	await shot("battle-boss")
	var displayed_molecule = battle._mol.molecule
	for preset in ["potent", "selective"]:
		var candidate := Molecule.create()
		candidate.apply_preset(preset)
		battle._mol.set_molecule(candidate)
		await shot("molecule-" + preset)
	battle._mol.set_molecule(displayed_molecule)
	battle._mol.flash_sites(["L1"], Color(0.9, 0.3, 0.25))
	battle._mol.hit(0.5)
	await shot("molecule-hit")
	manager.player.hp = 20
	battle._shown_player_hp = 20
	battle._refresh_all(true)
	await shot("battle-low-hp")
	manager.player.hp = 77
	battle._shown_player_hp = 77
	battle._refresh_all(true)
	for stage in ["三期临床试验", "一期临床试验"]:
		game.state.stage = stage
		game._start_battle("boss")
		await create_timer(5).timeout
		while battle._busy:
			await process_frame
		await shot("battle-multi" if stage == "三期临床试验" else "battle-dose")
	main._settings.open()
	await shot("settings")
	main._settings.visible = false
	main._help.open()
	await shot("help")
	main._help.close()
	main._pause_menu.open()
	await shot("pause")
	main._pause_menu.close()
	main._card_popup.show_cards(game.build_deck(), "view", 0, 0, game.get_ai_info())
	await shot("deck")
	# Reproduce the previously overflowing mirrored AI artwork at pick and detail scale.
	var pick_cards: Array = []
	for id in ["ai_intel", "clin_endpoint", "ai_tox_predict"]:
		pick_cards.append(ResearchCard.from_dict(game.get_card_by_id(id)))
	main._card_popup.show_cards(pick_cards, "add", 0, 40, game.get_ai_info())
	await shot("card-pick-fixed")
	main._card_popup.visible = false
	CardDetail.open(main, pick_cards[2], {}, game.get_ai_info())
	await shot("card-detail-fixed")
	CardDetail.close_current()
	main._battle_view.visible = false
	main._event_popup.show_event({"id": "research", "title_key": "node.research", "desc_key": "node.research.desc", "choices": [
		{"label_key": "milestone.continue", "effects": {"funding": -3, "data": 5}},
		{"label_key": "milestone.terminate", "effects": {}}]}, false, game.state)
	await shot("event")
	main._event_popup.visible = false
	main._reward_popup.show_reward({"kind": "fight", "resources": {"data": 8, "funding": 2}, "cards": [
		game.get_card_by_id("mol_hit"), game.get_card_by_id("exp_assay"), game.get_card_by_id("ai_screen")], "abilities": []})
	await shot("reward")
	main._reward_popup.visible = false
	var summary: Dictionary = game.company.settle_run(game.state.data, "approved", game.state.funding)
	main._ending.show_ending("approved", "ending.approved.flavor", summary, game.state)
	await shot("ending")
	main.queue_free()
	await process_frame
	await process_frame
	UIKit._art.clear()
	UIKit._icons.clear()
	print("Captured UI review to ", ProjectSettings.globalize_path(output))
	quit()
