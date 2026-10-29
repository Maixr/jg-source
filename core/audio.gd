extends Node

## 音效播放：预加载 + 复音池 + 按名字节流 + 静音开关。
##
## 素材是 CC0（见 art/sfx/CREDITS.md）。想换音效只要把同名 .wav 丢进
## art/sfx/ 覆盖即可，代码不用动；缺哪个文件就静默跳过，不会报错。
##
## 静音状态存在 GameState 的 settings.json 里（和键位同一个文件）。

const SFX_DIR := "res://art/sfx/"
const POOL_SIZE := 16

## 高频事件的最小间隔（毫秒）。不节流的话交火时会糊成一片。
const MIN_GAP := {
	"hit": 55,
	"die": 45,
	"heal": 220,
	"place": 40,
	"ui_click": 30,
	"wave": 400,
	# 攻击反馈：塔多了以后一秒可能十几次，压到 70~90ms 才不会糊成噪音
	"fire": 70,
	"swing": 90,
	"enemy_attack": 120,
}

## 固定名单：DirAccess 在某些导出包/平台上列不出目录时按它兜底加载
const KNOWN := [
	"ui_click", "ui_back", "place", "upgrade", "remove",
	"hit", "die", "leak", "wave", "win", "lose",
	"card", "drawer", "boss", "heal",
	"fire", "swing", "enemy_attack",
]

var streams := {}

var _players: Array[AudioStreamPlayer] = []
var _cursor := 0
var _last_msec := {}
var _gs: Node


func _ready() -> void:
	_gs = get_node_or_null("/root/GameState")
	_load_all()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		# 暂停游戏时音效还能播完，不然按暂停会卡住半个声音
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)


func _load_all() -> void:
	var found := {}
	var dir := DirAccess.open(SFX_DIR)
	if dir != null:
		for f in dir.get_files():
			# 导出后目录里看到的是 "place.wav.remap"，资源仍按原名加载
			var base := f.trim_suffix(".remap")
			if base.get_extension() == "wav":
				found[base.get_basename()] = base
	else:
		push_warning("Audio: 列不出音效目录 %s，改用固定名单" % SFX_DIR)

	# 目录列表 + 固定名单取并集：导出包里目录项缺失时也能全部装载
	for name in KNOWN:
		if not found.has(name):
			found[name] = name + ".wav"

	for name in found:
		var path := SFX_DIR + str(found[name])
		if ResourceLoader.exists(path):
			streams[name] = load(path)
		elif ResourceLoader.exists(SFX_DIR + str(name) + ".wav"):
			streams[name] = load(SFX_DIR + str(name) + ".wav")


func muted() -> bool:
	return _gs != null and bool(_gs.sfx_muted)


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if muted() or not streams.has(name):
		return
	var now := Time.get_ticks_msec()
	var gap: int = int(MIN_GAP.get(name, 0))
	if gap > 0 and now - int(_last_msec.get(name, -100000)) < gap:
		return
	_last_msec[name] = now
	var p := _players[_cursor]
	_cursor = (_cursor + 1) % _players.size()
	p.stream = streams[name]
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch)
	p.play()


## 同一事件连打时给一点随机音高，避免听起来像机关枪
func play_var(name: String, volume_db: float = 0.0, spread: float = 0.05) -> void:
	play(name, volume_db, 1.0 + randf_range(-spread, spread))


func loaded_names() -> Array:
	return streams.keys()
