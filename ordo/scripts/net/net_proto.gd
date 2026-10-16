class_name NetProto
extends RefCounted
## Протокол игры по сети (ТЗ §16 «Город по сети с другом»): порт, первый пакет сверки и сообщения партии.
## Владелец — NET (scripts/net/, CONTRACT §8).
##
## Порт один — 7777 (UDP), запасных нет (решение 2026-10-15). ENet: каналов CHANNELS, без сжатия — заданы раз и
## навсегда, как и первый пакет: иначе старая и новая игра не прочтут друг друга.
##
## ПЕРВЫЙ ПАКЕТ (SceneMultiplayer.send_auth) НЕ МЕНЯЕТСЯ НИКОГДА (решение 2026-10-16). Порядок байтов — старший
## первым (big-endian):
##   0   4 байта  знак «ORDO» (ASCII)
##   4   u16      номер протокола (PROTOCOL)
##   6   16 байт  номер версии, как у установщика («0.1.57»), UTF-8, добит нулями; «» — рабочая сборка
##   22  u32      дата сборки ГГГГММДД (20261015)
##   26  8 байт   код — начало суммы SHA-256 всей игры (NetVersion)
##   34  —        новое — только после этих полей. Протокол 1: u8 вид (HELLO / WELCOME / REFUSE) и поля u32:
##                HELLO   (подключившийся → хозяин): метка партии (0 — новый друг), Defs.hash (младшие и старшие 32 бита)
##                WELCOME (хозяин → другу: впустил): метка партии, 1 — это переподключение посреди партии
##                REFUSE  (хозяин → другу: не впустил): причина (Why)
## Пакет не разобрать (не тот знак, обрезан, другой номер протокола) — «Разные версии игры».
##
## После сверки — сообщения партии (SceneMultiplayer.send_bytes, надёжный упорядоченный канал 0): PackedInt32Array
## [вид, поля…] в байтах (одна и та же сборка у обоих — проверено сверкой). Виды — Msg.

const PORT := 7777
const PROTOCOL := 1
const MAGIC := "ORDO"
## ENet: каналов (без служебных Godot) и сжатие — раз и навсегда (ТЗ §16)
const CHANNELS := 2
const MAX_CLIENTS := 4
## Размер постоянной части первого пакета
const PREFIX := 34
const VER_BYTES := 16
const CODE_BYTES := 8

## Вид первого пакета (после постоянной части)
enum Auth { NONE, HELLO, WELCOME, REFUSE }
## Почему хозяин не впустил: другая версия; место занято (уже есть второй игрок); партии с такой меткой нет
enum Why { NONE, VERSION, BUSY, NO_MATCH }

## Сообщения после сверки
enum Msg {
	NONE,
	PING,       # [t_мс] — эхо PONG с тем же числом
	PONG,       # [t_мс]
	BYE,        # ухожу сам («Отмена», «Выйти», закрыл окно): дальше отключение — не «связь пропала»
	LOBBY,      # хозяин → другу: [сторона хозяина 0 — Коканд / 1 — кыпчаки, номер партии]
	START,      # хозяин → другу: [номер партии, сторона хозяина, карта, правила, задержка приказов]
	READY,      # игра загружена, симуляция на такте 0
	BATCH,      # [такт, подтверждено (сколько тактов друга получено подряд), флаги, значение, приказы SimCmd.encode…]
	RESUME,     # [такт паузы, игрок, вид: 1 — снять стоящую у обоих, 0 — отменить свою, ещё не наступившую]
	CHECK,      # [такт, младшие 32 бита суммы, старшие]
	SYNC,       # после переподключения: [свой такт, получено подряд от друга]
	REPLAY,     # [длина] + байты повтора (партия разошлась — повтор другу для разбора)
	MENU,       # [1 — открыл меню игры, 0 — закрыл] (записка «Друг открыл меню»)
}
## Флаги пакета такта: пауза после этого такта; скорость с этого такта (значение — скорость × 100)
const F_PAUSE := 1
const F_SPEED := 2

## Карта и правила в START — номерами (одна карта, одни правила «Города»)
const MAPS := ["valley"]
const RULES := [&"GOROD"]


# ================================================================= первый пакет

## Первый пакет: постоянная часть (info: {number, date, code}) + вид + поля u32
static func auth_packet(info: Dictionary, kind: int, fields := PackedInt64Array()) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.put_data(MAGIC.to_ascii_buffer())
	b.put_u16(PROTOCOL)
	var v := String(info.get("number", "")).to_utf8_buffer()
	v.resize(VER_BYTES)
	b.put_data(v)
	b.put_u32(int(info.get("date", 0)) & 0xFFFFFFFF)
	var c: PackedByteArray = (info.get("code", PackedByteArray()) as PackedByteArray).duplicate()
	c.resize(CODE_BYTES)
	b.put_data(c)
	b.put_u8(kind)
	for f in fields:
		b.put_u32(f & 0xFFFFFFFF)
	return b.data_array


## Разобрать первый пакет: {} — не разобрать (не тот знак, обрезан); иначе {protocol, number, date, code, kind,
## fields}. Другой номер протокола — kind = Auth.NONE (постоянная часть прочитана: версию друга видно)
static func read_auth(data: PackedByteArray) -> Dictionary:
	if data.size() < PREFIX or data.slice(0, 4).get_string_from_ascii() != MAGIC:
		return {}
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	b.data_array = data
	b.seek(4)
	var proto := b.get_u16()
	var vb := data.slice(6, 6 + VER_BYTES)
	var z := vb.find(0)
	if z >= 0:
		vb = vb.slice(0, z)
	b.seek(22)
	var date := b.get_u32()
	var out := {"protocol": proto, "number": vb.get_string_from_utf8(), "date": date,
		"code": data.slice(26, 26 + CODE_BYTES), "kind": Auth.NONE, "fields": PackedInt64Array()}
	if proto != PROTOCOL or data.size() < PREFIX + 1:
		return out
	b.seek(PREFIX)
	out["kind"] = b.get_u8()
	var f := PackedInt64Array()
	while b.get_position() + 4 <= data.size():
		f.append(b.get_u32())
	out["fields"] = f
	return out


# ================================================================= сообщения партии

static func msg(kind: int, fields := PackedInt32Array()) -> PackedByteArray:
	var a := PackedInt32Array([kind])
	a.append_array(fields)
	return a.to_byte_array()


## Пакет такта: [BATCH, такт, подтверждено, флаги, значение] + приказы (SimCmd.encode — те же int32)
static func batch(tick: int, ack: int, flags: int, value: int, cmds: Array[PackedInt32Array]) -> PackedByteArray:
	var a := PackedInt32Array([Msg.BATCH, tick, ack, flags, value])
	a.append_array(SimCmd.encode(cmds).to_int32_array())
	return a.to_byte_array()


## Сообщение с байтами в хвосте (повтор): [вид, длина] + байты, добитые до кратного 4
static func blob(kind: int, bytes: PackedByteArray) -> PackedByteArray:
	var out := PackedInt32Array([kind, bytes.size()]).to_byte_array()
	var tail := bytes.duplicate()
	tail.resize((bytes.size() + 3) / 4 * 4)
	out.append_array(tail)
	return out


## Сообщение → int32 (пустой массив — испорчено)
static func read_msg(bytes: PackedByteArray) -> PackedInt32Array:
	if bytes.size() < 4 or bytes.size() % 4 != 0:
		return PackedInt32Array()
	return bytes.to_int32_array()


## Байты хвоста blob
static func read_blob(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < 8:
		return PackedByteArray()
	var n := bytes.decode_s32(4)
	if n < 0 or 8 + n > bytes.size():
		return PackedByteArray()
	return bytes.slice(8, 8 + n)


## Приказы пакета такта (после пяти чисел заголовка)
static func batch_cmds(m: PackedInt32Array) -> Array[PackedInt32Array]:
	if m.size() <= 5:
		return [] as Array[PackedInt32Array]
	return SimCmd.decode(m.slice(5).to_byte_array())


## Сумма (до 40 бит) — в два int32 и обратно
static func split64(v: int) -> PackedInt32Array:
	return PackedInt32Array([v & 0xFFFFFFFF, (v >> 32) & 0xFFFFFFFF])


static func join64(lo: int, hi: int) -> int:
	return (lo & 0xFFFFFFFF) | ((hi & 0xFFFFFFFF) << 32)
