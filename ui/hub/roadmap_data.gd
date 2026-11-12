extends RefCounted

# Roadmap items (hub "Roadmaps" tab). Stored in BUNDLED_PATH, which ships
# with the game and is edited from the F12 dev panel (dev/dev_tools.gd) when
# running from the editor. Players' games also download the copy on GitHub's
# main branch (ONLINE_URL), so a committed + pushed edit shows up without a
# new build; the last download is cached for offline starts.
#
# Item: {"id", "title", "description", "expected": "YYYY-MM-DD", free text
#        like "Q1 2027", or "" (when the feature should arrive), "added": "YYYY-MM-DD" (when the item
#        was put on the roadmap - set automatically), "pinned": bool (shown
#        first, with the featured card)}. Stored as YYYY-MM-DD so they sort;
# shown and typed in European order, DD.MM.YYYY (pretty_date / from_input).

const BUNDLED_PATH := "res://assets/data/roadmap.json"
const ONLINE_URL := "https://raw.githubusercontent.com/davidkovacwebdev/Cite/main/assets/data/roadmap.json"
const CACHE_PATH := "user://roadmap_cache.json"
const TIMEOUT := 6.0


static func parse(text: String) -> Array:
	var data = JSON.parse_string(text)
	if not data is Dictionary or not data.get("items") is Array:
		return []
	var items := []
	for raw in data["items"]:
		if not raw is Dictionary or String(raw.get("title", "")).strip_edges().is_empty():
			continue
		items.append({
			"id": String(raw.get("id", "")),
			"title": String(raw.get("title", "")).strip_edges(),
			"description": String(raw.get("description", "")).strip_edges(),
			"expected": String(raw.get("expected", "")).strip_edges(),
			"added": String(raw.get("added", "")).strip_edges(),
			"pinned": bool(raw.get("pinned", false)),
		})
	return items


static func load_bundled() -> Array:
	return parse(FileAccess.get_file_as_string(BUNDLED_PATH)) if FileAccess.file_exists(BUNDLED_PATH) else []


static func load_cached() -> Array:
	return parse(FileAccess.get_file_as_string(CACHE_PATH)) if FileAccess.file_exists(CACHE_PATH) else []


# Writes BUNDLED_PATH (editor runs only - res:// is read-only in exports).
static func save_bundled(items: Array) -> bool:
	var f := FileAccess.open(BUNDLED_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"items": items}, "\t") + "\n")
	return true


# The list to show (await it). Dev runs: the local file you're editing.
# Players: the online copy (cached), else the last cached one, else bundled.
static func fetch(host: Node) -> Array:
	if Global.dev_tools_available():
		return load_bundled()
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	host.add_child(http)
	if http.request(ONLINE_URL) == OK:
		var reply: Array = await http.request_completed
		if is_instance_valid(http):
			http.queue_free()
		if int(reply[0]) == HTTPRequest.RESULT_SUCCESS and int(reply[1]) == 200:
			var text: String = (reply[3] as PackedByteArray).get_string_from_utf8()
			var items := parse(text)
			if not items.is_empty() or text.contains("\"items\""):
				var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
				if f:
					f.store_string(text)
				return items
	elif is_instance_valid(http):
		http.queue_free()
	var cached := load_cached()
	return cached if not cached.is_empty() else load_bundled()


static func is_valid_date(text: String) -> bool:
	var re := RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$")
	if re.search(text) == null:
		return false
	var parts := text.split("-")
	var month := parts[1].to_int()
	var day := parts[2].to_int()
	return month >= 1 and month <= 12 and day >= 1 and day <= 31


# "2026-12-05" -> "05.12.2026" (anything else is shown as typed).
static func pretty_date(text: String) -> String:
	if not is_valid_date(text):
		return text
	var parts := text.split("-")
	return "%s.%s.%s" % [parts[2], parts[1], parts[0]]


# What the editor accepts: DD.MM.YYYY (also with / - or spaces, and 1-digit
# day/month) -> "YYYY-MM-DD". "" when it isn't a valid date.
static func from_input(text: String) -> String:
	var re := RegEx.create_from_string("^(\\d{1,2})[./\\- ]+(\\d{1,2})[./\\- ]+(\\d{4})$")
	var m := re.search(text.strip_edges())
	if m == null:
		return ""
	var iso := "%s-%02d-%02d" % [m.get_string(3), m.get_string(2).to_int(), m.get_string(1).to_int()]
	return iso if is_valid_date(iso) else ""


static func today() -> String:
	return Time.get_date_string_from_system()
