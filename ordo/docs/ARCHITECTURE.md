# «Ордо», режим «Город»: итоговая архитектура

**Status:** final, decided by the technical director on 2026-10-12. It replaces proposal A ("unified core") and proposal B ("layered").

**Base:**
- Branch `claude/new-session-x8833z` at `b86f6e9`.
- Plus the bit-exact speed-ups in `perf/quick-wins` (`scripts/battle/sim.gd`): side masks per hash cell and block, a slot-offset cache, a dry-cell cache, and an early break in separation. **These are merged first, in M0.**

**Scope:** the playable skirmish «Город» (TZ §9). It covers:
- economy, building, hiring one by one, squads (§3–§5);
- walls, gates, towers, breaching (§6);
- 4 m pathfinding (§14);
- raid AI (§7);
- the themed Russian UI (§12) and PC controls (§10).

**Language:** code-level parts are in English. UI strings are in Russian.

---

## 0. Решение кратко (decision summary)

1. **Layered (B), with one body store.**
   - `BattleSim` (`scripts/battle/sim.gd`) stays the only owner of everything that walks, fights or dies: soldiers, officers, generals, workers and arbas. It is extended in place, and every new setting defaults to exact slice behaviour.
   - Three layers sit above it:
     - **NAV:** grid, paths, placement.
     - **ECON:** players, resources, buildings, resource nodes, herds, map fields, worker jobs, production.
     - **GAME:** tick order, commands, orders, AI, victory, map setup, replay.
   - The kernel never calls upward. Data is pushed in, and buffers are drained out.
2. **Taken from A:**
   - one 32-bit handle space;
   - an integer command stream (`PackedInt32Array`);
   - data as GDScript constants compiled into packed tables;
   - the WORK animation state in the kernel (`set_work`);
   - generic economy components;
   - pending impacts for arrows and cannon balls (stage 2);
   - an integer-only rules layer (milli-resources, timers in ticks).
3. **A unit hired one by one is a squad of one** (`sq_single = 1`, B), with a mandatory *single fast path*. Measured: without it, 1000 singles cost **83 ms/step**, because of the O(S²) `_nearest_enemy_squad`.
4. **Navigation: neither proposal survives measurement** (§1, rows 13–16). The final scheme, per team, is:
   - a **walk grid**, where structures are solid;
   - a **breach grid**, where enemy structures have weight 4;
   - a **sector region graph** for O(1) reachability and corridor refinement (HPA*-style).

   A breach happens only when no detour exists (TZ §6).
5. **Herds are economy entities** (B), drawn by a view-only flock. Sheep and horses are not kernel bodies.
6. **Events:**
   - A ring buffer with read cursors (B) carries A's event catalogue.
   - The kernel keeps its signals for FX only.
7. **Towers and garrisons:** the kernel shoots, using a structure mirror. ECON owns building HP and receives the hits.
8. **C++:**
   - `BattleSim` → `BattleCore`, ported whole, right after its API freeze (I1).
   - Navigation → `NavCore` at the multiplayer stage.
   - `CrowdPacker` if the view costs more than 3 ms.
9. **Six parallel code packages** (CORE, NAV, ECON, GAME, VIEW, UI) after the lead's M0 contract. Art runs on the existing art agents (`art-kokand`, `art-kipchak2`) and the Units area.

---

## 1. Проверка предложений по коду (verification)

Measured headless with Godot 4.7.2 on this VM, using scratch scripts outside the project.

| # | Claim | By | Verdict |
|---|---|---|---|
| 1 | Units exist only via `add_squad`; there is no despawn; `n` grows forever | A, B | **True.** `_new_unit`/`_new_squad` only append (sim.gd:285–355). |
| 2 | `_nearest_enemy_squad` is O(S) per squad, and is also called per fleeing unit | A, B | **True.** Called from `_squad_step` (717), `_units_think` (944) and `_heading_to_enemy`. **1000 squads of one, idle: 82.95 ms/step, 65.7 ms of it in `_squad_step`.** |
| 3 | `sq_single` already means "does not rout", so a hired unit can be a squad of one | B | **True** (723, 766). With nearest-enemy skipped for singles: **11.57 ms/step** for 1000 idle singles (squad step 2.88, think 5.31). The same 1000 units in 10 squads cost **13.55 ms/step**. So singles are viable only with the fast path and sleeping. |
| 4 | Single anchors need no change | B (implicit) | **False.** The anchor turns in place at 0.7 rad/s and moves only when aligned (`align²`, 836–839). A worker would need ~4.5 s to turn around. The fast path must turn singles quickly. |
| 5 | `vs_building`, `splash`, `min_range` are in `UnitStats` but never loaded | B | **True** (`type_index`, 200–224). |
| 6 | External write `scenario_clash.gd:220 sim.sq_melee[kip] = 0` | B | **True.** |
| 7 | Seven consumers are typed to `ScenarioClash` | B | **True.** `CineCamera` and `SquadSelection` also use `kok`/`kip`, and `BattleRoot` uses `restart()`. So `CineCamera` stays typed to `ScenarioClash`, and `SquadSelection` casts. |
| 8 | `BattleView._rebuild()` allocates slots once | A, B | **True.** Slots are also shared with `BattleAmbient` (appended after sim units). |
| 9 | `CrowdLayer` capacity is fixed | — | **True.** Growth means calling `setup()` again and rewriting all instances. `set_raw_buffer` needs the exact size. |
| 10 | 48 grass clearings; trees baked per 128 m cell with no per-tree id | A, B | **True** (`GrassField.MAX_CLEARINGS`, `WorldScatter._build_kind`). |
| 11 | Hash fixed at −512/256 | A, B | **True.** The terrain is 513² at 2 m = 1024 m, i.e. 256 cells of 4 m. A 1.6 km map needs 400². |
| 12 | `Terrain.is_water` per unit per tick is a hot spot | A | **True:** 0.77 ms/step per 1000 units. `perf/quick-wins` already caches dry cells. |
| 13 | A* floods on an unreachable goal (~13 ms) | B | **Worse than claimed.** Goal inside a solid ring: **19.6 ms (256²), 69.2 ms (400²)**. `allow_partial_path` does not help (18.8 / 66.2 ms). |
| 14 | Weighted walls (8…64) bound the search to ≤1.5 ms | B | **False.** w = 64: 9.8 / 24.2 ms. w = 30: 4.4 / 11.7 ms. Only small weights are cheap: w = 2: 0.18 / 0.37 ms; **w = 4: 0.38 / 0.94 ms**; w = 8: 0.96 / 2.6 ms. |
| 15 | Walk grid (solid) + breach grid; breach "when the walk path fails" | A | The failing walk query **is** the flood in row 13. It needs a reachability pre-check. |
| 16 | — (reachable but long detour) | — | Wall across the map with a gate at the edge: **7.4 ms (256²), 15.0 ms (400²)**. Long detours need corridor refinement. |
| 17 | GDScript BFS over the full grid is ~18 ms | A | Consistent: full component relabel **24.5 ms (256²), 70.8 ms (400²)**. Touching one 16×16 sector: ~0.04 ms. So only local (sector) relabels are affordable. |
| 18 | `time += DT` accumulates; libm trig is a lockstep risk | A | IEEE add/mul/sqrt are deterministic across x64/ARM, so accumulating time is not the risk. `sin/cos/atan2/exp` are, but they are used only in the kernel, so this is solved in C++ `BattleCore`. |
| 19 | A per-tick event buffer, cleared at step start | A | **Loses events** when the driver runs 2+ steps per frame (`ScenarioClash` runs up to 12; speed ×2; low fps). A ring buffer with cursors is needed. |
| 20 | Packed-array local aliases share storage, including `resize` | A | **Verified.** A local alias is a live reference, so readers must never write through it. |
| 21 | 1213-unit melee ≈ 14–15 ms avg, 30–32 ms worst | A, B | Both agree. `perf/quick-wins` lowers it bit-exactly. The real fix is `BattleCore`. |
| 22 | The WORK aux 0.75 "carry" walks the legs | A, B | **True** (`crowd_anim.gd:15`, `crowd_human.gdshaderinc:263`). Phase is driven like WALK by distance moved. |

---

## 2. Оценка двух предложений (scoring)

| Criterion | A: unified core | B: layered | Taken |
|---|---|---|---|
| **Correctness against code** | Strong findings. Missed the A* flood (row 15). Per-tick events get lost (row 19). Loose units (`u_squad = -1`) need guards in ≥8 combat functions that index `sq_*[u_squad[x]]` (`_units_think`, `_integrate`, `_charge_hit`, `_melee_hit`, `_fire`, `nearest_enemy` callers, `_kill`, `_fire_rank`). | Strong findings. The singles idea is right but under-specified (row 4). The weighted-wall claim is false (row 14). | B's kernel model, with fixes |
| **Determinism / lockstep** | Best rules: integers, ticks, count budgets, DMath. | Honest: same-binary now, cross-platform with C++. Ring events. | B's stance, plus A's integer-only rules layer |
| **1000+ units** | Think rates, movers-only separation. | Sleeping, singles fast path, corpse recycling. | Both: sleeping + staggering + presence masks (already in `perf/quick-wins`) |
| **Simplicity** | One store, but a huge move of approved code into static systems, and a giant shared `game_sim.gd`. | More interfaces (port, stubs), two id spaces bridged by handles. | B, with a narrower port |
| **Parallelism** | Bottleneck: every new shared array is a lead edit to `game_sim.gd`. | Stubs per interface; packages never edit the kernel. | B |
| **Keeps the slice working** | Rewrites `sim.gd` into a shim plus moved code (high risk). | Extends in place; defaults are the slice. | B |
| **C++ path** | Kernel inside GameSim; rules call setters. | Whole `BattleSim` → `BattleCore`; data in, buffers out, no callbacks. | B |

---

## 3. Разрешение конфликтов (every conflict, explicitly)

| # | Topic | A | B | **Final** | Why |
|---|---|---|---|---|---|
| 1 | Core shape | One `GameSim` store of units, buildings, nodes | `BattleSim` owns bodies; layers above | **B** | Lowest risk to the approved slice; one owner of `sim.gd`; clean C++ target. |
| 2 | Units hired one by one | Loose units (`u_squad = -1`) | Squad of one | **B + mandatory fast path** (§6.2 R2) | All combat code paths stay valid. Measured cost is close to regular squads (row 3). |
| 3 | Buildings | `b_*` inside GameSim | ECON `BuildingTable` + kernel structure mirror | **B.** Structure index = building slot (no mapping table) | Buildings are static, so the mirror is set once and cleared once. HP has a single owner (ECON). |
| 4 | Sheep, horses | Kernel units | ECON herds + view flock | **B** | No kernel bodies for 100–200 animals. Theft is a herd rule. The flock is drawn like `BattleAmbient`. |
| 5 | Navigation | Solid walk grid + breach grid | Single weighted grid | **Neither:** walk grid + breach grid (w = 4) + sector region graph | Rows 13–17. |
| 6 | Handles | 32-bit | 64-bit | **A** (32-bit) | Fits `PackedInt32Array` commands. 16-bit slots and 12-bit generations are enough. |
| 7 | Commands | `PackedInt32Array`, cm / mrad ints | `Array` of Variants | **A** | Compact, quantised, trivial encoding, no allocation of nested arrays. |
| 8 | Events | Per-tick buffer | Ring with cursors | **B's ring + A's catalogue** | Row 19. |
| 9 | Data | GDScript consts → `SimDefs` | JSON → `Defs` | **A's format, B's class name `Defs`** | Consistent with `UnitStats`. Errors at parse time. No export filter or I/O. |
| 10 | Economy numbers of units | Added to `UnitStats` | `units.json` | **New `scripts/data/unit_econ.gd` (`UnitEcon`, ECON-owned)** | One owner per file. `UnitStats.cost/time` stay as legacy mirrors until the lead removes them; `test_defs` asserts they match. |
| 11 | Deterministic math | `DMath` LUT now; `time = tick·DT` | Same-binary now | **B + A's rule** | Rules layer: integers and squared distances only; no transcendental functions outside the kernel. The kernel keeps built-in math (slice exactness) until `BattleCore`, which brings its own trig. |
| 12 | Signals | Re-emitted from events | Kept for FX; buffers for state | **B** | FX keep working. State changes go only through buffers. |
| 13 | Driver | `Skirmish` node | `SimDriver` extracted; `GameDriver extends SimDriver` | **B** | `BattleFx`, `BattleView`, `BattleHud` and `BattleAmbient` are reused unchanged after retyping. |
| 14 | Worker job state | `u_task` in the store | ECON `w_*` | **B for jobs, A for animation** | ECON owns jobs. The kernel holds `Act.WORK` + `u_work`, so views read only kernel arrays. |
| 15 | Workers under attack | No flee, fight back | FLEE to shelter | **TZ §4: no flee.** Workers get stance DEFENSIVE (retaliate within reach, never chase). | «Одиночные юниты и работники не бегут». A «Тревога» bell is [Свободно], stage 3. |
| 16 | Victory | `rules.victory` inside GameSim | `victory.gd` + kernel `NONE` | **B** | Defeat on HQ loss, or loss of the arba carrying the ordo. |
| 17 | Missile flight | Pending impacts | — | **A, at stage 2** | Needed for cannon splash, arrows from towers and hits on buildings. Muskets stay instant. |
| 18 | Formations through gates | Auto-column | Members follow the anchor trail | **B now, A later** | Emergent and simple. Auto-column is a polish item. |
| 19 | Path budget | 4–6 requests/tick | 24 requests + 6000 cells | **16 requests and 8000 estimated cells per tick** (counted, never timed) | Deterministic. With refinement, the worst request is ≤1 ms. |
| 20 | Corpse recycling | 20 s | 45 s | **30 s** (`GameRules.GOROD.corpse_s`). Battle: never. | |
| 21 | Collision with buildings | Push out of blocked cells | Block grid + OBB | **Exact OBB push-out for structures; cell block only for static terrain** | The 4 m grid is for paths only. Units touch walls; melee reaches the footprint edge. |
| 22 | Map data | `assets/world/gorod.json` | `data/maps/valley.json` | **`scripts/data/map_valley.gd` (`MapValley`)**, owned by GAME, seeded by the lead | Same format as the other data files. |
| 23 | UI strings | `strings_ru.gd` | `tr()` + CSV | **`tr("Русский текст")`** (msgid = Russian), no CSV yet | Readable for the author; ready for `.po` files later. |
| 24 | Save / replay | Both optional | | **Replay in MVP** (seed + map + defs hash + rules + command log). Save/load at stage 3; state is already serialisable. | |
| 25 | AI waves | `CHEAT` op | "Free waves" | **Explicit `Op.SPAWN`**, valid only for AI players when `rules.ai_free_waves` | The AI still acts only through commands. |
| 26 | Scene | `scenes/game/gorod.tscn` | `scenes/skirmish/skirmish.tscn` | **`scenes/gorod/gorod.tscn`** (VIEW) | |
| 27 | Packages | 7 | 7 | **6 code packages + art tracks** | Art already runs on separate agents. |

---

## 4. Карта модулей (module map)

```
scripts/contract/   LEAD (M0), frozen interfaces and shared tables; changed only by the lead
  ids.gd            Ids             32-bit handles
  sim_cmd.gd        SimCmd          opcodes, layout, constructors, encode/decode
  sim_events.gd     SimEvents       event ring buffer
  defs.gd           Defs            compiled packed tables from scripts/data/*
  combat_port.gd    CombatPort      interface: economy/orders/AI → bodies
  combat_port_stub.gd CombatPortStub kinematic bodies (straight moves) for ECON/GAME tests
  nav_api.gd        NavApi          interface: grid, paths, placement, wall planning
  path_result.gd    PathResult
  nav_stub.gd       NavStub         open field; overlap-only placement
  econ_api.gd       EconApi         interface: economy commands, ticks, queries
  econ_stub.gd      EconStub
  player_table.gd   PlayerTable     ┐
  building_table.gd BuildingTable   │ shared SoA tables: ECON writes, everyone else reads
  node_table.gd     NodeTable       │
  herd_table.gd     HerdTable       ┘
  game_query.gd     GameQuery       read-only facade for VIEW, UI, AI
  fake_city.gd      FakeCity        GameQuery stub: a populated, moving fake city
  selection_model.gd SelectionModel selected handles + control groups (UI implements behaviour)
scripts/data/       schema LEAD; values: ECON (economy), GAME (map, AI), CORE (UnitStats combat)
  unit_econ.gd resource_defs.gd building_defs.gd node_defs.gd herd_defs.gd recipe_defs.gd
  faction_defs.gd modifier_defs.gd game_rules.gd ai_defs.gd map_valley.gd
scripts/battle/     CORE: sim.gd (kernel), unit_stats.gd, combat_port_battle.gd, scenario_clash.gd,
                    sim_driver.gd (created by lead), the rest of the Battle area as today
scripts/nav/        NAV:  nav_grid.gd, regions.gd, path_service.gd, raster.gd, placement.gd, wall_tool.gd
scripts/econ/       ECON: economy_sim.gd, workers.gd, production.gd, population.gd, herds.gd, fields.gd,
                    network.gd, modifiers.gd, calendar.gd, bounty.gd, nomad.gd, exchange.gd, econ_query.gd
scripts/game/       GAME: game_sim.gd, command_queue.gd, orders.gd, victory.gd, map_setup.gd, replay.gd,
                    game_driver.gd, game_query_impl.gd, ai/{ai_controller,raid_director,garrison_ai}.gd
scripts/view/       VIEW: unit_view.gd, building_view.gd, building_look.gd, node_view.gd, herd_view.gd,
                    field_view.gd, ghost_view.gd, selection_view.gd, overlay_view.gd, city_fx.gd
scripts/ui/city/    UI:   city_hud.gd, top_bar.gd, bottom_panel.gd, minimap.gd, build_tabs.gd, cards.gd,
                    building_panel.gd, order_grid.gd, notes.gd, ui_theme.gd, cursor.gd
scripts/input/      UI:   rts_input.gd, placement_mode.gd, control_groups.gd, selection_impl.gd
scenes/gorod/       VIEW: gorod.tscn (World + GameDriver + views + BattleFx + RtsCamera + CityHud + RtsInput)
native/ordo_core/   later (perf track): BattleCore, NavCore, CrowdPacker
tests/              per package: test_combat_*, test_nav*, test_placement, test_econ_*, test_game_*, test_*_view, test_input…
```

**Data flow:**

```
 RtsInput ──SimCmd──► GameDriver.issue ─► CommandQueue ─┐            AI (in-sim, GameQuery) ──SimCmd──┘
                                                        ▼
 GameSim.step():  Orders ─► CombatPort ─► BattleSim (kernel)      Orders ─► EconApi ─► NavApi (stamp, place)
                  EconApi ◄─ drained: deaths+killer, structure hits, arrivals ─ CombatPort
                  NavApi ─► paths ─► CombatPort.deliver_paths ─► BattleSim.set_path
                  everything ─► SimEvents (ring)
 read-only:  UnitView ◄ BattleSim arrays · BuildingView/NodeView/HerdView/FieldView ◄ tables via GameQuery
             CityHud ◄ GameQuery + SimEvents · BattleFx ◄ SimDriver signals · CityFx ◄ SimEvents
```

---

## 5. Такт и детерминизм (tick order, determinism rules)

### 5.1 `GameSim.step()` — fixed order, 1/30 s

```gdscript
func step() -> void:
	tick += 1
	events.tick = tick
	for cmd in queue.take(tick):                 # sorted (player, seq)
		orders.apply(cmd)                        # validate → CombatPort / EconApi; failure → CMD_REJECTED
	for a in ai:                                 # phase-staggered; AI writes commands for tick + input_delay
		if (tick + a.phase) % a.period == 0:
			a.think(tick, query, _ai_out)
	for c in _ai_out: queue.push(c[SimCmd.H_PLAYER], tick, c)
	_ai_out.clear()
	econ.pre_step(tick)                          # worker FSM (10 Hz, thirds), queues, spawns, move requests
	if nav.version != _nav_seen:                 # sites placed or structures destroyed since last tick
		_nav_seen = nav.version
		port.on_nav_changed()                    # flag kernel repaths for paths crossing changed sectors
	nav.service(tick)                            # ≤16 requests, ≤8000 estimated cells
	port.deliver_paths()
	port.step()                                  # BattleSim.step()
	econ.post_step(tick, port.take_deaths(), port.take_structure_hits(), port.take_arrivals())
	if tick % 30 == 0: econ.slow_step(tick)      # upkeep, famine, pop, herds, exchange, calendar, tax
	if tick % 150 == 75: econ.fields_step(tick)  # grass regrowth/grazing, water coverage if dirty
	victory.check(tick)
	if tick % 30 == 0: checksums.append(checksum())
```

### 5.2 Rules (go into CONTRACT §10 «Город — симуляция»)

1. **Sim code is `RefCounted` only.** This covers `scripts/battle/sim.gd`, `scripts/{nav,econ}/*`, `scripts/game/*` except `game_driver.gd`, and `scripts/contract/*`. It never touches a Node, `Ordo`, `randf`/`randi`, `Time`, `OS` or physics. It reads `Terrain` (static, read-only), `UnitStats` and the defs.
2. **RNG streams are `BattleRng`, one per module:**
   - `battle.rng` is unchanged;
   - ECON uses `seed * 0x9E37 + 1`;
   - each AI uses `seed * 0x9E37 + 100 + player`;
   - NAV uses none.
3. **Iteration order:** arrays by index. A Dictionary is iterated only when its insertion order is deterministic. Never key by Object.
4. **Budgets are counted, never timed** (requests, cells, workers per tick).
5. **The rules layer (ECON, GAME, AI, NAV decisions) uses integers for game state:**
   - resources in milli-units (`int`, 1 food = 1000);
   - building HP in centi-points;
   - timers in ticks;
   - per-minute rates through remainder accumulators.
   It does distance checks on squared floats only. No `sin/cos/atan2/exp/pow` outside the kernel.
6. **Commands are the only input.** UI and AI produce `SimCmd`, applied at `tick + input_delay`: 1 in single player, 3–6 in multiplayer later. Pause and speed are local in single player.
7. **Checksum** every 30 ticks: `mix(battle.checksum(), econ.checksum(), nav.checksum(), Σ ai.checksum(), rng states)`.
8. **Determinism guarantee:** same-binary determinism now, which covers replays, tests and balance runs. Cross-platform determinism comes with `BattleCore`/`NavCore` at the multiplayer stage.
9. **Ownership:**
   - Only `sim.gd` writes kernel arrays.
   - Only ECON writes the four tables.
   - Readers take arrays into **locals at the top of a function and never store them in members.** This is required for the C++ copy-on-write boundary (§17).
10. **No upward calls from the kernel.** Kernel signals are FX-only; nothing that listens to them may change sim state.

---

## 6. Данные (data layout)

### 6.1 Handles — `scripts/contract/ids.gd`

```gdscript
class_name Ids
enum Kind { NONE = 0, UNIT = 1, SQUAD = 2, BUILDING = 3, NODE = 4, HERD = 5 }
const NULL := 0
static func make(kind: int, slot: int, gen: int) -> int:   # gen 1..4095 (0 never used, so a live handle ≠ 0)
	return (kind << 28) | ((gen & 0xFFF) << 16) | (slot & 0xFFFF)
static func kind(h: int) -> int: return (h >> 28) & 0x7
static func slot(h: int) -> int: return h & 0xFFFF
static func gen(h: int) -> int: return (h >> 16) & 0xFFF
static func next_gen(g: int) -> int: return 1 if g >= 0xFFF else g + 1
```

- **Validation:** whoever owns a store checks `store_gen[slot] == gen`. The kernel owns units and squads; ECON owns buildings, nodes and herds.
- **Stale handles:** commands carrying them are rejected (`CMD_REJECTED`, reason `STALE`).
- **UI:** drops invalid handles from the selection on every refresh.

### 6.2 Kernel — `BattleSim` (CORE)

**All existing names, values and signatures are kept.** Enums only get new values appended at the end.

```gdscript
enum Life { ALIVE, DYING, DEAD, FREE }          # FREE appended (slot reusable)
enum Act { NONE, AIM, MELEE, CHEER, WORK }      # WORK appended (aux in u_work → AnimSpec.Human.WORK)
enum Stance { AGGRESSIVE, DEFENSIVE, HOLD, PASSIVE }
enum Victory { BATTLE, NONE }
enum FleeMode { DIR, HOME }
const MAX_TEAMS := 4
const ST_BLOCK := 1; const ST_WALL := 2; const ST_GATE := 4; const ST_TOWER := 8
const ST_FIELD := 16; const ST_HQ := 32; const ST_SITE := 64          # structure flags
const MOD_ATK := 0; const MOD_SPEED := 1; const MOD_STAM := 2; const MOD_MORALE := 3; const MOD_RANGE := 4; const MOD_N := 5

# config (defaults = slice)
var victory_mode := Victory.BATTLE
var flee_mode := FleeMode.DIR
var corpse_steps := -1                  # −1 never recycle (slice); city: 30 s × 30
var team_home := PackedVector2Array()   # FleeMode.HOME targets

# units: new arrays (appended in _new_unit with defaults)
var u_gen := PackedInt32Array()         # 1..4095
var u_owner := PackedInt32Array()       # player (default = side)
var u_killer := PackedInt32Array()      # kernel index of killer, −1
var u_hurt_step := PackedInt32Array()   # step of last damage, −1
var u_sleep := PackedByteArray()        # 1 = asleep (R12)
var u_work := PackedFloat32Array()      # WORK aux, −1 none
var u_garrison := PackedInt32Array()    # structure index, −1 (stage 2)

# squads: new arrays
var sq_gen := PackedInt32Array()
var sq_owner := PackedInt32Array()
var sq_stance := PackedInt32Array()
var sq_path: Array[PackedVector2Array] = []
var sq_wp := PackedInt32Array()         # next waypoint
var sq_breach_st := PackedInt32Array()  # structure to break at sq_breach_wp, −1
var sq_breach_wp := PackedInt32Array()
var sq_st_target := PackedInt32Array()  # structure attack target, −1
var sq_enemy := PackedInt32Array()      # nearest enemy squad, cached once per step (real squads only)
var sq_trail: Array[PackedVector2Array] = []   # last 8 anchor points (gates: members follow the trail)

# structure mirror (index == ECON building slot)
var st_hw := 0
var st_ref, st_team, st_flags, st_alive, st_gar_cap, st_gar_n := PackedInt32Array()
var st_cx, st_cz, st_hx, st_hz, st_rot, st_top := PackedFloat32Array()   # center, half extents, yaw, platform height

# terrain grids (from NAV; empty = today's Terrain.is_water path)
var _blk_static := PackedByteArray()    # 1 = impassable terrain (cliff, deep water)
var _spd := PackedByteArray()           # speed ×16 per 4 m cell (shallow water 0.55 → 9)

# per-owner modifiers [owner * MOD_N + k], default 1.0
var own_mods := PackedFloat32Array()

# drained buffers (filled during step, emptied by CombatPortBattle)
var ev_dead := PackedInt32Array()       # pairs (u, killer)
var ev_st_b := PackedInt32Array(); var ev_st_dmg := PackedFloat32Array(); var ev_st_by := PackedInt32Array()
var ev_arrived := PackedInt32Array()    # squads whose MOVE ended this step
var ev_repath := PackedInt32Array()     # squads whose next waypoint became blocked / breach target fell
```

**Kernel changes** (R1–R18). Stage 1 is economy; stage 2 is fortifications.

| # | Stage | Change |
|---|---|---|
| R1 | 1 | **Lifecycle.**<br>• Free lists `_u_free` and `_sq_free`; generations; `n`/`squads` become high-water marks.<br>• Every loop skips `FREE`.<br>• `corpse_steps` turns DEAD into FREE. On recycle the unit leaves `sq_members` and the squad calls `_reslot(s)`; a squad with nobody left is freed.<br>• `remove_unit(u)` frees a body without death (packed into an arba, consumed). |
| R2 | 1 | **Singles fast path** (rows 2–4). For `sq_single == 1`:<br>• skip `_nearest_enemy_squad`, lag, morale aura and `_fire_control` (unless a fire target is set);<br>• anchor turn rate 8 rad/s with no `align²` gating;<br>• `_update_centroid` is a direct copy.<br>Real squads compute `sq_enemy[s]` once per step, and fleeing units read it instead of calling `_nearest_enemy_squad` per unit.<br>`add_general` keeps setting `general[side]`; `spawn_single` does not. |
| R3 | 1 | **Dynamic squads.**<br>• `form_squad(officer, members, formation, files)`: the officer gets role `OFFICER`, the last trooper gets `BANNER`, at most 100 of one type; the old singles are freed.<br>• `disband_squad(s) -> PackedInt32Array`: one new single per unit.<br>• `_reslot(s)` assigns slots by lateral and forward projection (no crossing paths). Members assemble with the existing scatter → formation behaviour. |
| R4 | 1 | **Owners and teams.**<br>• `u_side`/`sq_side` stay the team (enemy test unchanged); `u_owner`/`sq_owner` are the player.<br>• `side_init`, `side_flee_t` and `general` are sized `MAX_TEAMS`.<br>• `_victory_check` loops over `MAX_TEAMS` with the existing `side_init == 0` skip.<br>• Flee direction: `DIR` = today's ±X; `HOME` = toward `team_home[team]`. |
| R5 | 1 | **Pluggable victory:** `victory_mode = NONE` in the city, where `scripts/game/victory.gd` decides. |
| R6 | 1 | **Hash bounds from `Terrain.origin()`/`size()`** via `set_bounds`. On this map: −512 / 256 cells, identical to today. `perf/quick-wins` block masks resize with it. |
| R7 | 1 | **Movement against obstacles.**<br>• The anchor follows `sq_path` waypoints; final waypoint and facing = order target.<br>• Units collide exactly with structure OBBs (32 m bucket list), and with static terrain cells by axis-separated slide.<br>• Own gates (`ST_GATE`, same team) are ignored; fields (`ST_FIELD`) never collide.<br>• A member whose slot lies inside an obstacle steers along `sq_trail`, which makes formations pass gates as columns.<br>• `_spd` replaces `Terrain.is_water` when present. |
| R8 | 1 | **Structures as targets.**<br>• Load `t_vs_building`, `t_splash`, `t_min_range` from `UnitStats`.<br>• `order_attack_structure(s, st, gait)`: melee steers to the nearest OBB point; missiles hit at ×`t_vs_building`; muskets ×0.3 and cannons ×3 come from data.<br>• Hits go to `ev_st_*`; they are **never applied in the kernel**.<br>• `ST_SITE` structures are attackable (ECON scales their HP by progress). |
| R9 | 1 | **Stances.**<br>• `AGGRESSIVE` (default for soldiers): today's behaviour.<br>• `DEFENSIVE` (default for `WORKER`): acquires only enemies within reach + 1 m, never chases beyond 6 m, and returns to its anchor.<br>• `HOLD`: never moves to engage.<br>• `PASSIVE`: arbas.<br>Units with the `RAIDER` flag score `WORKER` targets at ×0.25 squared distance. |
| R10 | 1 | **Drained buffers** (`ev_*`), plus `u_killer` and `u_hurt_step`. The signals stay (FX). |
| R11 | 1 | **Per-owner multipliers:** `set_owner_mods(owner, mods)`, read through `u_owner` (famine, seasons).<br>Stage 3: `type_variant(base, key, overrides) -> int` and `retype(owner, from_t, to_t)` (smithy, flintlock). |
| R12 | 1 | **Sleeping** (deterministic).<br>• A unit sleeps when it is ALIVE, its squad holds, speed < 0.05, and it has no target, pending act, fire or hit and is not couched.<br>• Sleepers skip think and integrate; a sleeping single also skips squad step and centroid. They stay in the hash and can be pushed.<br>• Wake on: an order, damage, an enemy in the 16 m presence block (`_bmask` from `perf/quick-wins`), or being pushed more than 0.5 m off the slot (checked at 2 Hz, staggered by index).<br>• `Act.WORK` does not wake a unit; the view animates from `u_work`. |
| R13 | 1 | **No external writes.** Add `clear_melee(s)`; CORE updates `scenario_clash.gd:220` to use it. |
| R14 | 1 | **Checksum** also covers `u_gen`, `u_owner`, `sq_stance`, `sq_wp`, `st_alive` and the free lists. `test_sim` compares run against run, so it stays valid. |
| R15 | 1 | **Work animation.** `set_work(u, aux)` sets `u_act = Act.WORK` and `u_work = aux`; any order clears it. |
| R16 | 2 | **Garrison** (TZ §6).<br>• `garrison(u, st)`: the unit leaves the hash, sits on `st_top`, gets ranged ×1.3 and refills 1 arrow per 10 s; melee troops throw stones (32 m). Capacity is `st_gar_cap`.<br>• Missile hits on an occupied tower: 55% go to `ev_st_*`, 45% to a garrison unit; melee cannot reach the garrison.<br>• `ungarrison` happens on any move order. If the structure is cleared, the garrison is dropped around it at −30% HP. |
| R17 | 2 | **Pending impacts** `pi_*`: bows and cannons have flight ticks = dist / speed; splash 5.5 m against units and structures; minimum range; new FX signal `missile(from: Vector3, to: Vector3, kind: int, flight: float)`. |
| R18 | 2/3 | `KACHYP` (horse archers fire while retreating), fire/melee toggle (`set_fire_mode`), cannons ignoring targets inside minimum range. |

### 6.3 Economy tables (contract classes; ECON writes, others read)

```gdscript
class_name PlayerTable extends RefCounted
enum Ctrl { HUMAN, AI, NONE }
enum Stat { ATK, SPEED, STAM_REGEN, MORALE_REGEN, RANGE, GATHER, BUILD, UPKEEP, COUNT }
var count := 0
var team, faction, ctrl, alive, hq_b, pop_used, pop_reserved, pop_cap, famine, season := PackedInt32Array()
var res := PackedInt64Array()        # [p * R + r] milli
var rate_acc := PackedInt64Array()   # [p * R + r] remainders of per-minute flows
var income := PackedInt32Array()     # [p * R + r] milli per minute, for the UI (updated at 1 Hz)
var stat := PackedFloat32Array()     # [p * Stat.COUNT + k] compiled modifiers (1.0 neutral)

class_name BuildingTable extends RefCounted
enum State { FREE, SITE, ACTIVE, PACKED, RUIN }
const QMAX := 5
var hw := 0                                                # high-water mark (slots 0..hw-1)
var gen, btype, owner, team, state, rot_q, chain, flags := PackedInt32Array()
var x, z, rot := PackedFloat32Array()                      # center; rot radians (walls: any angle; buildings: rot_q · PI/2)
var ax, az, bx, bz := PackedFloat32Array()                 # wall/aryk links: endpoints
var hp_c, hp_max_c, progress := PackedInt32Array()         # centi-HP; progress 0..1000
var c0, r0, cw, ch := PackedInt32Array()                   # footprint rect in nav cells (links: bounding rect)
var q := PackedInt32Array()                                # [b * QMAX + i] unit def index, −1 empty
var q_n, q_t := PackedInt32Array()                         # queue length; ticks done on head
var rally_x, rally_z := PackedFloat32Array(); var rally_h := PackedInt32Array()
var recipe, recipe_t, workers_n, gar_n, store_mask, hit_tick := PackedInt32Array()
func handle(b: int) -> int ; func valid(h: int) -> bool ; func slot(h: int) -> int

class_name NodeTable extends RefCounted
var hw := 0
var gen, ntype, res, amount_milli, workers_n, workers_max, owner_b, scatter_ref, cell := PackedInt32Array()
var x, z := PackedFloat32Array()
func handle(n: int) -> int ; func valid(h: int) -> bool

class_name HerdTable extends RefCounted
enum State { FREE, PEN, DRIVEN, CAPTURED }
var hw := 0
var gen, htype, owner, pen_b, heads_milli, state, captor_u, capture_t := PackedInt32Array()
var x, z, graze_r := PackedFloat32Array()
func handle(h: int) -> int ; func valid(h: int) -> bool
```

**ECON-private state** (in `scripts/econ/*`, not in the contract):
- **Workers:** `w_unit`, `w_owner`, `w_job` (enum `Job { IDLE, TO_NODE, GATHER, TO_DROP, TO_SITE, BUILD, FARM, IN_ARBA }`), `w_target`, `w_carry_res`, `w_carry`, `w_t`, `w_prev_job`, `w_prev_target`, `w_path_key`.
- **Arba cargo:** `arba_cargo[u_slot] -> b_slot`.
- **Map fields:** grass is 16 m (64² on this map) with values 0..1000; water is 8 m.
- **Worker index:** `w_of_unit[u_slot]`.

### 6.4 Definitions — `Defs` and `scripts/data/*`

**Data files** are GDScript classes holding const Dictionaries. Each has a single owner, and the lead freezes the schema in M0:

| File / class | Content | Values owner |
|---|---|---|
| `scripts/battle/unit_stats.gd` `UnitStats` | Combat (as today). `cost`/`time` are a legacy mirror. | CORE |
| `unit_econ.gd` `UnitEcon.UNITS` | `cost`, `time`, `pop`, `upkeep` (food/min), `carry`, `gather` {res: per_s}, `build_rate`, `trained_at` [btype], `squad_max` | ECON |
| `resource_defs.gd` `ResourceDefs.RESOURCES` | `food, wood, stone, gold` + Kokand `clay, brick` + Kipchak `horse (backing: herd horse), wool, felt` (rule: 1–2 unique resources per side) | ECON |
| `building_defs.gd` `BuildingDefs.BUILDINGS` | Schema below; TZ §5.2–5.3, §6 values | ECON |
| `node_defs.gd` `NodeDefs.NODES` | `tree_poplar/willow/juniper/elm` (wood 100), `stone` (4000), `gold` (3000), `clay`; `work_aux`, `workers_max`, `blocks_cells` | ECON |
| `herd_defs.gd` `HerdDefs.HERDS` | `sheep` (food, wool per head·min; growth; graze_r), `horse` (resource backing, growth; capturable) | ECON |
| `recipe_defs.gd` `RecipeDefs.RECIPES` | `brick` (clay 4 + wood 1 → brick 2, 10 s, 2 workers), `felt` (wool 4 → felt 1) | ECON |
| `faction_defs.gd` `FactionDefs.FACTIONS` | `hq`, `worker`, `officer`, start resources/units (TZ §5.1), traits [`irrigation`, `bazaar`, `loot`, `koch`, `seasons`, `horses`], `ui_res`, `tabs`, `bounty` | ECON |
| `modifier_defs.gd` `ModifierDefs` | `MODIFIERS` {id: {stat, mul, add, when}}, `SEASONS` (jailoo 480 s, kyshtoo 240 s) | ECON |
| `game_rules.gd` `GameRules` | `GOROD` / `BATTLE`: `econ`, `corpse_s`, `pop_max` 500, upkeep, famine mods, loot, raids, trade, tax, `path_per_tick` 16, `path_cells_per_tick` 8000, `input_delay`, `ai_free_waves` | ECON (econ keys), GAME (others) |
| `ai_defs.gd` `AiDefs.RAID` | `peace_s` [300, 480, 720], `interval_s` [150, 240], `growth` 1.25, waves per faction, target weights, retreat thresholds, `warn_s` 30 | GAME |
| `map_valley.gd` `MapValley.MAP` | Start sites:<br>• Kipchak = the slice camp layout (CONTRACT §3: ordo (−60, 20), boz ring, koroo (−115, 65), jylky (−25, 90));<br>• Kokand urda on the east meadow.<br>Also: deposits ×5+5, clay pits, dam/aryk sources near the river, raid edge markers, jailoo/kyshtoo zones, AI base layout. | GAME |

**Building def schema.** Every key is optional except `name`, `faction`, `kind` and `size`.

```gdscript
"tegirmon": {"name": "Тегирмон", "faction": "kokand", "tab": "economy", "kind": "building",
	"size": Vector2(9, 9), "hp": 900, "cost": {"wood": 120}, "build_time": 30,
	"flags": ["drop", "blocks"], "accepts": ["food"],
	"place": {"max_slope": 1.2, "water": false, "territory": true},
	"model": "tegirmon", "render": "scene", "raid_value": 2, "enabled": true},
"dala": {"kind": "field", "size": Vector2(16, 16), "cost": {"wood": 60}, "flags": ["walkable"],
	"work": {"res": "food", "slots": 4, "per_worker_min": 18, "carry_to": ["tegirmon", "urda"]},
	"yield": [{"field": "water", "below": 500, "mul": 0.25}], "raid_value": 3},
"devor": {"kind": "wall", "tab": "fort", "size": Vector2(3.6, 1.8), "link": {"len": 3.6, "overlap": 0.4},
	"cost": {"wood": 3}, "hp": 420, "build_time": 4, "render": "multimesh"},
"burj": {"kind": "tower", "size": Vector2(7, 7), "cost": {"stone": 80, "wood": 30}, "hp": 2000,
	"garrison": {"cap": 10, "range_mult": 1.3, "absorb": 0.55, "stone_range": 32.0, "platform_h": 8.4},
	"place": {"on_wall": "replace"}},
"koroo": {"faction": "kipchak", "size": Vector2(14, 14), "cost": {"wood": 60}, "flags": ["pen", "packable"],
	"herd": {"htype": "sheep", "start": 20, "cap": 40}},
"ken": {"size": Vector2(8, 8), "cost": {"wood": 80}, "flags": ["drop"], "accepts": ["stone", "gold"],
	"place": {"near": {"nodes": ["stone", "gold"], "r": 26.0}}, "aura": {"gather_mult": 1.5, "r": 26.0}},
"aryk": {"faction": "kokand", "kind": "link", "link": {"len": 4.0, "overlap": 0.0}, "network": {"kind": "water", "coverage": 8.0}},
"togon": {"faction": "kokand", "kind": "dam", "place": {"across_river": true}, "network": {"kind": "water", "source": true}},
```

**`Defs` (compiled once; tests patch numbers through `build(overrides)`):**

```gdscript
class_name Defs extends RefCounted
enum BKind { BUILDING, FIELD, WALL, GATE, TOWER, LINK, DAM }
enum Render { SCENE, MULTIMESH }
const BF_HQ := 1; const BF_DROP := 2; const BF_HOUSE := 4; const BF_PACKABLE := 8; const BF_PEN := 16
const BF_TERRITORY := 32; const BF_BLOCKS := 64; const BF_ROUND := 128; const BF_NETWORK := 256
const BF_MARKET := 512; const BF_WALKABLE := 1024
static func shared() -> Defs
static func build(overrides := {}) -> Defs
func hash() -> int
func validate() -> PackedStringArray            # cross-references, sizes, costs ≥ 0 (tests/test_defs.gd)
var R := 0; var res_ids := PackedStringArray(); func res(id: StringName) -> int
func cost_of(d: Dictionary) -> PackedInt32Array # milli, size R
# units (economy view; combat stays in UnitStats/BattleSim.type_index)
var unit_ids := PackedStringArray(); func unit(id: StringName) -> int
var u_cost := PackedInt32Array()                # [u * R + r] milli
var u_gather := PackedInt32Array()              # [u * R + r] milli per second
var u_train_ticks, u_pop, u_upkeep_milli_min, u_carry_milli, u_build_rate, u_flags := PackedInt32Array()
var u_trained_at: Array[PackedInt32Array] = []
# buildings
var b_ids := PackedStringArray(); func building(id: StringName) -> int
var b_kind, b_flags, b_hp_c, b_build_ticks, b_pop_cap, b_accepts, b_cells_w, b_cells_h := PackedInt32Array()
var b_work_slots, b_gar_cap, b_raid_value, b_herd, b_render := PackedInt32Array()
var b_size := PackedVector2Array(); var b_cost := PackedInt32Array()     # [b * R + r]
var b_link_len, b_link_overlap, b_platform_h, b_range_mult, b_absorb := PackedFloat32Array()
var b_trains: Array[PackedInt32Array] = []; var b_recipes: Array[PackedInt32Array] = []
var b_place: Array[Dictionary] = []; var b_work: Array[Dictionary] = []; var b_aura: Array[Dictionary] = []
var b_passive: Array[Array] = []; var b_network: Array[Dictionary] = []
var b_model, b_name, b_tab, b_faction := PackedStringArray()
# nodes, herds, recipes, factions: n_*, h_*, rc_*, f_* in the same style; rules: Dictionary (compiled GameRules)
```

**Footprint in nav cells:** `cw = ceili(size.x / 4 − 0.1)`, `ch = ceili(size.y / 4 − 0.1)`. Rotation swaps them. Example sizes: urda 18 → 5 cells, uy 8 → 2, tegirmon 9 → 3, kazarma 16×12 → 4×3, boz 7 → 2. The center snaps to a cell center when the cell count is odd, and to a cell corner when it is even.

### 6.5 Navigation data (NAV-private)

- **Grid:** `w, h, origin` from `Terrain.info()` (256² now, 400² for 1.6 km).
- **Per-cell arrays:**
  - `flags: PackedByteArray` (`NavApi.F`);
  - `team_of: PackedByteArray` (structure team, 255 = none);
  - `struct_of: PackedInt32Array` (building slot + 1);
  - `static_w: PackedByteArray` (water/ford/soft weights).
- **Per team `t`:**
  - `walk[t]` and `breach[t]` (`AStarGrid2D`, octile, `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`);
  - `regions[t]` (sector graph: 16×16-cell sectors, sector-local component labels, portals, adjacency, global component ids);
  - `sector_ver[t][sector]` for repaths.

---

## 7. Ключевые API (frozen signatures)

### 7.1 `CombatPort` — `scripts/contract/combat_port.gd` (CORE implements `CombatPortBattle`)

Handles in, handles out. Unit handles given to orders resolve to their squad. Several singles ordered together share one path.

```gdscript
class_name CombatPort extends RefCounted
func setup(defs: Defs, nav: NavApi, cfg: Dictionary) -> void   # cfg: {teams, homes, corpse_s, bounds_origin, bounds_size}
func battle() -> BattleSim                                       # read-only kernel arrays (views); stub returns null
# lifecycle
func spawn(owner: int, team: int, type_id: StringName, pos: Vector2, heading: float) -> int            # unit handle (a single)
func spawn_squad(owner: int, team: int, type_id: StringName, count: int, pos: Vector2, heading: float,
		officer_type: StringName = &"", formation := 0, files := 0) -> int                               # squad handle
func remove(u_h: int) -> void                 # leaves the world without dying (packed into an arba, consumed)
func kill(u_h: int) -> void                   # tests and SPAWN/cheat tooling only
func valid(h: int) -> bool
# reads
func alive(u_h: int) -> bool
func pos(h: int) -> Vector2                   # unit position or squad centroid
func owner(h: int) -> int
func team(h: int) -> int
func type_id(u_h: int) -> StringName
func squad_of(u_h: int) -> int
func members(s_h: int) -> PackedInt32Array
func is_idle(h: int) -> bool
func hurt_within(u_h: int, ticks: int) -> bool
func units_near(team: int, pos: Vector2, r: float, enemies: bool, flags_any: int, out: PackedInt32Array) -> int
func enemy_near(team: int, pos: Vector2, r: float) -> bool
# orders
func move(hs: PackedInt32Array, to: Vector2, run := false, facing := NAN, line_to := Vector2(NAN, NAN)) -> void
func attack(hs: PackedInt32Array, target_h: int, run := true) -> void      # unit, squad or building handle
func attack_move(hs: PackedInt32Array, to: Vector2) -> void
func stop(hs: PackedInt32Array) -> void
func hold(hs: PackedInt32Array, facing := NAN) -> void
func set_stance(hs: PackedInt32Array, stance: int) -> void
func set_gait(hs: PackedInt32Array, gait: int) -> void
func set_formation(hs: PackedInt32Array, formation: int) -> void
func set_fire_mode(hs: PackedInt32Array, mode: int) -> void                # stage 2
func set_kachyp(hs: PackedInt32Array, on: bool) -> void                     # stage 2
func war_cry(general_h: int) -> bool
func form_squad(officer_h: int, candidates: PackedInt32Array, formation := 0) -> int   # squad handle or 0
func disband(s_h: int) -> PackedInt32Array                                  # unit handles, now singles
func set_work(u_h: int, aux: float) -> void                                 # AnimSpec WORK aux; < 0 stops
func face(u_h: int, heading: float) -> void
func garrison(hs: PackedInt32Array, b_h: int) -> void                       # stage 2
func ungarrison(b_h: int, at: Vector2) -> void                              # stage 2
# world mirror (ECON → kernel)
func structure_set(b_h: int, team: int, center: Vector2, half: Vector2, rot: float, flags: int,
		top := 0.0, gar_cap := 0) -> void
func structure_clear(b_h: int) -> void
func set_owner_mods(owner: int, mods: PackedFloat32Array) -> void           # BattleSim.MOD_*
func upgrade_type(owner: int, type_id: StringName, overrides: Dictionary) -> void   # stage 3
func on_nav_changed() -> void
# tick (GameSim only)
func deliver_paths() -> void
func step() -> void
func take_deaths() -> PackedInt32Array            # pairs [unit_h, killer_h]
func take_structure_hits() -> PackedInt32Array    # triples [building_h, dmg_centi, attacker_h]
func take_arrivals() -> PackedInt32Array          # squad handles whose MOVE completed
func checksum() -> int
func save_into(d: Dictionary) -> void
func load_from(d: Dictionary) -> void
```

**How `CombatPortBattle` routes things:**
- **Paths:** it keeps the original order per squad (goal, gait, facing). It requests a path per squad, or one for a group of singles, through `NavApi.request`.
- **Delivery:** in `deliver_paths()` it calls `BattleSim.set_path(...)`.
- **Repaths:** `ev_repath` and breach completion trigger a new request for the remembered goal.
- **Line moves:** `line_to` sets `files` from the line length, with facing perpendicular to the line. Several squads split the line in proportion to their size.
- **Breaches:** a breach becomes `set_path` with `breach_st`/`breach_wp`. At that waypoint the kernel switches to `order_attack_structure`, and a destroyed structure triggers a repath.

### 7.2 `NavApi`, `PathResult` (NAV implements `NavGrid` + `PathService` + `Placement` + `WallTool` behind it)

```gdscript
class_name NavApi extends RefCounted
const CELL := 4.0
const SECTOR := 16
enum F { STATIC = 1, WATER = 2, FORD = 4, STRUCT = 8, WALL = 16, GATE = 32, SOFT = 64, NODE = 128 }
enum Why { OK, OVERLAP, SLOPE, WATER, OUT_OF_MAP, NOT_NEAR, NOT_ON_WALL, NO_TERRITORY, ENEMY_UNITS, NO_RES, NOT_ALLOWED }
var w := 0; var h := 0; var origin := Vector2.ZERO; var version := 0
func setup(info: Dictionary, defs: Defs, econ: EconApi, port: CombatPort) -> void
# grid
func cell_of(p: Vector2) -> int
func cell_center(c: int) -> Vector2
func passable(team: int, c: int) -> bool
func reachable(team: int, a: Vector2, b: Vector2) -> bool                 # region graph, O(1) amortised
func nearest_passable(team: int, p: Vector2, max_r := 40.0) -> Vector2
func structure_at(p: Vector2) -> int                                      # building handle or 0
func static_grid() -> PackedByteArray                                     # terrain blocks, for kernel collision
func speed_grid() -> PackedByteArray                                      # ×16 speed factor per cell
func stamp_building(b_h: int, team: int, center: Vector2, btype: int, rot_q: int) -> Rect2i
func stamp_link(b_h: int, team: int, a: Vector2, b: Vector2, btype: int) -> Rect2i   # 4-connected supercover
func unstamp(b_h: int) -> void
# paths
func request(team: int, from: Vector2, to: Vector2, client: int, prio := 0) -> int  # ticket > 0
func service(tick: int) -> void
func result(ticket: int) -> PathResult                                    # null until served
func release(ticket: int) -> void
func stale(r: PathResult) -> bool                                         # crosses a sector changed since issue
func find_now(team: int, from: Vector2, to: Vector2) -> PathResult        # tests, tools
# placement (authoritative for SimCmd; the ghost uses the same calls)
func check_place(player: int, btype: int, center: Vector2, rot_q: int) -> int          # Why
func place_cells(player: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray  # Why per footprint cell
func snap(btype: int, p: Vector2, rot_q: int) -> Vector2
func plan_wall(player: int, wtype: int, pts: PackedVector2Array) -> Dictionary
		# {centers: PackedVector2Array, rots: PackedFloat32Array, why: PackedByteArray, cost: PackedInt32Array}
func snap_on_wall(player: int, btype: int, p: Vector2) -> Dictionary
		# {why, center: Vector2, rot: float, removes: PackedInt32Array (link handles)}
func ring_slots(player: int, center: Vector2, btypes: PackedInt32Array) -> PackedVector2Array   # köч unpack
func checksum() -> int

class_name PathResult extends RefCounted
var pts := PackedVector2Array()       # smoothed waypoints; last = goal snapped to passable
var breach_b := 0                     # building handle to break, 0 = none
var breach_wp := -1                   # index of the waypoint just before the breach
var no_route := false                 # own units cannot reach: pts end at the nearest reachable point
var cost := 0.0
var sectors := PackedInt32Array()     # traversed sectors (staleness)
var issued_ver := 0
```

### 7.3 `EconApi` (ECON implements `EconomySim`)

```gdscript
class_name EconApi extends RefCounted
enum Err { OK = 0, NOT_OWNER = 1, INVALID = 2, NO_RES = 3, POP_CAP = 4, QUEUE_FULL = 5, BAD_PLACE = 6,
	BUSY = 7, NOT_ALLOWED = 8, STALE = 9 }       # handlers return −Err (or −(100 + NavApi.Why))
var players: PlayerTable; var buildings: BuildingTable; var nodes: NodeTable; var herds: HerdTable
func setup(defs: Defs, rules: Dictionary, port: CombatPort, nav: NavApi, events: SimEvents, seed: int) -> void
# map setup
func add_player(team: int, faction: StringName, ctrl: int) -> int
func spawn_building(p: int, btype: int, center: Vector2, rot_q: int, active := true) -> int
func spawn_node(ntype: int, pos: Vector2, amount := -1, scatter_ref := -1) -> int
func spawn_herd(p: int, htype: int, pen_h: int, heads: int) -> int
func spawn_worker(p: int, pos: Vector2) -> int
# command handlers (Orders has checked ownership and handle validity)
func place_site(p: int, btype: int, center: Vector2, rot_q: int, workers: PackedInt32Array) -> int
func place_wall(p: int, wtype: int, pts: PackedVector2Array, workers: PackedInt32Array) -> int   # chain id
func assign_gather(p: int, workers: PackedInt32Array, source_h: int) -> int
func assign_build(p: int, workers: PackedInt32Array, b_h: int) -> int    # help build / repair (stage 2)
func train(p: int, b_h: int, utype: int, count: int) -> int
func cancel_train(p: int, b_h: int, index: int) -> int
func set_rally(p: int, b_h: int, at: Vector2, target_h: int) -> int
func demolish(p: int, b_h: int) -> int
func set_recipe(p: int, b_h: int, recipe: int) -> int
func trade(p: int, b_h: int, give: int, take: int, amount_milli: int) -> int
func set_dam(p: int, b_h: int, open: bool) -> int
func pack(p: int, b_h: int) -> int
func pack_all(p: int, hq_h: int) -> int
func unpack(p: int, arbas: PackedInt32Array, center: Vector2) -> int
func herd_move(p: int, herd_h: int, to: Vector2) -> int
func release_units(units: PackedInt32Array) -> void      # a non-economy order took these workers off their jobs
# tick
func pre_step(tick: int) -> void
func post_step(tick: int, deaths: PackedInt32Array, hits: PackedInt32Array, arrivals: PackedInt32Array) -> void
func slow_step(tick: int) -> void
func fields_step(tick: int) -> void
# queries (GameQuery, AI, Placement)
func res(p: int, r: int) -> int
func can_pay(p: int, cost: PackedInt32Array) -> bool
func node_near(res_mask: int, pos: Vector2, r: float) -> int
func in_territory(p: int, pos: Vector2) -> bool
func wall_link_at(p: int, pos: Vector2, r: float) -> int
func worker_job(u_h: int) -> int
func idle_workers(p: int) -> PackedInt32Array
func arba_cargo(u_h: int) -> int
func grass_grid() -> PackedByteArray
func water_grid() -> PackedByteArray
func building_panel(b_h: int) -> Dictionary
func build_menu(p: int, tab: StringName) -> Array[Dictionary]
func checksum() -> int
func save_into(d: Dictionary) -> void
func load_from(d: Dictionary) -> void
```

### 7.4 GAME classes

```gdscript
class_name GameSim extends RefCounted
const DT := BattleSim.DT
var tick := 0; var seed := 1; var defs: Defs; var rules: Dictionary
var port: CombatPort; var nav: NavApi; var econ: EconApi; var events: SimEvents
var queue: CommandQueue; var orders: Orders; var ai: Array[AiController] = []; var victory: Victory
var query: GameQuery; var checksums := PackedInt64Array()
func setup(map: Dictionary, players: Array[Dictionary], p_seed: int, rules_id := &"GOROD") -> void
		# players: [{faction, team, ctrl, difficulty}]; uses MapSetup
func submit(player: int, cmd: PackedInt32Array) -> void      # queue.push(player, tick, cmd)
func step() -> void                                          # §5.1
func checksum() -> int
func replay_record() -> Dictionary                           # {seed, map_id, defs_hash, rules_id, players, log}
static func from_replay(d: Dictionary) -> GameSim

class_name CommandQueue extends RefCounted
var input_delay := 1
var log: Array[PackedInt32Array] = []
func push(player: int, tick_now: int, cmd: PackedInt32Array) -> void   # stamps H_PLAYER, H_TICK = tick_now + delay, H_SEQ
func take(tick: int) -> Array[PackedInt32Array]                        # sorted (player, seq); appended to log

class_name Orders extends RefCounted
func setup(game: GameSim) -> void
func apply(cmd: PackedInt32Array) -> void      # shape, ownership, generation, rules → port / econ; CMD_REJECTED(player, op, reason)

class_name Victory extends RefCounted
func check(tick: int) -> void                  # PLAYER_DEFEATED: HQ destroyed, or the arba carrying the ordo died; VICTORY(team)

class_name MapSetup
static func populate(game: GameSim, map: Dictionary, players: Array[Dictionary]) -> void
		# trees from ScatterData (file order → scatter_ref), deposits, clay, start bases, workers, herds, AI controllers

class_name AiController extends RefCounted
var player := -1; var period := 30; var phase := 0; var rng: BattleRng
func setup(p_player: int, params: Dictionary, p_seed: int) -> void
func think(tick: int, q: GameQuery, out: Array[PackedInt32Array]) -> void    # commands only, never writes state
func checksum() -> int
class_name RaidDirector extends AiController     # enum Phase { PEACE, MUSTER, MARCH, STRIKE, RETREAT, COOLDOWN }
class_name GarrisonAi extends AiController       # AI base defence; stage 2: towers garrisoned with archers

class_name GameDriver extends SimDriver          # Node in scenes/gorod/gorod.tscn
var game: GameSim; var local_player := 0
signal ticked(tick: int)
func start_game(p_seed: int, player_faction: StringName, difficulty: int) -> void
func issue(cmd: PackedInt32Array) -> void        # game.submit(local_player, cmd)
func step() -> void                              # game.step(); kernel signals → SimDriver signals (FX); ticked
```

### 7.5 `GameQuery` (contract; GAME implements `GameQueryImpl`; the lead ships `FakeCity`)

```gdscript
class_name GameQuery extends RefCounted
func tick() -> int
func defs() -> Defs
func battle() -> BattleSim                                   # kernel arrays: take into locals, never write, never store
func players() -> PlayerTable
func buildings() -> BuildingTable
func nodes() -> NodeTable
func herds() -> HerdTable
func events() -> SimEvents
func grass() -> PackedByteArray ; func water() -> PackedByteArray ; func field_dims() -> Vector4i  # gw, gh, ww, wh
func unit_handle(u: int) -> int ; func unit_index(h: int) -> int
func pick(p: int, world: Vector2, r: float) -> int           # unit, building, node or herd handle (own first)
func units_of(p: int) -> PackedInt32Array                    # for box selection (UI projects positions itself)
func selection_info(hs: PackedInt32Array) -> Dictionary      # {kind, cards: [{type, count, hp, morale, stamina, banner}]}
func building_panel(b_h: int) -> Dictionary                  # {name, hp, state, progress, queue, trains[{utype, cost, enabled, why}], recipe, herd, water, gar}
func build_menu(p: int, tab: StringName) -> Array[Dictionary]  # {btype, name, cost, hotkey, enabled, why}
func orders_for(p: int, hs: PackedInt32Array) -> Array[Dictionary]   # order grid {op, label, key, enabled}
func check_place(p: int, btype: int, center: Vector2, rot_q: int) -> int
func place_cells(p: int, btype: int, center: Vector2, rot_q: int) -> PackedByteArray
func plan_wall(p: int, wtype: int, pts: PackedVector2Array) -> Dictionary
func snap(btype: int, p: Vector2, rot_q: int) -> Vector2
func idle_workers(p: int) -> PackedInt32Array
func raid_eta_ticks(p: int) -> int                           # −1 none
func minimap(p: int) -> Dictionary                           # {units: PackedVector3Array(x, z, team), buildings: …}
```

### 7.6 `SimDriver` (lead, M0) and `SelectionModel`

```gdscript
class_name SimDriver extends Node
signal started(seed: int)
signal finished
signal shot(unit: int, muzzle: Vector3, dir: Vector3, hit: bool)
signal volley(squad: int, rank: int, center: Vector3, count: int)
signal charge_ordered(squad: int)
signal impact(squad: int, pos: Vector3, strength: float)
signal charge_hit(unit: int, target: int, pos: Vector3)
signal melee_hit(attacker: int, target: int, pos: Vector3)
signal death(unit: int, pos: Vector3)
signal war_cry(unit: int, pos: Vector3)
signal rout(squad: int, pos: Vector3)
signal rallied(squad: int, pos: Vector3)
signal battle_over(winner: int)
const DT := BattleSim.DT
var sim: BattleSim
var time: float:
	get: return sim.time if sim else 0.0
var time_scale := 1.0; var paused := false; var alpha := 0.0; var current_seed := 1
var _acc := 0.0
func start(p_seed: int) -> void        # virtual
func step() -> void                    # virtual
func restart() -> void                 # start(current_seed)
func wire_sim(s: BattleSim) -> void    # virtual; connects sim signals → own signals
func _process(delta: float) -> void    # accumulator, ≤ 12 steps per frame, alpha (moved from ScenarioClash)

class_name SelectionModel extends RefCounted
signal changed(handles: PackedInt32Array)
var selected := PackedInt32Array()
var groups: Array[PackedInt32Array] = []          # 9
func set_selection(hs: PackedInt32Array) -> void
func add(hs: PackedInt32Array) -> void
func prune(q: GameQuery) -> void                  # drop invalid / dead handles
func set_group(i: int) -> void
func recall_group(i: int) -> PackedInt32Array
```

### 7.7 Events — `SimEvents`

```gdscript
class_name SimEvents extends RefCounted
enum Ev { NONE,
	UNIT_SPAWNED, UNIT_DIED, SQUAD_FORMED, SQUAD_DISBANDED,
	SITE_PLACED, BUILDING_DONE, BUILDING_HIT, BUILDING_DESTROYED, GATE_BREACHED, PACKED, UNPACKED,
	NODE_DEPLETED, TREE_FELLED, RES_DELIVERED, TRAINED, QUEUE_CHANGED, POP_CAPPED, NOT_ENOUGH, WORKER_IDLE,
	FAMINE, PASTURE_LOW, HERD_STOLEN, HERD_RETURNED, LOOT, SEASON, IRRIGATION_CHANGED,
	RAID_WARNING, RAID_STARTED, RAID_ENDED, CMD_REJECTED, PLAYER_DEFEATED, VICTORY }
const CAP := 8192
var tick := 0
var head := 0                                     # total pushed, monotonic
var e_tick, e_kind, e_player, e_a, e_b, e_c := PackedInt32Array()
var e_x, e_z := PackedFloat32Array()
func push(kind: int, player: int, a := 0, b := 0, c := 0, pos := Vector2.ZERO) -> void
func range_since(cursor: int) -> Vector2i          # [from, to) sequence numbers still in the ring
func at(seq: int) -> int                           # ring index for a sequence number
```

- Events are **output only**. They are not checksummed and not saved.
- Payload conventions for `a`/`b`/`c`:
  - handles for entities;
  - resource index plus milli amount for `LOOT` and `RES_DELIVERED`;
  - op plus reason for `CMD_REJECTED`;
  - ETA in ticks for `RAID_WARNING`.

---

## 8. Поток приказов (command stream)

**Layout:** `PackedInt32Array [op, player, tick, seq, n, id_0 … id_{n−1}, args…]`.
- Header indices: `H_OP=0, H_PLAYER=1, H_TICK=2, H_SEQ=3, H_N=4, H_IDS=5`.
- Positions are integer centimetres, angles integer milliradians, and `NO_ANGLE = 0x7FFFFFFF` stands for NAN.
- Def ids (unit, building, recipe, resource) are `Defs` indices; a replay records `defs.hash()`.

```gdscript
class_name SimCmd
enum Op { NONE, MOVE, MOVE_LINE, ATTACK, ATTACK_MOVE, STOP, HOLD, STANCE, GAIT, FORMATION, FIRE_MODE, KACHYP,
	WAR_CRY, FORM_SQUAD, DISBAND, GARRISON, UNGARRISON,
	GATHER, BUILD, BUILD_WALL, ASSIST, DEMOLISH, TRAIN, CANCEL_TRAIN, RALLY, SET_RECIPE, TRADE, SET_DAM,
	PACK, PACK_ALL, UNPACK, HERD_MOVE, SPAWN }
const H_OP := 0; const H_PLAYER := 1; const H_TICK := 2; const H_SEQ := 3; const H_N := 4; const H_IDS := 5
const NO_ANGLE := 0x7FFFFFFF
static func cm(v: float) -> int
static func mrad(a: float) -> int
static func ids(cmd: PackedInt32Array) -> PackedInt32Array
static func arg(cmd: PackedInt32Array, i: int) -> int
static func arg_pos(cmd: PackedInt32Array, i: int) -> Vector2
static func arg_angle(cmd: PackedInt32Array, i: int) -> float
static func move(ids: PackedInt32Array, to: Vector2, run := false, facing := NAN, queue := false) -> PackedInt32Array
static func move_line(ids: PackedInt32Array, a: Vector2, b: Vector2, run := false) -> PackedInt32Array
static func attack(ids: PackedInt32Array, target_h: int, run := true) -> PackedInt32Array
static func attack_move(ids: PackedInt32Array, to: Vector2) -> PackedInt32Array
static func stop(ids: PackedInt32Array) -> PackedInt32Array
static func hold(ids: PackedInt32Array, facing := NAN) -> PackedInt32Array
static func stance(ids: PackedInt32Array, stance: int) -> PackedInt32Array
static func gait(ids: PackedInt32Array, gait: int) -> PackedInt32Array
static func formation(ids: PackedInt32Array, f: int) -> PackedInt32Array
static func fire_mode(ids: PackedInt32Array, mode: int) -> PackedInt32Array
static func kachyp(ids: PackedInt32Array, on: bool) -> PackedInt32Array
static func war_cry(general_h: int) -> PackedInt32Array
static func form_squad(officer_h: int, ids: PackedInt32Array) -> PackedInt32Array
static func disband(squad_h: int) -> PackedInt32Array
static func garrison(ids: PackedInt32Array, building_h: int) -> PackedInt32Array
static func ungarrison(building_h: int) -> PackedInt32Array
static func gather(ids: PackedInt32Array, source_h: int) -> PackedInt32Array
static func build(ids: PackedInt32Array, btype: int, at: Vector2, rot_q: int) -> PackedInt32Array
static func build_wall(ids: PackedInt32Array, wtype: int, pts: PackedVector2Array) -> PackedInt32Array
static func assist(ids: PackedInt32Array, building_h: int) -> PackedInt32Array
static func demolish(building_h: int) -> PackedInt32Array
static func train(building_h: int, utype: int, count := 1) -> PackedInt32Array
static func cancel_train(building_h: int, index: int) -> PackedInt32Array
static func rally(building_h: int, at: Vector2, target_h := 0) -> PackedInt32Array
static func set_recipe(building_h: int, recipe: int) -> PackedInt32Array
static func trade(building_h: int, give: int, take: int, amount_milli: int) -> PackedInt32Array
static func set_dam(building_h: int, open: bool) -> PackedInt32Array
static func pack(building_h: int) -> PackedInt32Array
static func pack_all(hq_h: int) -> PackedInt32Array
static func unpack(arba_ids: PackedInt32Array, center: Vector2) -> PackedInt32Array
static func herd_move(herd_h: int, to: Vector2) -> PackedInt32Array
static func spawn(utype: int, count: int, at: Vector2, heading: float, officer_utype := -1) -> PackedInt32Array
static func validate_shape(cmd: PackedInt32Array) -> bool
static func encode(cmds: Array[PackedInt32Array]) -> PackedByteArray
static func decode(bytes: PackedByteArray) -> Array[PackedInt32Array]
```

| Ops | `Orders` → handler | Owner |
|---|---|---|
| MOVE, MOVE_LINE, ATTACK, ATTACK_MOVE, STOP, HOLD, STANCE, GAIT, FORMATION, FIRE_MODE, KACHYP, WAR_CRY, FORM_SQUAD, DISBAND, GARRISON, UNGARRISON | `CombatPort.*`. Workers in the id list first get `EconApi.release_units`. | CORE |
| GATHER, BUILD, BUILD_WALL, ASSIST, DEMOLISH, TRAIN, CANCEL_TRAIN, RALLY, SET_RECIPE, TRADE, SET_DAM, PACK, PACK_ALL, UNPACK, HERD_MOVE | `EconApi.*` | ECON |
| SPAWN | `CombatPort.spawn_squad`. Only for `PlayerTable.Ctrl.AI` when `rules.ai_free_waves`; the HQ door or an edge marker is the anchor. | GAME |

**`Orders` validation, in order:**
1. `validate_shape`.
2. The player is alive.
3. Every handle is valid and owned by the player. The exceptions are attack targets and gather sources, which must be valid but not owned.
4. Rules checks.

The handler's return code ≠ OK produces `CMD_REJECTED(player, op, reason)`, which the UI shows as a red note.

---

## 9. Навигация: стены, ворота, пролом (navigation)

1. **Static layer** (built once from `Terrain`):
   - slope over 0.75 (rise/run across a cell) and deep water are `STATIC`;
   - fords and shallow water are `WATER`/`FORD`, weight 2 and kernel speed ×0.55;
   - fields (`dala`) are `SOFT`, weight 1.5, walkable;
   - trees do not block; deposits block their 2×2 core.

   Static components are labelled once at load, and goals in another static component snap to the nearest cell of the start component.
2. **Stamps:**
   - buildings stamp their footprint rect;
   - wall, palisade and aryk links stamp a 4-connected supercover line, 1 cell wide;
   - gates are `GATE` + team; towers on walls replace the link cells.

   Each stamp:
   - bumps `version` and `sector_ver` of the touched sectors;
   - updates `walk[t]` and `breach[t]` for each team;
   - relabels only the touched sectors in `regions[t]` (≈0.04 ms per sector) and refreshes portal connectivity.

   Sites stamp on placement, so foundations block too.
3. **Per-team passability:**

   | Cell | `walk[t]` | `breach[t]` |
   |---|---|---|
   | static | solid | solid |
   | own structure | solid | solid |
   | own gate | free | free |
   | enemy structure, wall or gate | solid | weight `W_BREACH = 4` |
   | soft / water | weighted | weighted |

4. **Request algorithm** (served FIFO under the count budget):
   - **a. Snap** both ends to `nearest_passable(team)`.
   - **b. Reachable** (`regions[t]` same component):
     - Corridor = sector path from Dijkstra on the region graph (hundreds of nodes).
     - If the corridor spans ≤ 2 sectors: one `walk[t].get_id_path`.
     - Otherwise: refine sector by sector, with `get_id_path` between consecutive portal cells (each search is short: 6–13 µs measured), then concatenate.
     - This removes the measured 7–15 ms detour spikes.
   - **c. Not reachable, and enemy structures exist:**
     - Run `breach[t].get_id_path` (w = 4: ≤ 0.94 ms at 400², measured).
     - The first enemy structure cell on the path gives `breach_b`; `breach_wp` is the waypoint before it.
     - This is TZ §6: «враг ищет обход, а если его нет — ломает ближайшее звено или ворота».
   - **d. Not reachable, no enemy structures** (own enclosure without a gate, terrain): path to the start component's cell nearest to the goal; `no_route = true` (UI note «Нет прохода»).
   - **e. Smoothing:** string pulling with grid line of sight through weight-1 passable cells only.
   - **f. Optional tuning knob [Свободно]:** `rules.breach_ratio` (default 0 = off). When the corridor cost exceeds `ratio × octile`, the breach path is compared too.
5. **Budget:** `rules.path_per_tick = 16` requests and `rules.path_cells_per_tick = 8000` estimated cells (sum of octile estimates). Unserved tickets wait in FIFO order. Same result on any CPU.
6. **Repath triggers:**
   - `PathResult.stale` (a traversed sector's version changed);
   - `ev_repath` (next waypoint inside an obstacle, or the breach target destroyed);
   - no progress for 2 s;
   - attack target moved more than 8 m.
7. **Groups:**
   - one request per squad;
   - singles ordered together share one request from their centroid;
   - each single's last waypoint is its grid slot around the goal (1.5 m pitch).
8. **Workers:**
   - a commute cache keyed by `(node cell, drop cell, team)`, valid while the sectors on it are unchanged;
   - the return trip uses the reversed path.
9. **Formations through gates:** a member whose slot is blocked follows `sq_trail` (§6.2 R7). Auto-column on narrow corridors comes later.
10. **Not in GDScript:** flow fields (A measured 18 ms per full field). They arrive with C++ `NavCore` (HPA* + flow fields, integer costs, cross-platform).

---

## 10. Расстановка и стены (placement, wall tool)

**Rules** (data `place`, all evaluated by `NavApi.check_place`; the authoritative call from ECON and the ghost call are the same):
- inside the map;
- no overlap with stamped cells, nodes or other footprints;
- height spread over the footprint corners ≤ `max_slope` (1.2 m default);
- `water: false`;
- `territory` (within the radius of own HQ / territory buildings);
- `near` (ken: ≤ 26 m from stone/gold);
- `on_wall` (gate: on an own wall line, rotated to it, replaces links under it; tower: replaces links under its footprint);
- `across_river` (dam);
- own units inside the footprint are pushed out on placement; enemy units inside reject it (`ENEMY_UNITS`).

**Rotation:**
- Rectangular buildings use quarter turns (`rot_q`).
- Round yurts take a visual yaw from a hash of the handle.
- Footprints snap to cells (§6.4).

**Wall tool (TZ §6):**
- LMB sets the start; each next LMB adds a point and continues from the end; RMB or Esc finishes.
- This sends `SimCmd.build_wall(ids, wtype, pts)`.
- `plan_wall` places link centers at pitch `len − overlap` (devor/tosh 3.2 m, chep 3.0 m) and returns per-link `why` and the total cost.
- ECON creates one `SITE` building per link with a shared `chain` id. Workers build link after link in chain order («звено за звеном»).
- The ghost shows each link green or red.

---

## 11. Экономика (economy)

**Generic components.** Each faction mechanic is data plus one small system:

| Component (data key) | System file | Covers |
|---|---|---|
| `drop`, `accepts` | `workers.gd` | Drop-off at the nearest accepting building |
| Node (`node_defs`) + gather rates | `workers.gd` | Trees (100 wood; felled → `TREE_FELLED` → view hides the tree), stone 4000, gold 3000, clay |
| `work` (field slots) | `workers.gd` | Dala: 4 workers, infinite food, carry to tegirmon/urda |
| `recipes` | `production.gd` | Kiln clay → brick; felt yard wool → felt (later: Dzungar iron/powder) |
| `trains` + queue | `production.gd` | Hiring one by one, rally, pop reservation |
| `pop_cap`, upkeep | `population.gd` | Cap = min(500, Σ ACTIVE); 0.7 food/min per soldier; famine → `set_owner_mods` |
| `herd` (pen) | `herds.gd` | Sheep: food + wool per head × grass. Horses: the backing stock for the `horse` resource. Growth; theft. |
| Grass and water fields | `fields.gd`, `network.gd` | Pasture trampling/regrowth, `PASTURE_LOW`. Aryk networks: BFS from dam/river sources to coverage; dam destroyed → recompute. |
| `aura` | `workers.gd` | Ken: gathering +50% within 26 m |
| `passive` | `population.gd` | Tax (bazaar levy on population), koroo passive yield |
| Market | `exchange.gd` | `TRADE` with spread and deterministic drift |
| `packable` | `nomad.gd` | Köч: pack, pack_all within 170 m, unpack on ring slots (pop 0 in transit) |
| Bounty | `bounty.gd` | Olzho: 4 g + 6 f per kill, 10 + 10 per worker, a share of building cost, 400 g for an HQ |
| Calendar + modifiers | `calendar.gd`, `modifiers.gd` | Seasons jailoo/kyshtoo (Kipchak trait), famine, compiled into `PlayerTable.stat` |
| Spawner/Carrier, Tech (stage 3) | `convoy.gd`, `tech.gd` | Qing silver/rice convoys from the map edge (interceptable); smithy, flintlock; Dzungar faith |

**Worker job machine.** It runs at 10 Hz, staggered so that `worker_index % 3 == tick % 3`, and moves bodies only through `CombatPort`.

```
IDLE ─gather─► TO_NODE (reserve one of 8 ring spots, first free by index) ─arrive─► GATHER
  GATHER: port.set_work(u, node aux: 0 chop / 0.25 dig); every period carry += rate × aura × stat; node.amount −= …
     ─carry full / node empty─► TO_DROP (nearest accepting own building; set_work 0.75 while walking)
     ─arrive─► deposit (RES_DELIVERED) ─► TO_NODE (same node; else nearest of its kind ≤ 40 m; else IDLE + WORKER_IDLE)
IDLE ─build─► TO_SITE (perimeter spot) ─► BUILD (aux 0.5; progress += rate × n^0.75 / build_ticks; hp grows with progress)
     ─done─► resume w_prev_* (TZ: «возвращается к прежней работе»), else IDLE
FARM: field slot (≤ 4) → produce into carry → carry to tegirmon/urda → back to the same slot
Under attack: DEFENSIVE stance in the kernel (retaliate, no chase); the job resumes when no enemy is within 12 m.
```

**Production:**
- Cost is paid on enqueue and refunded on cancel. The queue holds at most 5.
- The head reserves pop when it starts. If `used + reserved + pop > cap`, the queue pauses and emits `POP_CAPPED`.
- A physical cost (`horse: 1`) removes a head from the nearest own horse herd.
- The unit spawns at the door (the +Z face rotated by `rot_q`, via `nearest_passable`) and goes to the rally point.
- Officers spawn as singles; `FORM_SQUAD` builds squads.

**Upkeep and famine:**
- Each second, `Σ upkeep_milli_min / 60` is charged, with remainders carried in `rate_acc`.
- When food would go below 0: food is set to 0, `famine = 1`, `FAMINE` is emitted, and `set_owner_mods(p, famine)` applies (attack ×0.75, speed ×0.9, no morale regen).
- Famine ends when food reaches one minute of upkeep.

**Herds and theft:**
- A herd is a count at a pen, with `graze_r`. Output = per head × average grass under the herd.
- Theft:
  - Trigger: enemy `RAIDER` or mounted units within 12 m, and no armed owner unit within 25 m, for 3 s.
  - Effect: up to 10 heads per raider become a `DRIVEN` herd that follows the captor (`HERD_STOLEN`).
  - If the captor dies, the driven herd walks back to its pen (`HERD_RETURNED`). On retreat it is banked by the raider's owner.

**Köч:**
- `pack(b)`:
  - state becomes `PACKED`;
  - `nav.unstamp` and `port.structure_clear`;
  - the pop cap is removed;
  - an `arba` single is spawned with `arba_cargo`.
- `pack_all(hq)` packs every packable within 170 m. The ordo's arba makes `Victory` watch it.
- `unpack(arbas, center)`:
  - `nav.ring_slots` around the center, avoiding trees and buildings;
  - each arba drives to its slot;
  - on arrival the building becomes a `SITE`, self-erecting over `unpack_s` (boz 12 s). Workers speed it up.

---

## 12. ИИ набегов (raid AI, TZ §7)

`RaidDirector` runs in-sim at 1 Hz, phase-staggered, with its own `BattleRng`. It reads `GameQuery` and writes `SimCmd` only.

1. **Peace period.** It lasts `AiDefs.RAID.peace_s[difficulty]` (5/8/12 min). After that, waves come every 150–240 s, each `growth` (×1.25) larger, up to `max_wave`.
2. **Warning.** `RAID_WARNING(eta)` fires 30 s before a wave and drives the top-bar timer.
3. **Muster.** The wave is spawned with `Op.SPAWN` at the AI base door, or at an edge marker, with an officer per 100. Economic AI is TZ §16.2, stage 3.
4. **Target choice.** A heat map of the enemy's assets in 32 m cells:
   - Score = Σ raid values (worker 5, herd 4, field 3, store 3, house 1, HQ 0.5) − tower coverage × `tower_penalty` − defenders within 60 m.
   - Ties go to the lowest cell index.
5. **March.** `ATTACK_MOVE` along a breach-aware path, through NAV.
6. **Strike.** Squads attack-move. `RAIDER` units prefer workers (kernel R9) and trigger herd theft (ECON). With no targets left, they attack structures (fields first).
7. **Retreat.** At 50% losses, when defenders outnumber the wave 1.5×, or at the time limit, the wave goes back to the edge. Survivors despawn with their loot and stolen herds credited. `RAID_ENDED` is emitted.

`GarrisonAi` covers the AI base:
- squads hold near the HQ;
- enemies inside the base radius send the nearest idle squads to attack;
- stage 2: two towers garrisoned with archers (TZ §7).

Battle AI (artillery on clusters, circling horse archers) is added later as per-squad behaviours on the same command path.

---

## 13. Отображение (view integration)

- **`UnitView extends BattleView`.** It reuses `_human_custom`/`_rider_custom` and replaces `_rebuild`/`_update_battle`:
  - Dynamic slots: `slot_of[u]` per visual layer and `unit_of_slot`, with swap-remove so `visible_count` stays compact. A `u_gen` change or `FREE` releases the slot, so no spawn events are needed.
  - Layers start at 512 instances and are re-`setup` at double capacity when full.
  - `Act.WORK` maps to `AnimSpec.Human.WORK` with aux `u_work`. Aux 0.75 while moving uses the WALK phase by distance (row 22).
  - Corpses sink during the last 3 s before recycling.
  - Garrisoned units are drawn on `st_top`.
  - Arbas are drawn as a dynamic instance of `kipchak/arba.glb` until the crowd "wagon" skeleton lands.
  - Only units within the camera rect plus 40 m are updated every frame; the rest every 4th frame.
- **`BuildingView` and `BuildingLook`:**
  - `BuildingLook` is a copy of the `KipchakCamp._setup_model` LOD, ground-hiding and tündük smoke logic; the slice camp is untouched.
  - **Model lookup** (matches the art worktrees):
    1. `scenes/<faction>/<id>.tscn` if present;
    2. otherwise `assets/models/<faction>/<id>.glb` with `<id>_lod1.glb`;
    3. `SITE` uses `<id>_site.glb`; `RUIN` uses `<id>_ruin.glb`; wall chain ends use `<id>_end*.glb`;
    4. if missing, a painterly box sized from `size`.
  - `render: "scene"` gives one node per building. `render: "multimesh"` (wall links, aryk, uy, boz, chep) uses one MultiMesh per (model, 128 m cell), like `WorldScatter`.
  - Damage above 50% adds fire and smoke FX.
- **`NodeView`:**
  - `TREE_FELLED` calls `WorldScatter.hide_tree(kind, index)`, plus a stump.
  - Deposits use 3 depletion stages.
  - Needs a World-area edit by VIEW, signed off by the lead: build a `(kind, index) → (MultiMesh, instance)` map in `_build_kind` and zero-scale both LODs.
- **`FieldView`:** `GrassField.set_mask(tex: Texture2D)` takes an R8 mask at 4 m per pixel (0 under footprints and fields, otherwise the grass value), so trampled pasture is visible. It replaces the 48-clearing limit in the city; the slice keeps its clearings. Updated ≤ 1 Hz when dirty. Irrigated fields get a lush tint.
- **`HerdView`:** `min(heads, 80)` flock actors per herd, using the `BattleAmbient` wander code, seeded by the herd handle. Drawn through its own `sheep`/`horse` CrowdLayers. A driven herd follows the herd position, which ECON moves after the captor.
- **`GhostView`:** translucent model + per-cell colours from `place_cells` + wall chain preview + gate/tower snapping. API for UI: `show_building(btype, center, rot_q, cells)`, `show_wall(plan: Dictionary)`, `hide()`.
- **`SelectionView`:** unit rings (`ui_ring.gdshader`), squad plates (`SquadBars` look), building outline + HP bar, rally flag (`tug.glb`). It reads `SelectionModel`.
- **FX:**
  - `BattleFx` is reused unchanged through `SimDriver` signals.
  - `CityFx` reads `SimEvents`: building hit dust, collapse smoke, tree-fall chips, floating loot and resource text on paper.
  - Stage 2: `missile` arcs.

---

## 14. Интерфейс и управление (UI, input; TZ §10, §12)

### Layout

**Layout source:** the author's screenshot reference (the relayed answer «на скрине»). The lead attaches it to UI's brief. **UI's first deliverable is one mock frame for the author's approval** (TZ appendix B).

| Area | Contents |
|---|---|
| **Top beam** (walnut, brass rivets) | • Resource chips generated from `FactionDefs.ui_res`: 4 common + 1–2 unique (Кирпич / Кони, Войлок), with income per minute on hover.<br>• «Население 112 / 175».<br>• «Набег через 2:30» (from `RAID_WARNING`).<br>• Season badge for Kipchak («Жайлоо»).<br>• Menu, pause, speed. |
| **Bottom panel** (faction ornament belt on top) | Kokand: turquoise tiles with eight-pointed stars. Kipchak: red felt with «кочкор мүйүз».<br>• **Minimap:** old-map tint, team dots, camera frustum; LMB moves the camera, RMB gives an order.<br>• **Info:** unit card / squad cards (banner, morale, stamina) / multi-select grid, or the building panel (HP, queue with progress, train buttons with cost and the disabled reason in Russian, rally, recipe, herd and grass for koroo, irrigation for dala).<br>• **Order grid** with hotkey labels.<br>• **Build tabs** «Хозяйство» / «Укрепления». |
| **Notes** | Paper with a wax seal. Red: `RAID_STARTED`, `BUILDING_DESTROYED`, `FAMINE`, `CMD_REJECTED`. Green: `BUILDING_DONE`, `TRAINED`, `LOOT`. Gold: `POP_CAPPED`, `PASTURE_LOW`, `NOT_ENOUGH`, `SEASON`. Clicking a note moves the camera. |
| **Other** | Arrowhead cursor with context variants. Fonts: Cormorant Unicase + Alegreya (OFL, added by the lead). Strings: `tr("…")`. UI refresh at 4–10 Hz; minimap at 4 Hz. |

### Input (`RtsInput`; InputMap actions are added by the lead)

| Input | Effect |
|---|---|
| LMB / box / double-click | Select / own units in the box / same type on screen |
| RMB | Context, decided by the kind of handle under `GameQuery.pick` and the selection:<br>• enemy → ATTACK<br>• node or own field with workers → GATHER<br>• own site or damaged building → ASSIST<br>• own tower/gate with infantry → GARRISON (stage 2)<br>• ground → MOVE |
| RMB drag | MOVE_LINE (frontage and facing) |
| Double RMB | Run / gallop |
| Shift | Queue |
| F / H / G / R / V / U | Formation cycle / STOP / KACHYP / fire–melee / WAR_CRY / FORM_SQUAD or DISBAND |
| K / Shift+K | PACK / PACK_ALL; K with arbas selected = UNPACK at the cursor |
| `.` | Cycle idle workers |
| Ctrl+1…9 / 1…9 | Set / recall group (double tap centers the camera) |
| P, + / −, M | Pause, speed, sound (local) |
| Placement mode | Ghost follows the cursor; wheel or R rotates 90°; LMB places (selected workers, else nearest idle); Shift keeps placing; wall tool as in §10 |
| Camera | `RtsCamera` gets `presets_enabled` (false in the city; presets move to F5–F8) and ignores edge pan over the HUD. In the city, R is fire/melee, not the slice's restart. |

---

## 15. Тесты (headless)

Run with `godot --headless --path . --script res://tests/X.gd`. `tests/run_all.sh` runs them all.

| Test | Owner | Checks |
|---|---|---|
| `test_sim.gd`, `test_view.gd` (existing) | CORE | **Unchanged and passing** (slice regression gate) |
| `test_defs.gd` | Lead → ECON | Schema and cross-references; TZ 11.6 sizes; `UnitEcon` ≡ `UnitStats` cost/time; defs hash stable |
| `test_combat_city.gd` | CORE | • 5000 random spawn/kill/recycle operations: handles invalidated, `n` bounded<br>• Form 100 + officer + banner, disband to singles<br>• 1000 idle singles ≤ 2 ms/step; 1213 melee not slower than the base<br>• Path following never enters obstacles in 60 s<br>• Structure DPS within ±10% of the formula<br>• Workers (DEFENSIVE) never chase beyond 6 m<br>• Ev buffers: one death record per death |
| `test_nav.gd`, `test_placement.gd`, `test_wall_tool.gd` | NAV | • Own gate passes, enemy gate blocks<br>• Enclosed goal: breach target is a link, ≤ 1.5 ms at 400²<br>• Wall across the map with a far gate: detour found, ≤ 3 ms at 400²<br>• 1000 random diagonal walls: no leaks<br>• Stamp marks traversed paths stale<br>• Ken ≤ 26 m; slope/water/overlap reasons; gate replaces links<br>• Budget: 64 requests over 4 ticks give an identical service order and results across runs |
| `test_econ_gather.gd`, `_build.gd`, `_pop_upkeep.gd`, `_herds_fields.gd`, `_nomad.gd`, `_recipes.gd`, `_determinism.gd` | ECON | Income within ±10% of an analytic trip model computed **from defs** (never hard-coded); 100 soldiers × 0.7 = 70 food/min ±1; famine toggles; `PASTURE_LOW`; kiln and felt; köч pack → pop 0 → unpack restores; bounty values; aryk dam destroyed → yield drops; 500 workers ≤ 1 ms/tick; two runs give the same checksum. All on `CombatPortStub` + `NavStub`, then rerun on real CORE + NAV at I2. |
| `test_game_determinism.gd`, `test_orders.gd`, `test_raid.gd`, `test_replay.gd` | GAME | • 15 min AI-vs-scripted ×2: identical checksum logs<br>• Replay from the log equals the live run<br>• Encode/decode round trip<br>• Rejected commands (stale, foreign, unaffordable) produce `CMD_REJECTED`<br>• First raid at peace end ±2 s per difficulty<br>• ≥ 60% of raider kills are workers or herds while they exist<br>• Retreat at the loss threshold<br>• Defeat on HQ loss and on ordo-arba loss<br>• AI ≤ 0.3 ms/tick average |
| `test_unit_view.gd`, `test_building_view.gd` | VIEW | Slot compaction invariants over 10k random spawn/free operations; WORK/CARRY mapping; MultiMesh counts after place/destroy |
| `test_input.gd`, `test_ui_bind.gd` | UI | Synthetic `InputEvent` sequences → exact `SimCmd` arrays (RMB context matrix, double RMB, drag line, wall tool LMB-LMB-continue, Ctrl+N groups); the top beam shows each faction's unique resources from defs; no hard-coded resource list |
| `tools/skirmish_headless.sh N` | GAME | AI-vs-AI batch for balance (TZ §14 «автобои») |

Look checks: shot series via `tools/shot.sh` on `scenes/gorod/gorod.tscn` and `scenes/test/gorod_look.tscn` (VIEW), at 1920×1080 and 1280×720.

---

## 16. Производительность (perf plan: 1000+ units, ~200 buildings, 30 Hz)

**Baselines on this VM:**
- 1213 melee: 14–15 ms avg, 30–32 ms worst.
- 1000 idle in squads: 13.6 ms.
- 1000 idle singles after the fast path: 11.6 ms.
- `BattleView` fill for 1020 units: 3.3 ms/frame.

| System | Target avg (p99) | How |
|---|---|---|
| Kernel, city at rest (≈600 workers mostly working, 300 soldiers holding, 100 moving) | ≤ 3 ms (5) | Sleeping (R12), singles fast path (R2), presence masks (`perf/quick-wins`), corpse recycling, `_spd` instead of `Terrain.is_water` |
| Kernel, big fight with 1000+ awake | GDScript ≈ 12–15 ms; **`BattleCore` ≤ 1.5 ms** | C++ port right after I1 |
| Economy | ≤ 1 ms (2) | 10 Hz staggered thirds (~170 worker thinks per tick at 500 workers); slow systems at 1 Hz and 0.2 Hz; event-driven buildings |
| Paths | ≤ 2 ms (4) | ≤ 16 requests and ≤ 8000 estimated cells per tick; corridor refinement; breach w = 4; commute cache; group paths |
| AI | ≤ 0.3 ms (1) | 1 Hz, staggered |
| Commands, events, checksum | ≤ 0.2 ms | |
| **Sim total at rest** | **≤ 6.5 ms (10)** | |
| View CPU (units + buildings + UI) | ≤ 4 ms/frame | Camera-rect culling for per-frame unit updates; static buildings; UI at 4–10 Hz; `CrowdPacker` (C++) if the units part exceeds 3 ms |
| Draw calls (PC, city, 1000 units) | ≤ 400 | MultiMesh for repeated buildings and wall links per 128 m cell; one atlas per side (CONTRACT §6); crowd layers as today. Phone budget (150–250) is met at quality «Низкое» later. |

**Later options:**
- **Phase 2 (optional):** run `GameSim.step()` on `WorkerThreadPool` between frames, with the view interpolating between published snapshots. Possible because the sim touches no Nodes. `Terrain._ensure()` must be called on the main thread at startup.
- **Perf gate:** `test_combat_city` and a `test_perf_city.gd` (GAME: 600 workers + 300 soldiers + 200 buildings + 100 links, 60 s) print avg/worst per system and fail above the targets. Run on the VM and on the author's PC (F9-style counter in the city HUD).

---

## 17. Граница C++ (C++ boundary)

| Order | Class (`native/ordo_core`, godot-cpp pinned to 4.7) | What moves | When |
|---|---|---|---|
| 1 | `BattleCore` | The whole `BattleSim`: hash, presence masks, squads, think, actions, integrate, separate, OBB collision, path following, structure targets, garrison. Same SoA names exposed as packed getters, same methods, same drained buffers. | Right after I1, when CORE freezes the `BattleSim` API (perf track) |
| 2 | `CrowdPacker` | Packing kernel arrays into CrowdLayer buffers (`set_raw_buffer`) | If view units exceed 3 ms/frame |
| 3 | `NavCore` | Integer-cost A*/HPA* + flow fields, replacing `AStarGrid2D` (cross-platform determinism) | Multiplayer stage |
| 4 | Deterministic math in `BattleCore` | LUT trig, `-ffp-contract=off`, no fast-math | Multiplayer stage |
| — | ECON, GAME, AI, orders, UI, view orchestration | Stay GDScript (10 Hz / 1 Hz logic) | |

**Rules that make the port a drop-in (enforced from now on):**
- **(a) No external writes and no upward calls.** Data comes in through methods; buffers go out.
- **(b) The C++ object owns its arrays.** Godot packed arrays passed into C++ and written through `ptrw()` are copied on write. Getters hand out refcounted copies, so consumers must take them into **locals per call** and never keep them in members (§5.2 rule 9); otherwise every kernel write copies the array.
- **(c) The GDScript `BattleSim` stays as the reference and the fallback.** It is loaded by path the way `BattleView` already loads `CrowdLayer`. C++ is validated by the same scenario assertions, not bit-exact against GDScript.
- **(d) Wrappers.** `CombatPortBattle` is the only caller of kernel mutators, so switching implementations touches one file.

---

## 18. Срез продолжает работать (slice compatibility)

- **Every new kernel setting defaults to the slice:**
  - `victory_mode = BATTLE`, `flee_mode = DIR`, `corpse_steps = −1`;
  - no structures and no terrain grids (the `Terrain.is_water` / dry-cache path);
  - hash bounds equal to today's on this map;
  - singles fast path only for `sq_single == 1`, which the slice uses only for the general. Behaviour is identical (row 3).
- **`SimDriver` extraction (M0)** is a type change only:
  - `ScenarioClash extends SimDriver`.
  - `BattleView`, `BattleFx`, `BattleHud`, `BattleRoot` and `BattleAmbient` retype `scenario` to `SimDriver`.
  - `SquadSelection` casts to `ScenarioClash` for `kok`/`kip`.
  - `CineCamera` stays typed to `ScenarioClash`.
  - `slice.gd` and `stress_scenario.gd` are unchanged.
- **Untouched:** `scenes/slice.tscn` remains the main scene. `BattleAmbient`, `KipchakCamp`, `World` and grass clearings are unchanged in the slice.
- **Gates** (lead checks at M0 and after every merge into `scripts/battle/`):
  - `test_sim.gd`, `test_view.gd`, `test_defs.gd` pass;
  - hero frames `--hero=9.8@CamVolley,14.3@CamImpact` compare equal before and after;
  - F9 stress is not slower.

---

## 19. Разбивка работ (work breakdown)

### 19.0 M0 — the lead creates these shared contract files first

Base: merge `perf/quick-wins` (bit-exact; `test_sim` checksum unchanged) **before** anything else.

| # | File | Exact content |
|---|---|---|
| 1 | `docs/CONTRACT.md` | • §8 owner rows for CORE, NAV, ECON, GAME, VIEW, UI (the folders in §4; `scripts/contract/*` is lead-only).<br>• New §10 «Город — симуляция»: the rules in §5.2, the handle format (§6.1), the command and event conventions (§7.7, §8), the model naming (§13). |
| 2 | `scripts/contract/ids.gd` | `Ids` exactly as §6.1 |
| 3 | `scripts/contract/sim_cmd.gd` | `SimCmd`: `Op`, header constants, all constructors, `validate_shape`, `encode`/`decode`, `cm`/`mrad`/`arg*` (§8). Complete, not a stub. |
| 4 | `scripts/contract/sim_events.gd` | `SimEvents`: `Ev`, ring buffer, `push`/`range_since`/`at` (§7.7). Complete. |
| 5 | `scripts/contract/defs.gd` + `scripts/data/*.gd` | `Defs` exactly as §6.4, compiling all data files.<br>Data files with the frozen schema and TZ §3, §5, §6 seed values; ECONOMY.md items present with `"enabled": false` until numbers land.<br>`MapValley.MAP` seeded from CONTRACT §3 and `Terrain.marker`. |
| 6 | `scripts/contract/combat_port.gd`, `combat_port_stub.gd` | `CombatPort` §7.1 (methods `push_error` and return defaults).<br>`CombatPortStub`: kinematic arrays (positions, owner, team, type, alive); straight moves at `UnitStats` speed; arrivals on reach; `kill()` feeds `take_deaths`; structure set/clear recorded; `battle()` returns null. |
| 7 | `scripts/contract/nav_api.gd`, `path_result.gd`, `nav_stub.gd` | `NavApi` §7.2, `PathResult`.<br>`NavStub`: everything passable; `request` returns `[goal]`; `reachable` true; placement = map bounds + overlap of stamped rects; `plan_wall` = straight pitch. |
| 8 | `scripts/contract/econ_api.gd`, `econ_stub.gd` | `EconApi` §7.3.<br>`EconStub`: tables created; `add_player` with start resources; `place_site` returns handles and records; queries return defaults. |
| 9 | `scripts/contract/{player,building,node,herd}_table.gd` | §6.3 exactly (arrays, enums, `handle`/`valid`/`slot`) |
| 10 | `scripts/contract/game_query.gd`, `fake_city.gd` | `GameQuery` §7.5.<br>`FakeCity`: a real `BattleSim` with a Kokand town and a Kipchak camp:<br>• 3 squads, 40 singles walking scripted loops, 10 with `set_work`-equivalent flags (`u_act = WORK`), one squad fighting;<br>• tables filled with TZ-sized buildings (sites at several progress values, ruins);<br>• trees and deposits, 2 herds;<br>• resources ticking;<br>• events pushed on a timer (`BUILDING_DONE`, `TRAINED`, `RAID_WARNING`, `FAMINE`, `LOOT`). |
| 11 | `scripts/contract/selection_model.gd` | `SelectionModel` §7.6 (storage + signal; UI adds behaviour in `scripts/input/selection_impl.gd`) |
| 12 | `scripts/battle/sim_driver.gd` + retypes | `SimDriver` §7.6; `ScenarioClash extends SimDriver`; the consumer retypes in §18. Afterwards owned by CORE. |
| 13 | `scripts/battle/sim.gd` — **declarations only** | • Append `Life.FREE` and `Act.WORK`.<br>• Add `Stance`, `Victory`, `FleeMode`, `MAX_TEAMS`, `ST_*`, `MOD_*`.<br>• Declare the new arrays of §6.2, appended in `_new_unit`/`_new_squad` with defaults (`u_gen 1`, `u_owner = side`, `u_work −1`, `u_garrison −1`, `sq_owner = side`, `sq_stance AGGRESSIVE`, …).<br>• Size `side_init`/`side_flee_t`/`general` to `MAX_TEAMS`.<br>• No behaviour change; `test_sim` checksum identical. Afterwards owned by CORE. |
| 14 | `scripts/units/anim_spec.gd` | Constants `WORK_CHOP := 0.0`, `WORK_DIG := 0.25`, `WORK_BUILD := 0.5`, `WORK_CARRY := 0.75`; `enum Wagon { IDLE, ROLL, DYING, DEAD }` for the arba skeleton (Units implements it in the shader later) |
| 15 | `scripts/world/scatter_data.gd` | `class_name ScatterData`, static, headless: `static func trees() -> Array` returning `[kind, index, x, z]` in file order (poplar, willow, juniper, elm). The source of `scatter_ref = kind << 16 \| index`. |
| 16 | `tests/sim_harness.gd`, `tests/run_all.sh` | `make_game(players, rules_id) -> GameSim`, `run_s(game, s)`, `check(ok, what)`, `check_range(v, lo, hi, what)`, `flat_spot()` (meadow 90, 0) |
| 17 | `project.godot`, `assets/ui/fonts/` | InputMap actions `ordo_select, ordo_order, ordo_stop (H), ordo_formation (F), ordo_kachyp (G), ordo_fire_mode (R), ordo_war_cry (V), ordo_squad (U), ordo_pack (K), ordo_idle_worker (.), ordo_group_1..9, ordo_pause (P), ordo_speed_up (+), ordo_speed_down (−), ordo_mute (M)`; fonts Cormorant Unicase + Alegreya (OFL, Cyrillic) |

**M0 gate:** `test_sim`, `test_view`, `test_defs` pass; slice hero frames unchanged; every package compiles against the stubs.

### 19.1 P1 CORE — combat kernel

- **Owns:** `scripts/battle/*` (sim.gd, unit_stats.gd, combat_port_battle.gd, scenario_clash.gd, sim_driver.gd after M0, the rest of the Battle area), `tests/test_sim.gd`, `tests/test_view.gd`, `tests/test_combat_*.gd`, later `native/ordo_core/` (with the perf track).
- **Provides:**
  - R1–R15 (stage 1) and R16–R18 (stage 2) from §6.2.
  - `CombatPortBattle extends CombatPort` (§7.1).
  - The frozen kernel API document (a section in `docs/CONTRACT.md` via the lead) for `BattleCore`.
- **Consumes:** `Ids`, `Defs`, `NavApi` (paths, `static_grid`, `speed_grid`). Uses `NavStub` until I1.
- **Acceptance:** §15 CORE rows. Slice gates (§18).
- **Art:** none.

### 19.2 P2 NAV — grid, paths, placement, walls

- **Owns:** `scripts/nav/*`, `tests/test_nav*.gd`, `tests/test_placement.gd`, `tests/test_wall_tool.gd`.
- **Provides:** `NavGrid extends NavApi`, together with `Regions`, `PathService`, `Raster` (supercover), `Placement`, `WallTool` behind it (§7.2, §9, §10).
- **Consumes:** `Terrain`, `Defs` (sizes, place rules), `EconApi` queries (`node_near`, `in_territory`, `wall_link_at`), `CombatPort.units_near` (enemy units in a footprint). Uses `EconStub` and `CombatPortStub`.
- **Stage 2:** gates and towers snapping to walls (`snap_on_wall`), breach selection, the optional `breach_ratio`.
- **Acceptance:** §15 NAV rows. Memory of 2 teams × (walk + breach) at 400² is reported (gate ≤ 96 MB). Identical results across runs.
- **Art:** none.

### 19.3 P3 ECON — economy and data values

- **Owns:** `scripts/econ/*`, the values in `scripts/data/{unit_econ,resource_defs,building_defs,node_defs,herd_defs,recipe_defs,faction_defs,modifier_defs}.gd` and the economy keys of `game_rules.gd`, `tests/test_econ_*.gd`, `tests/test_defs.gd` (after M0).
- **Provides:** `EconomySim extends EconApi` with every component in §11; fills the four tables; the economy events; `building_panel`/`build_menu` data.
- **Consumes:** `CombatPort` (spawn, move, set_work, structure mirror, owner mods, deaths, hits, arrivals), `NavApi` (stamps, placement, `ring_slots`, `nearest_passable`), `Defs`, `ScatterData`. Uses the stubs until I2.
- **Stage 2:** wall sites and chains, `ASSIST`/repair, garrison counts, AI-base towers' data.
- **Stage 3:** convoys, tech, faith.
- **Acceptance:** §15 ECON rows.
- **Art:** none (consumes model ids only).

### 19.4 P4 GAME — shell, commands, orders, AI, victory, map, replay

- **Owns:** `scripts/game/*`, `scripts/game/ai/*`, the values of `scripts/data/{ai_defs,map_valley}.gd` and the non-economy keys of `game_rules.gd`, `tests/test_game_*.gd`, `tests/test_orders.gd`, `tests/test_raid.gd`, `tests/test_replay.gd`, `tests/test_perf_city.gd`, `tools/skirmish_headless.sh`.
- **Provides:** `GameSim`, `CommandQueue`, `Orders`, `Victory`, `MapSetup`, `Replay`, `GameDriver extends SimDriver`, `GameQueryImpl extends GameQuery`, `AiController`, `RaidDirector`, `GarrisonAi` (§7.4, §8, §12).
- **Consumes:** `CombatPort`, `NavApi`, `EconApi` (stubs first, real implementations at I3), `SimCmd`, `SimEvents`, `Defs`.
- **Acceptance:** §15 GAME rows.
- **Art:** none.

### 19.5 P5 VIEW — world-space presentation

- **Owns:** `scripts/view/*`, `shaders/view/*`, `scenes/gorod/*`, `scenes/test/gorod_*`, `tests/test_unit_view.gd`, `tests/test_building_view.gd`.
- **Agreed small World-area edits** (lead signs off): `scripts/world/world_scatter.gd` (`hide_tree`, id map), `scripts/world/grass_field.gd` + `shaders/grass.gdshader` (`set_mask`).
- **Provides:** `UnitView`, `BuildingView`, `BuildingLook`, `NodeView`, `HerdView`, `FieldView`, `GhostView` (`show_building`, `show_wall`, `hide`), `SelectionView`, `OverlayView` (HP plates, rally flags, floating text), `CityFx`, and the scene `scenes/gorod/gorod.tscn` (World + GameDriver + views + BattleFx + RtsCamera + CityHud + RtsInput).
- **Consumes:** `GameQuery` (`FakeCity` until I4), kernel arrays, `SimEvents`, `SimDriver` signals, `SelectionModel`, the art below. Runtime placeholders replace missing models.
- **Acceptance:**
  - §15 VIEW rows.
  - Shot series of `gorod.tscn`: sites at 3 progress stages, wall line, ghost green/red, worker chop/dig/build/carry, selection.
  - With 1000 units and 200 buildings: view CPU ≤ 4 ms/frame, ≤ 400 draw calls.
  - Slice frames unchanged.
- **Art needed:**

  | Group | Items |
  |---|---|
  | Kokand (`art-kokand`) | Walls, gate and tower are done (`devor`, `tosh`, `darvoza`, `burj` with `_site`/`_ruin`/`_end`). Still needed: `urda`, `uy`, `dala` (3 crop stages), `tegirmon` (separate wheel node), `ombor`, `kazarma`, `otxona`, `topxona`, `bozor`, `xumdon` (kiln, smoke marker), `aryk` link (straight/corner/sluice), `togon` dam, all with `_lod1`/`_site`/`_ruin`. |
  | Kipchak (`art-kipchak2`) | Done: `ken`, `jooker`, `kurultai`, `chep`, `darbaza`, `munara`, `munara_arba`. Still needed: `kiyiz` felt yard; a burnt-yurt `boz_ruin`; `_site` for `boz`/`ordo`/`koroo`/`jylky` (kerege lattice stage). |
  | World nodes (World area) | Stone outcrop and gold vein (3 depletion stages each, distinct silhouettes TZ 11.2), clay pit, tree stump |
  | Units (Units area) | `kok_dehqon` and a `kip_malchy` retrofit with tools chosen by WORK aux (axe, ketmen, hammer, sack; crowd shader "tool" mode on UV2.y, CONTRACT §7). `kip_arba` as a crowd "wagon" skeleton with turning wheels. Military visuals now `""`: first `chabuulchu`, `atchan`, `kamonchi`, `nayzachi`, then the rest. |

### 19.6 P6 UI — HUD and input

- **Owns:** `scripts/ui/city/*`, `scripts/input/*`, `assets/ui/*`, `tools/gen_ui*.py`, `tests/test_input.gd`, `tests/test_ui_bind.gd`.
- **Agreed edit:** `scripts/camera/rts_camera.gd` (`presets_enabled`, HUD-aware edge pan); the slice camera is regression-checked.
- **Provides:** `CityHud` (top beam, bottom panel, minimap, build tabs, cards, building panel, order grid, notes, cursor), `RtsInput`, `PlacementMode`, `ControlGroups`, the `SelectionModel` behaviour (§14).
- **Consumes:** `GameQuery` (`FakeCity` until I4), `SimCmd`, `GameDriver.issue`, `SimEvents`, `GhostView` API (a debug ghost stub until I4), `RtsCamera`.
- **Acceptance:**
  - §15 UI rows.
  - **First deliverable: one mock frame for the author per the screenshot reference.**
  - Shots of both factions at 1920×1080 and 1280×720; every string in Russian through `tr()`; author review «не сайт».
- **Art (procedural, `tools/paint.py`, CONTRACT §5):**
  - walnut and brass 9-slices;
  - «самаркандская бумага»;
  - two ornament belts;
  - wax seals (red, green, gold);
  - arrowhead cursor set;
  - resource icons (food, wood, stone, gold, clay, brick, horse, wool, felt);
  - order icons;
  - old-map minimap frame;
  - unit and building portraits rendered from the models with `tools/shot.sh`.

### 19.7 Integration order

| Step | What | Gate |
|---|---|---|
| **M0** | Lead: §19.0 | §19.0 gate |
| **Parallel** | P1–P6 against stubs. UI and the art tracks deliver their approval frames first. | Each package's own tests on stubs |
| **I1** | CORE + NAV: `CombatPortBattle` on the real `NavGrid` | `test_combat_city` with real nav → **freeze the `BattleSim` API → start `BattleCore`** (perf track) |
| **I2** | ECON on I1 | Econ tests rerun with real movement; tolerances come from defs |
| **I3** | GAME on I2 | Headless skirmish: determinism, replay, raids (no walls) |
| **I4** | VIEW + UI on I3 | **First playable `gorod.tscn`:** both factions; hire, gather, farm, build, population, upkeep/famine, herds/pasture, köч, olzho, squads form/disband, raids |
| **I5** | Art swap-in | Review frames for the author |
| **Stage 2 «Укрепления»** | NAV `snap_on_wall` + breach; CORE R16–R18; ECON wall chains + repair; VIEW wall MultiMesh + missile arcs; UI «Укрепления» tab + wall tool; GAME AI-base towers | `test_nav` breach cases; tower vs 20 chabuulchu; cannon splash damages links |
| **Stage 3** (author's order) | Qing and Dzungars as data + Spawner/Carrier/Tech; economic AI (TZ §16.2); phones; 2×2 multiplayer with `BattleCore` deterministic math + `NavCore` | |

### 19.8 Risks

| Risk | Mitigation |
|---|---|
| GDScript kernel too slow in big city fights (14–15 ms avg, ~30 ms worst at 1.2k) | Sleeping, singles fast path, presence masks, recycling now; `BattleCore` right after I1; optional sim thread |
| Path spikes (floods 19–69 ms, detours 7–15 ms) | Region graph reachability, corridor refinement, breach w = 4, count budget. NAV acceptance numbers enforce it. |
| Approved slice regresses | Declarations-only M0 edit, defaults = slice, unchanged tests and hero frames as the merge gate for `scripts/battle/` |
| `sim.gd` merge conflicts | Only CORE edits it after M0; everyone else uses `CombatPort` or reads arrays |
| Designer data churn (ECONOMY.md not written yet) | Generic components; numbers only in `scripts/data`; tests derive expectations from `Defs` |
| Formations jamming in gates | Trail following now; auto-column later; test: 100 sarboz pass a gate in < 60 s |
| Raids frustrating (killable workers, no flee per TZ) | 30 s warning, DEFENSIVE retaliation, towers at stage 2, data-tuned waves, «Тревога» bell [Свободно] |
| Cross-platform desync | Integer rules layer now; kernel and nav determinism in C++ at the multiplayer stage; checksums from day one |
| Art lag | Runtime placeholders from `size`; missing unit visuals fall back to the nearest existing one (`juz_bashy` → `kip_sayisker`, as today) |
| Key conflicts (slice R = restart, 1–4 = camera presets) | City scene uses TZ §10: R = fire/melee, digits = groups; presets on F5–F8 |
