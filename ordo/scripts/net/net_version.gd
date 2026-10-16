class_name NetVersion
extends RefCounted
## Версия игры для сверки по сети (ТЗ §16 «Проверка версии»; владелец — NET).
##   номер — как у установщика («0.1.57», application/config/version: пишет tools/build_windows.sh);
##   дата  — ГГГГММДД (ordo/build/date: пишет tools/build_windows.sh; рабочая сборка — день самого нового файла);
##   код   — начало суммы SHA-256 всей игры: у выгруженной — весь .pck (скрипты и данные), у запуска из Godot —
##           все скрипты *.gd и данные мира (assets/world). Считается при запуске один раз, в отдельном потоке
##           (start(); файл большой): сумму файла нельзя записать в тот же файл.
## Пускает только совпадение кода (и Defs.hash); номер и дата — подсказка игроку, «новее» решается по дате.
## Проверки подменяют версию ключами --net_fake_version=0.1.52, --net_fake_date=20261002, --net_fake_code=9B12…

## Свои файлы рабочей сборки — что входит в код
const DEV_DIRS := ["res://scripts", "res://scenes"]
const DEV_FILES := ["res://assets/world/height.bin", "res://assets/world/height.json", "res://assets/world/scatter.json",
	"res://assets/world/far.bin"]
const CHUNK := 4 * 1024 * 1024
const MONTHS := ["янв.", "февр.", "марта", "апр.", "мая", "июня", "июля", "авг.", "сент.", "окт.", "нояб.", "дек."]

static var _thread: Thread
static var _code := PackedByteArray()
static var _date := 0
static var _done := false


## Начать счёт кода (один раз за запуск; повторный вызов ничего не делает)
static func start() -> void:
	if _done or _thread != null:
		return
	_thread = Thread.new()
	_thread.start(_work, Thread.PRIORITY_LOW)


## Код посчитан
static func ready() -> bool:
	if _done:
		return true
	if _thread != null and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		_done = true
	return _done


## Дождаться кода (обычно он давно готов: считается с запуска меню)
static func wait() -> void:
	if _done:
		return
	if _thread == null:
		start()
	_thread.wait_to_finish()
	_thread = null
	_done = true


## Своя версия: {number, date, code, defs_hash}; ждёт код, если он ещё не готов
static func info() -> Dictionary:
	wait()
	var number := String(ProjectSettings.get_setting("application/config/version", ""))
	var date := _date
	var code := _code
	var o := _ordo()
	if o:
		if o.call("has_arg", "net_fake_version"):
			number = String(o.call("arg", "net_fake_version"))
		if o.call("has_arg", "net_fake_date"):
			date = int(o.call("arg", "net_fake_date"))
		if o.call("has_arg", "net_fake_code"):
			code = String(o.call("arg", "net_fake_code")).hex_decode()
			code.resize(NetProto.CODE_BYTES)
	return {"number": number, "date": date, "code": code, "defs_hash": Defs.shared().hash()}


## «0.1.57 от 15 окт.» или «рабочая сборка от 15 окт.»
static func label(v: Dictionary) -> String:
	var n := String(v.get("number", ""))
	var d := date_text(int(v.get("date", 0)))
	var head := n if n != "" else "рабочая сборка"
	return head if d == "" else "%s от %s" % [head, d]


## «15 окт.» из ГГГГММДД
static func date_text(d: int) -> String:
	var m := (d / 100) % 100
	var day := d % 100
	if d <= 0 or m < 1 or m > 12 or day < 1:
		return ""
	return "%d %s" % [day, MONTHS[m - 1]]


## Код на экран — первые два байта: «7A3F»
static func code_text(code: PackedByteArray) -> String:
	return code.slice(0, 2).hex_encode().to_upper()


## Совпали ли игры: тот же код и те же данные
static func same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("code", PackedByteArray()) == b.get("code", PackedByteArray()) \
		and int(a.get("protocol", NetProto.PROTOCOL)) == int(b.get("protocol", NetProto.PROTOCOL))


## Кто обновляет игру (ТЗ §16, решение 2026-10-15): «same» — игры те же; «odd» — номер тот же, а код разный (игры
## собраны по-разному, никого не винить); «mine_old» — старая у меня; «theirs_old» — у друга. «Новее» — по дате,
## в один день — по номеру; пакет друга не разобрать — «odd»
static func verdict(mine: Dictionary, theirs: Dictionary) -> String:
	if theirs.is_empty():
		return "odd"
	if same(mine, theirs):
		return "same"
	var mn := String(mine.get("number", ""))
	var tn := String(theirs.get("number", ""))
	if mn == tn:
		return "odd"
	var md := int(mine.get("date", 0))
	var td := int(theirs.get("date", 0))
	if md != td:
		return "mine_old" if md < td else "theirs_old"
	return "mine_old" if _num_less(mn, tn) else "theirs_old"


## «0.1.52» < «0.1.57» по числам; рабочая сборка («») — старше любого номера
static func _num_less(a: String, b: String) -> bool:
	if a == "":
		return b != ""
	if b == "":
		return false
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x < y
	return false


# ================================================================= счёт кода (в потоке)

static func _work() -> void:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var newest := 0
	if OS.has_feature("template"):
		var pck := OS.get_executable_path().get_basename() + ".pck"
		var path := pck if FileAccess.file_exists(pck) else OS.get_executable_path()
		newest = _feed_file(ctx, path)
		var d := String(ProjectSettings.get_setting("ordo/build/date", ""))
		if d.length() == 10:
			_date = int(d.replace("-", ""))
	else:
		var files := PackedStringArray()
		for dir: String in DEV_DIRS:
			_collect(dir, files)
		for f: String in DEV_FILES:
			if FileAccess.file_exists(f):
				files.append(f)
		files.sort()
		for f in files:
			ctx.update(f.to_utf8_buffer())
			newest = maxi(newest, _feed_file(ctx, f))
	if _date == 0 and newest > 0:
		var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var dt := Time.get_datetime_dict_from_unix_time(newest + bias)
		_date = int(dt["year"]) * 10000 + int(dt["month"]) * 100 + int(dt["day"])
	_code = ctx.finish().slice(0, NetProto.CODE_BYTES)


## Файл в сумму кусками; вернуть время изменения файла (unix)
static func _feed_file(ctx: HashingContext, path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	while f.get_position() < f.get_length():
		ctx.update(f.get_buffer(CHUNK))
	return int(FileAccess.get_modified_time(path))


static func _collect(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)


static func _ordo() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Ordo") if tree else null
