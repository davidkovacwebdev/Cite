# SoundManager.gd
extends Node

class_name SoundManager

# Just one player for all sounds to keep it simple
@onready var music_player: AudioStreamPlayer2D = $MusicPlayer
@onready var sfx_player: AudioStreamPlayer2D = $SFXPlayer
@onready var master_player: AudioStreamPlayer2D = $MasterPlayer

var master_volume: float = 0.5
var sfx_volume: float = 0.5
var music_volume: float = 0.5


var last_play_time: int = 0

# Separate players for play_sfx_overlapping() - see there.
const SFX_POOL_SIZE := 6
var sfx_pool: Array[AudioStreamPlayer2D] = []
var sfx_pool_index: int = 0
var cooldown_ms: int = 50  # 0.05 seconds between sounds

const CLICK_SOUNDS = [
	preload("res://assets/sounds/sfx/click/click1.wav"),
	preload("res://assets/sounds/sfx/click/click2.wav"),
	preload("res://assets/sounds/sfx/click/click3.wav"),
	preload("res://assets/sounds/sfx/click/click4.wav"),
	preload("res://assets/sounds/sfx/click/click5.wav")
]

func _ready():
	# Create a single audio player
	# Make sure each player is on the correct bus
	music_player.bus = "Music"
	sfx_player.bus = "SFX"
	master_player.bus = "Master"
	
	for i in SFX_POOL_SIZE:
		var player = AudioStreamPlayer2D.new()
		player.bus = "SFX"
		add_child(player)
		sfx_pool.append(player)

	play_music_direct("res://assets/sounds/music/music.mp3")
	

# Basic play function - call this from anywhere
func play_sound(sound_path: String, bus: String = "SFX"):
	var current_time = Time.get_ticks_msec()
	if current_time - last_play_time < cooldown_ms:
		return  # Skip if too soon
	last_play_time = current_time
	var sound = load(sound_path)
	if sound:
		match bus:
			"Music":
				music_player.stream = sound
				music_player.play()
			"SFX":
				sfx_player.stream = sound
				sfx_player.play()
			"UI":
				master_player.stream = sound
				master_player.play()
			_:
				print("Unknown bus: ", bus)
	else:
		print("Sound not found: ", sound_path)
		
# Plays on its own player from a small round-robin pool instead of the shared
# sfx_player, and skips the global cooldown - so the sound can't be cut off by
# whatever plays next (e.g. the hover woosh of the card that slides under the
# mouse right after one is played) or skipped because something else just
# played. Used by the multiplayer card sounds. pitch_variation randomizes the
# pitch by up to +/- that fraction (0.05 = 5%).
func play_sfx_overlapping(sound_path: String, volume_db: float = 0.0, pitch_variation: float = 0.0) -> void:
	var sound = load(sound_path)
	if not sound:
		print("Sound not found: ", sound_path)
		return
	var player = sfx_pool[sfx_pool_index]
	sfx_pool_index = (sfx_pool_index + 1) % sfx_pool.size()
	player.stream = sound
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()

func play_sound_with_pitch(sound_path: String, bus: String = "SFX", min_pitch: float = 0.9, max_pitch: float = 1.1):
	var current_time = Time.get_ticks_msec()
	if current_time - last_play_time < cooldown_ms:
		return  # Skip if too soon
	last_play_time = current_time
	var sound = load(sound_path)
	if sound:
		match bus:
			"Music":
				music_player.stream = sound
				music_player.pitch_scale = randf_range(min_pitch, max_pitch)
				music_player.play()
			"SFX":
				sfx_player.stream = sound
				sfx_player.pitch_scale = randf_range(min_pitch, max_pitch)
				sfx_player.play()
			"Master":
				master_player.stream = sound
				master_player.pitch_scale = randf_range(min_pitch, max_pitch)
				master_player.play()
			_:
				print("Unknown bus: ", bus)
	else:
		print("Sound not found: ", sound_path)
		
		
		
		
func play_random_click(bus: String = "SFX", min_pitch: float = 0.9, max_pitch: float = 1.1):
	# 1. Cooldown Check
	var current_time = Time.get_ticks_msec()
	if current_time - last_play_time < cooldown_ms:
		return
	last_play_time = current_time

	# 2. Pick a random sound from the hardcoded array
	var sound = CLICK_SOUNDS.pick_random()
	
	# 3. Play Logic
	if sound:
		match bus:
			"SFX":
				sfx_player.pitch_scale = randf_range(min_pitch, max_pitch)
				sfx_player.stream = sound
				sfx_player.play()
			"Music":
				music_player.pitch_scale = randf_range(min_pitch, max_pitch)
				music_player.stream = sound
				music_player.play()
			"UI":
				master_player.pitch_scale = randf_range(min_pitch, max_pitch)
				master_player.stream = sound
				master_player.play()
	else:
		print("Error: Click sound resource is null.")
		
		
func play_random_sound_from_folder_with_pitch(folder_path: String, bus: String = "SFX", min_pitch: float = 0.9, max_pitch: float = 1.1):
	var current_time = Time.get_ticks_msec()
	if current_time - last_play_time < cooldown_ms:
		return  # Skip if too soon
	last_play_time = current_time
	var dir = DirAccess.open(folder_path)
	if dir:
		var sound_files = []
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".wav") or file_name.ends_with(".ogg") or file_name.ends_with(".mp3"):
				sound_files.append(file_name)
			file_name = dir.get_next()
		
		dir.list_dir_end()
		
		if sound_files.size() > 0:
			var random_file = sound_files[randi() % sound_files.size()]
			var full_path = folder_path.path_join(random_file)
			
			# Load and play with pitch variation
			var sound = load(full_path)
			if sound:
				match bus:
					"Music":
						music_player.pitch_scale = randf_range(min_pitch, max_pitch)
						music_player.stream = sound
						music_player.play()
					"SFX":
						sfx_player.pitch_scale = randf_range(min_pitch, max_pitch)
						sfx_player.stream = sound
						sfx_player.play()
					"UI":
						master_player.pitch_scale = randf_range(min_pitch, max_pitch)
						master_player.stream = sound
						master_player.play()
			else:
				print("Failed to load sound: ", full_path)
	else:
		print("Folder not found: ", folder_path)




func set_master_volume(value: float):
	master_volume = clamp(value, 0.0, 1.0)
	update_volumes()


func set_sfx_volume(value: float):
	sfx_volume = clamp(value, 0.0, 1.0)
	update_volumes()
	
func set_music_volume(value: float):
	
	music_volume = clamp(value, 0.0, 1.0)
	update_volumes()

	
func update_volumes():
	# Apply volumes to audio buses
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(master_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(sfx_volume))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(music_volume))
	
func play_music_direct(music_path: String):
	var music = load(music_path)
	if music:
		music_player.stream = music
		music_player.play()
	else:
		print("ERROR: Can't load music:", music_path)


func stop_music():
	music_player.stop()
