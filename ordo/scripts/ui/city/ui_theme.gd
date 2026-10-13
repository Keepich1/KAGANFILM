class_name UiTheme
extends RefCounted
## Материалы и шрифты интерфейса «Города» (ТЗ §12, ARCHITECTURE §14): орех, латунь, «самаркандская
## бумага», кожа вкладок; Cormorant Unicase (заголовки) + Alegreya (текст, числа).
## Картинки — tools/gen_ui.py → assets/ui. Всё грузится и без кэша импорта (безголовые тесты):
## сначала ресурс Godot, иначе файл PNG/TTF напрямую.
##
##   var th := UiTheme.make(&"kokand")      # Theme для корня интерфейса (кнопки, подсказки, метки)
##   UiTheme.tex("panel")                   # Texture2D из assets/ui/panel.png
##   UiTheme.icon("res", "food")            # assets/ui/icons/res_food.png

const DIR := "res://assets/ui/"
const FONT_HEAD := "res://assets/ui/fonts/cormorant_unicase/CormorantUnicase-SemiBold.ttf"
const FONT_HEAD_BOLD := "res://assets/ui/fonts/cormorant_unicase/CormorantUnicase-Bold.ttf"
const FONT_TEXT := "res://assets/ui/fonts/alegreya/Alegreya-VariableFont_wght.ttf"
const FONT_ITALIC := "res://assets/ui/fonts/alegreya/Alegreya-Italic-VariableFont_wght.ttf"

## Цвета: светлый текст по ореху, тушь по бумаге, сигналы
const PARCH := Color("#f0dfb8")          # текст на дереве
const PARCH_DIM := Color("#b9a27a")
const SHADOW := Color(0.06, 0.03, 0.01, 0.92)
const INK := Color("#2b1a10")            # тушь на бумаге
const INK_SOFT := Color("#5a4028")
const RED := Color("#a3281c")
const RED_LIGHT := Color("#ff8a6a")
const GREEN := Color("#2f6b3a")
const GREEN_LIGHT := Color("#9ad48a")
const GOLD := Color("#9a6a1c")
const GOLD_LIGHT := Color("#ffd27a")
const HP := Color("#b8382a")
const MORALE := Color("#d6a43a")
const STAMINA := Color("#5f8fa8")
## Цвета команд (ТЗ 2.1, 2.2): 0 — Коканд, 1 — кыпчаки
const TEAM := [Color("#2f8f74"), Color("#b0392f"), Color("#c9a24a"), Color("#6a5aa8")]
const TEAM_LIGHT := [Color("#7fe8c8"), Color("#ffa597"), Color("#ffe28a"), Color("#b8a8ff")]

static var _cache := {}


## Текстура по имени (assets/ui/<name>.png); null, если нет
static func tex(name: String) -> Texture2D:
	return _load_tex(DIR + name + ".png")


## Значок: kind — res | ord | unit | bld | crest; null, если нет
static func icon(kind: String, name: String) -> Texture2D:
	return _load_tex(DIR + "icons/" + kind + "_" + name + ".png")


static func _load_tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	if t == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			t = ImageTexture.create_from_image(img)
	_cache[path] = t
	return t


## Шрифт (с запасным путём без импорта); weight — толщина переменной Alegreya (400..900)
static func font(path: String, weight := 0) -> Font:
	var key := "%s@%d" % [path, weight]
	if _cache.has(key):
		return _cache[key]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	if f == null and FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(ProjectSettings.globalize_path(path)) == OK:
			f = ff
	if f == null:
		f = ThemeDB.fallback_font
	if weight > 0:
		var fv := FontVariation.new()
		fv.base_font = f
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		f = fv
	_cache[key] = f
	return f


static func head() -> Font:
	return font(FONT_HEAD)


static func head_bold() -> Font:
	return font(FONT_HEAD_BOLD)


static func text(weight := 500) -> Font:
	return font(FONT_TEXT, weight)


static func italic(weight := 500) -> Font:
	return font(FONT_ITALIC, weight)


## 9-slice из картинки: поля margin (пиксели картинки), середина — растянуть или плиткой
static func box(name: String, margin: float, content := -1.0, tile := false) -> StyleBox:
	var t := tex(name)
	if t == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color("#4a2f1c")
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	var c := margin if content < 0.0 else content
	sb.content_margin_left = c
	sb.content_margin_right = c
	sb.content_margin_top = c
	sb.content_margin_bottom = c
	if tile:
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


## Тема интерфейса: кнопки (орех в латуни), вкладки (кожа), подсказка (записка), метки (пергамент)
static func make(faction: StringName = &"kokand") -> Theme:
	var th := Theme.new()
	th.default_font = text(500)
	th.default_font_size = 18
	for st in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(st, "Button", box("button_" + st, 16, 6))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_stylebox("hover_pressed", "Button", box("button_active", 16, 6))
	th.set_color("font_color", "Button", PARCH)
	th.set_color("font_hover_color", "Button", Color("#fff1cf"))
	th.set_color("font_pressed_color", "Button", GOLD_LIGHT)
	th.set_color("font_disabled_color", "Button", PARCH_DIM)
	th.set_color("font_outline_color", "Button", SHADOW)
	th.set_constant("outline_size", "Button", 4)
	th.set_font("font", "Button", head())
	th.set_font_size("font_size", "Button", 18)
	# вкладки — тот же Button с вариантом CityTab
	th.set_type_variation("CityTab", "Button")
	th.set_stylebox("normal", "CityTab", box("tab", 16, 8))
	th.set_stylebox("hover", "CityTab", box("tab_hover", 16, 8))
	th.set_stylebox("pressed", "CityTab", box("tab_active", 16, 8))
	th.set_stylebox("hover_pressed", "CityTab", box("tab_active", 16, 8))
	th.set_stylebox("disabled", "CityTab", box("tab", 16, 8))
	th.set_font_size("font_size", "CityTab", 18)
	# открытая вкладка — самая светлая надпись, закрытые — приглушённые (видно и при 1280×720)
	th.set_color("font_color", "CityTab", PARCH_DIM)
	th.set_color("font_hover_color", "CityTab", PARCH)
	th.set_color("font_pressed_color", "CityTab", Color("#fff6de"))
	th.set_color("font_hover_pressed_color", "CityTab", Color("#fff6de"))
	# подсказка — бумажная записка, тушь
	var tip := box("note", 26, 14)
	tip.content_margin_left = 20
	tip.content_margin_right = 20
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_font("font", "TooltipLabel", text(500))
	th.set_font_size("font_size", "TooltipLabel", 17)
	th.set_color("font_color", "TooltipLabel", INK)
	th.set_color("font_shadow_color", "TooltipLabel", Color(0, 0, 0, 0))
	# метки
	th.set_color("font_color", "Label", PARCH)
	th.set_color("font_shadow_color", "Label", SHADOW)
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 2)
	th.set_constant("shadow_outline_size", "Label", 3)
	th.set_type_variation("InkLabel", "Label")
	th.set_color("font_color", "InkLabel", INK)
	th.set_color("font_shadow_color", "InkLabel", Color(1, 0.96, 0.85, 0.35))
	th.set_constant("shadow_offset_x", "InkLabel", 0)
	th.set_constant("shadow_offset_y", "InkLabel", 1)
	th.set_constant("shadow_outline_size", "InkLabel", 0)
	return th


## Метка с нашим шрифтом (ink — тушь на бумаге, иначе пергамент по дереву)
static func label(txt: String, f: Font, size: int, ink := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	if ink:
		l.theme_type_variation = "InkLabel"
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Значок ресурса по Defs (r_icon)
static func res_icon(defs: Defs, r: int) -> Texture2D:
	var name := defs.r_icon[r] if r >= 0 and r < defs.r_icon.size() else ""
	return icon("res", name if name != "" else defs.res_ids[r])


## Портрет рода войск из модели толпы (assets/ui/portraits/<вид>.png, сцена ui_portraits); null — нет вида
static func unit_portrait(type_id: String) -> Texture2D:
	var vid := UnitStats.visual_for(type_id)
	if vid == "":
		return null
	return _load_tex(DIR + "portraits/" + vid + ".png")


## Портрет постройки из её модели (assets/ui/portraits/bld_<id>.png, сцена ui_portraits); null — нет
static func building_portrait(defs: Defs, btype: int) -> Texture2D:
	if btype < 0 or btype >= defs.b_ids.size():
		return null
	return _load_tex(DIR + "portraits/bld_" + defs.b_ids[btype] + ".png")


## Портрет, если есть, иначе эмблема рода
static func unit_face(type_id: String) -> Texture2D:
	var t := unit_portrait(type_id)
	return t if t else unit_icon(type_id)


## Эмблема рода войск по флагам UnitStats (если у рода нет портрета)
static func unit_icon(type_id: String) -> Texture2D:
	var st: Dictionary = UnitStats.get_stats(type_id)
	var f := int(st.get("flags", 0))
	var kind := "infantry"
	if f & UnitStats.WAGON:
		kind = "arba"
	elif f & UnitStats.WORKER:
		kind = "worker"
	elif f & UnitStats.GENERAL:
		kind = "general"
	elif f & UnitStats.OFFICER:
		kind = "officer"
	elif f & UnitStats.CANNON:
		kind = "cannon"
	elif f & UnitStats.KACHYP:
		kind = "horse_archer"
	elif f & UnitStats.MOUNTED and f & UnitStats.SPEAR:
		kind = "lancer"
	elif f & UnitStats.MOUNTED:
		kind = "cavalry"
	elif f & UnitStats.MUSKET:
		kind = "musket"
	elif f & UnitStats.BOW:
		kind = "archer"
	elif f & UnitStats.SPEAR:
		kind = "spear"
	return icon("unit", kind)


## Значок постройки по id (общие глифы на обе стороны)
const BUILDING_GLYPH := {
	"urda": "hq_kokand", "ordo": "hq_kipchak", "uy": "house", "boz": "yurt", "dala": "field", "tegirmon": "mill",
	"ombor": "store", "ken": "mine", "kazarma": "barracks", "jooker": "barracks", "otxona": "stable",
	"jylky": "horse_yard", "topxona": "cannon_yard", "kurultai": "kurultai", "xumdon": "kiln", "bozor": "bazaar",
	"togon": "dam", "aryk": "canal", "koroo": "pen", "devor": "wall", "tosh": "wall", "chep": "palisade",
	"darvoza": "gate", "darbaza": "gate", "burj": "tower", "munara": "tower", "temirchixona": "smithy",
	"temirchi": "smithy", "kiyiz": "felt_yard"}


static func building_icon(defs: Defs, btype: int) -> Texture2D:
	var id := defs.b_ids[btype] if btype >= 0 and btype < defs.b_ids.size() else ""
	return icon("bld", BUILDING_GLYPH.get(id, "store"))


## Значок приказа по SimCmd.Op
static func order_icon(op: int) -> Texture2D:
	var name := String(SimCmd.name_of(op)).to_lower()
	match op:
		SimCmd.Op.MOVE_LINE: name = "move"
		SimCmd.Op.STANCE: name = "stance"
		SimCmd.Op.BUILD_WALL: name = "build"
		SimCmd.Op.CANCEL_TRAIN: name = "stop"
		SimCmd.Op.SET_RECIPE: name = "recipe"
	return icon("ord", name)


## Число милли → строка единиц («1 234»)
static func amount(milli: int) -> String:
	var v := int(floor(milli / 1000.0))
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("−" if v < 0 else "") + s + out


## Цена «дерево 120 · камень 30» (милли → единицы; имя ресурса впереди — без падежей)
static func cost_text(defs: Defs, cost: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for r in cost.size():
		if cost[r] > 0:
			parts.append("%s %d" % [TranslationServer.translate(defs.r_name[r]).to_lower(), ceili(cost[r] / 1000.0)])
	return " · ".join(parts)


## Время «2:05» из тактов
static func clock(ticks: int) -> String:
	var s := maxi(0, ceili(ticks / 30.0))
	return "%d:%02d" % [s / 60, s % 60]
