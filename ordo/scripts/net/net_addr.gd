class_name NetAddr
extends RefCounted
## Адреса хозяина для друга (ТЗ §16 «Адреса хозяина»; владелец — NET): две строки лобби — «Radmin VPN» и «Дома».
##   Radmin — по имени адаптера («Radmin VPN») или по сети 26.0.0.0/8 (она не частная: проверка «частный / не
##            частный» положила бы её не туда). Не найден — «не установлен или выключен» (выключенный адаптер от
##            неустановленного не отличить).
##   Дома   — адаптеры Wi-Fi и Ethernet из 10/8, 172.16/12, 192.168/16, кроме vEthernet (Hyper-V, WSL), VirtualBox,
##            VMware, Radmin (и других виртуальных); осталось два — оба.
## Строки «Через интернет» в лобби нет (ловушка для новичка): адрес в интернете — только в справке (NetUpnp).

## Адаптеры не для «Дома»: виртуальные машины, контейнеры, чужие сети и Bluetooth (имена — подстроки, без регистра)
const NOT_HOME := ["vethernet", "hyper-v", "wsl", "virtualbox", "vmware", "radmin", "zerotier", "hamachi", "tailscale",
	"docker", "bluetooth", "loopback", "vpn", "tap-", "tun"]


## Свои адреса: {radmin: "26.…" или "", home: [адреса, не больше двух]} — по списку адаптеров
## (IP.get_local_interfaces: [{name, friendly, index, addresses}])
static func scan(interfaces: Array = []) -> Dictionary:
	if interfaces.is_empty():
		interfaces = IP.get_local_interfaces()
	var radmin := ""
	var home := PackedStringArray()
	for it: Dictionary in interfaces:
		var nm := (String(it.get("friendly", "")) + " " + String(it.get("name", ""))).to_lower()
		var is_radmin := nm.contains("radmin")
		var virt := false
		for w: String in NOT_HOME:
			if nm.contains(w):
				virt = true
				break
		for a: String in it.get("addresses", []):
			if not is_v4(a):
				continue
			if radmin == "" and (is_radmin or a.begins_with("26.")):
				radmin = a
				continue
			if not virt and is_private(a) and not home.has(a) and home.size() < 2:
				home.append(a)
	return {"radmin": radmin, "home": home}


## Четыре числа 0–255 через точку
static func is_v4(a: String) -> bool:
	var p := a.split(".")
	if p.size() != 4:
		return false
	for s in p:
		if not s.is_valid_int() or int(s) < 0 or int(s) > 255:
			return false
	return true


## Частная сеть дома: 10/8, 172.16/12, 192.168/16
static func is_private(a: String) -> bool:
	if not is_v4(a):
		return false
	var p := a.split(".")
	var x := int(p[0])
	var y := int(p[1])
	return x == 10 or (x == 172 and y >= 16 and y <= 31) or (x == 192 and y == 168)


## Адрес провайдера без своего адреса в интернете: частный или 100.64/10 (CGNAT) — «у вашего провайдера так не выйдет»
static func is_not_public(a: String) -> bool:
	if not is_v4(a):
		return true
	var p := a.split(".")
	var x := int(p[0])
	var y := int(p[1])
	return is_private(a) or (x == 100 and y >= 64 and y <= 127) or x == 127 or x == 0 or (x == 169 and y == 254) or x >= 224


## Адрес друга подходит: четыре числа, первое 1–223 (0.x, 224.x и выше — служебные, ENet по ним откажет сразу)
static func friend_ok(a: String) -> bool:
	return is_v4(a) and int(a.split(".")[0]) >= 1 and int(a.split(".")[0]) <= 223
