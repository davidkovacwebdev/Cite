extends Control

class_name OpponentPanel

var toast_timer: Timer


func _ready() -> void:
	visible = Global.is_multiplayer_match
	if not visible:
		return

	%NameLabel.text = Global.multiplayer_opponent_name
	%GuessToast.visible = false
	if not Global.is_dummy_opponent:
		_load_avatar()

	MultiplayerSync.opponent_vitals_updated.connect(_on_opponent_vitals_updated)
	MultiplayerSync.opponent_guess_result.connect(_on_opponent_guess_result)
	# HealthComponent/ManaComponent's is_display_only branch resets to full
	# every round (it has no memory of the opponent's real vitals), so apply
	# the last known values immediately instead of waiting for the next real
	# broadcast to correct it.
	%HealthDisplay.set_display_vitals(Global.last_known_opponent_hp, Global.last_known_opponent_max_hp)
	%ManaDisplay.set_display_vitals(Global.last_known_opponent_mana, Global.last_known_opponent_max_mana)

	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 2.5
	toast_timer.timeout.connect(func(): %GuessToast.visible = false)
	add_child(toast_timer)


func _on_opponent_vitals_updated(hp: int, max_hp: int, mana: int, max_mana: int) -> void:
	%HealthDisplay.set_display_vitals(hp, max_hp)
	%ManaDisplay.set_display_vitals(mana, max_mana)


func _on_opponent_guess_result(correct: bool, damage: int) -> void:
	if correct:
		return  # the dramatic banner (board.gd) covers this case
	%GuessToast.text = "Opponent guessed wrong!"
	%GuessToast.visible = true
	toast_timer.start()


func _load_avatar() -> void:
	var steam_id = Global.multiplayer_opponent_id
	var handle = Steam.getMediumFriendAvatar(steam_id)
	if handle > 0:
		_apply_avatar_handle(handle)
	else:
		Steam.avatar_image_loaded.connect(_on_avatar_image_loaded)


func _on_avatar_image_loaded(steam_id: int, width: int, height: int, buffer: PackedByteArray) -> void:
	if steam_id != Global.multiplayer_opponent_id:
		return
	Steam.avatar_image_loaded.disconnect(_on_avatar_image_loaded)
	_apply_avatar_image(width, height, buffer)


func _apply_avatar_handle(handle: int) -> void:
	var size_data = Steam.getImageSize(handle)
	if not size_data.get("success", false):
		return
	var buffer_data = Steam.getImageRGBA(handle)
	if not buffer_data.get("success", false):
		return
	_apply_avatar_image(int(size_data["width"]), int(size_data["height"]), buffer_data["buffer"])


func _apply_avatar_image(width: int, height: int, buffer: PackedByteArray) -> void:
	if width <= 0 or height <= 0 or buffer.is_empty():
		return
	var image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, buffer)
	%Avatar.texture = ImageTexture.create_from_image(image)
