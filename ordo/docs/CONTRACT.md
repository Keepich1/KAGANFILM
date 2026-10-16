# Ордо — договор для разработки среза стиля

Этот документ — общие правила для всех, кто пишет код и делает ресурсы среза
(этап 0 ТЗ: «лагерь кыпчаков на закате и столкновение двух отрядов»).
Главный документ — [TZ.md](TZ.md); здесь только технические соглашения.

## 1. Движок и запуск

- **Godot 4.7.2**, рендер Forward+ (ПК, «Высокое» качество), Mobile — для телефонов («Низкое»).
- Проект: папка `ordo/`, файл `project.godot`. Открыть в Godot → F5.
- Без монитора (сервер, облако): `tools/godot.sh` (Xvfb + программный Vulkan).
  - `tools/import.sh` — импорт новых glb/png (создаёт `.godot/`, в git не идёт);
  - `tools/shot.sh res://scenes/X.tscn out.png --at=6 --cam=Имя --size=1920x1080` — кадр;
  - `tools/movie.sh res://scenes/X.tscn out.mp4 20 --size=1280x720` — видео
    (для среза: `… 25 --size=1280x720 --movie --battle_skip=0.5` — без подсказок, бой с 0,5 с).
  - Время сцены идёт ровно 1/30 с за кадр (`--fixed-fps 30`), кадры повторяемы.
- Windows (ПК автора, видеокарта): кадр — `tools\shot.cmd` с теми же ключами, что у `shot.sh`
  (PowerShell, Git Bash не нужен); в Git Bash работают и `tools/*.sh`, `tests/run_all.sh`. Godot — `GODOT`, `C:\Godot`
  или файл в `C:\` (путь знает `tools/godot.sh --which`). `movie.sh` нужен ffmpeg, генераторам — Python; `build_windows.sh` — облако.
  Отпечатки `test_combat_slice` сняты на Linux: на Windows 2 из 5 расходятся (другая математика Godot), ворота среза — облако.
  Кадр не больше экрана (больше — `shot.cmd` сообщает об ошибке); пыль и дым от запуска к запуску чуть разные.
- Автозагрузка `Ordo` (`scripts/core/ordo.gd`): качество `Ordo.quality` (`high`/`low`),
  аргументы командной строки `Ordo.arg("имя")`, зерно `Ordo.seed`, время суток `Ordo.light_mode`
  (`day` — по умолчанию / `sunset`; `Ordo.set_light_mode()`, сигнал `light_mode_changed`, ключ `--light=`),
  масштаб интерфейса `Ordo.ui_scale` (0,75–1,5; `Ordo.set_ui_scale()`, сигнал `ui_scale_changed`, ключ `--ui_scale=75..150`).
  Множитель холста окна (`Window.content_scale_factor`) ставит только `Ordo`; сцене для мелких окон —
  `Ordo.set_ui_boost(func(окно, раскладка) -> float)` (так делает `CityHud`). Холст бывает от 1280×720 (150 %)
  до 2560×1440 (75 %): интерфейс раскладывается по `get_viewport_rect()`, а не по 1920×1080.

## 2. Единицы и оси

- Метры, Y вверх. **+X — восток, −Z — север.** Модели смотрят фасадом в +Z (ТЗ 11.6).
- Начало координат модели — центр основания на уровне земли.
- Симуляция боя: фиксированный шаг **1/30 с**, детерминирована (без `randf()` — только
  свой генератор с зерном), отделена от графики (ТЗ 14).

## 3. Раскладка карты среза

Кусок долины 1024 × 1024 м, центр в (0, 0, 0). Предгорья Тянь-Шаня, степь.

| Что | Где (x, z), м | Примечание |
|---|---|---|
| Лагерь кыпчаков | центр ставки (−60, 20) | Хан ордосу + 8–10 боз үй кольцом радиусом 30–45 м |
| Короо (загон с отарой) | (−115, 65) | отара пасётся и вокруг |
| Жылкы короосу (кони) | (−25, 90) | |
| Древко с трезубцем | у входа в ставку | вымпел с волнистым краем |
| Поле боя | центр (90, 0), ±80 м | ровный луг, лёгкий уклон, без деревьев и камней |
| Река с бродом | дугой на севере, z ≈ −160…−220 | рощи тополей и ив по берегам |
| Горы | по краям карты, снежные вершины на севере и северо-западе | дальний фон — рисованные слои |

**Солнце** — по времени суток (решение автора 2026-10-14, `scripts/world/light_presets.gd`):
«День» (по умолчанию) — юго-юго-запад, ~48°, почти белый чуть тёплый свет, голубое заполнение неба;
«Закат» — запад-юго-запад, 10°, тёплый ключевой свет, холодное сине-бирюзовое заполнение, контровой свет.
В обоих земля темнее и спокойнее юнитов (ТЗ 11.2).

## 4. Общий живописный свет

- Все непрозрачные шейдеры подключают `shaders/include/painterly.gdshaderinc`
  (граница света ломается мазком, тёплая полоса на терминаторе, цветная тень, контровой свет).
- Общие параметры — глобальные uniform `ordo_*` в `project.godot` (раздел `[shader_globals]`).
  Тон картинки настраивается там, а не в каждом шейдере. Значения ставит мир по времени суток
  (`LightPresets`, `World.apply_light`) при запуске и при смене режима; в `project.godot` — значения заката
  (тестовые сцены со своим низким солнцем). Свет, небо, туман и ordo_* обоих режимов — только в `LightPresets`.
- `ordo_wind` (vec4): xy — куда дует ветер в мировых x/z (не откуда), z — сила (толпа умножает
  на 6 м/с), w — порывистость. `ordo_sun_dir` (vec3) — единичный вектор НА солнце (ставит мир).
  Процессорным эффектам (дым, частицы) те же значения отдаёт автозагрузка: `Ordo.wind`,
  `Ordo.sun_dir`; менять ветер — `Ordo.set_wind(v)` (шейдеры и процессор видят одно и то же).
- `ordo_clouds` (vec4) — тени облаков на земле (сила, масштаб 1/м, снос м/с). Во всех `light()`
  вместо `ATTENUATION` пишите `PAINT_ATTEN` (так делают `PAINT_LIGHT` и `CROWD_LIGHT`) — тогда тени
  облаков ложатся одинаково на землю, траву, деревья, юрты и юнитов.
- `paint_diffuse_soft(..., soft_mul)` — тот же живописный свет с более мягкой границей (юниты).
- Скрипты, которые могут работать в безголовых тестах (`godot --script`), берут автозагрузку
  по пути: `get_node_or_null("/root/Ordo")` — по имени `Ordo` её там не видно.
- `shaders/painterly_surface.gdshader` и `painterly_cutout.gdshader` — готовые материалы.
  `Painterly.apply(node)` переводит материалы импортированного glb в живописные.

## 5. Рисованные текстуры

- Только процедурно: `tools/paint.py` (класс `Canvas`: подмалёвок, мазки, линии «от руки»,
  орнамент: `ram_horn` — «кочкор мүйүз», `rhomb`). Одна «рука» для всех текстур.
- Палитра — `tools/palette.py` (цвета сторон из ТЗ 2.1/2.2, земля, материалы, свет).
- Свет и тень частично нарисованы в цвете (градиенты, затемнение низа, светлые кромки),
  без фотошума и «пластика».
- Размеры: до 2048 на ПК, 512–1024 для телефонов (главные здания до 1024). Один материал
  на объект, лучше общий атлас на сторону (ТЗ 11.5).

## 6. Модели (glb)

- Генерация кодом: `tools/meshkit.py` (примитивы) + `tools/glb.py` (запись .glb с текстурой).
- Формат ТЗ 11.6. Нижние грани и интерьер не нужны. Размеры в плане — по таблице ТЗ 11.6.
- Бюджеты треугольников — ТЗ 11.5; проверка: `python3 tools/check_budgets.py`.
- У каждой модели облегчённая версия `<имя>_lod1.glb` (~40–55% треугольников).
  В сцене: `visibility_range_end` у LOD0, `visibility_range_begin` у LOD1.
- Имена файлов зданий — как в ТЗ 11.6 (`boz`, `ordo`, `koroo`, `jylky`, …).
- Юниты: `assets/models/units/kip_*.glb`, `kok_*.glb`, животные `sheep.glb`, `horse.glb`.

## 7. Толпа: юниты на видеокарте

- Каждый вид юнита — один `MultiMeshInstance3D` (инстансинг), анимация в вершинном шейдере
  `shaders/crowd.gdshader`. Без скелетов на процессоре. Цель — 1000+ солдат (ТЗ 11.5).
- Меш юнита собран из жёстких частей. **UV2.x — номер части** (кость), UV2.y — запас.
  Точки вращения частей — константы в шейдере (один скелет на вид: человек, конь+всадник, овца).
- Данные экземпляра `INSTANCE_CUSTOM` и состояния анимаций — `scripts/units/anim_spec.gd`
  (`AnimSpec`). Это договор симуляции и шейдера: меняйте его только вместе.
- Цвет стороны занимает 20–30% силуэта (плащ, попона, знамя) и узнаётся с любого зума (ТЗ 11.2).

## 7а. Сборка среза

`scenes/slice.tscn` (`scripts/slice.gd`) — главная сцена: `Cameras` (кадры Cam*), `World`
(`scenes/world/world.tscn`: земля, небо, солнце, туман, трава, деревья, река, живописный фильтр —
единственные WorldEnvironment и DirectionalLight3D), `Camp` (`scenes/camp/camp.tscn` в корне без
сдвига, сам встаёт на `Terrain.height_at`) и `Battle` (`scenes/battle/battle.tscn`). Бой берёт свет
из мира (первый DirectionalLight3D), метки лагеря — по именам (SheepPen, HorsePen, WorkSpot_*,
GuardPost_*), толпу — из `scripts/units/crowd_layer.gd`. Свои небо и солнце тестовых сцен
(stand-in) в срез не идут. Серия кадров: `-- --hero=9.8@CamVolley,14.3@CamImpact --hero_out=DIR`.

## 8. Владельцы папок

Чтобы параллельная работа не сталкивалась, у каждой области свои папки.
Общие файлы (`project.godot` с InputMap, `scripts/core/*`, `shaders/include/painterly.gdshaderinc`,
`shaders/painterly_*.gdshader`, `tools/{meshkit,glb,paint,palette,check_budgets}.py`,
`scripts/units/anim_spec.gd`, `docs/*`) меняет только ведущий; нужна правка — опишите её в отчёте.
Договор «Города» (§10) — тоже только ведущий: `scripts/contract/*`, схема `scripts/data/*` (значения —
владельцы ниже), `scripts/world/scatter_data.gd`, `tests/sim_harness.gd`, `tests/run_all.sh`,
`tests/test_contract.gd`, `assets/ui/fonts/`.

| Область | Папки и файлы |
|---|---|
| Лагерь | `tools/gen_camp*.py`, `assets/models/kipchak/`, `assets/textures/kipchak/`, `shaders/cloth.gdshader`, `scripts/camp/`, `scenes/camp/`, `scenes/test/camp_*` |
| Юниты | `tools/gen_units*.py`, `assets/models/units/`, `assets/textures/units/`, `shaders/crowd.gdshader`, `shaders/include/crowd_*.gdshaderinc`, `scripts/units/` (кроме anim_spec.gd), `scenes/test/units_*` |
| Мир | `tools/gen_world*.py`, `assets/world/`, `assets/textures/world/`, `assets/models/world/`, `shaders/{terrain,grass,sky,water}.gdshader`, `shaders/post/`, `scripts/world/`, `scenes/world/`, `scenes/test/world_*` |
| Бой = CORE (ядро боя) | `scripts/battle/` (sim.gd, unit_stats.gd, combat_port_battle.gd, scenario_clash.gd, sim_driver.gd), `scripts/fx/`, `scripts/camera/` (кроме согласованной правки UI в rts_camera.gd), `scripts/ui/` (кроме `scripts/ui/city/`), `shaders/fx/`, `assets/textures/fx/`, `tools/gen_fx*.py`, `scenes/battle/`, `scenes/test/battle_*`, `tests/test_sim.gd`, `tests/test_view.gd`, `tests/test_combat_*.gd`, позже `native/ordo_core/` |
| Сборка | `scenes/slice.tscn`, `scripts/slice.gd`, `scripts/stress_scenario.gd`, `export_presets.cfg`, `docs/shots/` |
| NAV (навигация) | `scripts/nav/*`, `tests/test_nav*.gd`, `tests/test_placement.gd`, `tests/test_wall_tool.gd` |
| ECON (экономика) | `scripts/econ/*`; значения `scripts/data/{unit_econ,resource_defs,building_defs,node_defs,herd_defs,recipe_defs,faction_defs,modifier_defs}.gd` и ключей экономики в `game_rules.gd`; `tests/test_econ_*.gd`, `tests/test_defs.gd` (после M0) |
| GAME (игра) | `scripts/game/*`, `scripts/game/ai/*`; значения `scripts/data/{ai_defs,map_valley}.gd` и остальных ключей `game_rules.gd`; `tests/test_game_*.gd`, `tests/test_orders.gd`, `tests/test_raid.gd`, `tests/test_replay.gd`, `tests/test_perf_city.gd`, `tools/skirmish_headless.sh` |
| VIEW (вид) | `scripts/view/*`, `shaders/view/*`, `scenes/gorod/*`, `scenes/test/gorod_*`, `tests/test_unit_view.gd`, `tests/test_building_view.gd`; согласованные правки (подпись ведущего): `scripts/world/world_scatter.gd` (`hide_tree`, карта деревьев), `scripts/world/grass_field.gd` + `shaders/grass.gdshader` (`set_mask`) |
| UI (интерфейс) | `scripts/ui/city/*`, `scripts/input/*`, `assets/ui/*` (кроме `assets/ui/fonts/`), `tools/gen_ui*.py`, `tests/test_input.gd`, `tests/test_ui_bind.gd`; согласованная правка: `scripts/camera/rts_camera.gd` (`presets_enabled`, край экрана над HUD) |

`scripts/world/scatter_data.gd` лежит в папке Мира, но это файл договора (ведущий).

Кадры проверки — в `renders/<область>/` (в git не идут).

## 9. Код

- GDScript 4 со статической типизацией, комментарии и строки интерфейса — по-русски.
- Генераторы на Python 3 + numpy + Pillow, детерминированы (seed), запускаются из `ordo/`:
  `python3 tools/gen_camp.py` и т. п. Результат (glb/png) коммитится, чтобы проект открывался
  без Python.
- Файлы `.import` коммитятся, папка `.godot/` — нет.

## 10. «Город» — симуляция

Итоговая схема — [ARCHITECTURE.md](ARCHITECTURE.md); здесь правила, обязательные для всех пакетов
(CORE, NAV, ECON, GAME, VIEW, UI). Договорные классы — `scripts/contract/*` (меняет только ведущий).

### 10.1 Слои и такт

- `BattleSim` (`scripts/battle/sim.gd`) — единственный владелец всего, что ходит, бьётся и гибнет
  (солдаты, офицеры, полководцы, работники, арбы). Над ним: **NAV** (`NavApi`: сетка 4 м, пути,
  расстановка), **ECON** (`EconApi` и четыре таблицы), **GAME** (`GameSim`: такт, приказы, ИИ, победа).
  Ядро никогда не зовёт наверх: данные входят методами, буферы `ev_*` забираются.
- Такт `GameSim.step()` — 1/30 с, порядок фиксирован (ARCHITECTURE §5.1): приказы такта → ИИ →
  `econ.pre_step` → `port.on_nav_changed` (если сменилась `nav.version`) → `nav.service` →
  `port.deliver_paths` → `port.step` → `econ.post_step(смерти, попадания, прибытия)` → раз в 30 тактов
  `econ.slow_step`, на 75-м из каждых 150 `econ.fields_step` → `victory.check` → контрольная сумма раз в 30 тактов.

### 10.2 Правила симуляции

1. **Код симуляции — только `RefCounted`:** `sim.gd`, `scripts/{nav,econ}/*`, `scripts/game/*` (кроме
   `game_driver.gd`), `scripts/contract/*`. Никаких Node, `Ordo`, `randf`/`randi`, `Time`, `OS`, физики.
   Читать можно `Terrain` (статично), `UnitStats`, `Defs`.
2. **Случайность — `BattleRng`, своя у каждого модуля:** ядро — `battle.rng` (как было);
   ECON — зерно `seed * 0x9E37 + 1`; ИИ игрока p — `seed * 0x9E37 + 100 + p`; NAV — без случайности.
3. **Порядок обхода:** массивы — по индексу. Dictionary обходить только при детерминированном порядке
   вставки; ключами никогда не делать Object.
4. **Бюджеты — счётом, не временем** (запросы путей, клетки, работники за такт).
5. **Слой правил (ECON, GAME, ИИ, решения NAV) — целые числа:** ресурсы — милли (1 еда = 1000),
   HP построек — санти (× 100), таймеры — такты, потоки «в минуту» — через остатки (`rate_acc`).
   Расстояния сравнивать по квадратам; `sin/cos/atan2/exp/pow` — только в ядре.
6. **Приказы — единственный вход.** Интерфейс и ИИ делают `SimCmd`; приказ исполняется на такте
   `tick + input_delay` (1 в одиночной игре). Пауза и скорость — локальны.
7. **Контрольная сумма** раз в 30 тактов: `battle.checksum()`, `econ.checksum()`, `nav.checksum()`,
   Σ `ai.checksum()`, состояния генераторов.
8. **Детерминизм сейчас — «тот же исполняемый файл»** (повторы, тесты, баланс). Межплатформенный —
   с `BattleCore`/`NavCore` (этап мультиплеера).
9. **Владение данными:** массивы ядра пишет только `sim.gd` (снаружи — только через `CombatPort`);
   четыре таблицы (`PlayerTable`, `BuildingTable`, `NodeTable`, `HerdTable`) пишет только ECON.
   Читатели берут массивы **в локальные переменные в начале функции и никогда не хранят их в полях**
   (граница C++: иначе каждая запись ядра копирует массив).
10. **Сигналы ядра — только для эффектов** (`BattleFx` через `SimDriver`): кто их слушает, не меняет
    состояние симуляции. Состояние идёт только через буферы ядра и `SimEvents`.
11. **Новое в ядре по умолчанию = срез:** `victory_mode = BATTLE`, `flee_mode = DIR`, `corpse_steps = −1`,
    без структур и сеток. `test_sim` (та же контрольная сумма), `test_view`, `test_defs` и кадры среза —
    ворота каждого слияния в `scripts/battle/`.

### 10.3 Описатели (`Ids`)

32 бита: `kind << 28 | (gen & 0xFFF) << 16 | slot` — вид (`UNIT 1, SQUAD 2, BUILDING 3, NODE 4, HERD 5`),
поколение 1..4095, слот 0..65535. `Ids.NULL = 0` — «ничего»; у живого описателя поколение ≥ 1.
Проверяет владелец хранилища: `gen[slot] == Ids.gen(h)` и слот занят (ядро — юниты и отряды, ECON —
здания, узлы, стада; у таблиц — `valid(h)`). Приказ с устаревшим описателем → `CMD_REJECTED` с причиной
`STALE`; интерфейс выбрасывает такие из выделения (`SelectionModel.prune`) при каждом обновлении.
Одиночка (нанятый по одному) — отряд из одного: описатель юнита в приказе означает его отряд.

### 10.4 Приказы (`SimCmd`)

- Раскладка `PackedInt32Array [op, player, tick, seq, n, id_0 … id_{n−1}, args…]`; заголовок
  `H_OP=0, H_PLAYER=1, H_TICK=2, H_SEQ=3, H_N=4, H_IDS=5`. Игрока, такт и номер ставит `CommandQueue`.
- **ids — свои** сущности игрока (Orders проверяет: действительны и принадлежат ему); **описатели в args**
  (цель атаки, источник добычи, цель сбора) могут быть чужими — только действительными.
- Позиции — сантиметры (`SimCmd.cm`), углы — миллирадианы (`SimCmd.mrad`), `NO_ANGLE = 0x7FFFFFFF` — NAN.
  Номера юнитов, построек, рецептов, ресурсов — индексы `Defs`.
- Аргументы каждого `Op` — в шапке `scripts/contract/sim_cmd.gd`. Приказы делать только конструкторами
  `SimCmd.*`; читать — `SimCmd.ids/arg/arg_pos/arg_angle/wall_points`.
- `Orders.apply`: `validate_shape` → игрок жив → каждый id действителен и свой → правила → обработчик
  (`CombatPort.*` — бой, `EconApi.*` — хозяйство; работники в боевом приказе сперва уходят с работы через
  `EconApi.release_units`). Отказ обработчика (`−EconApi.Err` или `−(100 + NavApi.Why)`) →
  `CMD_REJECTED(player, op, причина)`, интерфейс показывает красную записку.
- `Op.SPAWN` — только игрокам `PlayerTable.Ctrl.AI` при `rules.ai_free_waves`.
- Повтор = зерно + карта + `Defs.hash()` + правила + журнал приказов (`SimCmd.encode/decode`).

### 10.5 События (`SimEvents`)

Кольцо на `CAP = 8192` событий: `push(kind, player, a, b, c, pos)`; читатель держит свой курсор
(`range_since(cursor)` → `[from, to)`, `at(seq)` → индекс в `e_*`) и не теряет события при нескольких
тактах за кадр. События — только выход: не входят в контрольную сумму и не сохраняются. Пишут ECON и
GAME. Полезная нагрузка `a/b/c` каждого `Ev` — в шапке `scripts/contract/sim_events.gd` (сущности —
описатели; `LOOT`, `RES_DELIVERED` — ресурс + милли; `CMD_REJECTED` — op + причина + seq;
`RAID_WARNING` — ETA в тактах).

### 10.6 Данные (`Defs`, `scripts/data/*`)

- Данные — классы GDScript с константными словарями (`UnitEcon.UNITS`, `BuildingDefs.BUILDINGS`, …);
  схему заморозил ведущий (лишний ключ — ошибка `Defs.validate()`), значения — владельцы из §8.
  Боевые числа юнитов — `UnitStats` (CORE); экономика юнитов — `UnitEcon` (ECON); `UnitStats.cost/time` —
  старое зеркало, `test_defs` их сверяет.
- `Defs.shared()` — общий экземпляр; тесты правят числа через `Defs.build({раздел: {id: {ключ: …}}})`.
  Порядок записей в файлах = индексы: **новые записи — только в конец раздела**.
- Числа — ТЗ с правками docs/ECONOMY.md (где цифры расходятся, верны ECONOMY.md). Записи без
  окончательных чисел и из следующих сборок (Сб. 2+: кийиз, сезоны и зоны, кузницы) стоят с
  `"enabled": false` (индекс занят, меню и верхняя балка их не показывают). Глина и шерсть — не запасы
  (ECONOMY §1.2), их индексы ресурсов оставлены по ARCHITECTURE §6.4 и выключены.
- Скомпилированные единицы: милли, санти-HP, такты, `raid_value` — десятые доли; секунды правил
  (`*_s`) получают пару `*_ticks`. Подписи (`name`) в `Defs.hash()` не входят.

### 10.7 Заглушки до интеграции

| Договор | Заглушка | Кто на ней работает |
|---|---|---|
| `CombatPort` | `CombatPortStub` (прямые ходы со скоростью `UnitStats`, без боя) | ECON, GAME, NAV — до I1/I2 |
| `NavApi` | `NavStub` (открытое поле, путь — прямо к цели) | CORE, ECON, GAME — до I1 |
| `EconApi` | `EconStub` (таблицы, старт, стройки; приказы пишутся в `calls`) | NAV, GAME — до I2/I3 |
| `GameQuery` | `FakeCity` (настоящий `BattleSim`: город Коканда и лагерь кыпчаков); узел `FakeCityDriver extends SimDriver` | VIEW, UI — до I4 |

`SimHarness.make_stubs()` собирает связку заглушек; `tests/run_all.sh` запускает все тесты
(`tests/run_all.sh econ` — только с «econ» в имени).

### 10.8 Модели построек (VIEW, арт)

Поиск модели постройки `id` стороны `faction` (поле `model` в `BuildingDefs`, по умолчанию — id):
1. `scenes/<faction>/<id>.tscn`, если есть;
2. иначе `assets/models/<faction>/<id>.glb` и `<id>_lod1.glb`;
3. стройка (`SITE`) — `<id>_site.glb`, руина (`RUIN`) — `<id>_ruin.glb`, концы стен — `<id>_end*.glb`;
4. файла нет — живописный ящик по `size`.

`render: "multimesh"` (звенья стен, арыки, уй, боз үй, чеп) — один MultiMesh на (модель, клетка 128 м).
Работа юнита — `Act.WORK` + `u_work` = `AnimSpec.WORK_CHOP 0 / WORK_DIG 0.25 / WORK_BUILD 0.5 / WORK_CARRY 0.75`;
арба — скелет `AnimSpec.Wagon`.

### 10.9 Управление и шрифты

- Действия InputMap (`project.godot`, физические клавиши): `ordo_select` (ЛКМ), `ordo_order` (ПКМ),
  `ordo_stop` (H), `ordo_formation` (F), `ordo_kachyp` (G), `ordo_fire_mode` (R), `ordo_war_cry` (V),
  `ordo_squad` (U), `ordo_pack` (K; Shift+K — весь лагерь), `ordo_idle_worker` (.), `ordo_group_1…9`
  (1…9; с Ctrl — запомнить), `ordo_pause` (P), `ordo_speed_up` (+), `ordo_speed_down` (−), `ordo_mute` (M).
  Модификаторы (Shift, Ctrl, двойное нажатие) проверяет `RtsInput`.
- Шрифты (OFL, кириллица вместе с ү ө ң қ ҳ ў ғ): `assets/ui/fonts/cormorant_unicase/CormorantUnicase-{Regular,Medium,SemiBold,Bold}.ttf`
  (заголовки), `assets/ui/fonts/alegreya/Alegreya-VariableFont_wght.ttf` и `Alegreya-Italic-VariableFont_wght.ttf`
  (текст; толщина — `FontVariation`); лицензии `OFL.txt` рядом. Строки интерфейса — `tr("Русский текст")`.
