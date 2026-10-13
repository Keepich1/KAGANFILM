class_name FakeCityDriver
extends SimDriver
## Узел для сцен VIEW и UI до I4: шагает FakeCity как SimDriver (30 Гц, пауза, скорость, alpha) и отдаёт
## сигналы ядра для эффектов (BattleFx). Окно чтения — query (FakeCity extends GameQuery).
## После I4 сцена «Города» берёт GameDriver — тот же SimDriver, поэтому вид и интерфейс не меняются.
##
## Внимание: в FakeCity число юнитов ядра растёт (найм, новые налёты) — вид должен выделять места
## динамически (UnitView, ARCHITECTURE §13); старый BattleView для этого не годится.
##
## Ведущий (M0).

## Запускаться самому при входе в дерево (зерно — аргумент --seed=N или 1)
@export var autostart := true

var city: FakeCity
var query: GameQuery


func _ready() -> void:
	if Engine.is_editor_hint() or not autostart:
		return
	var s := 1
	var ordo := get_node_or_null("/root/Ordo")
	if ordo and ordo.has_arg("seed"):
		s = int(ordo.arg("seed"))
	start(s)


func start(p_seed: int) -> void:
	current_seed = p_seed
	city = FakeCity.new()
	city.setup(p_seed)
	query = city
	sim = city.sim
	_acc = 0.0
	alpha = 0.0
	wire_sim(sim)
	started.emit(p_seed)


func step() -> void:
	if city:
		city.step()


## Приказ от интерфейса (как GameDriver.issue): игрок 0
func issue(cmd: PackedInt32Array) -> void:
	if city:
		city.submit(0, cmd)
