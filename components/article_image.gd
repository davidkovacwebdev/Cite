extends RefCounted

# The article's lead image from Wikipedia, shown with the answer once a
# round ends. ArticleComponent prefetches it when the round starts so it's
# usually ready by the time the answer appears; articles without one (or
# with only a GIF/SVG lead) just show no picture. Requests hang off Global
# so they survive scene changes. Keeps the last few in memory only.

const ArticleHighlight := preload("res://ui/hub/article_highlight.gd")

const API := "https://en.wikipedia.org/w/api.php?action=query&prop=pageimages&piprop=thumbnail&pithumbsize=480&pageids=%d&format=json&formatversion=2"
const MAX_CACHED := 8

static var _cache := {}  # page id -> Texture2D, or null when it has no usable image
static var _pending := {}


# Starts loading in the background; safe to call repeatedly.
static func prefetch(id: int) -> void:
	if id <= 0 or _cache.has(id) or _pending.has(id):
		return
	_pending[id] = true
	var tex := await _load(id)
	_pending.erase(id)
	while _cache.size() >= MAX_CACHED:
		_cache.erase(_cache.keys()[0])
	_cache[id] = tex


# The image if it's already loaded, otherwise null right away.
static func get_cached(id: int) -> Texture2D:
	return _cache.get(id)


# Waits for the image if it's still loading (or starts it). Null if none.
static func fetch(id: int) -> Texture2D:
	if id <= 0:
		return null
	if not _cache.has(id) and not _pending.has(id):
		prefetch(id)
	while _pending.has(id):
		await Global.get_tree().process_frame
	return _cache.get(id)


# Size that fits `tex` inside `max_size`, keeping its aspect ratio.
static func fit_size(tex: Texture2D, max_size: Vector2) -> Vector2:
	var s := tex.get_size()
	if s.x <= 0 or s.y <= 0:
		return Vector2.ZERO
	var k: float = min(max_size.x / s.x, max_size.y / s.y)
	return (s * k).floor()


static func _load(id: int) -> Texture2D:
	var body: PackedByteArray = await ArticleHighlight._fetch(Global, API % id)
	if body.is_empty():
		return null
	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json is Dictionary or not json.get("query") is Dictionary:
		return null
	var pages = json["query"].get("pages")
	if not pages is Array or pages.is_empty() or not pages[0] is Dictionary:
		return null
	var thumb = pages[0].get("thumbnail")
	if not thumb is Dictionary:
		return null
	var bytes: PackedByteArray = await ArticleHighlight._fetch(Global, str(thumb.get("source", "")))
	return ArticleHighlight._texture(bytes)
