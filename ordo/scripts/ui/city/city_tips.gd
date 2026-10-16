class_name CityTips
extends RefCounted
## Подсказки кнопок «Города» (просьба автора 2026-10-15: «на каждую кнопку описание, особенно для стройки
## и для воинов»). Текст собирается из тех же таблиц, что и игра (Defs, UnitStats): цена, время, население,
## что даёт постройка и что нужно для неё, здоровье, броня, атака, стрельба — чисел в коде нет. Сильные и
## слабые стороны воина выводятся из тех же полей (натиск, копья против конницы, щиты, дальность, броня).
## Чего в игре ещё нет (качып атуу, режим огня, гарнизоны, запруда — заглушки этапа 2 в CombatPortBattle и
## RtsInput.dam_button), подсказка честно помечает «в следующих сборках», а не обещает.
##
## Запись подсказки: первая строка — заголовок, дальше — строки; «! …» — почему сейчас нельзя (идёт сразу под
## заголовком), «+ …» — сильная сторона, «− …» — слабая, «~ …» — пояснение (что это, как пользоваться).
## Кнопка TipButton рисует запись бумажной запиской (panel): заголовок — шрифтом заголовков, «+» зелёным,
## «−» и «!» красным полужирным, «~» курсивом; длинные строки переносятся по ширине MAX_W (точки раскладки —
## масштаб интерфейса увеличивает записку вместе со всем, край экрана Godot не даёт переступить).

## Ширина записки (точки раскладки): длиннее — перенос по словам
const MAX_W := 430.0
const TITLE_SIZE := 21
const TEXT_SIZE := 17
const PLUS := Color("#24501c")
const MINUS := Color("#7a2416")
const WHY := Color("#a3261b")
## Отступ продолжения перенесённой строки «+» / «−» (под текст после знака)
const HANG := "   "

## Пороги сильных и слабых сторон (поля UnitStats)
const CHARGE_STRONG := 1.8      # натиск с разгона: сильный
const CHARGE_CRUSH := 2.5       # сокрушительный
const RANGE_FAR := 100          # дальний бой, м
const ARMOUR_HEAVY := 6
const ARMOUR_LIGHT := 1
const SPEED_FAST := 8.0         # м/с
const SPEED_SLOW := 3.0
const MELEE_WEAK := 10          # атака стрелка в рукопашной ниже — слаб
const RELOAD_LONG := 6.0        # с

## Строи (BattleSim.Formation) и стойки (BattleSim.Stance) — по порядку перебора кнопкой
const FORMS := ["линия", "колонна", "каре", "рассыпной"]
const STANCES := ["напор", "оборона", "стоять", "не отвечать"]

## Что делает приказ (SimCmd.Op): строка под заголовком; клавиша и доступность — из GameQuery.orders_for.
## Строй и стойку дописывает order() из FORMS / STANCES
const ORDER_TEXT := {
	SimCmd.Op.MOVE: "Идти в точку: кнопка, затем ЛКМ по земле (или сразу ПКМ по земле).",
	SimCmd.Op.STOP: "Остановиться и ждать на месте.",
	SimCmd.Op.ATTACK_MOVE: "Идти в точку, вступая в бой со всеми врагами по пути. ПКМ по врагу — сразу атаковать его.",
	SimCmd.Op.FORMATION: "Сменить строй отряда по кругу:",
	SimCmd.Op.STANCE: "Как встречать врага, по кругу:",
	SimCmd.Op.KACHYP: "«Качып атуу»: конные лучники стреляют на отходе и не дают себя догнать.",
	SimCmd.Op.FIRE_MODE: "Переключить: стрелять издалека или идти в рукопашную.",
	SimCmd.Op.WAR_CRY: "Полководец кличем поднимает боевой дух бойцов рядом.",
	SimCmd.Op.FORM_SQUAD: "Собрать выбранных бойцов в отряд под началом офицера.",
	SimCmd.Op.DISBAND: "Распустить отряд: бойцы станут одиночками.",
	SimCmd.Op.GATHER: "Добывать: ПКМ по лесу, жиле, полю или своему стаду.",
	SimCmd.Op.BUILD: "Открыть вкладку «Хозяйство» и выбрать постройку.",
	SimCmd.Op.ASSIST: "Помогать строить: ПКМ по своей стройке.",
	SimCmd.Op.UNPACK: "Развернуть арбу: наведите мышь на место и нажмите K.",
	SimCmd.Op.RALLY: "Куда идут нанятые здесь: ПКМ по земле.",
	SimCmd.Op.PACK: "Свернуть постройку в арбу для переезда (көч).",
	SimCmd.Op.PACK_ALL: "Свернуть в арбы весь лагерь.",
	SimCmd.Op.SET_RECIPE: "Сменить, что делает мастерская.",
	SimCmd.Op.SET_DAM: "Открыть или закрыть воду запруды.",
	SimCmd.Op.TRADE: "Обмен — кнопками «Продать» и «Купить» в панели базара.",
	SimCmd.Op.UNGARRISON: "Вывести бойцов со стен и башен.",
	SimCmd.Op.DEMOLISH: "Снести здание сразу, без вопроса. За готовое ничего не вернут, за стройку — часть цены.",
	SimCmd.Op.HERD_MOVE: "Перегнать стадо: кнопка, затем ЛКМ по карте.",
}
## Приказы, которых в игре ещё нет (заглушки этапа 2): кнопка есть, подсказка честно говорит
const NOT_YET := [SimCmd.Op.KACHYP, SimCmd.Op.FIRE_MODE, SimCmd.Op.UNGARRISON, SimCmd.Op.SET_DAM]
## Почему приказ недоступен (условия GameQueryImpl.orders_for)
const ORDER_WHY := {
	SimCmd.Op.FORMATION: "Строй — только у отряда (собрать отряд: U)",
	SimCmd.Op.FORM_SQUAD: "Нужен офицер среди выбранных",
	SimCmd.Op.DEMOLISH: "Ставку снести нельзя",
	SimCmd.Op.UNGARRISON: "В гарнизоне никого",
	SimCmd.Op.RALLY: "Здесь никого не нанимают",
	SimCmd.Op.KACHYP: "Нет конных лучников среди выбранных",
	SimCmd.Op.FIRE_MODE: "Нет стрелков среди выбранных",
	SimCmd.Op.WAR_CRY: "Нет полководца среди выбранных",
}


# ================================================================= постройка

## Подсказка кнопки стройки (вкладки «Хозяйство», «Укрепления») и медальона здания: что это, цена и время,
## что даёт, что нужно; why — почему сейчас нельзя, cost — цена из GameQuery.build_menu (пусто — из Defs)
static func building(defs: Defs, bt: int, hotkey := "", why := "", cost := PackedInt32Array()) -> String:
	if bt < 0 or bt >= defs.b_name.size():
		return ""
	var t := PackedStringArray()
	t.append(_tr(defs.b_name[bt]) + ((" (%s)" % hotkey) if hotkey != "" else ""))
	if why != "":
		t.append("! " + why)
	var kind := _building_kind(defs, bt)
	if kind != "":
		t.append("~ " + kind)
	var price_txt := UiTheme.cost_text(defs, cost) if not cost.is_empty() else _cost_of(defs, defs.b_cost, bt)
	var price := PackedStringArray()
	if price_txt != "":
		var step := defs.b_link_len[bt] - defs.b_link_overlap[bt]
		price.append((_tr("Цена за звено (%s м): %s") % [_num(step), price_txt]) if step > 0.0 else (_tr("Цена: %s") % price_txt))
	if defs.b_build_ticks[bt] > 0:
		price.append(_tr("стройка %s с одним работником") % _sec(defs.b_build_ticks[bt]))
	if not price.is_empty():
		t.append(" · ".join(price))
	t.append_array(_building_gives(defs, bt))
	if why == "":
		t.append_array(_building_needs(defs, bt))
	else:
		# требование уже сказано строкой «!» — здесь только место
		for s in _building_needs(defs, bt):
			if not s.begins_with(_tr("Сначала постройте")):
				t.append(s)
	var sz := defs.b_size[bt]
	var tail := _tr("Размер %d×%d м") % [roundi(sz.x), roundi(sz.y)]
	if defs.b_hp_c[bt] > 0:
		tail += " · " + _tr("прочность %d") % roundi(defs.b_hp_c[bt] / 100.0)
	t.append(tail)
	return "\n".join(t)


## Что это за постройка — по её виду и флагам (имена построек — местные: Уй, Дала, Тегирмон)
static func _building_kind(defs: Defs, bt: int) -> String:
	var f := defs.b_flags[bt]
	match defs.b_kind[bt]:
		Defs.BKind.FIELD:
			return _tr("Поле")
		Defs.BKind.WALL:
			return _tr("Стена: держит врага. Ставится линией: ЛКМ по точкам, ПКМ — конец")
		Defs.BKind.GATE:
			return _tr("Ворота в стене: свои проходят, чужие — нет")
		Defs.BKind.TOWER:
			return _tr("Башня")
		Defs.BKind.LINK:
			return _tr("Канал: ставится линией, как стена")
		Defs.BKind.DAM:
			return _tr("Запруда на реке: даёт воду")
	if f & Defs.BF_HQ:
		return _tr("Ставка — сердце стороны: падёт — партия проиграна")
	if f & Defs.BF_HOUSE:
		return _tr("Жильё")
	if f & Defs.BF_MARKET:
		return _tr("Базар: обмен ресурсов на золото")
	if f & Defs.BF_PEN:
		return _tr("Загон для скота")
	if not defs.b_recipes[bt].is_empty():
		return _tr("Мастерская")
	if f & Defs.BF_DROP:
		return _tr("Склад")
	if not defs.b_trains[bt].is_empty():
		return _tr("Здесь нанимают войско")
	return ""


## Что постройка даёт — по таблице (населению, складу, работе, рецептам, стаду, найму, воде…)
static func _building_gives(defs: Defs, bt: int) -> PackedStringArray:
	var t := PackedStringArray()
	var side := defs.b_faction[bt]
	if defs.b_pop_cap[bt] > 0:
		t.append("+ " + _tr("Население: +%d") % defs.b_pop_cap[bt])
	if defs.b_accepts[bt] != 0:
		var acc := _res_list(defs, defs.b_accepts[bt], side)
		if acc != "":
			# мастерская хранит то, что делает; склад принимает от работников
			var what := "Хранит: %s" if not defs.b_recipes[bt].is_empty() else "Принимает: %s"
			t.append("+ " + _tr(what) % acc)
	var wk: Dictionary = defs.b_work[bt]
	if int(wk.get("slots", 0)) > 0 and int(wk.get("res", -1)) >= 0:
		t.append("+ " + _tr("Работников: до %d, каждый — %s %s в минуту") % [int(wk["slots"]),
			_tr(defs.r_name[int(wk["res"])]).to_lower(), _num(int(wk.get("per_worker_min_milli", 0)) / 1000.0)])
	for y: Dictionary in defs.b_yield[bt]:
		if bool(y.get("enabled", true)) and String(y.get("field", "")) == "water" and float(y.get("mul", 1.0)) < 1.0:
			t.append("− " + _tr("Без воды урожай ×%s") % _num(float(y["mul"])))
	for rc in defs.b_recipes[bt]:
		if defs.rc_enabled[rc] == 0:
			continue
		t.append("+ " + _tr("Работники (до %d): %s → %s за %s с каждый") % [defs.rc_workers[rc],
			_cost_of(defs, defs.rc_in, rc), _cost_of(defs, defs.rc_out, rc), _sec(defs.rc_ticks[rc])])
	if defs.b_herd[bt] >= 0 and defs.b_herd_cap[bt] > 0:
		var h := defs.b_herd[bt]
		var s := _tr("Стадо: %s, до %d голов") % [_tr(defs.h_name[h]).to_lower(), defs.b_herd_cap[bt]]
		if defs.b_herd_start[bt] > 0:
			s += _tr(" (сразу %d)") % defs.b_herd_start[bt]
		if defs.b_herd_breed[bt] != 0:
			s += _tr(", с приплодом")
		t.append("+ " + s)
		var per_head := PackedStringArray()
		for r in defs.R:
			var y := defs.h_yield[h * defs.R + r] if h * defs.R + r < defs.h_yield.size() else 0
			if y > 0 and _side_has(defs, side, r):
				per_head.append("%s %s" % [_tr(defs.r_name[r]).to_lower(), _num(y / 1000.0)])
		if not per_head.is_empty():
			t.append("+ " + _tr("С головы в минуту: %s") % " · ".join(per_head))
	if not defs.b_trains[bt].is_empty():
		var names := PackedStringArray()
		for u in defs.b_trains[bt]:
			if defs.u_enabled[u] != 0:
				names.append(_tr(defs.u_name[u]))
		if not names.is_empty():
			t.append("+ " + _tr("Нанимает: %s") % ", ".join(names))
	if defs.b_gar_cap[bt] > 0:
		t.append("~ " + _tr("Гарнизон до %d бойцов — в следующих сборках") % defs.b_gar_cap[bt])
	var net: Dictionary = defs.b_network[bt]
	if bool(net.get("source", false)) and int(net.get("places", 0)) > 0:
		t.append("+ " + _tr("Мест у воды: %d — на все поля и мастерские") % int(net["places"]))
	elif net.has("zone"):
		t.append("+ " + _tr("Несёт воду от Тўғона: поля и мастерские до %s м от него поливаются") % _num(float(net["zone"])))
	var au: Dictionary = defs.b_aura[bt]
	if float(au.get("gather_mult", 1.0)) > 1.0:
		var res := _res_list(defs, int(au.get("res_mask", 0)), side)
		if res != "":
			t.append("+ " + _tr("Рядом (%s м) добыча быстрее ×%s: %s") % [_num(float(au.get("r", 0.0))),
				_num(float(au["gather_mult"])), res])
	if defs.b_tax_milli_min[bt] > 0:
		t.append("+ " + _tr("Подать: %s золота в минуту, пока есть Бозор") % _num(defs.b_tax_milli_min[bt] / 1000.0))
	if defs.b_shelter[bt] > 0:
		t.append("+ " + _tr("По тревоге укрывает работников: %d") % defs.b_shelter[bt])
	if defs.b_flags[bt] & Defs.BF_TERRITORY and defs.b_territory_r[bt] > 0.0:
		t.append("+ " + _tr("Своя земля вокруг: %s м") % _num(defs.b_territory_r[bt]))
	var ab: Dictionary = defs.b_ability[bt]
	if not ab.is_empty():
		t.append("+ " + _tr("Умение «%s» (V)") % RtsInput.ability_name(ab))
	if defs.b_flags[bt] & Defs.BF_PACKABLE:
		t.append("+ " + _tr("Сворачивается в арбу для переезда (көч)"))
	return t


## Что нужно, чтобы поставить: постройки раньше, место (у жилы, у воды, на стене), предел
static func _building_needs(defs: Defs, bt: int) -> PackedStringArray:
	var t := PackedStringArray()
	var req := PackedStringArray()
	for b in defs.b_requires[bt]:
		req.append(_tr(defs.b_name[b]))
	if not req.is_empty():
		t.append(_tr("Сначала постройте: %s") % ", ".join(req))
	var pl: Dictionary = defs.b_place[bt]
	if pl.has("near"):
		var near: Dictionary = pl["near"]
		var nodes := PackedStringArray()
		for n in near.get("nodes", PackedInt32Array()):
			nodes.append(_tr(defs.n_name[n]).to_lower())
		t.append(_tr("Ставить рядом (до %s м): %s") % [_num(float(near.get("r", 0.0))), ", ".join(nodes)])
	if bool(pl.get("water_zone", false)):
		t.append(_tr("Ставить там, где есть вода (у арыка)"))
	if bool(pl.get("across_river", false)):
		t.append(_tr("Ставить поперёк реки"))
	match String(pl.get("on_wall", "")):
		"align":
			t.append(_tr("Ставится на линию стены"))
		"replace":
			t.append(_tr("Встаёт в стену вместо её звена"))
	if not bool(pl.get("territory", true)):
		t.append(_tr("Можно и вне своей земли"))
	if defs.b_max_per_player[bt] > 0:
		t.append(_tr("Не больше %d на сторону") % defs.b_max_per_player[bt])
	return t


## Умение здания (Ҳашар у Урды): действие, длительность, перезарядка — из Defs.b_ability
static func ability(ab: Dictionary) -> String:
	if ab.is_empty():
		return ""
	var t := PackedStringArray([RtsInput.ability_name(ab) + " (V)"])
	var fx := PackedStringArray()
	if ab.has("build_mult"):
		fx.append(_tr("стройка и ремонт ×%s") % _num(float(ab["build_mult"])))
	if ab.has("repair_cost_mult"):
		fx.append(_tr("ремонт дешевле ×%s") % _num(float(ab["repair_cost_mult"])))
	if ab.has("worker_attack") or ab.has("worker_armour"):
		fx.append(_tr("работники бьются: атака %d, броня %d") % [int(ab.get("worker_attack", 0)), int(ab.get("worker_armour", 0))])
	if not fx.is_empty():
		t.append("+ " + _tr("На %d с: %s") % [int(ab.get("duration_s", 0)), ", ".join(fx)])
	if int(ab.get("cooldown_s", 0)) > 0:
		t.append(_tr("Снова — через %d с") % int(ab["cooldown_s"]))
	return "\n".join(t)


# ================================================================= воин

## Подсказка найма, карточки и портрета воина: кто это, цена, время, население и содержание, что нужно,
## здоровье, броня, атака, скорость, стрельба, сильные и слабые стороны (по полям UnitStats); why — почему
## сейчас нельзя нанять; cost — цена из GameQuery.building_panel (пусто — из Defs); with_cost false — без цены
static func unit(defs: Defs, ut: int, why := "", with_cost := true, cost := PackedInt32Array()) -> String:
	if ut < 0 or ut >= defs.unit_ids.size():
		return ""
	var id := String(defs.unit_ids[ut])
	var st := UnitStats.get_stats(id)
	var t := PackedStringArray()
	var role := String(st.get("role", ""))
	t.append(_tr(defs.u_name[ut]) + ((" — " + _tr(role)) if role != "" else ""))
	if why != "":
		t.append("! " + why)
	if with_cost:
		var price := PackedStringArray()
		var price_txt := UiTheme.cost_text(defs, cost) if not cost.is_empty() else _cost_of(defs, defs.u_cost, ut)
		if price_txt != "":
			price.append(_tr("Цена: %s") % price_txt)
		if defs.u_train_ticks[ut] > 0:
			price.append(_tr("найм %s с") % _sec(defs.u_train_ticks[ut]))
		if not price.is_empty():
			t.append(" · ".join(price))
		var keep := PackedStringArray()
		if defs.u_pop[ut] > 0:
			keep.append(_tr("население %d") % defs.u_pop[ut])
		if defs.u_upkeep_milli_min[ut] > 0:
			keep.append(_tr("содержание %s еды в минуту") % _num(defs.u_upkeep_milli_min[ut] / 1000.0))
		if not keep.is_empty():
			t.append(_cap(" · ".join(keep)))
		var req := PackedStringArray()
		for b in defs.u_requires[ut]:
			req.append(_tr(defs.b_name[b]))
		if not req.is_empty():
			t.append(_tr("Нужны постройки: %s") % ", ".join(req))
		if defs.u_unique[ut] != 0:
			var one := _tr("Один на сторону")
			if defs.u_respawn_ticks[ut] > 0:
				one += _tr("; после гибели — снова через %s с") % _sec(defs.u_respawn_ticks[ut])
			t.append("~ " + one)
	if st.is_empty():
		return "\n".join(t)
	t.append(_tr("Здоровье %d · броня %d · атака %d · скорость %s м/с") % [int(st.get("hp", 0)), int(st.get("armour", 0)),
		int(st.get("attack", 0)), _num(float(st.get("speed", 0.0)))])
	if UnitStats.has_flag(id, UnitStats.WORKER):
		var got := PackedStringArray()
		for r in defs.R:
			var g := defs.u_gather[ut * defs.R + r] if ut * defs.R + r < defs.u_gather.size() else 0
			if g > 0 and defs.r_enabled[r] != 0 and _side_has(defs, defs.u_faction[ut], r):
				got.append("%s %s" % [_tr(defs.r_name[r]).to_lower(), _num(g * 60.0 / 1000.0)])
		if not got.is_empty():
			t.append(_tr("Добыча в минуту: %s") % " · ".join(got))
	if int(st.get("missile", 0)) > 0:
		var shot := _tr("Стрельба: урон %d, дальность %d м, перезарядка %s с") % [int(st["missile"]), int(st.get("range", 0)),
			_num(float(st.get("reload", 0.0)))]
		if int(st.get("ammo", -1)) > 0:
			shot += _tr(", запас %d") % int(st["ammo"])
		t.append(shot)
	for s in strengths(id):
		t.append("+ " + s)
	for s in weaknesses(id):
		t.append("− " + s)
	return "\n".join(t)


## Сильные стороны воина — из полей UnitStats (без чисел в коде); слова годятся и для одного, и для отряда
static func strengths(id: String) -> PackedStringArray:
	var st := UnitStats.get_stats(id)
	var f := int(st.get("flags", 0))
	var t := PackedStringArray()
	if f & UnitStats.WAGON:
		t.append(_tr("Везёт свёрнутую постройку: на месте — K, развернуть"))
		return t
	if f & UnitStats.WORKER:
		t.append(_tr("Стройка, добыча, переноска в склад"))
	if f & UnitStats.GENERAL:
		t.append(_tr("Полководец: боевой дух рядом выше, боевой клич (V)"))
	elif f & UnitStats.OFFICER:
		t.append(_tr("Ведёт отряд до %d бойцов") % int(st.get("squad_max", 0)))
	if float(st.get("vs_cav", 1.0)) > 1.0:
		t.append(_tr("Копья: держат натиск, по коннице урон ×%s") % _num(float(st["vs_cav"])))
	var charge := float(st.get("charge", 1.0))
	if charge >= CHARGE_CRUSH:
		t.append(_tr("Сокрушительный натиск с разгона ×%s") % _num(charge))
	elif charge >= CHARGE_STRONG:
		t.append(_tr("Сильный натиск с разгона ×%s") % _num(charge))
	if f & UnitStats.SHIELD:
		t.append(_tr("Щит: урон от стрел вдвое меньше"))
	if int(st.get("missile", 0)) > 0 and int(st.get("range", 0)) >= RANGE_FAR:
		t.append(_tr("Дальний бой"))
	if f & UnitStats.MUSKET:
		t.append(_tr("Пули пробивают броню и могут свалить коня"))
	if float(st.get("vs_building", 0.0)) >= 1.0:
		t.append(_tr("Урон по постройкам и стенам ×%s") % _num(float(st["vs_building"])))
	if f & UnitStats.RAIDER:
		t.append(_tr("Налёты: бьют прежде всего работников"))
	if int(st.get("armour", 0)) >= ARMOUR_HEAVY:
		t.append(_tr("Тяжёлая броня"))
	if float(st.get("speed", 0.0)) >= SPEED_FAST:
		t.append(_tr("Очень высокая скорость"))
	return t


## Слабые стороны воина — из тех же полей
static func weaknesses(id: String) -> PackedStringArray:
	var st := UnitStats.get_stats(id)
	var f := int(st.get("flags", 0))
	var t := PackedStringArray()
	if f & UnitStats.WAGON:
		t.append(_tr("В пути беззащитна — нужна охрана"))
		return t
	if f & UnitStats.WORKER:
		t.append(_tr("В бою почти бесполезен"))
		return t
	if f & UnitStats.MOUNTED:
		t.append(_tr("Как всякая конница — уязвимость к копьям"))
	if f & UnitStats.CANNON:
		t.append(_tr("Медлительность; вблизи без защиты"))
	elif f & (UnitStats.BOW | UnitStats.MUSKET) and int(st.get("attack", 0)) < MELEE_WEAK:
		t.append(_tr("Слабость в рукопашной"))
	if f & UnitStats.MUSKET and float(st.get("reload", 0.0)) >= RELOAD_LONG:
		t.append(_tr("Долгая перезарядка"))
	if int(st.get("armour", 0)) <= ARMOUR_LIGHT and f & UnitStats.CANNON == 0:
		t.append(_tr("Лёгкая защита — опасны стрелы"))
	if float(st.get("speed", 0.0)) < SPEED_SLOW and f & UnitStats.CANNON == 0:
		t.append(_tr("Низкая скорость"))
	if f & UnitStats.OFFICER and f & UnitStats.GENERAL == 0:
		t.append(_tr("Гибель офицера — удар по духу отряда"))
	return t


# ================================================================= приказ

## Подсказка кнопки приказа: «Строй (F)», почему нельзя (если нельзя), что делает, «в следующих сборках»
static func order(op: int, label: String, key: String, enabled := true) -> String:
	var t := PackedStringArray()
	t.append(_tr(label) + ((" (%s)" % key) if key != "" else ""))
	if not enabled:
		t.append("! " + _tr(String(ORDER_WHY.get(op, "Сейчас нельзя"))))
	var what := _tr(String(ORDER_TEXT.get(op, "")))
	if op == SimCmd.Op.FORMATION:
		what += " " + " → ".join(FORMS) + "."
	elif op == SimCmd.Op.STANCE:
		what += " " + " → ".join(STANCES) + "."
	if what != "":
		t.append(what)
	if op in NOT_YET:
		t.append("~ " + _tr("Пока не работает — появится в следующих сборках"))
	return "\n".join(t)


# ================================================================= записка

## Кнопка с подсказкой-запиской (заголовок, строки «!», «+», «−», «~» — каждая своим видом)
class TipButton extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		return CityTips.panel(for_text)


## Карточка (9-срез) с той же запиской — карточки выбранных воинов
class TipNine extends NinePatchRect:
	func _make_custom_tooltip(for_text: String) -> Object:
		return CityTips.panel(for_text)


## Содержимое записки по тексту подсказки (Godot кладёт его в TooltipPanel темы — бумажную записку)
static func panel(text: String) -> Control:
	if text.strip_edges() == "":
		return null
	var lines := text.split("\n")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var head := UiTheme.head_bold()
	var title := _line(_wrap(lines[0], head, TITLE_SIZE, ""), head, TITLE_SIZE, UiTheme.INK)
	title.name = "Title"
	box.add_child(title)
	if lines.size() > 1:
		var rule := ColorRect.new()
		rule.color = Color(UiTheme.INK, 0.3)
		rule.custom_minimum_size = Vector2(0, 1)
		box.add_child(rule)
	for i in range(1, lines.size()):
		var s := lines[i]
		var font := UiTheme.text(500)
		var col := UiTheme.INK
		var hang := ""
		if s.begins_with("+ "):
			col = PLUS
			font = UiTheme.text(600)
			hang = HANG
		elif s.begins_with("− "):
			col = MINUS
			font = UiTheme.text(600)
			hang = HANG
		elif s.begins_with("! "):
			col = WHY
			font = UiTheme.text(700)
			s = s.substr(2)
		elif s.begins_with("~ "):
			col = UiTheme.INK_SOFT
			font = UiTheme.italic(500)
			s = s.substr(2)
		box.add_child(_line(_wrap(s, font, TEXT_SIZE, hang), font, TEXT_SIZE, col))
	return box


static func _line(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.add_theme_constant_override("line_spacing", -2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Перенос по словам до MAX_W (шрифт font размера size); продолжение строки — с отступом hang
static func _wrap(s: String, font: Font, size: int, hang: String) -> String:
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= MAX_W:
		return s
	var out := PackedStringArray()
	var cur := ""
	for w in s.split(" "):
		var next := w if cur == "" else cur + " " + w
		if cur != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > MAX_W:
			out.append(cur)
			cur = hang + w
		else:
			cur = next
	if cur != "":
		out.append(cur)
	return "\n".join(out)


# ================================================================= мелочи

## Цена «дерево 80 · камень 20» по строке таблицы arr[i * R + r] (милли)
static func _cost_of(defs: Defs, arr: PackedInt32Array, i: int) -> String:
	var c := PackedInt32Array()
	c.resize(defs.R)
	for r in defs.R:
		if i * defs.R + r < arr.size():
			c[r] = arr[i * defs.R + r]
	return UiTheme.cost_text(defs, c)


## Ресурсы по маске (1 << r) — только те, что есть у стороны side
static func _res_list(defs: Defs, mask: int, side: String) -> String:
	var out := PackedStringArray()
	for r in defs.R:
		if mask & (1 << r) and defs.r_enabled[r] != 0 and _side_has(defs, side, r):
			out.append(_tr(defs.r_name[r]).to_lower())
	return ", ".join(out)


## Ресурс есть у стороны (её балка, FactionDefs.ui_res): у кыпчаков нет камня; сторона не задана — есть
static func _side_has(defs: Defs, faction: String, r: int) -> bool:
	var f := defs.f_ids.find(faction)
	return f < 0 or defs.f_ui_res[f].has(r)


## Секунды из тактов (Defs.TICKS_PER_S)
static func _sec(ticks: int) -> String:
	return _num(float(ticks) / Defs.TICKS_PER_S)


## Число без лишних нулей, до сотых: 3.4 → «3,4», 0.25 → «0,25», 25.0 → «25»
static func _num(v: float) -> String:
	var s := String.num(snappedf(v, 0.01), 2)
	if s.contains("."):
		s = s.rstrip("0").trim_suffix(".")
	return s.replace(".", ",")


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s


static func _tr(s: String) -> String:
	return TranslationServer.translate(s)
