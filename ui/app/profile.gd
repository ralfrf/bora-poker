extends RefCounted
## Perfil guardado só neste celular (SPEC 4.4, 11.1 e 11.3): apelido, avatar, o último
## modo usado, as últimas escolhas da mesa offline e as configurações (som e
## vibração). Sem cadastro e sem dado pessoal.
##
## device é um código aleatório deste aparelho, usado pelo servidor para reconhecer
## quem volta (SPEC 6.1). Nunca aparece na tela.

const Room := preload("res://server/room.gd")
const Prefs := preload("res://ui/app/prefs.gd")

const PATH: String = "user://perfil.cfg"
const MODE_OFFLINE: String = "offline"
const MODE_WIFI: String = "wifi"
const MODE_ONLINE: String = "online"
const MODES: Array[String] = [MODE_OFFLINE, MODE_WIFI, MODE_ONLINE]

var nick: String = ""
var avatar: int = 0
var last_mode: String = MODE_WIFI   ## SPEC 2: a primeira abertura mostra o Mesmo Wi-Fi
var offline: Dictionary = {}
var wifi: Dictionary = {}       ## escolhas da última sala criada no Wi-Fi
var device: String = ""
var sound: bool = true
var vibration: bool = true
var mute_reactions: bool = false

var _path: String = PATH


## Lê o perfil. Arquivo ausente ou estragado vira um perfil novo, sem apelido.
func load_file(path: String = PATH) -> void:
	_path = path
	var file: ConfigFile = ConfigFile.new()
	if file.load(path) == OK:
		var raw_nick: Variant = file.get_value("perfil", "apelido", "")
		nick = Room.clean_nick(raw_nick) if typeof(raw_nick) == TYPE_STRING \
			and (raw_nick as String).strip_edges() != "" else ""
		var raw_avatar: Variant = file.get_value("perfil", "avatar", 0)
		avatar = clampi(raw_avatar, 0, Room.AVATARS - 1) if typeof(raw_avatar) == TYPE_INT else 0
		var raw_mode: Variant = file.get_value("perfil", "ultimo_modo", MODE_WIFI)
		last_mode = raw_mode if MODES.has(raw_mode) else MODE_WIFI
		var raw_device: Variant = file.get_value("perfil", "aparelho", "")
		device = raw_device if typeof(raw_device) == TYPE_STRING else ""
		var raw_offline: Variant = file.get_value("offline", "escolhas", {})
		offline = raw_offline if typeof(raw_offline) == TYPE_DICTIONARY else {}
		var raw_wifi: Variant = file.get_value("wifi", "escolhas", {})
		wifi = raw_wifi if typeof(raw_wifi) == TYPE_DICTIONARY else {}
		sound = _flag(file.get_value("config", "sons", true), true)
		vibration = _flag(file.get_value("config", "vibracao", true), true)
		mute_reactions = _flag(file.get_value("config", "silenciar_reacoes", false), false)
	if device.length() < 16:
		device = Crypto.new().generate_random_bytes(12).hex_encode()
	apply()


func save() -> bool:
	var file: ConfigFile = ConfigFile.new()
	file.set_value("perfil", "apelido", nick)
	file.set_value("perfil", "avatar", avatar)
	file.set_value("perfil", "ultimo_modo", last_mode)
	file.set_value("perfil", "aparelho", device)
	file.set_value("offline", "escolhas", offline)
	file.set_value("wifi", "escolhas", wifi)
	file.set_value("config", "sons", sound)
	file.set_value("config", "vibracao", vibration)
	file.set_value("config", "silenciar_reacoes", mute_reactions)
	return file.save(_path) == OK


## Primeira abertura: ainda não escolheu apelido.
func is_new() -> bool:
	return nick == ""


func set_nick(text: String) -> void:
	nick = Room.clean_nick(text) if text.strip_edges() != "" else ""


## Põe as configurações deste perfil em vigor no app.
func apply() -> void:
	Prefs.sound = sound
	Prefs.vibration = vibration
	Prefs.mute_reactions = mute_reactions


static func _flag(raw: Variant, fallback: bool) -> bool:
	return raw if typeof(raw) == TYPE_BOOL else fallback
