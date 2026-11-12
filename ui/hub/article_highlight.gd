extends RefCounted

# Hub's "Article of the Day": one article from the official playlists with
# its Wikipedia image. Picked from the UTC date, so everyone sees the same
# one; today's Daily Challenge articles are skipped (no spoilers). Articles
# without an image are passed over. Cached per day in user://.

const DailyState := preload("res://ui/daily/daily_state.gd")

const CACHE := "user://article_highlight.json"
const IMAGE_CACHE := "user://article_highlight.img"
const API := "https://en.wikipedia.org/w/api.php?action=query&prop=pageimages%%7Cextracts&piprop=thumbnail&pithumbsize=640&exintro=1&explaintext=1&exsentences=2&exlimit=20&pageids=%s&format=json&origin=*"
const HEADERS := ["User-Agent: Cite/1.0 (https://github.com/davidkovacwebdev/Cite)"]
const BATCH := 20
const TIMEOUT := 8.0


static func page_url(id: int) -> String:
	return "https://en.wikipedia.org/?curid=%d" % id


# Today's highlight: {id, title, extract, texture} or {} if it can't load.
static func load_today(host: Node) -> Dictionary:
	var today := DailyState.today_date()
	var cached := _read_cache(today)
	if not cached.is_empty():
		return cached
	var picked := await _pick(host, today)
	if picked.is_empty():
		return {}
	var bytes := await _fetch(host, picked["image"])
	var tex := _texture(bytes)
	if tex == null:
		return {}
	var file := FileAccess.open(IMAGE_CACHE, FileAccess.WRITE)
	if file:
		file.store_buffer(bytes)
		file.close()
	picked.erase("image")
	picked["date"] = today
	file = FileAccess.open(CACHE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(picked))
		file.close()
	picked["texture"] = tex
	return picked


static func _read_cache(today: String) -> Dictionary:
	var file := FileAccess.open(CACHE, FileAccess.READ)
	if not file:
		return {}
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not (data is Dictionary and data.get("date") == today):
		return {}
	var tex := _texture(FileAccess.get_file_as_bytes(IMAGE_CACHE))
	if tex == null:
		return {}
	data["id"] = int(data.get("id", 0))
	data["texture"] = tex
	return data


# Shuffles the official pool with the date as seed, then takes the first
# article (in that order) that has an image and an intro.
static func _pick(host: Node, today: String) -> Dictionary:
	var skip := {}
	for id in DailyState.scheduled_ids(today):
		skip[int(id)] = true
	var ids: Array = []
	for id in Global.get_playlist_article_ids(Global.OFFICIAL_POOL):
		if not skip.has(int(id)):
			ids.append(int(id))
	if ids.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = ("highlight" + today).hash()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	for start in range(0, mini(ids.size(), BATCH * 3), BATCH):
		var batch := ids.slice(start, start + BATCH)
		var body := await _fetch(host, API % "|".join(batch.map(func(i): return str(i))))
		var data = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
		if not (data is Dictionary):
			return {}
		var pages: Dictionary = data.get("query", {}).get("pages", {})
		for id in batch:
			var p = pages.get(str(id))
			if p is Dictionary and p.get("thumbnail") is Dictionary and str(p.get("extract", "")).length() > 40:
				return {"id": id, "title": str(p.get("title", "")), "extract": str(p["extract"]).strip_edges(),
					"image": str(p["thumbnail"].get("source", ""))}
	return {}


static func _fetch(host: Node, url: String) -> PackedByteArray:
	if url.is_empty() or not is_instance_valid(host):
		return PackedByteArray()
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	host.add_child(http)
	if http.request(url, HEADERS) != OK:
		http.queue_free()
		return PackedByteArray()
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return PackedByteArray()
	return res[3]


static func _texture(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	elif bytes.slice(0, 3).get_string_from_ascii() == "GIF":
		return null
	if err != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
