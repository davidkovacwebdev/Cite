extends Node

# Steam Workshop support for community multiplayer playlists.
#
# A playlist is the same {"Article Title": wikipedia_page_id, ...} format as
# the built-in ones in Global.MULTIPLAYER_PLAYLIST_FOLDER. Uploading creates
# a Workshop item holding a single playlist.json.
#
# Which uploads show up in game: with REQUIRE_APPROVAL on, only the items in
# the developer's APPROVED_COLLECTION_ID collection (approving = adding it to
# that collection on Steam). With it off, every published Cite playlist.
# refresh_community_playlists() re-reads that list (on launch and whenever
# the lobby opens), downloads anything new or updated, and copies each
# playlist into CACHE_DIR so it still works offline / after Steam cleans up
# its download. Community playlists are addressed as "ws_<file_id>"
# everywhere a built-in one would use its filename.
#
# Upload flow: validate_playlist() -> upload_playlist() -> createItem ->
# item_created -> startItemUpdate/set fields -> submitItemUpdate ->
# item_updated. Progress is polled each frame while uploading.

signal upload_progress(stage: String, fraction: float)
signal upload_finished(success: bool, file_id: int, message: String, needs_legal_agreement: bool)
signal community_playlists_changed
signal playlist_ready(file_id: int, ok: bool)

const APP_ID := 4339350
const PLAYLIST_FILENAME := "playlist.json"
const PLAYLIST_TAG := "Playlist"
const METADATA_FORMAT_VERSION := 1
const UPLOAD_STAGING_DIR := "user://workshop_upload/"

const APPROVED_COLLECTION_ID := 3822228992
const REQUIRE_APPROVAL := true
const COMMUNITY_PREFIX := "ws_"
const CACHE_DIR := "user://workshop_playlists/"
const CACHE_INDEX_PATH := CACHE_DIR + "index.json"
# The collection's item list comes from Steam's public web API: GodotSteam's
# getQueryUGCChildren returns garbled IDs in this plugin version.
const COLLECTION_DETAILS_URL := "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/"
const COLLECTION_TIMEOUT_SECONDS := 15.0

const MIN_PLAYLIST_ARTICLES := 30
const MAX_PLAYLIST_ARTICLES := 5000
const MAX_TITLE_LENGTH := 128  # Steam's limit
const MAX_DESCRIPTION_LENGTH := 8000  # Steam's limit
const MAX_FILE_BYTES := 1024 * 1024
const MAX_PREVIEW_BYTES := 1024 * 1024  # Steam's limit for preview images
const PREVIEW_EXTENSIONS := ["png", "jpg", "jpeg"]
# Downloaded previews are shrunk to this before caching - they're only shown
# as small icons in the playlist list.
const PREVIEW_CACHE_SIZE := 128

const LEGAL_AGREEMENT_URL := "https://steamcommunity.com/sharedfiles/workshoplegalagreement"
const ITEM_PAGE_URL := "https://steamcommunity.com/sharedfiles/filedetails/?id=%d"

var is_uploading: bool = false
var update_handle: int = 0

# Kept between the createItem callback and the submit, so a failed submit
# can delete the empty item it would otherwise leave behind.
var pending_file_id: int = 0
var pending_title: String = ""
var pending_description: String = ""
var pending_article_count: int = 0
var pending_preview_path: String = ""

# file_id (String, JSON-safe) -> {"title": String, "time_updated": int,
# "preview_url": String (URL of the cached preview, "" if none)}, for every
# community playlist currently available in game - mirrors CACHE_INDEX_PATH,
# where each one's file is CACHE_DIR/<file_id>.json and its preview icon
# CACHE_DIR/<file_id>_preview.png.
var community_playlists: Dictionary = {}
# file_id (String) -> preview URL Steam reported in the latest refresh
var latest_preview_urls: Dictionary = {}
var preview_downloads: Dictionary = {}  # file_id (String) -> HTTPRequest
var preview_textures: Dictionary = {}  # file_id (String) -> Texture2D
var is_refreshing: bool = false
var query_handle: int = 0
var query_stage: String = ""  # "collection" (web API) or "details" (Steam query)
var collection_request: HTTPRequest
# file_id -> {"title", "time_updated"} for downloads still in flight
var pending_downloads: Dictionary = {}


func _ready() -> void:
	Steam.item_created.connect(_on_item_created)
	Steam.item_updated.connect(_on_item_updated)
	Steam.ugc_query_completed.connect(_on_ugc_query_completed)
	Steam.item_downloaded.connect(_on_item_downloaded)
	set_process(false)
	collection_request = HTTPRequest.new()
	collection_request.timeout = COLLECTION_TIMEOUT_SECONDS
	collection_request.request_completed.connect(_on_collection_response)
	add_child(collection_request)
	_load_cache_index()
	refresh_community_playlists.call_deferred()


# --- Community playlists (download side) -----------------------------------

static func is_community_id(playlist_id: String) -> bool:
	return playlist_id.begins_with(COMMUNITY_PREFIX)


static func file_id_of(playlist_id: String) -> int:
	return playlist_id.trim_prefix(COMMUNITY_PREFIX).to_int()


static func playlist_id_of(file_id: int) -> String:
	return COMMUNITY_PREFIX + str(file_id)


# Community playlist IDs, sorted by title.
func get_playlist_ids() -> Array:
	var keys = community_playlists.keys()
	keys.sort_custom(func(a, b): return community_playlists[a].title.naturalnocasecmp_to(community_playlists[b].title) < 0)
	return keys.map(func(key): return COMMUNITY_PREFIX + key)


func has_playlist(file_id: int) -> bool:
	return community_playlists.has(str(file_id)) and FileAccess.file_exists(cache_path(file_id))


func get_title(file_id: int) -> String:
	return community_playlists.get(str(file_id), {}).get("title", "")


func get_time_updated(file_id: int) -> int:
	return int(community_playlists.get(str(file_id), {}).get("time_updated", 0))


func cache_path(file_id: int) -> String:
	return CACHE_DIR + str(file_id) + ".json"


func preview_path(file_id: int) -> String:
	return CACHE_DIR + str(file_id) + "_preview.png"


# The playlist's Workshop preview image, or null if it has none (yet).
func get_preview_texture(file_id: int) -> Texture2D:
	var key = str(file_id)
	if preview_textures.has(key):
		return preview_textures[key]
	var texture: Texture2D = null
	if FileAccess.file_exists(preview_path(file_id)):
		var image = Image.load_from_file(ProjectSettings.globalize_path(preview_path(file_id)))
		if image:
			texture = ImageTexture.create_from_image(image)
	preview_textures[key] = texture
	return texture


func refresh_community_playlists() -> void:
	if is_refreshing or not Steam.loggedOn():
		return
	is_refreshing = true
	if REQUIRE_APPROVAL:
		query_stage = "collection"
		var body = "collectioncount=1&publishedfileids%%5B0%%5D=%d" % APPROVED_COLLECTION_ID
		var error = collection_request.request(COLLECTION_DETAILS_URL,
			["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, body)
		if error != OK:
			print("Workshop: couldn't request the approved collection (error %d)" % error)
			_end_refresh()
		return
	else:
		query_stage = "details"
		query_handle = Steam.createQueryAllUGCRequestPage(Steam.UGC_QUERY_RANKED_BY_PUBLICATION_DATE,
			Steam.UGC_MATCHING_UGC_TYPE_ITEMS_READY_TO_USE, APP_ID, APP_ID, 1)
		Steam.addRequiredTag(query_handle, PLAYLIST_TAG)
	_send_query()


func _send_query() -> void:
	if query_handle == Steam.UGC_QUERY_HANDLE_INVALID:
		_end_refresh()
		return
	# Always ask Steam itself - a cached answer could hide a playlist that
	# was just approved or removed.
	Steam.setAllowCachedResponse(query_handle, 0)
	Steam.sendQueryUGCRequest(query_handle)


func _on_ugc_query_completed(handle: int, result: int, results_returned: int, _total_matching: int, _cached: bool, _next_cursor: String = "") -> void:
	if handle != query_handle or not is_refreshing:
		return
	if result != Steam.RESULT_OK:
		print("Workshop: playlist query failed (%s)" % _result_text(result))
		Steam.releaseQueryUGCRequest(handle)
		_end_refresh()
		return

	var found: Dictionary = {}
	for i in results_returned:
		var item: Dictionary = Steam.getQueryUGCResult(handle, i)
		if item.get("result", 0) != Steam.RESULT_OK or item.get("banned", false):
			continue
		if int(item.get("consumer_app_id", APP_ID)) != APP_ID:
			continue
		found[str(item.file_id)] = {
			"title": String(item.get("title", "Untitled")),
			"time_updated": int(item.get("time_updated", 0)),
			"preview_url": Steam.getQueryUGCPreviewURL(handle, i),
		}
	Steam.releaseQueryUGCRequest(handle)
	_apply_refreshed_list(found)


func _on_collection_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not is_refreshing or query_stage != "collection":
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		# Offline or Steam down - keep the cached playlists as they are.
		print("Workshop: approved collection unavailable (result %d, HTTP %d)" % [result, response_code])
		_end_refresh()
		return

	var children = _parse_collection_children(body.get_string_from_utf8())
	if children == null:
		print("Workshop: unexpected approved collection response")
		_end_refresh()
		return
	if children.is_empty():
		_apply_refreshed_list({})
		return
	query_stage = "details"
	query_handle = Steam.createQueryUGCDetailsRequest(children)
	_send_query()


# Item IDs in the collection, or null if the response doesn't look right
# (so a bad response can't wipe every community playlist).
func _parse_collection_children(text: String) -> Variant:
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var details = data.get("response", {}).get("collectiondetails", [])
	if typeof(details) != TYPE_ARRAY or details.is_empty() or typeof(details[0]) != TYPE_DICTIONARY:
		return null
	if int(details[0].get("result", 0)) != Steam.RESULT_OK:
		return null
	var ids: Array = []
	for child in details[0].get("children", []):
		# filetype 0 = a regular item (not a nested collection)
		if typeof(child) == TYPE_DICTIONARY and int(child.get("filetype", 0)) == 0:
			var file_id = String(child.get("publishedfileid", "")).to_int()
			if file_id > 0:
				ids.append(file_id)
	return ids


# Drops playlists no longer listed (unapproved/deleted), keeps up-to-date
# ones, and downloads the rest.
func _apply_refreshed_list(found: Dictionary) -> void:
	for key in community_playlists.keys():
		if not found.has(key):
			community_playlists.erase(key)
			preview_textures.erase(key)
			DirAccess.remove_absolute(cache_path(int(key)))
			DirAccess.remove_absolute(preview_path(int(key)))

	for key in found:
		var info = found[key]
		var file_id = int(key)
		latest_preview_urls[key] = info.preview_url
		if has_playlist(file_id) and get_time_updated(file_id) >= info.time_updated:
			community_playlists[key].title = info.title
			_ensure_preview(file_id)
		else:
			_fetch(file_id, info.title, info.time_updated)

	_save_cache_index()
	_end_refresh()
	community_playlists_changed.emit()


func _end_refresh() -> void:
	is_refreshing = false
	query_handle = 0
	query_stage = ""


# Makes sure a specific playlist is available locally - used by the guest
# for whatever the host picked. Answers through playlist_ready.
func ensure_playlist(file_id: int, title: String, time_updated: int, force: bool = false) -> void:
	if not force and has_playlist(file_id) and get_time_updated(file_id) >= time_updated:
		playlist_ready.emit.call_deferred(file_id, true)
		return
	_fetch(file_id, title, time_updated)


func _fetch(file_id: int, title: String, time_updated: int) -> void:
	var state = Steam.getItemState(file_id)
	var installed = (state & Steam.ITEM_STATE_INSTALLED) != 0 and (state & Steam.ITEM_STATE_NEEDS_UPDATE) == 0
	if installed and _cache_from_install(file_id, title, time_updated):
		_save_cache_index()
		_ensure_preview(file_id)
		community_playlists_changed.emit.call_deferred()
		playlist_ready.emit.call_deferred(file_id, true)
		return

	pending_downloads[file_id] = {"title": title, "time_updated": time_updated}
	if not Steam.downloadItem(file_id, true):
		pending_downloads.erase(file_id)
		print("Workshop: couldn't start downloading playlist ", file_id)
		playlist_ready.emit.call_deferred(file_id, false)


func _on_item_downloaded(result: int, file_id: int, app_id: int) -> void:
	if app_id != APP_ID or not pending_downloads.has(file_id):
		return
	var info = pending_downloads[file_id]
	pending_downloads.erase(file_id)
	var ok = result == Steam.RESULT_OK and _cache_from_install(file_id, info.title, info.time_updated)
	if not ok:
		print("Workshop: playlist %d didn't download (%s)" % [file_id, _result_text(result)])
	else:
		_save_cache_index()
		_ensure_preview(file_id)
		community_playlists_changed.emit()
	playlist_ready.emit(file_id, ok)


# Copies a downloaded playlist.json into CACHE_DIR, exactly as uploaded so
# both players end up with byte-identical files (see Global.get_playlist_hash).
func _cache_from_install(file_id: int, title: String, time_updated: int) -> bool:
	var info: Dictionary = Steam.getItemInstallInfo(file_id)
	var folder = String(info.get("folder", ""))
	if folder.is_empty():
		return false
	var source = folder.path_join(PLAYLIST_FILENAME)
	var check = validate_playlist_file(source)
	if not check.ok:
		print("Workshop: playlist %d is invalid: %s" % [file_id, check.error])
		return false
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var text = FileAccess.get_file_as_string(source)
	var file = FileAccess.open(cache_path(file_id), FileAccess.WRITE)
	if not file:
		return false
	file.store_string(text)
	file.close()
	var entry: Dictionary = community_playlists.get(str(file_id), {"preview_url": ""})
	entry.title = title
	entry.time_updated = time_updated
	community_playlists[str(file_id)] = entry
	return true


# Downloads the playlist's preview image if it's new or changed since the
# cached one. Only known after a refresh (latest_preview_urls) - a guest
# fetching the host's pick directly just shows the fallback icon until then.
func _ensure_preview(file_id: int) -> void:
	var key = str(file_id)
	if not community_playlists.has(key) or not latest_preview_urls.has(key) or preview_downloads.has(key):
		return
	var url: String = latest_preview_urls[key]
	var entry: Dictionary = community_playlists[key]
	if url.is_empty():
		if not String(entry.get("preview_url", "")).is_empty():
			entry.preview_url = ""
			preview_textures.erase(key)
			DirAccess.remove_absolute(preview_path(file_id))
			_save_cache_index()
			community_playlists_changed.emit.call_deferred()
		return
	if entry.get("preview_url", "") == url and FileAccess.file_exists(preview_path(file_id)):
		return

	var request = HTTPRequest.new()
	request.timeout = COLLECTION_TIMEOUT_SECONDS
	add_child(request)
	preview_downloads[key] = request
	request.request_completed.connect(_on_preview_downloaded.bind(file_id, url))
	if request.request(url) != OK:
		preview_downloads.erase(key)
		request.queue_free()


func _on_preview_downloaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, file_id: int, url: String) -> void:
	var key = str(file_id)
	if preview_downloads.has(key):
		preview_downloads[key].queue_free()
		preview_downloads.erase(key)
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or not community_playlists.has(key):
		return
	var image = _image_from_bytes(body)
	if image == null:
		print("Workshop: couldn't read the preview image for playlist ", file_id)
		return
	var longest = max(image.get_width(), image.get_height())
	if longest > PREVIEW_CACHE_SIZE:
		var scale = float(PREVIEW_CACHE_SIZE) / longest
		image.resize(max(1, int(image.get_width() * scale)), max(1, int(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	if image.save_png(preview_path(file_id)) != OK:
		return
	community_playlists[key].preview_url = url
	preview_textures.erase(key)
	_save_cache_index()
	community_playlists_changed.emit()


func _image_from_bytes(bytes: PackedByteArray) -> Image:
	if bytes.size() < 4:
		return null
	var image = Image.new()
	var error = ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:  # PNG
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:  # JPEG
		error = image.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x47 and bytes[1] == 0x49:  # GIF - not decodable here
		return null
	elif bytes[0] == 0x52 and bytes[1] == 0x49:  # RIFF/WebP
		error = image.load_webp_from_buffer(bytes)
	return image if error == OK else null


func _load_cache_index() -> void:
	community_playlists.clear()
	if not FileAccess.file_exists(CACHE_INDEX_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(CACHE_INDEX_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for key in data:
		var entry = data[key]
		if typeof(entry) == TYPE_DICTIONARY and FileAccess.file_exists(cache_path(int(key))):
			community_playlists[key] = {
				"title": String(entry.get("title", "Untitled")),
				"time_updated": int(entry.get("time_updated", 0)),
				"preview_url": String(entry.get("preview_url", "")),
			}


func _save_cache_index() -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var file = FileAccess.open(CACHE_INDEX_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(community_playlists, "  "))
		file.close()


# --- Validation ------------------------------------------------------------

# Reads and checks a playlist file. Returns {"ok": true, "playlist": Dictionary}
# with the cleaned-up playlist, or {"ok": false, "error": String}.
func validate_playlist_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _invalid("File not found.")
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return _invalid("Couldn't open the file.")
	if file.get_length() > MAX_FILE_BYTES:
		return _invalid("File is too large (max 1 MB).")
	var text = file.get_as_text()
	file.close()
	return validate_playlist_text(text)


func validate_playlist_text(text: String) -> Dictionary:
	var json = JSON.new()
	if json.parse(text) != OK:
		return _invalid("Not valid JSON (line %d: %s)." % [json.get_error_line() + 1, json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _invalid("A playlist must be a JSON object: {\"Article Title\": page_id, ...}")

	var cleaned: Dictionary = {}
	var seen_ids: Dictionary = {}
	for title in json.data.keys():
		var value = json.data[title]
		var clean_title = String(title).strip_edges()
		if clean_title.is_empty():
			return _invalid("An article has an empty title.")
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return _invalid("\"%s\" needs a Wikipedia page ID number, not %s." % [clean_title, type_string(typeof(value))])
		if typeof(value) == TYPE_FLOAT and value != floor(value):
			return _invalid("\"%s\" has a page ID that isn't a whole number." % clean_title)
		var page_id = int(value)
		if page_id <= 0:
			return _invalid("\"%s\" has an invalid page ID (%d)." % [clean_title, page_id])
		if seen_ids.has(page_id):
			return _invalid("\"%s\" and \"%s\" share page ID %d." % [seen_ids[page_id], clean_title, page_id])
		seen_ids[page_id] = clean_title
		cleaned[clean_title] = page_id

	if cleaned.size() < MIN_PLAYLIST_ARTICLES:
		return _invalid("Playlist has %d articles - it needs at least %d." % [cleaned.size(), MIN_PLAYLIST_ARTICLES])
	if cleaned.size() > MAX_PLAYLIST_ARTICLES:
		return _invalid("Playlist has %d articles - the limit is %d." % [cleaned.size(), MAX_PLAYLIST_ARTICLES])
	return {"ok": true, "playlist": cleaned}


func _invalid(message: String) -> Dictionary:
	return {"ok": false, "error": message}


# Checks an optional preview image for an upload: PNG/JPG, under Steam's
# 1 MB limit, and actually readable.
func validate_preview_image(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _invalid("Image not found.")
	if path.get_extension().to_lower() not in PREVIEW_EXTENSIONS:
		return _invalid("The image must be a PNG or JPG.")
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return _invalid("Couldn't open the image.")
	var size = file.get_length()
	file.close()
	if size > MAX_PREVIEW_BYTES:
		return _invalid("The image is too large (max 1 MB).")
	if Image.load_from_file(path) == null:
		return _invalid("Couldn't read that image.")
	return {"ok": true}


# --- Upload ----------------------------------------------------------------

# Starts uploading an already-validated playlist. Results arrive through
# upload_progress / upload_finished.
func upload_playlist(playlist: Dictionary, title: String, description: String, preview_image_path: String = "") -> void:
	if is_uploading:
		return
	if not Steam.loggedOn():
		upload_finished.emit(false, 0, "Not connected to Steam.", false)
		return

	pending_title = title.strip_edges().left(MAX_TITLE_LENGTH)
	pending_description = description.strip_edges().left(MAX_DESCRIPTION_LENGTH)
	pending_article_count = playlist.size()
	pending_preview_path = preview_image_path
	pending_file_id = 0

	if not _stage_playlist(playlist):
		upload_finished.emit(false, 0, "Couldn't prepare the file for upload.", false)
		return

	is_uploading = true
	upload_progress.emit("Creating Workshop item...", 0.0)
	Steam.createItem(APP_ID, Steam.WORKSHOP_FILE_TYPE_COMMUNITY)


# Writes the cleaned playlist into an empty staging folder - setItemContent
# uploads a whole folder, so it must hold nothing but playlist.json.
func _stage_playlist(playlist: Dictionary) -> bool:
	var dir = DirAccess.open("user://")
	if not dir:
		return false
	if not dir.dir_exists(UPLOAD_STAGING_DIR):
		if dir.make_dir_recursive(UPLOAD_STAGING_DIR) != OK:
			return false
	var staging = DirAccess.open(UPLOAD_STAGING_DIR)
	for leftover in staging.get_files():
		staging.remove(leftover)

	var file = FileAccess.open(UPLOAD_STAGING_DIR + PLAYLIST_FILENAME, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify(playlist, "  "))
	file.close()
	return true


func _on_item_created(result: int, file_id: int, accept_tos: bool) -> void:
	if not is_uploading:
		return
	if result != Steam.RESULT_OK:
		_finish(false, 0, "Couldn't create the Workshop item: " + _result_text(result), false)
		return

	pending_file_id = file_id
	update_handle = Steam.startItemUpdate(APP_ID, file_id)
	Steam.setItemTitle(update_handle, pending_title)
	Steam.setItemDescription(update_handle, pending_description)
	Steam.setItemContent(update_handle, ProjectSettings.globalize_path(UPLOAD_STAGING_DIR))
	Steam.setItemTags(update_handle, [PLAYLIST_TAG], false)
	if not pending_preview_path.is_empty():
		Steam.setItemPreview(update_handle, ProjectSettings.globalize_path(pending_preview_path))
	Steam.setItemMetadata(update_handle, JSON.stringify({
		"format": METADATA_FORMAT_VERSION,
		"articles": pending_article_count,
	}))
	Steam.setItemVisibility(update_handle, Steam.REMOTE_STORAGE_PUBLISHED_VISIBILITY_PUBLIC)
	Steam.submitItemUpdate(update_handle, "Initial upload")
	set_process(true)
	if accept_tos:
		print("Workshop: user still needs to accept the legal agreement")


func _process(_delta: float) -> void:
	if not is_uploading or update_handle == 0:
		return
	var progress: Dictionary = Steam.getItemUpdateProgress(update_handle)
	var status = progress.get("status", Steam.ITEM_UPDATE_STATUS_INVALID)
	var total = float(progress.get("total", 0))
	var fraction = float(progress.get("processed", 0)) / total if total > 0 else 0.0
	upload_progress.emit(_status_text(status), fraction)


func _on_item_updated(result: int, need_to_accept_tos: bool, file_id: int = 0) -> void:
	if not is_uploading:
		return
	var uploaded_id = file_id if file_id != 0 else pending_file_id
	if result != Steam.RESULT_OK:
		# Don't leave an empty, half-made item sitting on the Workshop.
		if pending_file_id != 0:
			Steam.deleteItem(pending_file_id)
		_finish(false, 0, "Upload failed: " + _result_text(result), false)
		return

	if need_to_accept_tos:
		_finish(true, uploaded_id, "Uploaded! It stays hidden until you accept the Steam Workshop agreement.", true)
	else:
		_finish(true, uploaded_id, "Uploaded! It will appear in game once it's approved.", false)


func _finish(success: bool, file_id: int, message: String, needs_legal_agreement: bool) -> void:
	is_uploading = false
	update_handle = 0
	pending_file_id = 0
	set_process(false)
	upload_finished.emit(success, file_id, message, needs_legal_agreement)


func _status_text(status: int) -> String:
	match status:
		Steam.ITEM_UPDATE_STATUS_PREPARING_CONFIG:
			return "Preparing..."
		Steam.ITEM_UPDATE_STATUS_PREPARING_CONTENT:
			return "Preparing playlist..."
		Steam.ITEM_UPDATE_STATUS_UPLOADING_CONTENT:
			return "Uploading playlist..."
		Steam.ITEM_UPDATE_STATUS_UPLOADING_PREVIEW_FILE:
			return "Uploading preview..."
		Steam.ITEM_UPDATE_STATUS_COMMITTING_CHANGES:
			return "Finishing up..."
	return "Uploading..."


func _result_text(result: int) -> String:
	match result:
		Steam.RESULT_ACCESS_DENIED, Steam.RESULT_INSUFFICIENT_PRIVILEGE:
			return "Steam denied access. Workshop may not be enabled yet, or this account can't upload."
		Steam.RESULT_BANNED:
			return "this account is banned from uploading to the Workshop."
		Steam.RESULT_LIMIT_EXCEEDED:
			return "your Steam Cloud space is full."
		Steam.RESULT_TIMEOUT, Steam.RESULT_NO_CONNECTION, Steam.RESULT_SERVICE_UNAVAILABLE:
			return "couldn't reach Steam. Try again in a moment."
		Steam.RESULT_NOT_LOGGED_ON:
			return "not logged in to Steam."
		Steam.RESULT_FILE_NOT_FOUND:
			return "the playlist file went missing during upload."
	return "Steam error %d." % result


# --- Steam pages -----------------------------------------------------------

func open_item_page(file_id: int) -> void:
	_open_url(ITEM_PAGE_URL % file_id)


func open_legal_agreement() -> void:
	_open_url(LEGAL_AGREEMENT_URL)


func _open_url(url: String) -> void:
	if Steam.isOverlayEnabled():
		Steam.activateGameOverlayToWebPage(url)
	else:
		OS.shell_open(url)
