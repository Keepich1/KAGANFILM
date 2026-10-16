extends Control
## «Игра с другом» — лобби игры по сети (Город один на один по адресу: один создаёт игру, другой подключается;
## ТЗ §16). Настоящая сеть — NetSession (scripts/net/: ENet по UDP 7777, сверка версий, сторона и номер партии
## хозяина у друга сразу, «Начать игру» — партия у обоих: NetMatch, сцена «Города»). Экраны и тексты — ровно
## одобренного макета (кадры renders/online/r6); что показать, решают события сети (_on_net), а не часы макета.
##
## МАКЕТ (--online_mock=1; кадры состояний --menu_online=… — тоже он): сети нет — ни сокетов, ни IP.get_local_*,
## ни запросов в интернет (иначе Windows спросит про доступ к сети прямо во время съёмки, а в кадр попадут
## настоящие адреса). Все адреса и числа выдуманные; 203.0.113.x — диапазон для примеров, никому не принадлежит.
## Под листом макета — строка «Макет экрана»; у настоящего лобби её нет.
##
## Способы связи (решение 2026-10-15): рядом — один Wi-Fi («Дома»), далеко — Radmin VPN; для знатоков — порт
## на роутере, только в справке (в лобби строки «Через интернет» нет: для новичка это ловушка).
##
## Лист — та же бумага, что «Настройки»; место и масштаб даёт меню (MainMenu._place_online). Высота листа — по
## содержимому, не ниже MainMenu.ONLINE_MIN_H: ряд кнопок у низа листа, коротким состояниям не остаётся пустых
## полос. Верх листа — вровень с верхним краем доски во всех состояниях; масштаб — один на весь ход лобби (FLOWS:
## выбор, хозяин, подключение, справка), тело — всегда сразу под линией шага (никакого выравнивания посередине).
## Сообщения — одна записка листа (_msg): полоска рваной бумаги с сургучной печатью (красная — плохо, зелёная —
## хорошо, золотая — к сведению) на одном месте, первой под линией шага; место под неё занято с самого начала
## (золотой запиской-советом), так что новая записка меняет только текст и печать. На пейзаж под листом текст не
## выходит. Советы («Как связаться», «Где взять адрес») — не записки: разлинованная вставка без печати и рваного
## края (RuleBox). Рамка фокуса видна, только когда по листу ходят клавишами (KbdGate).
## Тело собирается заново при каждой смене состояния (_show).
## Скрипт без class_name: меню грузит его само и отдаёт себя (setup) — отсюда шрифты, картинки и цвета.
## Состояния: choose, host_wait, host_ready, join, join_connecting, join_fail, join_wait, version, help;
## варианты (--menu_online_alt=N) — в _show и _body_<состояние>; --menu_online_side=kipchak — хозяин за
## кыпчаков, --menu_online_kbd — рамка фокуса видна (как после Tab). F8 / Shift+F8 — следующее / предыдущее
## состояние (только с ключом --menu_online, для кадров).
## Макет можно прощёлкать: «Создать игру» — друг «входит» через 6 с; «Подключиться» к 26.115.40.12 — через
## 3 с вы в игре у друга, к любому другому адресу — «Не получилось подключиться».
## Настоящее лобби для кадров двух окон: --net_auto=host | join:адрес (сразу «Создать игру» / «Подключиться»),
## --net_show_addr=mock — в строках адресов выдуманные адреса макета (настоящие в кадр не попадут).

const STATES := ["choose", "host_wait", "host_ready", "join", "join_connecting", "join_fail", "join_wait",
	"version", "help"]
## Варианты состояний (для теста и кадров): состояние → число вариантов, считая основной
const ALTS := {"choose": 2, "host_wait": 8, "host_ready": 2, "join": 3, "join_connecting": 2, "join_fail": 2,
	"join_wait": 5, "version": 3, "help": 5}
## Ходы лобби: у каждого свой масштаб листа, один на все его состояния и варианты (внутри хода лист не растёт и не
## мельчает; между ходами экран меняется целиком). FLOW_H — высота (точки раскладки), по которой меню считает
## масштаб: не ниже самого высокого состояния хода — и в мелком окне или на крупном масштабе интерфейса, где мелкие
## строки плотнее (_boost); тест test_ui_scale следит. Короткие ходы (выбор, подключение) на 150 % крупнее
const FLOWS := {"choose": "choose", "host_wait": "host", "host_ready": "host", "join": "join",
	"join_connecting": "join", "join_fail": "join", "join_wait": "join", "version": "join", "help": "help"}
const FLOW_H := {"choose": 805.0, "host": 855.0, "join": 790.0, "help": 955.0}
## Поля листа (как у «Настроек»): столбец 672 в ширину
const PAD := Vector2(54, 36)
## Зазор под линией шага: записка или тело листа начинаются сразу под ней
const BODY_TOP := 16.0
## Ряд кнопок: левая и главная
const LEFT_W := 280.0
const MAIN_W := 340.0
## «Адрес друга» и «Подключаемся» — одной высоты: ряд кнопок у низа листа не прыгает при «Подключиться» (и в мелком
## окне, где мелкие строки плотнее и «Адрес друга» чуть выше; масштаб листа и так один во всех состояниях)
const JOIN_H := 784.0

## Выдуманные данные макета — одни и те же во всех кадрах
const ADDR_RADMIN := "26.115.40.12"
const ADDR_HOME := "192.168.1.34"
const ADDR_NET := "203.0.113.57"
const ADDR_PART := "26.115.40"
const PORT := 7777
## Версия игры — номер, как у установщика («Ордо 0.1.N» на GitHub, Ordo-Setup-0.1.N.exe), и дата сборки
## (на утверждение автору: «номер + дата» или «дата + код», ТЗ §16). Код всей игры — скрытая проверка; на экран
## он выходит, только когда номера совпали, а файлы разные (version, вариант 1). Номер и дату порознь: в
## предложении «…от 15 окт.» на конце дала бы две точки подряд
const VER_MINE := "0.1.57"
const VER_OLD := "0.1.52"
const DATE_MINE := "15 окт."
const DATE_OLD := "2 окт."
const CODE_MINE := "7A3F"
const CODE_ODD := "9B12"
const WAIT_MOCK := 42
const SEED_MOCK := 482913
## Подключение: предел ожидания (с) и сколько секунд прошло в кадре (счётчик пишет, сколько осталось)
const CONNECT_LIMIT := 15.0
const CONNECT_MOCK := 6.0
## Макет: к чужому адресу счётчик идёт в 5 раз быстрее (15 с — за 3 с) и кончается «Не получилось»;
## к ADDR_RADMIN друг отвечает через CONNECT_OK с, ещё CHECK_OK с — сверка версий, и вы в игре у друга
const CONNECT_SPEED := 5.0
const CONNECT_OK := 2.4
const CHECK_OK := 0.8
## Хозяин: друг «входит» через столько секунд ожидания
const FRIEND_COMES := 6.0
const MOCK_FLASH := "Это макет: игра по сети ещё не подключена."
## Строка под листом: что это макет (не «связи нет» — так она читалась как состояние связи)
const MOCK_NOTE := "Макет экрана: игра по сети пока не работает"
## Записка хозяина о вопросе Windows про сеть (окно Windows может открыться за игрой во весь экран — Alt+Tab)
const FIREWALL_NOTE := "Windows спросит про сеть — отметьте обе галочки и нажмите «Разрешить доступ». Не видно окна — нажмите Alt+Tab."
## Неразрывный пробел (U+00A0): тире не начинает строку, предлог не висит в конце строки. На глаз его не
## отличить от обычного пробела — правка файла его легко теряет; тест test_ui_scale проверяет код знака
const NBSP := " "

## Цвета — те же, что у меню; стороны; красные чернила записки — как у записок «Города» (CityNotes)
const PARCH := MainMenu.PARCH
const PARCH_DIM := MainMenu.PARCH_DIM
const BRASS := MainMenu.BRASS
const BRASS_DIM := MainMenu.BRASS_DIM
const INK := MainMenu.INK
const INK_SOFT := MainMenu.INK_SOFT
const SHADOW := MainMenu.SHADOW
const WALNUT := Color("#3a2414")
const KOKAND := Color("#1f6f5c")
const KIPCHAK := Color("#9a2f26")
const GREEN := Color("#24501c")
## Красные чернила: черта под неверным адресом (RED) и текст красной записки (RED_INK, темнее — для строк)
const RED := Color("#a3261b")
const RED_INK := Color("#6a140e")
## Мелкое окно: лист на экране мельче этого — тонкий курсив мелких строк плотнее и темнее (_boost); так же — на
## масштабе интерфейса от BIG_UI (кто выбрал крупный интерфейс, тому и мелкие строки нужны жирнее)
const SMALL_K := 0.8
const BIG_UI := 1.25
## Номера списков — латунь темнее BRASS_DIM: на бумаге и в мелком окне не бледнеют
const NUM_INK := Color("#7d5c26")

## Подсказки (записки CityTips: первая строка — заголовок; «!» — причина, «+»/«−» — за и против, «~» — пояснение).
## {port} подставляет _tip из PORT — число в одном месте. После адреса точку не ставим: её примут за часть адреса
const TIPS := {
	"Online_host": "Создать игру\nВы выбираете сторону, игра показывает ваш адрес — отправьте его другу.\n~ Если Windows спросит про доступ к сети — разрешите.",
	"Online_join": "Подключиться\nВойти в игру, которую создал друг.\n~ Нужен адрес с его экрана: четыре числа через точку.",
	"Online_help": "Как играть по сети\nРядом — Wi-Fi, далеко — Radmin VPN; для знатоков — роутер.\n~ И как открыть игре доступ к сети в Windows.",
	"Online_help_fw": "Как открыть игре доступ к сети\nСправка откроется на этом месте: что нажать в Windows.\n~ Делает тот, кто создаёт игру, — у себя на компьютере.",
	"Radmin_how": "Как поставить Radmin VPN\nПрограмма бесплатная: скачайте её с сайта radmin-vpn.com и установите.\n~ Ставят оба — и вы, и друг; один создаёт в ней сеть.\n~ Имя и пароль сети — пришлите другу.\n~ Подробно — в справке, способ 2.",
	"Side_kokand": "Коканд\nГород у арыков: поля, кирпич, стены и ворота.\n~ Друг будет за кыпчаков.",
	"Side_kipchak": "Кыпчаки\nКочевой лагерь: юрты, табуны, набеги и көч.\n~ Друг будет за Коканд.",
	"Seed_new": "Другой номер партии\nОт номера зависят случайности в бою. Карта та же.\n~ Другу номер отправлять не нужно — он увидит его сам.",
	"Copy_0": "Копировать\nАдрес в сети Radmin VPN — для друга в другом доме.\n+ Роутер настраивать не нужно\n~ Вы оба должны быть в одной сети Radmin VPN.",
	"Copy_1": "Копировать\nДомашний адрес — для друга в том же Wi-Fi или по проводу.\n− Из другого дома по нему не войти",
	"Net_find": "Узнать мой адрес в интернете\nИгра спросит роутер (если нужно — сайт ipify.org) и сама попробует открыть на нём порт {port} (UDP).\n− У многих провайдеров так не выйдет — тогда берите Radmin VPN",
	"Copy_net": "Копировать\nВаш адрес в интернете.\n~ Сработает, только если на роутере открыт порт {port} (UDP).",
	"Online_ping": "Связь с другом\nОтвет от друга приходит почти мгновенно.\n+ Быстрее десятой доли секунды — играть удобно\n− Дольше четверти секунды — приказы будут заметно запаздывать\n~ Приказ выполняется, когда его получили оба, — поэтому всегда с небольшой задержкой.",
	"Online_ping_slow": "Связь с другом\nОтвет от друга идёт дольше четверти секунды.\n− Приказы будут чуть запаздывать\n~ Так бывает, когда далеко или сеть занята: кто-то в доме качает файлы или смотрит видео.",
	"Join_addr": "Адрес друга\nЧетыре числа через точку, как у него на экране.\nМожно вставить его сообщение целиком: Ctrl+V.",
	"Join_paste": "Вставить\nВставить адрес или всё сообщение друга (Ctrl+V).",
	"Join_recent": "В прошлый раз\nАдрес, к которому вы подключались в прошлый раз. Нажмите — он впишется в поле.",
	"main_host_wait": "Начать игру\n! Друг ещё не подключился\n~ Отправьте ему адрес и подождите.",
	"main_host_ready": "Начать игру\nПартия начнётся у обоих сразу. Пауза общая.\n~ Если связь пропадёт — игра встанет и подождёт друга.",
	"left_host": "Отмена\nЗакрыть игру и вернуться к выбору. Если друг уже подключился, он это увидит. Esc",
	"left_choose": "Назад\nВ главное меню. Esc",
	"left_join": "Назад\nК выбору: создать игру или подключиться. Esc",
	"main_join_off": "Подключиться\n! Сначала впишите адрес друга",
	"main_join": "Подключиться\nСтучимся к другу по этому адресу — обычно пара секунд. Enter",
	"left_connecting": "Отмена\nПерестать подключаться. Esc",
	"main_fail": "Попробовать снова\nЕщё раз постучаться к другу по тому же адресу.",
	"left_fail": "Изменить адрес\nВернуться к полю адреса. Esc",
	"left_wait": "Выйти\nОтключиться от друга и вернуться к выбору. Esc",
	"main_wait": "Начнёт друг\n! Партию начинает друг — тот, кто создал игру\n~ Ждите здесь: друг нажмёт «Начать игру».",
	"left_closed": "Назад\nК выбору: создать свою игру или подключиться снова. Esc",
	"main_rejoin": "Подключиться снова\nЕщё раз постучаться к другу по тому же адресу.\n~ Друг должен видеть у себя «Ждём друга…».",
	"main_version": "Понятно\nВернуться к адресу друга. Esc",
	"main_help": "Понятно\nВернуться назад. Esc",
}

## Меню, лист (его ставит и ужимает меню) и части листа
var menu: MainMenu
var sheet: Control
var _col: VBoxContainer
var _title: Label
var _step: Label
var _body: VBoxContainer
var _left: Button
var _main: Button
var _build: Label
## Строка «это макет» под листом (только у макета)
var _mock_note: Label
## Макет (MainMenu._online_mock: --online_mock=1, кадры состояний) или настоящая сеть (NetSession)
var _mock := true
var _net: NetSession
## Настоящая сеть: свои адреса (NetAddr.scan; у хозяина), версия друга из его первого пакета (отказ «Разные
## версии»), с какого мига хозяин ждёт друга и подключающийся стучится (мс), адрес в интернете из справки,
## друг вошёл, а сторона и номер партии хозяина ещё не пришли
var _addrs := {"radmin": "", "home": PackedStringArray()}
var _their := {}
var _host_t0 := 0
var _conn_t0 := 0
var _net_addr := ""
var _lobby_wait := false
## Кадры: хозяин сам жмёт «Начать игру», когда друг вошёл (--net_auto=host:start)
var _net_auto_start := false
## Подключившийся: сторона на табличке «Вы» сейчас (хозяин сменил сторону — записка «теперь вы за …»)
var _guest_shown := ""
## Записка листа: сама, печать, текст, отступ под ней; какая сейчас ("red" / "green" / "gold", "" — нет),
## какая у состояния по умолчанию [печать, текст, подсказка], сколько строк держит всегда
var _msg: MsgNote
var _msg_seal: TextureRect
var _msg_text: Label
var _msg_gap: Control
var _msg_kind := ""
var _msg_default := ["", "", ""]
var _msg_lines := 0
## Номер записки: временная (flash) возвращает записку состояния, только если её не сменили раньше
var _msg_serial := 0
## Высоту листа меню пересчитывает раз за кадр (_queue_fit)
var _fit_queued := false
## Шрифты листа с цифрами в рост строки (_lining) и обратно: шрифт → [файл, толщина, цифры одной ширины]
var _fonts := {}
var _font_key := {}
## Мелкое окно (лист на экране мельче SMALL_K) или крупный интерфейс (от BIG_UI): мелкие строки курсивом плотнее
## и темнее (_boost)
var _small := false
## Рамка фокуса — только после Tab, стрелок или геймпада; мышь её снова прячет (FocusRing)
var _gate := KbdGate.new()
## Пустой фокус (_rest): «Подключаемся» и «Вы в игре у друга» не ставят фокус на «Отмена» / «Выйти» — второе
## нетерпеливое Enter не отменит подключение
var _rest: Control
## Состояние макета: какое, вариант, откуда пришли в «Как играть по сети» (и шли ли там счётчики, сколько
## хозяин уже ждал друга); справку открыли ссылкой «Как открыть игре доступ к сети?» — блок про Windows отмечен
var _state := "choose"
var _alt := 0
var _help_from := "choose"
var _help_alt := 0
var _help_live := false
var _help_fw := false
## Выбор хозяина: его сторона, номер партии; адрес в интернете уже узнан (справка, способ 3) и что вышло с портом
## ("green" — открыт, "gold" — роутер не открыл)
var _side := "kokand"
var _seed := SEED_MOCK
var _net_found := false
var _net_kind := "green"
## Подключившийся: что в поле адреса (и где в нём курсор — переживает поход в справку); макет — удастся ли
## подключение (адрес ADDR_RADMIN), друг уже ответил
var _addr := ""
var _addr_caret := -1
var _ok_mock := false
var _checking := false
## Живые счётчики (только после нажатий; состояние, открытое ключом, стоит на месте)
var _live := false
var _clock := 0.0
var _t := 0.0
var _shot := false
## Части тела, которые оживают в _process
var _dots: Array[Label] = []
var _dots_base: PackedStringArray = []
var _count: Label
var _wait_lbl: Label
var _seed_lbl: Label
var _seed_ghost: Label
var _friend_side_lbl: Label
var _friend_disc: Disc
var _field: TipLine
var _field_deco: SlipDeco
## Адрес в сообщении: четыре числа через точку и, может быть, порт — через «:» или «ж» (русская раскладка)
var _ip_re := RegEx.create_from_string("(?<![0-9])([0-9]{1,3}(?:\\.[0-9]{1,3}){3})([:жЖ][0-9]{1,5})?(?![0-9])")
## Вписано одними цифрами и знаками раскладки: это адрес, набранный при русской раскладке, — его чиним целиком
var _typed_re := RegEx.create_from_string("^[0-9.,:бБюЮжЖ]+$")
var _full_re := RegEx.create_from_string("^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})(?::([0-9]{1,5}))?$")


# ================================================================= лист

## Собрать лист (меню зовёт один раз, после того как добавило узел в дерево)
func setup(m: MainMenu) -> void:
	menu = m
	_shot = menu._ordo != null and menu._ordo.has_arg("shot")
	if menu._ordo != null and String(menu._ordo.arg("menu_online_side", "")) == "kipchak":
		_side = "kipchak"
	# кадр с рамкой фокуса, как после ходьбы клавишами (--menu_online_kbd)
	if menu._ordo != null and menu._ordo.has_arg("menu_online_kbd"):
		_gate.on = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = _tip_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.02, 0.01, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	sheet = Control.new()
	sheet.name = "OnlineSheet"
	sheet.size = Vector2(MainMenu.ONLINE_W, MainMenu.ONLINE_MIN_H)
	add_child(sheet)
	# пустой фокус — первым на листе: Tab с него идёт на первую кнопку листа; мышью и Tab на него не попасть
	_rest = Control.new()
	_rest.name = "Rest"
	_rest.focus_mode = Control.FOCUS_CLICK
	_rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(_rest)
	# бумага растянута, а не плиткой: швы плиток легли бы поперёк строк
	var paper := menu._nine("paper", 28.0, Color("#e9d8b0"))
	if paper is NinePatchRect:
		(paper as NinePatchRect).axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		(paper as NinePatchRect).axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	sheet.add_child(paper)
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.border_color = Color(INK_SOFT, 0.6)
	edge.set_border_width_all(2)
	edge.set_expand_margin_all(-14)
	var ep := Panel.new()
	ep.add_theme_stylebox_override("panel", edge)
	ep.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(ep)
	_col = VBoxContainer.new()
	_col.name = "Col"
	_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_col.offset_left = PAD.x
	_col.offset_right = -PAD.x
	_col.offset_top = PAD.y
	_col.offset_bottom = -PAD.y
	_col.add_theme_constant_override("separation", 0)
	sheet.add_child(_col)
	_title = menu._label("", menu._font(MainMenu.FONT_HEAD_BOLD), 46, INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_title)
	_col.add_child(menu._gap(2))
	# строка шага — что делать сейчас; тушью, а не бледно: это единственная строка, что меняется под заголовком
	_step = menu._label("", _italic(500), 22, INK)
	_step.name = "Step"
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_step)
	_col.add_child(menu._gap(12))
	# линия тушью под шагом: поля по 40
	var line_box := Control.new()
	line_box.custom_minimum_size = Vector2(0, 2)
	line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := ColorRect.new()
	line.color = Color(INK_SOFT, 0.35)
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 40.0
	line.offset_right = -40.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_box.add_child(line)
	_col.add_child(line_box)
	_col.add_child(menu._gap(BODY_TOP))
	# записка — первой под линией шага, на одном месте во всех состояниях
	_build_msg()
	_col.add_child(_msg)
	_msg_gap = menu._gap(12)
	_col.add_child(_msg_gap)
	# тело — сверху, сразу под запиской (или линией шага); свободное место — над рядом кнопок
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 10)
	_col.add_child(_body)
	var fill := Control.new()
	fill.name = "Fill"
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_child(fill)
	_col.add_child(menu._gap(12))
	# ряд кнопок: второстепенная всегда слева, главная всегда справа
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.custom_minimum_size = Vector2(0, 58)
	row.add_theme_constant_override("separation", 0)
	_col.add_child(row)
	_left = _button("Online_left", "", "", Vector2(LEFT_W, 58), 30)
	_left.pressed.connect(_on_left)
	row.add_child(_left)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_main = _button("Online_main", "", "", Vector2(MAIN_W, 58), 30)
	_style_main(_main)
	_main.pressed.connect(_on_main)
	row.add_child(_main)
	_col.add_child(menu._gap(6))
	_build = menu._label("", _italic(450), 20, INK_SOFT)
	_build.name = "Build"
	_build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(_build)
	# под листом макета — только «это макет», мелко (сообщения — в записке на листе); у настоящего лобби — ничего
	_mock_note = menu._label(tr(MOCK_NOTE), _italic(500), 20, PARCH_DIM)
	_mock_note.name = "MockNote"
	_mock_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mock_note.add_theme_constant_override("outline_size", 6)
	_mock_note.add_theme_color_override("font_outline_color", SHADOW)
	sheet.add_child(_mock_note)
	layout()
	# высота листа — по содержимому: тело сменилось или строки досчитали перенос — меню ставит лист заново
	_col.minimum_size_changed.connect(_queue_fit)


## Записка листа: полоска рваной бумаги («note», как записки «Города»), слева сургучная печать, текст тушью
## (у красной — красными чернилами); подсказка — записка CityTips (у «связь хорошая» — про связь)
func _build_msg() -> void:
	_msg = MsgNote.new()
	_msg.name = "Msg"
	_msg.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := menu._box("note", 24.0, Color("#efe2c2"))
	sb.content_margin_left = 10
	sb.content_margin_right = 24
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	_msg.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.add_child(row)
	_msg_seal = _icon("seal_gold", 48.0) as TextureRect
	_msg_seal.name = "Msg_seal"
	row.add_child(_msg_seal)
	_msg_text = menu._label("", _text(600), 21, INK)
	_msg_text.name = "Msg_text"
	_msg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_msg_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_text.custom_minimum_size = Vector2(1, 0)
	row.add_child(_msg_text)
	_msg.visible = false


## Открыть лист в состоянии state (вариант alt); неизвестное состояние — выбор роли. Макет — с чистого листа.
## Настоящее лобби открывается на выборе (или «Адрес друга», справка): дальше состояния ведут события сети
func open(state := "choose", alt := 0) -> void:
	visible = true
	_live = false
	_mock = menu._online_mock()
	_mock_note.visible = _mock
	_reset_mock()
	if not _mock:
		if not (state in ["choose", "join", "help"]):
			state = "choose"
		alt = 0
	_show(state, alt)
	if not _mock and menu._ordo != null and menu._ordo.has_arg("net_auto"):
		var spec := String(menu._ordo.arg("net_auto"))
		menu._ordo.clear_arg("net_auto")
		_auto.call_deferred(spec)


## Высота листа (точки раскладки): содержимое столбца с полями, не ниже ONLINE_MIN_H (у «Адреса друга» и
## «Подключаемся» — JOIN_H)
func sheet_height() -> float:
	var lo := JOIN_H if _state in ["join", "join_connecting"] else MainMenu.ONLINE_MIN_H
	return maxf(lo, _col.get_combined_minimum_size().y + PAD.y * 2.0)


## Высота, по которой меню считает масштаб листа: своя у каждого хода лобби (FLOW_H) — масштаб один на весь ход.
## Настоящий хозяин с двумя домашними адресами (строк адресов три) выше макета — масштаб по нему
func top_h() -> float:
	var h := float(FLOW_H[FLOWS.get(_state, "choose")])
	if not _mock and FLOWS.get(_state, "") == "host":
		h = maxf(h, sheet_height())
	return h


## Меню поставило лист (место, масштаб, высоту): строка «макет» — под его нижним краем; лист на экране стал
## мельче SMALL_K (или интерфейс крупный, от BIG_UI) — мелкие строки курсивом плотнее, иначе как были (_boost_all)
func layout() -> void:
	_mock_note.position = Vector2(-60.0, sheet.size.y + 6.0)
	_mock_note.size = Vector2(sheet.size.x + 120.0, 34.0)
	var small := screen_k() < SMALL_K or _ui_scale() >= BIG_UI - 0.001
	if small != _small:
		_small = small
		_boost_all()


## Масштаб интерфейса игрока (Ordo.ui_scale; без автозагрузки — 1)
func _ui_scale() -> float:
	if menu == null or menu._ordo == null:
		return 1.0
	return float(menu._ordo.get("ui_scale"))


## Во сколько раз лист мельче на экране, чем в точках раскладки: масштаб листа × холст окна (canvas_items,
## aspect expand: окно к раскладке по меньшей стороне, на множитель Ordo)
func screen_k() -> float:
	var w := get_window()
	var k := sheet.scale.x
	if w == null or w.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return k
	var base := Vector2(w.content_scale_size)
	if base.x > 0.0 and base.y > 0.0:
		k *= minf(w.size.x / base.x, w.size.y / base.y)
	return k * w.content_scale_factor


func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit.call_deferred()


func _fit() -> void:
	_fit_queued = false
	if is_inside_tree() and not is_equal_approx(sheet.size.y, sheet_height()):
		menu._place_online()


## Esc: левая кнопка (её нет — главная); в выборе роли — закрыть лист
func escape() -> void:
	if _state == "choose":
		_close()
	elif _left.visible:
		_on_left()
	elif _main.visible and not _main.disabled:
		_on_main()


## Временная записка (подтверждение, «это макет», строка меню) на hold секунд, потом — снова записка состояния
## (кадр проверки держит её до конца)
func flash(text: String, hold := 2.4, kind := "gold") -> void:
	if _shot:
		hold = maxf(hold, 60.0)
	_msg_serial += 1
	_put_msg(kind, text)
	get_tree().create_timer(hold).timeout.connect(_msg_back.bind(_msg_serial))


func _msg_back(serial: int) -> void:
	if serial == _msg_serial:
		_put_msg(_msg_default[0], _msg_default[1], _msg_default[2])


## Записка состояния: kind — "red" / "green" / "gold" ("" — записки нет); lines — сколько строк она держит
## всегда (где записка меняется на ходу, лист и всё под ней не прыгают); tip — ключ подсказки TIPS
func _set_msg(kind: String, text: String, lines := 0, tip := "") -> void:
	_msg_default = [kind, text, tip]
	_msg_lines = lines
	_put_msg(kind, text, tip)


func _put_msg(kind: String, text: String, tip := "") -> void:
	var was := _msg_kind
	var old := _msg_text.text
	_msg_kind = kind
	_msg.visible = kind != ""
	_msg_gap.visible = _msg.visible
	if kind == "":
		return
	_msg_seal.texture = menu._tex("seal_" + kind)
	# версия рабочей сборки кончается сокращением («от 16 окт.») — в конце предложения не две точки подряд
	_msg_text.text = _nb(tr(text)).replace("..", ".")
	_msg_text.add_theme_color_override("font_color", RED_INK if kind == "red" else INK)
	# строки — как у самой надписи: высота строки и межстрочный зазор (иначе две строки текста выше запаса)
	var lh := _text(600).get_height(21)
	var gap := float(_msg_text.get_theme_constant("line_spacing"))
	_msg_text.custom_minimum_size = Vector2(1, (lh * _msg_lines + gap * maxi(_msg_lines - 1, 0)) if _msg_lines > 0 else 0.0)
	_msg.tooltip_text = _tip(tip) if tip != "" else ""
	# новая записка на том же месте — мягко проявляется, чтобы смену заметили (на кадре — сразу)
	if not _shot and visible and (was != kind or old != _msg_text.text):
		_msg.modulate.a = 0.35
		create_tween().tween_property(_msg, "modulate:a", 1.0, 0.3)


func _close() -> void:
	_live = false
	_stop_net()
	# порт, открытый из справки без «Создать игру», — закрыть, поиск адреса — бросить (ТЗ §16: «Отмена» и выход)
	if not _mock and _net != null:
		_net.forget_external()
	_reset_mock()
	menu._close_online()


## Лобби с начала: «Отмена» у хозяина и закрытый лист забывают номер партии, узнанный адрес в интернете и адрес
## друга (новая игра — с чистого листа)
func _reset_mock() -> void:
	_seed = SEED_MOCK
	_net_found = false
	_net_kind = "green"
	_addr = ""
	_addr_caret = -1
	_help_fw = false
	_help_from = "choose"
	_help_alt = 0
	_help_live = false
	_their = {}
	_net_addr = ""
	_lobby_wait = false
	_guest_shown = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_live = false


# ================================================================= клавиши и время

## Esc — раньше полей ввода: иначе первое нажатие съедает поле адреса (снимает правку), и лист стоит на месте
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var k := event as InputEventKey
	# кадр проверки: окно съёмки на миг берёт фокус — случайное нажатие на ПК не должно попасть в поле адреса
	if k and _shot:
		get_viewport().set_input_as_handled()
		return
	# рамка фокуса: ходят клавишами или геймпадом — видна, нажали мышью — снова спрятана
	if k and k.pressed and k.keycode in [KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		_kbd(true)
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		_kbd(true)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_kbd(false)
	if k and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		escape()
		get_viewport().set_input_as_handled()


## Клавиши или мышь: рамка фокуса и подсветка дощечек выбора (Plate слушает _gate.changed) — по KbdGate
func _kbd(on: bool) -> void:
	if _gate.on == on:
		return
	_gate.on = on
	var f := get_viewport().gui_get_focus_owner()
	if f:
		f.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	# F8 / Shift+F8 — листать состояния (только для кадров: ключ --menu_online)
	if k.keycode == KEY_F8 and menu._ordo and menu._ordo.has_arg("menu_online"):
		var i := STATES.find(_state)
		i = (i + (STATES.size() - 1 if k.shift_pressed else 1)) % STATES.size()
		print("[меню] макет: ", STATES[i])
		menu._open_online(STATES[i], 0)
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	# Enter — главная кнопка, если она доступна (у кнопки в фокусе Enter свой — до нас не доходит)
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and _main.visible and not _main.disabled:
		_on_main()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# многоточие «Ждём…» шагает раз в 0,5 с; в кадре — всегда «…»
	for i in _dots.size():
		if is_instance_valid(_dots[i]):
			var n := 3 if _shot else int(_t / 0.5) % 4
			_dots[i].text = _dots_base[i] + ("…" if n == 3 else ".".repeat(n))
	# «Начать игру» мягко светится, когда друг вошёл
	if _state == "host_ready":
		var g := 1.1 if _shot else 1.0 + 0.15 * (0.5 - 0.5 * cos(TAU * _t / 1.6))
		_main.self_modulate = Color(g, g, g)
	# настоящая сеть: сколько хозяин ждёт друга, сколько ещё ждать ответа (что дальше — решают события сети)
	if not _mock:
		if _state == "host_wait" and is_instance_valid(_wait_lbl):
			_wait_lbl.text = _wait_text(_host_sec())
		elif _state == "join_connecting" and not _checking:
			_tick_connect(minf((Time.get_ticks_msec() - _conn_t0) / 1000.0, CONNECT_LIMIT))
		return
	# макет: хозяин ушёл в справку, пока ждал друга, — игра не закрыта: время ожидания идёт дальше, друг всё равно
	# «входит», справка закрывается сама
	if _state == "help" and _help_live and _help_from == "host_wait":
		_clock += delta
		if _clock >= FRIEND_COMES:
			_live = true
			_show("host_ready", 0)
		return
	if not _live:
		return
	_clock += delta
	match _state:
		"join_connecting":
			if not _ok_mock:
				var sec := minf(_clock * CONNECT_SPEED, CONNECT_LIMIT)
				_tick_connect(sec)
				if sec >= CONNECT_LIMIT:
					_show("join_fail", 0)
			elif _clock < CONNECT_OK:
				_tick_connect(_clock)
			elif not _checking:
				_set_checking()
			elif _clock >= CONNECT_OK + CHECK_OK:
				_show("join_wait", 0)
		"host_wait":
			_wait_lbl.text = _wait_text(int(_clock))
			if _clock >= FRIEND_COMES:
				_show("host_ready", 0)


## Друг ответил: счётчик убран, строка ожидания — «Сверяем версии игры…», записка — зелёная
func _set_checking() -> void:
	_checking = true
	_put_msg("green", "Друг ответил — связь есть.")
	if not _dots.is_empty() and is_instance_valid(_dots[0]):
		_dots_base[0] = _nb(tr("Сверяем версии игры"))
		_dots[0].text = _dots_base[0] + "…"
	if is_instance_valid(_count):
		_count.text = ""


## Счётчик подключения: sec — сколько секунд стучимся; пишет, сколько ещё ждать («ещё 9 секунд»)
func _tick_connect(sec: float) -> void:
	if is_instance_valid(_count):
		_count.text = _remain_text(CONNECT_LIMIT - sec)


## «ещё 9 секунд» / «ещё 2 секунды» / «ещё 1 секунду» (сколько ещё ждать, целых секунд с округлением вверх)
static func _remain_text(sec: float) -> String:
	var n := maxi(0, ceili(sec - 0.001))
	var w := "секунд"
	if n % 10 == 1 and n % 100 != 11:
		w = "секунду"
	elif n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		w = "секунды"
	return "ещё %d %s" % [n, w]


# ================================================================= состояния

## Собрать тело листа заново; кнопки ряда и записка — по состоянию. keep_clock — время ожидания не сбрасывать
## (возврат из справки: хозяин ждёт друга дальше, «уже 0:42» не прыгает на «0:00»)
func _show(state: String, alt := 0, keep_clock := false) -> void:
	_state = state if state in STATES else "choose"
	_alt = alt
	if not keep_clock:
		_clock = 0.0
	_checking = false
	if _state != "help":
		_help_fw = false
	# временная записка прошлого состояния не вернётся поверх новой
	_msg_serial += 1
	_field = null
	_field_deco = null
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_dots.clear()
	_dots_base.clear()
	_count = null
	_wait_lbl = null
	_seed_lbl = null
	_seed_ghost = null
	_friend_side_lbl = null
	_friend_disc = null
	_main.self_modulate = Color.WHITE
	_title.text = tr("Игра с другом")
	# своя версия — внизу листа, просто как есть; в «разных версиях» и в справке её нет (там свои строки).
	# Хозяин, вариант 5, — у него старая версия
	var old_mine := _state == "host_wait" and _alt == 5
	if not _mock:
		_build.text = "" if _state in ["version", "help"] else tr("Ваша версия игры: %s") % NetVersion.label(_me())
	else:
		_build.text = "" if _state in ["version", "help"] else tr("Ваша версия игры: %s от %s") % [
			VER_OLD if old_mine else VER_MINE, DATE_OLD if old_mine else DATE_MINE]
	_build.visible = _build.text != ""
	var focus: Control = _main
	match _state:
		"choose":
			_set_left("Назад", "left_choose")
			_set_main("", "")
			# записка на месте с самого начала (золотой совет): ошибка «Создать игру» меняет только текст и печать,
			# дощечки не уезжают из-под мыши. Порт у игры один — 7777 (ТЗ §16): занят — значит, игру уже создало
			# второе окно «Ордо» (или чужая программа — тогда поможет перезагрузка). Строка шага — что сделать,
			# записка — что случилось
			if _alt == 1:
				_set_step("Закройте второе окно «Ордо» и нажмите «Создать игру» снова.")
				_set_msg("red", "Не получилось создать игру: место для игры по сети уже занято. Если не помогло — перезагрузите компьютер.", 2)
			else:
				_set_step("Выберите: создать игру или подключиться к другу.")
				_set_msg("gold", "Договоритесь, кто создаёт игру, — второй подключается.", 2)
			focus = _body_choose()
		"host_wait", "host_ready":
			var joined := _state == "host_ready"
			_set_step("Можно начинать — нажмите «Начать игру»." if joined else "Вы создали игру. Отправьте другу адрес.")
			_set_left("Отмена", "left_host")
			_set_main("Начать игру", "main_host_ready" if joined else "main_host_wait", joined)
			# записка хозяина держит две строки всегда: «Скопировано», «друг вышел», «друг вошёл» не сдвигают адреса.
			# Разные версии: обновляет игру тот, у кого версия старая (вариант 1 — старая у друга, 5 — у вас; 7 —
			# номер тот же, а игры собраны по-разному). Где сообщение длинное, строка шага говорит, что сделать
			if joined:
				if _alt == 1:
					_set_msg("gold", "Связь медленная — приказы будут чуть запаздывать.", 2, "Online_ping_slow")
				else:
					_set_msg("green", "Связь с другом хорошая, версия игры та же.", 2, "Online_ping")
			else:
				match _alt:
					1:
						_set_step("Пусть друг обновит игру и подключится снова.")
						_set_msg("red", tr("Друг не смог войти: у него старая версия игры (%s), у вас — %s. Пусть скачает новую там же, откуда ставил игру.") % [
							_ver_theirs(), _ver_mine()], 2)
					2:
						_set_msg("red", "Друг вышел. Адрес тот же — он может войти снова.", 2)
					4:
						# Radmin VPN не найден: в строке Radmin — «не найден» красными чернилами и «Как поставить»
						_set_msg("gold", "Radmin VPN не найден — друг издалека не подключится. Как" + NBSP + "поставить — по ссылке в строке Radmin.", 2)
					5:
						_set_step("Друг не смог войти — обновите игру.")
						_set_msg("red", tr("У вас старая версия (%s), у друга — %s: скачайте новую там же, откуда ставили, и снова нажмите «Создать игру».") % [
							VER_OLD if _mock else _ver_mine(), VER_MINE if _mock else _ver_theirs()], 2)
					6:
						# друг пропал без «пока» (ENet: peer_disconnected без прощания) — не «вышел»
						_set_msg("red", "Связь с другом пропала. Адрес тот же — он может войти снова.", 2)
					7:
						_set_step("Скачайте игру заново — и вы, и друг — с одного и того же сайта.")
						_set_msg("red", "Друг не смог войти: номер версии тот же, а игры собраны по-разному.", 2)
					_:
						# окно Windows может открыться за игрой во весь экран — отсюда Alt+Tab
						_set_msg("gold", FIREWALL_NOTE, 2)
			_body_host(joined)
			if joined:
				focus = _main
			else:
				focus = _body.find_child("Copy_1" if _alt == 4 else "Copy_0", true, false) as Control
			if _alt == 3 and not joined:
				flash(tr("Адрес скопирован. Вставьте его в сообщение другу в Telegram или WhatsApp и ждите друга здесь."), 3.0, "green")
		"join":
			# адрес в интернете (справка, способ 3) — дело хозяина: подключившемуся макет его не помнит
			_net_found = false
			_set_step("Друг уже создал игру? Впишите его адрес.")
			_set_left("Назад", "left_join")
			_set_main("Подключиться", "main_join_off", false)
			_set_msg("gold", "Друг далеко? У обоих должен быть Radmin VPN, и вы оба — в одной сети Radmin.", 2)
			focus = _body_join()
		"join_connecting":
			_set_step("Подключаемся к другу…")
			_set_left("Отмена", "left_connecting")
			# пока стучимся, нажать можно только «Отмена» — мёртвой «Подключиться» рядом нет
			_set_main("", "")
			# макет: удастся только подключение к ADDR_RADMIN (порт не важен)
			_ok_mock = (_addr if _addr != "" else ADDR_RADMIN).get_slice(":", 0) == ADDR_RADMIN
			# сколько ещё ждать — в строке со звездой; записка не повторяет секунды
			_set_msg("gold", "Обычно хватает пары секунд.", 2)
			_body_connecting()
			# вариант 1 — друг уже ответил, сверяем версии (в настоящей игре — миг, в макете — меньше секунды)
			if _alt == 1:
				_set_checking()
			# фокус — пустой, не на «Отмена»: нетерпеливое второе Enter не отменит подключение (Esc — отменит)
			focus = _rest
		"join_fail":
			# строка шага — что делать дальше, записка — что случилось
			_set_step("Место у друга занято. Что сделать — ниже." if _alt == 1
				else "Проверьте по списку и нажмите «Попробовать снова».")
			_set_left("Изменить адрес", "left_fail")
			_set_main("Попробовать снова", "main_fail")
			if _alt == 1:
				# друг уже играет с кем-то: хозяин отказывает с причиной, а не молчит (иначе — «не ответил»)
				_set_msg("red", "У друга в игре уже есть второй игрок — место занято.")
			else:
				_set_msg("red", tr("Не получилось подключиться к %s — друг не ответил за %d секунд.") % [
					_addr if _addr != "" else ADDR_RADMIN, int(CONNECT_LIMIT)])
			_body_fail()
		"join_wait":
			if _alt in [2, 3]:
				var lost := _alt == 3
				_set_step("Если друг ещё ждёт — подключитесь снова по тому же адресу." if lost
					else "Если друг создаст игру снова — подключитесь по тому же адресу.")
				_set_left("Назад", "left_closed")
				_set_main("Подключиться снова", "main_rejoin")
				# друг вышел сам (ENet: «пока» дошло) или связь пропала (peer_disconnected без «пока»)
				_set_msg("red", "Связь с другом пропала." if lost else "Друг вышел из игры: нажал «Отмена» или закрыл «Ордо».", 1)
				_body_closed(lost)
			else:
				# «ждём» здесь один раз — в строке со звездой; кнопка говорит, кто начнёт
				_set_step("Вы в игре у друга.")
				_set_left("Выйти", "left_wait")
				_set_main("Начнёт друг", "main_wait", false)
				if _alt == 4:
					_set_msg("gold", "Связь медленная — приказы будут чуть запаздывать.", 1, "Online_ping_slow")
				else:
					_set_msg("green", "Вы подключились к другу. Связь хорошая, версия та же.", 1, "Online_ping")
				_body_join_wait()
				# фокус — пустой, не на «Выйти»: Enter по привычке не выведет из игры друга (Esc — выведет)
				focus = _rest
				if _alt == 1 and _mock:
					flash(tr("Друг сменил сторону: теперь вы за Коканд."), 4.0, "gold")
		"version":
			# обновляет игру тот, у кого версия старая: 0 — старая у вас, 2 — у друга; 1 — номер тот же, код разный
			_set_step(["Скачайте новую версию и подключитесь снова.", "Оба переустановите игру и подключитесь снова.",
				"Пусть друг скачает новую версию и создаст игру снова."][clampi(_alt, 0, 2)])
			_set_left("", "")
			_set_main("Понятно", "main_version")
			_set_msg("red", "Номер версии тот же, а игры собраны по-разному — вместе играть не выйдет." if _alt == 1
				else "Разные версии игры — вместе играть не выйдет.")
			_body_version()
		"help":
			_title.text = tr("Как играть по сети")
			_set_step("Рядом — один Wi-Fi, далеко — Radmin VPN.")
			_set_left("", "")
			_set_main("Понятно", "main_help")
			# что вышло с «Узнать мой адрес в интернете» — в записке, на месте золотого совета (варианты 1–3 — для
			# кадра): адрес нашёлся и порт открыт, у провайдера так не выйдет, адрес есть, а роутер порт не открыл.
			# Вариант 4 — справку открыли ссылкой «Как открыть игре доступ к сети?»: блок про Windows отмечен
			match _alt:
				1:
					_net_found = true
					_net_kind = "green"
				2:
					_net_found = false
				3:
					_net_found = true
					_net_kind = "gold"
				4:
					_help_fw = true
			if _alt == 2:
				_set_msg("red", "У вашего провайдера так не выйдет — берите Radmin VPN.", 2)
			elif _net_found:
				_set_msg(_net_kind, _net_text(), 2)
			else:
				_set_msg("gold", "Не знаете, что выбрать — берите Radmin VPN.", 2)
			_body_help()
	if focus == null or not focus.visible:
		focus = _left if _left.visible else _main
	_focus_later.call_deferred(focus)
	_boost_all()
	_queue_fit()


## Фокус после сборки тела; за этот кадр состояние могло смениться ещё раз (F8 подряд) — тогда узла уже нет
func _focus_later(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()


func _set_step(text: String) -> void:
	_step.text = tr(text)


func _set_left(text: String, tip: String) -> void:
	_left.visible = text != ""
	_left.text = tr(text)
	_left.tooltip_text = _tip(tip)


func _set_main(text: String, tip: String, on := true) -> void:
	_main.visible = text != ""
	_main.text = tr(text)
	_main.tooltip_text = _tip(tip)
	# длинная надпись («Подключиться снова») — мельче, чтобы не упиралась во внутреннюю рамку доски
	var fs := 30
	while fs > 24 and _head().get_string_size(_main.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > MAIN_W - 56.0:
		fs -= 2
	_main.add_theme_font_size_override("font_size", fs)
	_main_on(on)


## Главная кнопка доступна или нет: недоступная — простая ореховая доска, потускневшая (_style_main)
func _main_on(on: bool) -> void:
	_main.disabled = not on
	_main.self_modulate = Color.WHITE
	# у тусклой доски текст без обводки, как вдавленный: читается, но не зовёт
	_main.add_theme_constant_override("outline_size", 4 if on else 0)


## Левая кнопка ряда — по состоянию (настоящая сеть: хозяин закрывает игру, друг отключается — оба шлют «пока»)
func _on_left() -> void:
	_live = false
	match _state:
		"choose":
			_close()
		"host_wait", "host_ready":
			# хозяин закрыл игру — номер партии и узнанный адрес забыты
			_stop_net()
			_reset_mock()
			_show("choose")
		"join", "join_wait":
			_stop_net()
			_show("choose")
		"join_connecting", "join_fail":
			_stop_net()
			_show("join")


## Главная кнопка ряда — по состоянию
func _on_main() -> void:
	match _state:
		"host_ready":
			if _mock:
				flash(tr(MOCK_FLASH))
			else:
				_start_match()
		"join":
			if _field and _addr_ok(_field.text):
				_addr = _field.text
				_connect()
			elif _field:
				_field_error(_field.text)
		"join_fail":
			_connect()
		"join_wait":
			if _alt in [2, 3]:
				_connect()
		"version":
			_show("join")
		"help":
			# назад туда, откуда пришли; хозяин, ждавший друга, — снова ждёт с тем же временем ожидания (игра не
			# закрывалась). Адрес в интернете макет помнит, только пока хозяин ждёт друга
			if _help_from != "host_wait":
				_net_found = false
			_live = _help_live
			_show(_help_from, _help_alt, true)


## Переход после нажатия: счётчики идут (открытое ключом состояние стоит на месте)
func _go_live(state: String) -> void:
	_live = true
	_show(state, 0)


# ================================================================= настоящая сеть (NetSession)

## «Создать игру»: макет — «друг войдёт» через 6 с; настоящая — сервер на 7777 (занят — выбор, вариант 1),
## свои адреса, номер партии; сторона и номер — другу сразу, как войдёт
func _on_host_pressed() -> void:
	if _mock:
		_go_live("host_wait")
		return
	_session()
	if _net.host() != OK:
		_show("choose", 1)
		return
	_seed = randi_range(100000, 999999)
	_their = {}
	_addrs = _scan_addrs()
	_host_t0 = Time.get_ticks_msec()
	_live = true
	_net.send_lobby(_side_index(), _seed)
	var no_radmin := String(_addrs.get("radmin", "")) == ""
	_show("host_wait", 4 if no_radmin else 0)
	# Radmin VPN не найден — записка о нём; но сперва — о вопросе Windows про сеть (он сейчас и откроется)
	if no_radmin:
		flash(tr(FIREWALL_NOTE), 12.0, "gold")


## «Подключиться» (и «Попробовать снова», «Подключиться снова»): макет — часы; настоящая — к адресу (порт после «:»)
func _connect() -> void:
	if _mock:
		_go_live("join_connecting")
		return
	_session()
	_their = {}
	_lobby_wait = false
	var host := _addr.get_slice(":", 0)
	var port := int(_addr.get_slice(":", 1)) if _addr.contains(":") else -1
	_conn_t0 = Time.get_ticks_msec()
	_live = true
	if _net.join(host, port) != OK:
		_show("join_fail", 0)
		return
	_show("join_connecting", 0)


## «Начать игру»: партия у обоих (NetMatch) — и в «Город»; друг пропал в этот миг — снова ждём его
func _start_match() -> void:
	if _net == null or _net.start_match(_side_index(), _seed) == null:
		_show("host_wait", 6)
		return
	_go_game()


func _go_game() -> void:
	_live = false
	menu._go(MainMenu.GOROD, tr("Игра с другом"))


## Закрыть сеть лобби (хозяин закрыл игру, друг вышел): «пока» другу — у него не «связь пропала»
func _stop_net() -> void:
	if not _mock and _net != null and _net.active():
		_net.leave()


func _session() -> void:
	if _net == null:
		_net = NetSession.get_or_create(get_tree())
	if not _net.event.is_connected(_on_net):
		_net.event.connect(_on_net)


## Сторона хозяина для сети: 0 — Коканд, 1 — кыпчаки
func _side_index() -> int:
	return 0 if _side == "kokand" else 1


## Хозяин сменил сторону или номер партии — друг видит сразу
func _lobby_changed() -> void:
	if not _mock and _net != null and _net.role == NetSession.Role.HOST:
		_net.send_lobby(_side_index(), _seed)


## Свои адреса для строк «Radmin VPN» и «Дома» (--net_show_addr=mock — выдуманные, для кадров)
func _scan_addrs() -> Dictionary:
	if menu._ordo != null and String(menu._ordo.arg("net_show_addr", "")) == "mock":
		return {"radmin": ADDR_RADMIN, "home": PackedStringArray([ADDR_HOME])}
	return NetAddr.scan()


## Сколько секунд хозяин ждёт друга (с «Создать игру»; справка часы не сбрасывает)
func _host_sec() -> int:
	return (Time.get_ticks_msec() - _host_t0) / 1000


## Своя версия (макет — выдуманная), версии для текстов: номер, у рабочей сборки — «рабочая сборка от …»
func _me() -> Dictionary:
	if _mock:
		return {"number": VER_MINE, "date": 20261015, "code": CODE_MINE.hex_decode()}
	return _net.mine() if _net != null else NetVersion.info()


func _ver_mine() -> String:
	return VER_MINE if _mock else _ver_short(_me())


func _ver_theirs() -> String:
	return VER_OLD if _mock else _ver_short(_their)


static func _ver_short(v: Dictionary) -> String:
	if v.is_empty():
		return "неизвестная"
	var n := String(v.get("number", ""))
	return n if n != "" else NetVersion.label(v)


## События сети → состояния лобби (ТЗ §16). Справку хозяина закрывают сами: друг вошёл — «Друг подключился»
func _on_net(kind: StringName, info: Dictionary) -> void:
	if _mock or not is_inside_tree() or not visible:
		return
	match kind:
		&"friend_joined":
			_show("host_ready", 1 if _net.slow else 0, true)
			if _net_auto_start:
				get_tree().create_timer(1.5).timeout.connect(func() -> void:
					if _state == "host_ready":
						_on_main())
		&"friend_refused":
			# друг уже здесь, а не впустили чужого — у хозяина ничего не меняется
			if _net.connected():
				return
			_their = info.get("their", {})
			var v := String(info.get("verdict", "odd"))
			_show("host_wait", 1 if v == "theirs_old" else (5 if v == "mine_old" else 7), true)
		&"friend_left":
			_show("host_wait", 2, true)
		&"friend_lost":
			_show("host_wait", 6, true)
		&"ping":
			var slow := bool(info.get("slow", false))
			if _state == "host_ready":
				_show("host_ready", 1 if slow else 0, true)
			elif _state == "join_wait" and _alt in [0, 4]:
				_show("join_wait", 4 if slow else 0)
		&"reached":
			if _state == "join_connecting":
				_set_checking()
		&"joined":
			# сторона и номер партии хозяина идут следом (LOBBY) — ждём их, но не дольше секунды
			if _net.lobby_seed != 0:
				_seed = _net.lobby_seed
				_show("join_wait", 4 if _net.slow else 0)
			else:
				_lobby_wait = true
				get_tree().create_timer(1.0).timeout.connect(func() -> void:
					if _lobby_wait and _state == "join_connecting" and _net.connected():
						_lobby_wait = false
						_show("join_wait", 4 if _net.slow else 0))
		&"lobby":
			# сторона, что сейчас на экране (в сессии уже новая)
			var before := _guest_shown
			_seed = int(info.get("seed", _seed))
			if _lobby_wait or (_state == "join_wait" and _alt in [0, 4]):
				_lobby_wait = false
				_show("join_wait", 4 if _net.slow else 0)
				var now := _guest_side()
				if before != "" and now != before and _state == "join_wait":
					flash(tr("Друг сменил сторону: теперь вы за %s.") % (tr("Коканд") if now == "kokand" else tr("кыпчаков")), 4.0, "gold")
		&"refused":
			var why := String(info.get("why", ""))
			if why == "version":
				_their = info.get("their", {})
				var v := String(info.get("verdict", "odd"))
				_show("version", 0 if v == "mine_old" else (2 if v == "theirs_old" else 1))
			else:
				_show("join_fail", 1 if why == "busy" else 0)
		&"connect_failed":
			_show("join_fail", 0)
		&"host_left":
			_show("join_wait", 2)
		&"host_lost":
			_show("join_wait", 3)
		&"start":
			_go_game()


## Сторона подключившегося (у настоящей сети — по стороне хозяина из LOBBY); «» — ещё не знаем
func _guest_side() -> String:
	if _mock:
		return "kokand" if _alt == 1 else "kipchak"
	if _net == null or _net.lobby_seed == 0:
		return ""
	return "kipchak" if _net.lobby_side == 0 else "kokand"


## Кадры двух настоящих окон (--net_auto): «host» — сразу «Создать игру» («host:start» — и «Начать игру», как только
## друг вошёл); «join:адрес» — вписать и «Подключиться»
func _auto(spec: String) -> void:
	if spec.begins_with("host"):
		if spec == "host:start":
			_net_auto_start = true
		_on_host_pressed()
	elif spec.begins_with("join:"):
		_show("join", 0)
		_on_field_changed(spec.substr(5), true)
		_on_main()


## В справку: состояние, вариант, шли ли счётчики и время ожидания — запомнить, чтобы вернуться в то же место;
## вписанный адрес друга и курсор в нём — тоже. fw — открыли ссылкой «Как открыть игре доступ к сети?»: блок про
## Windows в справке отмечен
func _to_help(fw := false) -> void:
	_help_from = _state
	_help_alt = _alt
	_help_live = _live
	if _state == "join" and is_instance_valid(_field):
		_addr = _field.text
		_addr_caret = _field.caret_column
	_live = false
	_help_fw = fw
	_show("help", 0, true)


# ---------------------------------------------------------------- choose

func _body_choose() -> Control:
	var host := _plate("Online_host", "icons/bld_kurultai", "Создать игру", "Вы выбираете сторону и ждёте друга")
	# макет: друг «входит» сам через FRIEND_COMES секунд ожидания; настоящая сеть — сервер (_on_host_pressed)
	host.pressed.connect(_on_host_pressed)
	_body.add_child(host)
	var join := _plate("Online_join", "icons/unit_cavalry", "Подключиться", "Друг уже создал игру — нужен его адрес")
	join.pressed.connect(_show.bind("join", 0))
	_body.add_child(join)
	# способ «для знатоков» (роутер) здесь не зазываем — он только в справке. Записка над дощечками — другой
	# совет («договоритесь, кто создаёт»), вставка его не повторяет
	_body.add_child(_info_box("Как связаться", [
		"Рядом, в одном Wi-Fi — ничего ставить не нужно.",
		"Далеко — оба ставите бесплатный Radmin VPN и входите в одну сеть.",
	]))
	_body.add_child(_link("Как играть по сети?"))
	return host


# ---------------------------------------------------------------- host_wait / host_ready

func _body_host(joined: bool) -> void:
	_body.add_child(_side_switch())
	# порт здесь не пишем: друг вписал бы «:7777» к адресу; порт — в подсказках и в справке
	_body.add_child(_section("Адрес для друга"))
	# адреса: каждая строка со своей кнопкой; метка — где друг. Radmin VPN не найден (вариант 4) — в строке
	# «не найден» и ссылка «Как поставить» (справка, способ 2)
	var copied := _alt == 3 and not joined and _mock
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	if _mock:
		if _alt == 4 and not joined:
			rows.add_child(_addr_row("Radmin VPN", "не найден", "", "Radmin_how"))
		else:
			rows.add_child(_addr_row("Radmin VPN", "друг далеко, у обоих Radmin", ADDR_RADMIN, "Copy_0", copied))
		rows.add_child(_addr_row("Дома", "друг рядом, в том же Wi-Fi", ADDR_HOME, "Copy_1"))
	else:
		# свои адреса (NetAddr): Radmin VPN — или «не найден»; дома — один или два (оба), нет — «не найден»
		var radmin := String(_addrs.get("radmin", ""))
		if radmin == "":
			rows.add_child(_addr_row("Radmin VPN", "не найден", "", "Radmin_how"))
		else:
			rows.add_child(_addr_row("Radmin VPN", "друг далеко, у обоих Radmin", radmin, "Copy_0"))
		var home: PackedStringArray = _addrs.get("home", PackedStringArray())
		if home.is_empty():
			rows.add_child(_addr_row("Дома", "не найден", "", "", false, "нет Wi-Fi и провода к роутеру"))
		for i in home.size():
			rows.add_child(_addr_row("Дома", "друг рядом, в том же Wi-Fi", home[i], "Copy_%d" % (i + 1)))
	_body.add_child(_card(rows))
	_body.add_child(_friend_slot(joined))
	# строка под местом друга и номер партии — ровно одной высоты в обоих состояниях (друг вошёл — ряд кнопок и
	# низ листа не сдвигаются ни на точку): у каждой строки невидимый двойник с текстом другого состояния (_twin).
	# Пока ждём — ссылка, как открыть игре доступ к сети (частая беда у того, кто создаёт игру; справка вернёт сюда
	# же, игра не закрывается), друг вошёл — что ещё можно поменять
	var can := _para("Сторону и номер партии ещё можно сменить — друг увидит сразу.", _italic(480), 21, INK_SOFT)
	can.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var fw := _link("Как открыть игре доступ к сети?", "Online_help_fw", true)
	_body.add_child(_twin(can, fw) if joined else _twin(fw, can))
	# номер партии — ниже адресов: его не отправляют, главное здесь — адрес
	_body.add_child(_seed_row())
	_sync_side()


## Строка ровно той высоты, что выше из двух: shown видна, ghost — невидимый двойник (текст другого состояния)
## только держит место; кнопок в двойнике не нажать и фокусом не достать
func _twin(shown: Control, ghost: Control) -> Control:
	var box := MarginContainer.new()
	box.name = "Twin"
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	ghost.modulate.a = 0.0
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.focus_mode = Control.FOCUS_NONE
	ghost.name = "Ghost"
	ghost.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(ghost)
	box.add_child(shown)
	return box


## «Ваша сторона: Коканд | Кыпчаки» — половины встык, выбранная закрашена цветом стороны
func _side_switch() -> Control:
	var row := HBoxContainer.new()
	row.name = "SideSwitch"
	row.custom_minimum_size = Vector2(0, 60)
	row.add_theme_constant_override("separation", 0)
	var cap := menu._label(tr("Ваша сторона"), _head(), 28, INK)
	# подпись шириной 198 (при 190 «Ваша сторона» встаёт впритык к переключателю), половины по 237
	cap.custom_minimum_size = Vector2(198, 0)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	var group := ButtonGroup.new()
	for side: String in ["kokand", "kipchak"]:
		var left := side == "kokand"
		var b := CityTips.TipButton.new()
		b.name = "Side_" + side
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = side == _side
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(237, 60)
		b.tooltip_text = _tip("Side_" + side)
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, _side_box(st, side, left))
		# фокус — латунная рамка по краю половины, только при ходьбе клавишами
		var ring := _focus_ring()
		ring.box = _side_box("focus", side, left)
		b.add_theme_stylebox_override("focus", ring)
		# заливка половины — крашеная бумага (не плоский цвет): цвет стороны или орех, светлее сверху и темнее
		# снизу, сквозь краску видны волокна бумаги; скругление снаружи, внутри рамки
		var paint := SidePaint.new()
		paint.button = b
		paint.left = left
		paint.color_on = KOKAND if left else KIPCHAK
		paint.fibre = menu._tex("paper")
		paint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(paint)
		b.toggled.connect(func(_on: bool) -> void: paint.queue_redraw())
		b.mouse_entered.connect(paint.queue_redraw)
		b.mouse_exited.connect(paint.queue_redraw)
		# полоса пояса внутри снизу (у выбранной) с кромкой тушью: читается и на красном; снаружи скругление —
		# полоса короче на радиус
		var belt := _belt(side)
		belt.anchor_top = 1.0
		belt.anchor_bottom = 1.0
		belt.anchor_right = 1.0
		belt.offset_left = 10.0 if left else 2.0
		belt.offset_right = -2.0 if left else -10.0
		belt.offset_top = -13.0
		belt.offset_bottom = -2.0
		b.add_child(belt)
		var inner := HBoxContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_bottom = -8.0
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.add_theme_constant_override("separation", 12)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inner)
		var disc := _disc(side, 36.0)
		inner.add_child(disc)
		var name_lbl := menu._label(tr("Коканд" if left else "Кыпчаки"), _head(), 30, PARCH)
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(name_lbl)
		# фокус надпись не красит: его показывает рамка (_side_box, только при ходьбе клавишами)
		var lit := func() -> void:
			var on := b.button_pressed
			name_lbl.add_theme_color_override("font_color", PARCH if on else PARCH_DIM)
			disc.modulate.a = 1.0 if on else 0.55
			belt.visible = on
		b.toggled.connect(func(on: bool) -> void:
			lit.call()
			if on:
				_side = side
				_sync_side()
				_lobby_changed())
		lit.call()
		row.add_child(b)
	return row


## Половина переключателя стороны: рамка латунная 2 px (заливку рисует SidePaint под надписью); фон рамки —
## тёмный орех на случай щели по краю скругления
func _side_box(state: String, side: String, left: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var on := state in ["pressed", "hover_pressed"]
	sb.bg_color = (KOKAND if side == "kokand" else KIPCHAK).darkened(0.3) if on else WALNUT
	sb.border_color = BRASS if state in ["hover", "focus", "hover_pressed"] else BRASS_DIM
	sb.set_border_width_all(2)
	var r := 10
	sb.corner_radius_top_left = r if left else 0
	sb.corner_radius_bottom_left = r if left else 0
	sb.corner_radius_top_right = 0 if left else r
	sb.corner_radius_bottom_right = 0 if left else r
	sb.set_content_margin_all(6)
	if state == "focus":
		# рамка фокуса на точку шире наружу: краска половины (SidePaint) лежит поверх доски кнопки
		sb.draw_center = false
		sb.set_border_width_all(3)
		sb.set_expand_margin_all(1)
	return sb


## Номер партии с пояснением и «Другой номер»: случайности боя и ИИ, карта та же; другу не отправляют. Пока ждём
## друга — ещё и «Друг увидит его сам»; друг вошёл — без этого (строкой выше и так «друг увидит сразу»), а место
## держит невидимый двойник с длинным текстом (_twin; тексты — _sync_side)
func _seed_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "SeedRow"
	row.add_theme_constant_override("separation", 14)
	_seed_lbl = _para("", _italic(480), 20, INK_SOFT)
	_seed_ghost = _para("", _italic(480), 20, INK_SOFT)
	var twin := _twin(_seed_lbl, _seed_ghost)
	twin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	twin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(twin)
	var other := _button("Seed_new", "Другой номер", "Seed_new", Vector2(204, 40), 24)
	other.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	other.pressed.connect(_new_seed)
	row.add_child(other)
	return row


func _new_seed() -> void:
	_seed = randi_range(100000, 999999)
	_sync_side()
	_lobby_changed()


## Подписи, зависящие от стороны хозяина и номера партии
func _sync_side() -> void:
	var friend := "kipchak" if _side == "kokand" else "kokand"
	if is_instance_valid(_seed_lbl):
		# прямо сказать, что номер не для отправки: иначе его примут за код комнаты. Друг вошёл — строкой выше уже
		# «друг увидит сразу»; двойник держит место длинного текста
		var full := _nb(tr("Номер партии %s: от него зависят случайности в бою. Друг увидит его сам.") % _seed_text(_seed))
		_seed_lbl.text = _nb(tr("Номер партии %s: от него зависят случайности в бою.") % _seed_text(_seed)) if _state == "host_ready" else full
		if is_instance_valid(_seed_ghost):
			_seed_ghost.text = full
	if is_instance_valid(_friend_side_lbl):
		_friend_side_lbl.text = tr("за кыпчаков") if friend == "kipchak" else tr("за Коканд")
	if is_instance_valid(_friend_disc):
		_friend_disc.tex = menu._tex("icons/crest_" + friend)
		_friend_disc.queue_redraw()


## «482 913» — тысячи через пробел
static func _seed_text(n: int) -> String:
	var s := str(n)
	return s if s.length() <= 3 else s.substr(0, s.length() - 3) + " " + s.substr(s.length() - 3)


## «уже 0:42» (строкой выше — «Ждём друга…»: второй раз «ждём» не пишем)
static func _wait_text(sec: int) -> String:
	return "уже %d:%02d" % [sec / 60, sec % 60]


## Строка адреса: [сеть / где друг] [адрес] [кнопка]. Адреса нет (Radmin VPN не найден) — название тише, под ним
## «не найден» красными чернилами, на месте адреса — почему (why: «не установлен или выключен»), вместо
## «Копировать» — ссылка «Как поставить» в справку (btn пусто — без ссылки: «Дома» не найден)
func _addr_row(net: String, tag: String, addr: String, btn: String, copied := false,
		why := "не установлен или выключен") -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 54)
	row.add_theme_constant_override("separation", 12)
	var names := VBoxContainer.new()
	names.custom_minimum_size = Vector2(240, 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", -4)
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# латиница — только Alegreya (у Cormorant Unicase она капителью)
	names.add_child(menu._label(net, _text(600), 22, INK if addr != "" else INK_SOFT))
	names.add_child(menu._label(tr(tag), _italic(600 if addr == "" else 500), 20, RED_INK if addr == "" else INK_SOFT))
	row.add_child(names)
	# почему адреса нет — в две плотные строки: строка не шире столбца листа и не выше строки с адресом (54 —
	# ряд кнопок у хозяина не сдвигается)
	var a := menu._label(addr, _addr_font(), 34, INK) if addr != "" \
		else _para(why, _italic(480), 20, INK_SOFT)
	if addr == "":
		a.add_theme_constant_override("line_spacing", -8)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(a)
	if addr == "" and btn == "":
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(190, 44)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gap)
		return row
	if addr == "":
		var how := _flat(btn, tr("Как поставить"), _text(600), 22, INK)
		how.custom_minimum_size = Vector2(190, 44)
		how.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_lit_link(how)
		how.pressed.connect(_to_help.bind(false))
		row.add_child(how)
		return row
	var b := _button(btn, "Скопировано" if copied else "Копировать", "Copy_1" if btn == "Copy_2" else btn, Vector2(190, 44), 24)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(_on_copy.bind(b, addr))
	row.add_child(b)
	return row


## «Копировать» — выдуманный адрес в буфер обмена, на 2 с «Скопировано», зелёная записка — что дальше
func _on_copy(b: Button, addr: String) -> void:
	DisplayServer.clipboard_set(addr)
	b.text = tr("Скопировано")
	flash(tr("Адрес скопирован. Вставьте его в сообщение другу в Telegram или WhatsApp и ждите друга здесь."), 3.0, "green")
	get_tree().create_timer(2.0).timeout.connect(_copy_back.bind(b))


func _copy_back(b: Button) -> void:
	if is_instance_valid(b):
		b.text = tr("Копировать")


## Место друга. Пусто — блёклая бумажка с рваным краем, латунная звезда, «Ждём друга…», сколько ждём, и бледный
## герб его стороны; друг вошёл — простая карточка в рамке тушью: «Друг подключился» и его сторона (не «в игре»:
## партия ещё не начата). Без печати: «связь хорошая» — в записке листа, как у всех сообщений. Высота места —
## одна (72) в обоих видах
func _friend_slot(joined: bool) -> Control:
	var slot := SlotBox.new()
	slot.name = "Friend_slot"
	slot.filled = joined
	slot.ink = _ink_box()
	slot.custom_minimum_size = Vector2(0, 72)
	var row := _row_in(slot, 18.0, 22.0, 14)
	if not joined:
		row.add_child(_spinner())
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -8)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	if joined:
		texts.add_child(menu._label(tr("Друг подключился"), _head(), 30, INK))
	else:
		var wait := menu._label(tr("Ждём друга…"), _head(), 30, INK_SOFT)
		texts.add_child(wait)
		_dots.append(wait)
		_dots_base.append(tr("Ждём друга"))
		# после справки время ожидания идёт дальше (_clock не сброшен; у настоящей сети — с «Создать игру»)
		var sec := (int(_clock) if _live else WAIT_MOCK) if _mock else _host_sec()
		_wait_lbl = menu._label(tr(_wait_text(sec)), _italic(480), 21, INK_SOFT)
		texts.add_child(_wait_lbl)
	_friend_disc = _disc("kipchak", 44.0)
	_friend_disc.modulate.a = 1.0 if joined else 0.55
	row.add_child(_friend_disc)
	_friend_side_lbl = menu._label("", _italic(480), 21, INK if joined else INK_SOFT)
	_friend_side_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_friend_side_lbl)
	return slot


# ---------------------------------------------------------------- join

func _body_join() -> Control:
	_body.add_child(_section("Адрес друга"))
	var row := HBoxContainer.new()
	row.name = "FieldRow"
	row.add_theme_constant_override("separation", 16)
	_field = _line_edit()
	_field_deco = _field.get_node("Deco") as SlipDeco
	# вписанное раньше (и до похода в справку) — на месте, курсор там же, где был
	_field.text = ADDR_PART if _alt == 1 and _mock else (ADDR_RADMIN if _alt == 2 and _mock else _addr)
	_field.caret_column = _field.text.length() if _addr_caret < 0 or _alt != 0 else mini(_addr_caret, _field.text.length())
	_addr = _field.text
	_field.text_changed.connect(_on_field_changed)
	_field.text_submitted.connect(func(_t: String) -> void: _on_main())
	# ошибку показываем, когда вписали и ушли из поля (или Enter), а не пока человек ещё пишет
	_field.focus_exited.connect(_on_field_left)
	row.add_child(_field)
	var paste := _button("Join_paste", "Вставить", "Join_paste", Vector2(150, 60), 24)
	paste.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paste.pressed.connect(_on_paste)
	row.add_child(paste)
	_body.add_child(row)
	# адрес, к которому подключались в прошлый раз (у настоящей сети — из настроек; первый раз — ссылки нет)
	var last := ADDR_RADMIN if _mock else NetSession.last_addr()
	if last != "":
		var recent := _flat("Join_recent", tr("В прошлый раз: %s") % last, _text(600), 22, INK)
		_lit_link(recent)
		recent.pressed.connect(_on_recent.bind(last))
		_body.add_child(recent)
	# над советом — чуть воздуха: запас высоты «Адреса друга» (JOIN_H, как у «Подключаемся») не копится одной
	# пустой полосой над кнопками
	_body.add_child(menu._gap(8))
	_body.add_child(_info_box("Где взять адрес", [
		"Адрес — на экране у друга, после «Создать игру».",
		"Пусть пришлёт его в Telegram или WhatsApp — скопируйте его сообщение целиком и нажмите «Вставить».",
	]))
	_body.add_child(_link("Как играть по сети?"))
	if _alt == 1 and _mock:
		_field_error(ADDR_PART)
	elif _alt == 2 and _mock:
		_field_found(ADDR_RADMIN)
	_sync_join()
	return _field


## «Вставить»: сообщение друга из буфера обмена. Адреса в нём нет — поле остаётся как было, только красная записка
func _on_paste() -> void:
	if _field == null:
		return
	_field.grab_focus()
	_on_field_changed(DisplayServer.clipboard_get(), true)


func _on_recent(addr: String) -> void:
	if _field == null:
		return
	_field.text = addr
	_field.caret_column = _field.text.length()
	_field.grab_focus()
	_on_field_changed(_field.text)


## Поле адреса — бумажная полоска на листе (светлее листа, с тенью снизу): латунные уголки и черта тушью под
## строкой (SlipDeco); шрифт адреса 36; образец — курсивом, чтобы не спутать с вписанным адресом. dim — поле не
## поправить («Подключаемся»): полоска почти цвета листа, уголки и черта блёклые, адрес бледнее — как тусклая
## «Вставить» рядом
func _line_edit(dim := false) -> TipLine:
	var f := TipLine.new()
	f.name = "Join_addr"
	f.custom_minimum_size = Vector2(506, 76)
	f.add_theme_font_override("font", _addr_font())
	f.add_theme_font_size_override("font_size", 36)
	var slip := StyleBoxFlat.new()
	slip.bg_color = Color("#f4e9cd").lerp(Color("#e2cfa4"), 0.7) if dim else Color("#f4e9cd")
	slip.shadow_color = Color(0.17, 0.1, 0.05, 0.12 if dim else 0.3)
	slip.shadow_size = 4
	slip.shadow_offset = Vector2(0, 2)
	slip.content_margin_left = 24
	slip.content_margin_right = 24
	slip.content_margin_top = 6
	slip.content_margin_bottom = 16
	f.add_theme_stylebox_override("normal", slip)
	f.add_theme_stylebox_override("read_only", slip)
	# фокус видно по латунной черте и уголкам (SlipDeco), без рамки поверх полоски
	f.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	f.add_theme_color_override("font_uneditable_color", Color(INK_SOFT, 0.72) if dim else INK_SOFT)
	# курсор ввода — тонкий, тушью посветлее (не толстая палка у первой буквы); в кадре проверки его нет
	f.add_theme_constant_override("caret_width", 2)
	f.add_theme_color_override("caret_color", Color(0, 0, 0, 0) if _shot else INK_SOFT)
	f.tooltip_text = _tip("Join_addr")
	f.max_length = 400
	var deco := SlipDeco.new()
	deco.name = "Deco"
	deco.field = f
	deco.dim = dim
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.add_child(deco)
	f.focus_entered.connect(deco.queue_redraw)
	f.focus_exited.connect(deco.queue_redraw)
	# образец — без настоящего адреса (26.x — чей-то Radmin: новичок вписал бы образец как есть); на 10 правее
	# начала строки — курсор не прилипает к первой букве
	f.hint = menu._label(tr("впишите адрес с экрана друга"), _italic(450), 26, Color(INK_SOFT, 0.62))
	f.hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.hint.offset_left = 34.0
	f.hint.offset_bottom = -6.0
	f.hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	f.add_child(f.hint)
	f.text_changed.connect(func(_t: String) -> void: f.sync_hint())
	return f


## Ввод чистится сам: пробелы и «http://» прочь, курсор остаётся у того же знака. Вписаны одни цифры и знаки — это
## адрес при русской раскладке: «ю», «б», «,» — точка, «ж» — двоеточие. Иначе это сообщение целиком: в нём, как
## есть, ищем первый адрес (раскладку не трогаем — «1,2,3,4» в обычной фразе адресом не станет; порт через «ж»
## найдётся и так). Вставили («Вставить» или Ctrl+V — прибавилось сразу несколько знаков) текст без адреса — поле
## остаётся как было, только красная записка. Что в поле и где курсор — в _addr / _addr_caret (переживают справку)
func _on_field_changed(raw: String, pasted := false) -> void:
	if _field == null:
		return
	var before := _addr
	var bulk := pasted or raw.length() > before.length() + 1
	var caret := raw.length() if pasted else clampi(_field.caret_column, 0, raw.length())
	var plain := _clean(raw)
	var at := _clean(raw.substr(0, caret)).length()
	var found := ""
	var junk := ""
	if plain == "":
		if pasted:
			# буфер обмена пуст — поле как было
			junk = "Сначала скопируйте сообщение друга целиком, потом нажмите «Вставить»."
	elif _typed_re.search(plain) != null:
		plain = _layout_fix(plain)
	else:
		var m := _ip_re.search(raw)
		if m != null and m.get_string(0) != plain:
			found = _layout_fix(m.get_string(0))
			plain = found
			at = plain.length()
		elif m == null and bulk:
			junk = "В скопированном нет адреса: нужно четыре числа через точку, как у друга на экране."
	if junk != "":
		plain = before
		at = before.length() if _addr_caret < 0 else _addr_caret
	if plain != _field.text:
		_field.text = plain
	_field.caret_column = clampi(at, 0, plain.length())
	_addr = _field.text
	_addr_caret = _field.caret_column
	_field_clear()
	if junk != "":
		_put_msg("red", junk)
	elif found != "":
		_field_found(found)
	elif pasted and not _addr_ok(plain):
		_field_error(plain)
	elif _addr_ok(plain) and plain.begins_with("127."):
		# 127.x — свой же компьютер: предупреждаем, но не запрещаем (две копии игры на одном ПК — проверка)
		_put_msg("gold", "Это адрес вашего компьютера. Нужен адрес друга — с его экрана.")
	_sync_join()


## Без «http://» и пробелов (и неразрывных, и переносов строк)
static func _clean(s: String) -> String:
	var t := s.replace("https://", "").replace("http://", "")
	var out := ""
	for ch in t:
		if not (ch in [" ", "\t", "\n", "\r", NBSP]):
			out += ch
	return out


## Знаки русской раскладки — в знаки адреса: «ю», «б», «,» — точка, «ж» — двоеточие
static func _layout_fix(s: String) -> String:
	var out := ""
	for ch in s:
		if ch in ["ю", "Ю", "б", "Б", ","]:
			out += "."
		elif ch in ["ж", "Ж"]:
			out += ":"
		else:
			out += ch
	return out


## Ушли из поля: вписано и неверно — сказать сразу. Проверка — кадром позже: если ушли мышью на «Назад»,
## «Вставить» или «В прошлый раз», поле сейчас сменится само — красная черта не мигает зря
func _on_field_left() -> void:
	_field_left_check.call_deferred()


func _field_left_check() -> void:
	if _field == null or not is_instance_valid(_field) or not _field.is_inside_tree() or _state != "join":
		return
	var f := get_viewport().gui_get_focus_owner()
	if f != null and (f == _left or (String(f.name) in ["Join_paste", "Join_recent"]
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))):
		return
	if _field.text != "" and not _addr_ok(_field.text):
		_field_error(_field.text)


## «Подключиться» горит, только когда адрес верный
func _sync_join() -> void:
	if _field == null:
		return
	_field.sync_hint()
	var ok := _addr_ok(_field.text)
	_main_on(ok)
	_main.tooltip_text = _tip("main_join" if ok else "main_join_off")


## Верный адрес: четыре числа 0–255 через точку, первое — 1–223 (0.x, 224.x и выше — служебные: к другу по
## ним не подключиться, ENet откажет сразу, а не «не ответил»), и, может быть, порт 1–65535 после «:»
func _addr_ok(t: String) -> bool:
	if not _addr_shape(t):
		return false
	var m := _full_re.search(t)
	var first := int(m.get_string(1))
	if first < 1 or first > 223:
		return false
	var port := m.get_string(5)
	return port == "" or (int(port) >= 1 and int(port) <= 65535)


## Похоже на адрес: четыре числа 0–255 через точку (и, может быть, порт)
func _addr_shape(t: String) -> bool:
	var m := _full_re.search(t)
	if m == null:
		return false
	for i in range(1, 5):
		if int(m.get_string(i)) > 255:
			return false
	return true


## Сообщение поля снято: черта снова тушью, записка — снова своя у «Адреса друга»
func _field_clear() -> void:
	_field_mark(false)
	_put_msg(_msg_default[0], _msg_default[1], _msg_default[2])


func _field_error(t: String) -> void:
	_field_mark(true)
	if t.to_lower() == "localhost":
		_put_msg("red", "Это адрес вашего компьютера. Нужен адрес друга — с его экрана.")
	elif _addr_shape(t):
		# четыре числа есть, но такого адреса у друга не бывает (0.x, 224.x и выше) или порт не тот
		_put_msg("red", "Такой адрес не подойдёт — проверьте его по экрану друга, цифра в цифру.")
	else:
		_put_msg("red", "Не похоже на адрес: нужно четыре числа через точку, как у друга на экране.")


## Адрес нашёлся в сообщении: зелёная записка. После адреса — без точки (её приняли бы за часть адреса)
func _field_found(addr: String) -> void:
	_field_mark(false)
	_put_msg("green", tr("Нашли адрес в сообщении — %s") % addr)


## Неверный адрес — черта под строкой красными чернилами, волной
func _field_mark(err: bool) -> void:
	if is_instance_valid(_field_deco):
		_field_deco.err = err
		_field_deco.queue_redraw()


# ---------------------------------------------------------------- join_connecting / join_fail / join_wait

## Подключаемся: поле и «Вставить» на тех же местах, что в «Адресе друга» (только не нажать — оба блёклые), под
## ними — латунная звезда, «Стучимся к другу…» и сколько ещё ждать (полоски загрузки нет: звезда и так говорит
## «ждём»)
func _body_connecting() -> void:
	_body.add_child(_section("Адрес друга"))
	var row := HBoxContainer.new()
	row.name = "FieldRow"
	row.add_theme_constant_override("separation", 16)
	var f := _line_edit(true)
	f.text = _addr if _addr != "" else ADDR_RADMIN
	f.editable = false
	f.focus_mode = Control.FOCUS_NONE
	f.sync_hint()
	row.add_child(f)
	var paste := _button("Join_paste", "Вставить", "", Vector2(150, 60), 24)
	paste.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paste.disabled = true
	paste.focus_mode = Control.FOCUS_NONE
	row.add_child(paste)
	_body.add_child(row)
	var st := _wait_row("Стучимся к другу", _remain_text(CONNECT_LIMIT - (0.0 if _live else CONNECT_MOCK)))
	_body.add_child(st)
	_count = st.get_node_or_null("Right") as Label
	_body.add_child(menu._gap(2))
	_body.add_child(_info_box("Что будет дальше", [
		"Друг ответит — сверим версии игры.",
		"Версии те же — вы в игре у друга.",
		"Друг нажмёт «Начать игру» — партия начнётся у обоих сразу.",
	]))


func _body_fail() -> void:
	if _alt == 1:
		_body.add_child(_para("По сети играют только вдвоём. Может быть, вы уже подключились к нему из другого окна игры — или к нему зашёл кто-то ещё.",
			_italic(480), 21, INK))
		_body.add_child(_section("Что сделать"))
		_body.add_child(_numbered([
			"Закройте второе окно «Ордо», если оно открыто.",
			"Пусть друг нажмёт «Отмена» и снова «Создать игру».",
			"Потом нажмите «Попробовать снова».",
		]))
		return
	_body.add_child(_section("Что проверить"))
	_body.add_child(_numbered([
		"Друг нажал «Создать игру» и видит у себя «Ждём друга…».",
		"Адрес вписан точно как у друга — цифра в цифру.",
		"Вы далеко? У обоих включён Radmin VPN, и вы в одной сети Radmin. Адрес нужен из строки «Radmin VPN» у друга на экране.",
		"Windows у друга могла закрыть игре доступ к сети. Открыть его должен друг — тот, кто создал игру, у себя на компьютере.",
	]))
	# ссылка названа тем, что нужно здесь (пункт 4); справка откроется на блоке про Windows
	_body.add_child(_link("Как открыть игре доступ к сети?", "Online_help_fw", true))


func _body_join_wait() -> void:
	# сторона — другая, чем у хозяина (настоящая сеть: из его LOBBY), номер партии — его
	var me := _guest_side()
	if me == "":
		me = "kipchak"
	_guest_shown = me
	if not _mock and _net != null and _net.lobby_seed != 0:
		_seed = _net.lobby_seed
	var friend := "kipchak" if me == "kokand" else "kokand"
	var row := HBoxContainer.new()
	row.name = "Tablets"
	row.add_theme_constant_override("separation", 0)
	row.add_child(_side_card(me, "Вы"))
	var vs := menu._label(tr("против"), _italic(480), 22, INK_SOFT)
	vs.custom_minimum_size = Vector2(96, 0)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(vs)
	row.add_child(_side_card(friend, "Друг"))
	_body.add_child(row)
	_body.add_child(_para("Карта — долина у Тянь-Шаня · номер партии %s" % _seed_text(_seed), _italic(480), 21, INK_SOFT))
	_body.add_child(_wait_row("Друг нажмёт «Начать игру» — и партия начнётся", ""))
	_body.add_child(menu._gap(2))
	_body.add_child(_info_box("Как пойдёт игра", [
		"Сторону и номер партии выбирает друг — вы увидите сразу.",
		"Пауза общая: если один нажмёт паузу — игра встанет у обоих.",
		"Если связь пропадёт — игра встанет и подождёт друга.",
	]))


## Друг вышел или связь пропала (lost), пока вы ждали начала: что случилось — в записке, здесь — что делать
func _body_closed(lost: bool) -> void:
	_body.add_child(_section("Что сделать"))
	if lost:
		_body.add_child(_numbered([
			"Проверьте, что интернет работает, а если вы далеко — что Radmin VPN включён, у вас и у друга.",
			"Если друг ещё ждёт — нажмите «Подключиться снова»: адрес тот же.",
			"Или нажмите «Назад» и создайте игру сами.",
		]))
		_body.add_child(_link("Как играть по сети?"))
		return
	_body.add_child(_numbered([
		"Спросите друга, создаст ли он игру снова.",
		"Если друг создал игру снова — нажмите «Подключиться снова»: адрес тот же.",
		"Или нажмите «Назад» и создайте игру сами.",
	]))


## Табличка стороны: карточка в рамке тушью (как адреса и место друга), пояс сверху внутри рамки, герб на кружке,
## кто («Вы» / «Друг») и сторона
func _side_card(side: String, who: String) -> Control:
	var p := Panel.new()
	p.name = "Tablet_me" if who == "Вы" else "Tablet_friend"
	p.custom_minimum_size = Vector2(288, 120)
	p.add_theme_stylebox_override("panel", _ink_box())
	var belt := _belt(side)
	belt.anchor_right = 1.0
	belt.offset_left = 8.0
	belt.offset_right = -8.0
	belt.offset_top = 8.0
	belt.offset_bottom = 20.0
	p.add_child(belt)
	var row := _row_in(p, 20.0, 12.0, 16)
	row.offset_top = 19.0
	row.offset_bottom = -4.0
	row.add_child(_disc(side, 56.0))
	var texts := VBoxContainer.new()
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -6)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(menu._label(tr(who), _head(), 24, INK_SOFT))
	texts.add_child(menu._label(tr("Коканд" if side == "kokand" else "Кыпчаки"), _head(), 32, INK))
	row.add_child(texts)
	return p


# ---------------------------------------------------------------- version / help

## Разные версии. Правило одно: обновляет игру тот, у кого версия старая. Вариант 0 — старая у вас (у хозяина в
## это же время — host_wait, вариант 1), 2 — старая у друга (у хозяина — host_wait, вариант 5); 1 — номер тот же,
## а код разный (у хозяина — host_wait, вариант 7): игры собраны по-разному, никого не винить. Перевыпуска с тем же
## номером не бывает (в версию пишется номер попытки сборки, ТЗ §16) — остаются игра не с того сайта, местная
## сборка или испорченные файлы: «поставлена не оттуда же»
func _body_version() -> void:
	# макет: «новая» и «старая» выдуманные; настоящая сеть — своя версия и версия друга из его первого пакета
	var mine := tr("%s от %s") % [VER_MINE, DATE_MINE]
	var old := tr("%s от %s") % [VER_OLD, DATE_OLD]
	var me_txt := old if _alt == 0 else mine
	var friend_txt := mine if _alt == 0 else old
	var code_me := CODE_MINE
	var code_friend := CODE_ODD
	var newer_num := VER_MINE
	if not _mock:
		me_txt = NetVersion.label(_me())
		friend_txt = NetVersion.label(_their) if not _their.is_empty() else tr("неизвестная версия")
		code_me = NetVersion.code_text(_me().get("code", PackedByteArray()))
		code_friend = NetVersion.code_text(_their.get("code", PackedByteArray())) if not _their.is_empty() else "—"
		newer_num = _ver_theirs() if _alt == 0 else _ver_mine()
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)
	match _alt:
		1:
			grid.add_child(_build_row("У вас:", "%s · код %s" % [me_txt if not _mock else mine, code_me], ""))
			grid.add_child(_build_row("У друга:", "%s · код %s" % [friend_txt if not _mock else mine, code_friend], ""))
		2:
			grid.add_child(_build_row("У вас:", me_txt, "новее"))
			grid.add_child(_build_row("У друга:", friend_txt, ""))
		_:
			grid.add_child(_build_row("У вас:", me_txt, ""))
			grid.add_child(_build_row("У друга:", friend_txt, "новее"))
	_body.add_child(grid)
	if _alt == 1:
		_body.add_child(_para("Так бывает, если одна из игр поставлена не оттуда же, откуда другая.", _italic(480), 21, INK))
		_body.add_child(_section("Что сделать"))
		_body.add_child(_numbered([
			"Скачайте игру заново — и вы, и друг — с одного и того же сайта, и установите.",
			"Потом подключитесь снова.",
		]))
		return
	_body.add_child(_para("Вместе можно играть только на одной и той же версии. Новую ставит тот, у кого версия старая.",
		_italic(480), 21, INK))
	_body.add_child(_section("Что сделать"))
	if _alt == 2:
		_body.add_child(_numbered([
			tr("У друга старая версия — пусть скачает новую, %s, там же, откуда ставил игру.") % newer_num,
			"Потом друг снова нажмёт «Создать игру» — подключитесь по тому же адресу.",
		]))
	else:
		_body.add_child(_numbered([
			tr("У вас старая версия — скачайте новую, %s, там же, откуда ставили игру, и установите.") % newer_num,
			"Потом подключитесь снова.",
		]))


func _build_row(who: String, build: String, mark: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var a := menu._label(tr(who), _text(600), 24, INK)
	a.custom_minimum_size = Vector2(120, 0)
	row.add_child(a)
	row.add_child(menu._label(build, _text(600), 24, INK))
	if mark != "":
		var m := menu._label(tr(mark), _italic(600), 21, GREEN)
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(m)
	return row


## Справка: три способа по порядку (рядом — Wi-Fi; далеко — Radmin VPN: где скачать, кто создаёт сеть и что
## прислать другу; для знатоков — роутер, у него — «Узнать мой адрес в интернете»), внизу — как открыть игре
## доступ к сети в Windows (одно название везде: ссылки «Как открыть игре доступ к сети?» ведут сюда и отмечают
## этот блок латунной чертой слева и тёплым тоном — _help_fw)
func _body_help() -> void:
	_body.add_child(_numbered([
		"Рядом, в одном Wi-Fi или по проводу, — ничего ставить не нужно. Адрес — из строки «Дома».",
		"Далеко — Radmin VPN: скачайте бесплатную программу с сайта radmin-vpn.com и установите — оба. Один нажимает «Создать сеть» и придумывает имя и пароль — пусть отправит их другу. Другой нажимает «Присоединиться к сети» и вписывает те же имя и пароль. Адрес — из строки «Radmin VPN».",
		_f("Без программ — для знатоков: открыть порт {port} (UDP) на роутере того, кто создаёт игру, и отправить другу адрес в интернете. У многих провайдеров так не выйдет — тогда берите Radmin VPN."),
	], {2: _net_row()}))
	# брандмауэр — совет (вставка без печати: печать у записок о том, что случилось). Путь в настройках — только
	# то, что не зависит от выпуска Windows; в списке игра — «Ордо: Сражение и Город» (описание файла игры)
	var fw := _info_box("Как открыть игре доступ к сети (Windows)", [
		"Отметьте в окне обе галочки и нажмите «Разрешить доступ».",
		"Нажали «Отмена»? Пуск → наберите «разрешение взаимодействия» → «Изменить параметры» → у «Ордо» поставьте обе галочки.",
	], "Это делает тот, кто создаёт игру, — у себя на компьютере.")
	fw.name = "Firewall"
	_body.add_child(fw)
	if _help_fw:
		_mark_box(fw)


## Блок справки, ради которого её открыли ссылкой: латунная черта слева и тёплый тон, тон через миг стихает до
## лёгкого (на кадре — как в первый миг)
func _mark_box(p: Control) -> void:
	var sb := p.get_theme_stylebox("panel") as RuleBox
	if sb == null:
		return
	sb.mark = true
	sb.warm = 1.0
	if _shot:
		return
	var tw := p.create_tween()
	tw.tween_interval(0.6)
	tw.tween_method(_warm_step.bind(p, sb), 1.0, 0.35, 1.4)


func _warm_step(v: float, p: Control, sb: RuleBox) -> void:
	sb.warm = v
	p.queue_redraw()


## Что вышло с адресом в интернете: зелёная — порт открыт (хозяин, который уже ждёт друга, — «отправьте адрес»,
## остальным — сначала «Создать игру»), золотая — адрес есть, а роутер порт сам не открыл
func _net_text() -> String:
	if _net_kind == "gold":
		return "Роутер сам порт не открыл — откройте его в настройках роутера или берите Radmin VPN."
	if _help_from == "host_wait":
		return _f("Адрес нашли, порт {port} открыт — отправьте адрес другу.")
	return _f("Адрес нашли, порт {port} открыт — теперь нажмите «Создать игру» и отправьте адрес другу.")


## «Узнать мой адрес в интернете» (макет: через 1 с выдуманный адрес и «Копировать»; никуда не ходим).
## Что вышло (порт открыт, роутер не открыл или у провайдера так не выйдет) — в записке листа
func _net_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "NetRow"
	row.add_theme_constant_override("separation", 16)
	# одной высоты с кнопкой и с адресом: адрес нашёлся — «Понятно» и низ листа не сдвигаются
	row.custom_minimum_size = Vector2(0, 48)
	_fill_net_row(row)
	return row


func _fill_net_row(row: HBoxContainer) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	if _net_found:
		var shown := ADDR_NET if _mock else _net_addr
		var a := menu._label(shown, _addr_font(), 30, INK)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(a)
		var b := _button("Copy_net", "Копировать", "Copy_net", Vector2(190, 44), 24)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_copy_net.bind(b, shown))
		row.add_child(b)
		return
	var f := _button("Net_find", "Узнать мой адрес в интернете", "Net_find", Vector2(400, 46), 24)
	f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	f.pressed.connect(_on_net_find.bind(f, row))
	row.add_child(f)


## «Узнать мой адрес в интернете»: макет — через 1 с выдуманный; настоящая сеть — роутер (UPnP, порт с арендой) или
## сайт ipify, в отдельном потоке (NetSession.find_external → NetUpnp)
func _on_net_find(b: Button, row: HBoxContainer) -> void:
	b.disabled = true
	b.text = tr("Узнаём…")
	if _mock:
		get_tree().create_timer(1.0).timeout.connect(_net_done.bind(row))
		return
	_session()
	var u := _net.find_external()
	u.finished.connect(_net_result.bind(row), CONNECT_ONE_SHOT)


## Что вышло с адресом в интернете (настоящая сеть): зелёная — адрес и порт открыт; золотая — адрес есть, порт
## роутер не открыл; красная — у провайдера так не выйдет (или не узнать совсем)
func _net_result(res: Dictionary, row: HBoxContainer) -> void:
	if not is_instance_valid(row) or not row.is_inside_tree() or _state != "help":
		return
	var kind := String(res.get("kind", "none"))
	_net_addr = String(res.get("addr", ""))
	_net_found = kind in ["green", "gold"] and _net_addr != ""
	if _net_found:
		_net_kind = kind
		_set_msg(kind, _net_text(), 2)
	elif kind == "red":
		_set_msg("red", "У вашего провайдера так не выйдет — берите Radmin VPN.", 2)
	else:
		_set_msg("red", "Не получилось узнать адрес: нет ответа ни от роутера, ни из интернета. Берите Radmin VPN.", 2)
	_fill_net_row(row)
	_boost_all()
	var b := row.get_node_or_null("Copy_net") as Control
	if b:
		_focus_later.call_deferred(b)


## Адрес «узнан» (макет — всегда удачно, порт открыт) — только если справка ещё открыта (ушли раньше — макет его не
## запоминает); записка — зелёная на месте золотого совета, адрес с «Копировать» — у способа 3
func _net_done(row: HBoxContainer) -> void:
	if not is_instance_valid(row) or not row.is_inside_tree() or _state != "help":
		return
	_net_found = true
	_net_kind = "green"
	_set_msg("green", _net_text(), 2)
	_fill_net_row(row)
	_boost_all()
	var b := row.get_node_or_null("Copy_net") as Control
	if b:
		_focus_later.call_deferred(b)


## Копировать адрес в интернете: «Скопировано» на самой кнопке (записка уже говорит, что делать с адресом)
func _on_copy_net(b: Button, addr: String) -> void:
	DisplayServer.clipboard_set(addr)
	b.text = tr("Скопировано")
	get_tree().create_timer(2.0).timeout.connect(_copy_back.bind(b))


# ================================================================= детали

## Кнопка листа (ореховая из темы): имя узла, текст, подсказка из TIPS, размер, шрифт заголовков. Наведено —
## дерево чуть теплее и светлее (не светлая внутренняя рамка: так выглядела бы главная). В фокусе — рамка снаружи
## доски (FocusRing), и только когда по листу ходят клавишами; текст в фокусе тот же. Недоступная — та же доска,
## потускневшая
func _button(node_name: String, text: String, tip: String, min_size: Vector2, font_size: int) -> Button:
	var b := CityTips.TipButton.new()
	b.name = node_name
	b.text = tr(text)
	b.tooltip_text = _tip(tip)
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", _head())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("hover", _wood(Color(1.22, 1.13, 1.0)))
	b.add_theme_stylebox_override("focus", _focus_ring())
	b.add_theme_stylebox_override("disabled", _dull_board())
	b.add_theme_color_override("font_focus_color", PARCH)
	b.add_theme_color_override("font_disabled_color", Color(PARCH_DIM, 0.6))
	return b


## Ореховая доска кнопки (button_normal), подкрашенная tint: светлее — наведено, темнее — нажато
func _wood(tint: Color) -> StyleBox:
	var sb := menu._box("button_normal", 16.0, Color("#5a3a22"))
	if sb is StyleBoxTexture:
		(sb as StyleBoxTexture).modulate_color = tint
	elif sb is StyleBoxFlat:
		(sb as StyleBoxFlat).bg_color = (sb as StyleBoxFlat).bg_color * tint
	return sb


## Тусклая доска недоступной кнопки: простая ореховая, без латуни главной, латунь рамки и орех темнее — как
## нечищеная латунь
func _dull_board() -> StyleBox:
	var off := menu._box("button_normal", 16.0, Color("#4a3020"))
	if off is StyleBoxTexture:
		(off as StyleBoxTexture).modulate_color = Color(0.62, 0.57, 0.52)
	elif off is StyleBoxFlat:
		var fl := off as StyleBoxFlat
		fl.bg_color = fl.bg_color.darkened(0.35)
		fl.border_color = Color(BRASS_DIM, 0.5)
	return off


## Рамка фокуса (FocusRing): снаружи доски, с зазором, только при ходьбе клавишами (_gate)
func _focus_ring() -> FocusRing:
	var ring := FocusRing.new()
	ring.gate = _gate
	return ring


## Главная кнопка: та же ореховая доска, что у соседней (размер тот же, наружу ничего не выходит), и своя
## латунь — вторая рамка внутри и заклёпки по углам (BrassBoard), текст латунью с обводкой. Наведено — дерево
## светлее, нажато — темнее; недоступна — простая тусклая доска (_dull_board), текст без обводки. Фокус — та же
## рамка снаружи доски, что у соседних кнопок: латунь и заклёпки главной она не закрывает
func _style_main(b: Button) -> void:
	var looks := {"normal": Color.WHITE, "hover": Color(1.2, 1.12, 1.0), "pressed": Color(0.82, 0.78, 0.74)}
	for st: String in looks:
		var bb := BrassBoard.new()
		bb.base = _wood(looks[st])
		bb.bright = st == "hover"
		bb.set_content_margin_all(10)
		b.add_theme_stylebox_override(st, bb)
		if st == "pressed":
			b.add_theme_stylebox_override("hover_pressed", bb)
	b.add_theme_stylebox_override("focus", _focus_ring())
	b.add_theme_stylebox_override("disabled", _dull_board())
	for c in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, BRASS)
	b.add_theme_color_override("font_disabled_color", Color(PARCH_DIM, 0.62))
	b.add_theme_color_override("font_hover_color", Color("#f6dc9c"))
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.85))


## Дощечка выбора (как пункт доски): значок 64, заголовок, подпись курсивом. Заголовок латунью и наконечник —
## только под мышью или в фокусе, когда ходят клавишами (Plate): в покое ни одна дощечка не выглядит выбранной
func _plate(node_name: String, icon: String, head: String, sub: String) -> Button:
	var b := Plate.new()
	b.name = node_name
	b.gate = _gate
	b.tooltip_text = _tip(node_name)
	b.custom_minimum_size = Vector2(0, 96)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# фокус без клавиш ничем не виден (у темы фокус — как наведено: дощечка выглядела бы выбранной)
	b.add_theme_stylebox_override("focus", _focus_ring())
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22.0
	row.offset_right = -18.0
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	if menu._tex(icon) != null:
		row.add_child(_icon(icon, 64.0))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", -2)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)
	b.head = menu._label(tr(head), _head(), 36, PARCH)
	b.head.add_theme_constant_override("outline_size", 4)
	b.head.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.9))
	texts.add_child(b.head)
	texts.add_child(menu._label(tr(sub), _italic(480), 20, PARCH_DIM))
	b.mark = MainMenu.ArrowMark.new()
	b.mark.custom_minimum_size = Vector2(26, 30)
	b.mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mark.visible = false
	b.mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(b.mark)
	return b


## Подпись раздела («Адрес для друга», «Что проверить»)
func _section(text: String) -> Control:
	var l := menu._label(tr(text), _head(), 28, INK)
	l.custom_minimum_size = Vector2(0, 34)
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l


## Строка ожидания: латунная звезда, текст тушью с шагающим многоточием; справа — курсив («Right»: счётчик
## подключения)
func _wait_row(text: String, right: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 42)
	row.add_theme_constant_override("separation", 12)
	row.add_child(_spinner())
	var l := menu._label(_nb(tr(text)) + "…", _text(600), 24, INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1, 0)
	row.add_child(l)
	_dots.append(l)
	_dots_base.append(_nb(tr(text)))
	if right != "":
		var r := menu._label(right, _italic(480), 22, INK_SOFT)
		r.name = "Right"
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(r)
	return row


## Абзац с переносом по словам
func _para(text: String, font: Font, fsize: int, color: Color) -> Label:
	var l := menu._label(_nb(tr(text)), font, fsize, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1, 0)
	return l


## Неразрывные пробелы: тире держится за слово перед ним (строка не начинается с «—»), короткий предлог,
## союз или «не» — за словом после него (не висит в конце строки), частица «же», «ли», «бы» — за словом перед
## ней («та же» не рвётся), короткое название в кавычках («Создать игру», «Radmin VPN») не рвётся на две
## строки, короткое последнее слово абзаца — за предыдущим (одно на строке не остаётся: «…в одну / сеть.»).
## Подсказки (_tip) — тоже, по строкам: CityTips переносит по обычным пробелам
static func _nb(s: String) -> String:
	s = s.replace(" — ", NBSP + "— ")
	for w: String in ["в", "к", "с", "у", "о", "и", "а", "по", "на", "из", "за", "от", "до", "не", "ни", "со", "во", "об"]:
		for v: String in [w, w.substr(0, 1).to_upper() + w.substr(1)]:
			s = s.replace(" " + v + " ", " " + v + NBSP)
	for p: String in ["же", "ли", "бы"]:
		for end: String in [" ", ".", ",", "!", "?", "»", ":"]:
			s = s.replace(" " + p + end, NBSP + p + end)
	var quoted := RegEx.create_from_string("«[^«»]{1,26}»")
	for m in quoted.search_all(s):
		s = s.replace(m.get_string(), m.get_string().replace(" ", NBSP))
	# название программы одной строкой и без кавычек
	s = s.replace("Radmin VPN", "Radmin" + NBSP + "VPN")
	# слово через дефис («по-разному», «Wi-Fi») не рвётся на дефисе: после дефиса — невидимый знак «не разрывать
	# здесь» (U+2060, word joiner)
	s = RegEx.create_from_string("(\\p{L})-(\\p{L})").sub(s, "$1-" + String.chr(0x2060) + "$2", true)
	# хвост — одно короткое слово (не «в бою»: там уже два слова держатся вместе)
	var lines := s.split("\n")
	for i in lines.size():
		var cut := lines[i].rfind(" ")
		var tail := lines[i].substr(cut + 1)
		if cut > 0 and tail.length() <= 12 and not tail.contains(NBSP):
			lines[i] = lines[i].substr(0, cut) + NBSP + tail
	return "\n".join(lines)


## Совет («Как связаться», «Где взять адрес»): не записка, а разлинованная вставка листа — сверху и снизу
## двойная линия тушью, без рваного края, тени и печати (полоска с печатью — только у сообщений, _msg); подпись,
## может быть, строка «кто это делает» (intro) и строки с латунными ромбами
func _info_box(caption: String, lines: Array, intro := "") -> Control:
	var p := PanelContainer.new()
	p.name = "Info"
	var sb := RuleBox.new()
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(menu._label(tr(caption), _head(), 26, INK))
	if intro != "":
		v.add_child(_para(intro, _italic(600), 21, INK))
	v.add_child(_bullets(lines, _italic(480), 21))
	p.add_child(v)
	return p


## Строки с латунным ромбом 8 точек перед каждой (знак рисуется, не из шрифта; колонка ромбов 18)
func _bullets(lines: Array, font: Font, fsize: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	for s: String in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var d := Diamond.new()
		d.custom_minimum_size = Vector2(18, fsize * 1.4)
		d.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(d)
		var l := _para(s, font, fsize, INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		v.add_child(row)
	return v


## Нумерованный список шагов: номера латунью в колонке 32, текст с переносом; extra — {номер строки (с 0):
## узел под её текстом} (кнопка «Узнать мой адрес» у способа 3 справки)
func _numbered(lines: Array, extra := {}) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	for i in lines.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		# номер — цифрами в рост строки (lnum), на одной линии букв с первой строкой текста
		var col := Control.new()
		col.custom_minimum_size = Vector2(32, 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := menu._label(str(i + 1), _num_font(), 26, NUM_INK)
		n.position = Vector2(2, _text(500).get_ascent(21) - _num_font().get_ascent(26))
		col.add_child(n)
		row.add_child(col)
		var l := _para(String(lines[i]), _text(500), 21, INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if extra.has(i):
			var stack := VBoxContainer.new()
			stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stack.add_theme_constant_override("separation", 6)
			stack.add_child(l)
			stack.add_child(extra[i] as Control)
			row.add_child(stack)
		else:
			row.add_child(l)
		v.add_child(row)
	return v


## Ссылка в справку «Как играть по сети»: латунный наконечник (курсор игры) и тушь; при наведении — латунь.
## Надпись — о том, что нужно на этом экране; подсказка — из TIPS по tip; fw — справка откроется с отмеченным
## блоком «Как открыть игре доступ к сети (Windows)»
func _link(text: String, tip := "Online_help", fw := false) -> Button:
	var b := _flat("Online_help", text, _text(600), 22, INK)
	b.tooltip_text = _tip(tip)
	_lit_link(b)
	b.pressed.connect(_to_help.bind(fw))
	return b


## Ссылка-надпись: при наведении и в фокусе текст латунью, наконечник ярче
func _lit_link(b: Button) -> void:
	for c in ["font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, BRASS_DIM)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var arrow := b.get_node_or_null("Arrow") as Arrowhead
	if arrow == null:
		return
	# метод наконечника, а не лямбда: отложенный вызов после смены состояния (узлы уже удалены) просто
	# пропадает, без ошибки «Lambda capture was freed»
	arrow.button = b
	b.mouse_entered.connect(arrow.sync, CONNECT_DEFERRED)
	b.mouse_exited.connect(arrow.sync, CONNECT_DEFERRED)
	b.focus_entered.connect(arrow.sync)
	b.focus_exited.connect(arrow.sync)


## Плоская кнопка-надпись (без доски) с латунным наконечником слева (поле 26), подсказка — записка CityTips
func _flat(node_name: String, text: String, font: Font, fsize: int, color: Color) -> Button:
	var b := CityTips.TipButton.new()
	b.name = node_name
	b.text = tr(text)
	b.tooltip_text = _tip(node_name)
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var empty := StyleBoxEmpty.new()
	empty.content_margin_bottom = 3
	empty.content_margin_left = 26
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fsize)
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, color)
	var a := Arrowhead.new()
	a.name = "Arrow"
	a.anchor_top = 0.5
	a.anchor_bottom = 0.5
	a.offset_left = 0.0
	a.offset_right = 16.0
	a.offset_top = -10.0
	a.offset_bottom = 8.0
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(a)
	return b


## Рамка тушью для карточек листа (адреса, место друга, таблички сторон)
func _ink_box() -> InkBox:
	var sb := InkBox.new()
	sb.set_content_margin_all(12)
	return sb


## Карточка адресов в рамке тушью
func _card(content: Control) -> Control:
	var p := PanelContainer.new()
	p.name = "Addresses"
	p.add_theme_stylebox_override("panel", _ink_box())
	p.add_child(content)
	return p


## Ряд внутри узла на весь его размер, с полями слева/справа
func _row_in(parent: Control, left: float, right: float, sep: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = left
	row.offset_right = -right
	row.add_theme_constant_override("separation", sep)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(row)
	return row


func _icon(tex_name: String, s: float) -> Control:
	var t := TextureRect.new()
	t.texture = menu._tex(tex_name)
	t.custom_minimum_size = Vector2(s, s)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Герб стороны на пергаментном кружке (иначе бирюзовая звезда пропадёт на бирюзе)
func _disc(side: String, s: float) -> Disc:
	var d := Disc.new()
	d.tex = menu._tex("icons/crest_" + side)
	d.custom_minimum_size = Vector2(s, s)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## Полоса пояса стороны (изразцы Коканда / войлок кыпчаков): узор плиткой в свою высоту (не сплющен), тонкая
## кромка тушью сверху и снизу
func _belt(side: String) -> BeltStrip:
	var b := BeltStrip.new()
	b.tex = menu._tex("belt_" + side)
	b.fallback = Color("#2f8f74") if side == "kokand" else Color("#b0392f")
	b.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Латунная звезда ожидания 40; на кадре проверки стоит на месте
func _spinner() -> Control:
	var s := Spinner.new()
	s.still = _shot
	s.custom_minimum_size = Vector2(40, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _head() -> Font:
	return menu._font(MainMenu.FONT_HEAD)


## Текст подсказки по ключу TIPS: перевод, порт ({port}) и неразрывные пробелы (_nb)
func _tip(key: String) -> String:
	var s := String(TIPS.get(key, ""))
	return _nb(_f(tr(s))) if s != "" else ""


## Порт макета в тексте: {port} — PORT (одно место на весь лист)
static func _f(s: String) -> String:
	return s.format({"port": PORT})


## Подсказки над листом — бумажная записка потемнее и потеплее листа: на бумаге листа она не сливается
## (тема на корне макета: подсказка берёт тему от узла, над которым мышь; остальное — из темы меню)
func _tip_theme() -> Theme:
	var th := Theme.new()
	var sb := UiTheme.tip_box().duplicate() as StyleBox
	if sb is StyleBoxTexture:
		(sb as StyleBoxTexture).modulate_color = Color(0.9, 0.82, 0.7)
	elif sb is StyleBoxFlat:
		(sb as StyleBoxFlat).bg_color = (sb as StyleBoxFlat).bg_color.darkened(0.12)
	th.set_stylebox("panel", "TooltipPanel", sb)
	return th


## Текст и курсив листа — с цифрами в рост строки (lnum): адреса, сборки и номер партии читаются ровно
## («0.1.57», а не старинными цифрами Alegreya)
func _text(weight := 500) -> Font:
	return _lining(MainMenu.FONT_TEXT, weight)


func _italic(weight := 480) -> Font:
	return _lining(MainMenu.FONT_ITALIC, weight)


## Номера списков: шрифт заголовков, но цифры в рост строки — у Cormorant они по умолчанию «старинные»
func _num_font() -> Font:
	return _lining(MainMenu.FONT_HEAD, 0)


## Шрифт адресов: Alegreya полужирная, цифры прямые и одной ширины (lnum, tnum) — столбцы не пляшут
func _addr_font() -> Font:
	return _lining(MainMenu.FONT_TEXT, 700, true)


## Шрифт файла path толщины weight (0 — как есть) с цифрами в рост строки; tabular — ещё и одной ширины
func _lining(path: String, weight: int, tabular := false) -> Font:
	var key := "%s@%d@%s" % [path, weight, tabular]
	if _fonts.has(key):
		return _fonts[key]
	var ts := TextServerManager.get_primary_interface()
	var fv := FontVariation.new()
	fv.base_font = menu._font(path)
	if weight > 0:
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	var feats := {ts.name_to_tag("lnum"): 1}
	if tabular:
		feats[ts.name_to_tag("tnum")] = 1
	fv.opentype_features = feats
	_fonts[key] = fv
	_font_key[fv] = [path, weight, tabular]
	return fv


## Мелкое окно (_small): мелкие строки курсивом (подписи строк адресов, «уже 0:42», пункты советов, номер
## партии, версия под кнопками) — толщиной 600 вместо тонких 450–500, на точку крупнее, бледная тушь — тушью.
## Крупное окно — как были. Зовут после сборки тела и при смене мелкого / крупного окна
func _boost_all() -> void:
	if _col == null:
		return
	for n in _col.find_children("*", "Label", true, false):
		_boost(n as Label)


func _boost(l: Label) -> void:
	if not l.has_meta("orig"):
		var f := l.get_theme_font("font")
		if not _font_key.has(f) or String(_font_key[f][0]) != MainMenu.FONT_ITALIC:
			return
		var fs := l.get_theme_font_size("font_size")
		if fs > 22:
			return
		l.set_meta("orig", [f, fs, l.get_theme_color("font_color")])
	var o: Array = l.get_meta("orig")
	var key: Array = _font_key[o[0]]
	var c: Color = o[2]
	if _small:
		l.add_theme_font_override("font", _lining(key[0], maxi(int(key[1]), 600), key[2]))
		l.add_theme_font_size_override("font_size", int(o[1]) + 1)
		l.add_theme_color_override("font_color", INK if c.is_equal_approx(INK_SOFT) else c)
	else:
		l.add_theme_font_override("font", o[0])
		l.add_theme_font_size_override("font_size", o[1])
		l.add_theme_color_override("font_color", c)


# ================================================================= рисованные мелочи

## Записка листа: подсказка — записка CityTips (у «Вы подключились…» — про связь)
class MsgNote extends PanelContainer:
	func _make_custom_tooltip(for_text: String) -> Object:
		return CityTips.panel(for_text)


## Поле ввода: подсказка-записка CityTips и свой образец курсивом (у LineEdit образец тем же шрифтом,
## что вписанный адрес, — его легко принять за уже вписанный)
class TipLine extends LineEdit:
	var hint: Label

	func _make_custom_tooltip(for_text: String) -> Object:
		return CityTips.panel(for_text)

	func sync_hint() -> void:
		if hint:
			hint.visible = text == ""


## Поле адреса — бумажная полоска: латунные уголки (как оковка на углах шкатулки) и черта тушью под строкой.
## В фокусе черта латунью и толще, уголки ярче; неверный адрес — черта красными чернилами, волной, как
## подчёркнуто от руки; dim — поле не поправить (подключаемся): уголки и черта блёклые
class SlipDeco extends Control:
	var err := false
	var dim := false
	var field: Control

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var on := field != null and field.has_focus()
		var y := h - 14.0
		var fade := 0.45 if dim else 1.0
		if err:
			var pts := PackedVector2Array()
			var x := 18.0
			while x <= w - 18.0:
				pts.append(Vector2(x, y + sin(x * 0.19) * 1.6))
				x += 3.0
			draw_polyline(pts, RED, 2.8, true)
		elif on:
			draw_line(Vector2(18.0, y), Vector2(w - 18.0, y), Color("#7d5c26"), 2.6, true)
		else:
			draw_line(Vector2(18.0, y), Vector2(w - 18.0, y), Color(0.24, 0.15, 0.08, 0.7 * fade), 1.6, true)
		var brass := Color("#e2bf72") if on else Color("#c9a25a")
		var edge := Color(0.16, 0.08, 0.02, 0.9)
		if dim:
			brass = Color(brass.lerp(Color("#cdbb94"), 0.5), fade)
			edge.a *= fade
		var cap := 16.0
		var t := 4.0
		for cx in 2:
			for cy in 2:
				var o := Vector2(0.0 if cx == 0 else w, 0.0 if cy == 0 else h)
				var s := Vector2(1.0 if cx == 0 else -1.0, 1.0 if cy == 0 else -1.0)
				var poly := PackedVector2Array([o, o + Vector2(cap, 0) * s, o + Vector2(cap, t) * s,
					o + Vector2(t, t) * s, o + Vector2(t, cap) * s, o + Vector2(0, cap) * s])
				draw_colored_polygon(poly, brass)
				poly.append(poly[0])
				draw_polyline(poly, edge, 1.0, true)
				# гвоздик оковки
				draw_circle(o + Vector2(t + 3.0, t + 3.0) * s, 1.6, edge)


## Рамка тушью карточек листа: бумага чуть светлее листа и двойная линия — толстая снаружи, тонкая внутри,
## как рамка на документе (не серая фаска)
class InkBox extends StyleBox:
	var fill := Color(0.97, 0.92, 0.8, 0.5)
	var ink := Color(0.24, 0.15, 0.08, 0.9)

	func _draw(to: RID, rect: Rect2) -> void:
		RenderingServer.canvas_item_add_rect(to, rect, fill)
		_frame(to, rect, ink, 2.0)
		_frame(to, rect.grow(-5.0), Color(ink, 0.5), 1.0)

	static func _frame(to: RID, r: Rect2, c: Color, w: float) -> void:
		RenderingServer.canvas_item_add_rect(to, Rect2(r.position, Vector2(r.size.x, w)), c)
		RenderingServer.canvas_item_add_rect(to, Rect2(Vector2(r.position.x, r.end.y - w), Vector2(r.size.x, w)), c)
		RenderingServer.canvas_item_add_rect(to, Rect2(Vector2(r.position.x, r.position.y + w), Vector2(w, r.size.y - w * 2.0)), c)
		RenderingServer.canvas_item_add_rect(to, Rect2(Vector2(r.end.x - w, r.position.y + w), Vector2(w, r.size.y - w * 2.0)), c)


## Герб на кружке: пергамент, ободок тушью 2 точки
class Disc extends Control:
	var tex: Texture2D

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		draw_circle(c, r - 1.0, Color("#f0dfb8"))
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color("#2b1a10"), 2.0, true)
		if tex:
			var k := r * 1.62
			draw_texture_rect(tex, Rect2(c - Vector2(k, k) * 0.5, Vector2(k, k)), false)


## Полоса пояса: картинка плиткой в высоту полосы (узор не сплющен), без картинки — цвет стороны; кромка тушью
## сверху и снизу
class BeltStrip extends Control:
	var tex: Texture2D
	var fallback := Color.WHITE

	func _draw() -> void:
		if tex == null:
			draw_rect(Rect2(Vector2.ZERO, size), fallback)
		else:
			var th := float(tex.get_height())
			var k := size.y / th
			var tw := tex.get_width() * k
			var x := 0.0
			while x < size.x - 0.01:
				var w := minf(tw, size.x - x)
				draw_texture_rect_region(tex, Rect2(x, 0.0, w, size.y), Rect2(0.0, 0.0, w / k, th))
				x += tw
		var ink := Color(0.17, 0.1, 0.05, 0.85)
		draw_line(Vector2(0.0, 0.5), Vector2(size.x, 0.5), ink, 1.0)
		draw_line(Vector2(0.0, size.y - 0.5), Vector2(size.x, size.y - 0.5), ink, 1.0)


## Ожидание: латунная звезда о восьми лучах медленно поворачивается (оборот за 12 с), грани лучей — светлая
## и тёмная, как у литой звезды; still — стоит (кадр проверки)
class Spinner extends Control:
	var t := 0.0
	var still := false

	func _process(delta: float) -> void:
		if still:
			return
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var a0 := 0.2 + t * TAU / 12.0
		var pts := PackedVector2Array()
		for i in 16:
			var a := a0 + TAU * float(i) / 16.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.48))
		var lit := Color("#ecd08c")
		var dark := Color("#a8864a")
		for i in 8:
			var tip: Vector2 = pts[i * 2]
			draw_colored_polygon(PackedVector2Array([c, pts[(i * 2 + 15) % 16], tip]), lit)
			draw_colored_polygon(PackedVector2Array([c, tip, pts[i * 2 + 1]]), dark)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0.16, 0.08, 0.02, 0.9), 1.4, true)
		draw_circle(c, r * 0.17, Color("#7d5c26"))
		draw_arc(c, r * 0.17, 0.0, TAU, 16, Color(0.16, 0.08, 0.02, 0.9), 1.2, true)


## Место друга: пусто — блёклая бумажка с рваным краем тушью; друг вошёл — карточка в рамке тушью (ink),
## как адреса и таблички сторон
class SlotBox extends Control:
	var filled := false
	var ink: StyleBox

	func _draw() -> void:
		if filled and ink:
			draw_style_box(ink, Rect2(Vector2.ZERO, size))
			return
		var pts := _torn(Rect2(Vector2(3.0, 3.0), size - Vector2(6.0, 6.0)))
		draw_colored_polygon(pts, Color(0.97, 0.93, 0.82, 0.42))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.35, 0.25, 0.16, 0.6), 1.4, true)

	## Рваный край: точка через ~8 по контуру, каждая сдвинута поперёк края на ±2 (одинаково в каждом кадре)
	static func _torn(r: Rect2) -> PackedVector2Array:
		var out := PackedVector2Array()
		var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var k := 0
		for side in 4:
			var a: Vector2 = corners[side]
			var b: Vector2 = corners[(side + 1) % 4]
			var n := maxi(2, int(a.distance_to(b) / 8.0))
			var step := (b - a) / float(n)
			var nrm := Vector2(-step.y, step.x).normalized()
			for i in n:
				k += 1
				var j := fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0) * 2.0 - 1.0
				out.append(a + step * float(i) + nrm * j * 2.0)
		return out


## Латунный ромб 8 точек (точка списка)
class Diamond extends Control:
	func _draw() -> void:
		var c := Vector2(minf(size.x * 0.5, 9.0), minf(size.y * 0.5, 15.0))
		var pts := PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)])
		draw_colored_polygon(pts, Color("#c9a25a"))
		pts.append(pts[0])
		draw_polyline(pts, Color("#5a4028"), 1.2, true)


## Латунный наконечник остриём вправо (к надписи ссылки) — курсор интерфейса игры; bright — наведено
class Arrowhead extends Control:
	var bright := false
	var button: BaseButton

	## Ярче, пока над ссылкой мышь или на ней фокус
	func sync() -> void:
		if is_instance_valid(button):
			bright = button.is_hovered() or button.has_focus()
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var tip := Vector2(w - 1.0, h * 0.5)
		var pts := PackedVector2Array([tip, Vector2(1.0, 2.0), Vector2(w * 0.38, h * 0.5), Vector2(1.0, h - 2.0)])
		draw_colored_polygon(pts, Color("#e2bf72") if bright else Color("#c9a25a"))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.16, 0.08, 0.02, 0.9), 1.4, true)


## Ходит ли игрок по листу клавишами или геймпадом (тогда видна рамка фокуса и подсвечена дощечка в фокусе);
## мышь — нет. Один на лист; changed — включили или выключили
class KbdGate extends RefCounted:
	signal changed
	var on := false:
		set(v):
			if v != on:
				on = v
				changed.emit()


## Рамка фокуса кнопок листа: рисуется, только пока ходят клавишами (gate.on). Снаружи доски, с зазором 3
## точки: тушь — светлая латунь 2 — тушь (на бумаге листа видна, от наведения — светлее дерево — отличается
## сразу; латунь и заклёпки главной кнопки не закрывает); или своя рамка box (половины переключателя стороны)
class FocusRing extends StyleBox:
	var gate: KbdGate
	var box: StyleBox

	func _draw(to: RID, rect: Rect2) -> void:
		if gate == null or not gate.on:
			return
		if box:
			box.draw(to, rect)
			return
		var r := rect.grow(7.0)
		var ink := Color(0.16, 0.08, 0.02, 0.92)
		InkBox._frame(to, r, ink, 1.0)
		InkBox._frame(to, r.grow(-1.0), Color("#f2d488"), 2.0)
		InkBox._frame(to, r.grow(-3.0), ink, 1.0)


## Дощечка выбора («Создать игру», «Подключиться»): заголовок латунью и наконечник — только под мышью или в
## фокусе, когда ходят клавишами (gate); в покое ни одна не выглядит выбранной. Мышь навели — фокус сюда же
## (клавиши пойдут отсюда)
class Plate extends CityTips.TipButton:
	var gate: KbdGate
	var head: Label
	var mark: Control

	func _ready() -> void:
		mouse_entered.connect(grab_focus)
		mouse_entered.connect(sync, CONNECT_DEFERRED)
		mouse_exited.connect(sync, CONNECT_DEFERRED)
		focus_entered.connect(sync)
		focus_exited.connect(sync)
		if gate:
			gate.changed.connect(sync)
		sync()

	func sync() -> void:
		var on := is_hovered() or (has_focus() and gate != null and gate.on)
		if mark:
			mark.visible = on
		if head:
			head.add_theme_color_override("font_color", MainMenu.BRASS if on else MainMenu.PARCH)


## Доска главной кнопки: ореховая base (как у соседних) и своя латунь — вторая рамка светлой латунью внутри
## и четыре заклёпки на её углах; bright — наведено (латунь ещё светлее)
class BrassBoard extends StyleBox:
	var base: StyleBox
	var bright := false

	func _draw(to: RID, rect: Rect2) -> void:
		if base:
			base.draw(to, rect)
		var r := rect.grow(-6.0)
		var brass := Color("#f0d48e") if bright else Color("#e2bf72")
		var dark := Color(0.12, 0.06, 0.02, 0.85)
		# тёмная кромка под латунью — рамка читается и на светлом волокне ореха
		InkBox._frame(to, r.grow(1.0), dark, 1.0)
		InkBox._frame(to, r, brass, 2.0)
		InkBox._frame(to, r.grow(-2.0), dark, 1.0)
		for p: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var c := p + (r.get_center() - p).sign() * 1.0
			RenderingServer.canvas_item_add_circle(to, c, 4.4, dark)
			RenderingServer.canvas_item_add_circle(to, c, 3.4, brass)
			RenderingServer.canvas_item_add_circle(to, c + Vector2(-1.0, -1.0), 1.3, Color("#fff1c9"))


## Разлинованная вставка совета: сверху и снизу двойная линия тушью (толстая снаружи, тонкая внутри), по
## бумаге — чуть заметный тон, без рамки по бокам, рваного края и тени (это не записка). mark — ради этой вставки
## открыли справку: латунная черта слева (как закладка) и тон теплее (warm — от 0 до 1)
class RuleBox extends StyleBox:
	var ink := Color(0.24, 0.15, 0.08, 0.8)
	var mark := false
	var warm := 0.0

	func _draw(to: RID, rect: Rect2) -> void:
		var x := rect.position.x
		var w := rect.size.x
		var tone := Color(0.55, 0.38, 0.18, 0.06).lerp(Color(0.86, 0.6, 0.2, 0.22), warm)
		RenderingServer.canvas_item_add_rect(to, Rect2(x, rect.position.y + 5.0, w, rect.size.y - 10.0), tone)
		if mark:
			var bar := Rect2(x - 12.0, rect.position.y + 8.0, 5.0, rect.size.y - 16.0)
			RenderingServer.canvas_item_add_rect(to, bar.grow(1.0), Color(0.16, 0.08, 0.02, 0.9))
			RenderingServer.canvas_item_add_rect(to, bar, Color("#d9b062"))
		RenderingServer.canvas_item_add_rect(to, Rect2(x, rect.position.y, w, 2.0), ink)
		RenderingServer.canvas_item_add_rect(to, Rect2(x, rect.position.y + 4.0, w, 1.0), Color(ink, 0.45))
		RenderingServer.canvas_item_add_rect(to, Rect2(x, rect.end.y - 5.0, w, 1.0), Color(ink, 0.45))
		RenderingServer.canvas_item_add_rect(to, Rect2(x, rect.end.y - 2.0, w, 2.0), ink)


## Заливка половины переключателя стороны: крашеная бумага. Выбранная — цвет стороны, другая — орех
## (наведено — орех светлее); сверху светлее, снизу темнее; волокна бумаги («paper») сквозь краску. Скругление —
## только снаружи (левая половина — слева, правая — справа), внутри латунной рамки 2 точки
class SidePaint extends Control:
	var button: BaseButton
	var left := true
	var color_on := Color.WHITE
	var fibre: Texture2D

	func _draw() -> void:
		var on := button != null and button.button_pressed
		var base := color_on if on else (Color("#5a3a22") if button != null and button.is_hovered() else Color("#3a2414"))
		# волокна бумаги светлые (~0,9): краску чуть ярче, чтобы цвет стороны не потемнел
		var k := 1.12 if fibre else 1.0
		var top := base.lightened(0.12) * k
		var bottom := base.darkened(0.2) * k
		top.a = 1.0
		bottom.a = 1.0
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var rad := 8.0
		var pts := PackedVector2Array()
		if left:
			pts.append(Vector2(r.end.x, r.position.y))
			pts.append(r.end)
			pts.append_array(_arc(Vector2(r.position.x + rad, r.end.y - rad), rad, PI * 0.5, PI))
			pts.append_array(_arc(Vector2(r.position.x + rad, r.position.y + rad), rad, PI, PI * 1.5))
		else:
			pts.append(r.position)
			pts.append_array(_arc(Vector2(r.end.x - rad, r.position.y + rad), rad, PI * 1.5, TAU))
			pts.append_array(_arc(Vector2(r.end.x - rad, r.end.y - rad), rad, 0.0, PI * 0.5))
			pts.append(Vector2(r.position.x, r.end.y))
		var cols := PackedColorArray()
		var uvs := PackedVector2Array()
		# у каждой половины свой кусок листа бумаги: волокна не повторяются один в один
		var off := Vector2(40.0 if left else 300.0, 120.0)
		var ts := Vector2(fibre.get_size()) if fibre else Vector2.ONE
		for p in pts:
			cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
			uvs.append((p + off) / ts)
		draw_polygon(pts, cols, uvs if fibre else PackedVector2Array(), fibre)

	static func _arc(c: Vector2, rad: float, a0: float, a1: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 7:
			var a := lerpf(a0, a1, float(i) / 6.0)
			pts.append(c + Vector2(cos(a), sin(a)) * rad)
		return pts
