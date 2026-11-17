extends RefCounted
## Sessão de jogo do app (SPEC 8 e 9.1): fala com o servidor de mesa só pelo protocolo,
## por uma ponta com send() e poll(). A mesma para o offline (ui/app/offline_game.gd) e
## para o Wi-Fi (ui/app/wifi_game.gd); a tela só vê esta interface.
##
## Quem usa chama update() a cada quadro e desenha as mensagens que ele devolve.

const Protocol := preload("res://server/protocol.gd")

var my_id: String = ""
var room_id: String = ""
var last_state: Dictionary = {}
## A mensagem closed (placar), quando a sala encerra.
var final: Dictionary = {}

## Salas com amigos (Wi-Fi e à distância): o que a sala de espera usa.
## Por que não deu (texto em português, já para a tela).
var error_text: String = ""
## A partida já começou e há lugar livre: a tela pergunta se quer entrar (confirm_join).
var confirm_seat: bool = false
## Wi-Fi: a sala roda neste celular.
var is_host: bool = false

var _client: Object = null


## Faz a sessão andar e devolve as mensagens que chegaram do servidor.
func update() -> Array[Dictionary]:
	_pump()
	var messages: Array[Dictionary] = []
	if _client != null:
		messages = _client.call("poll")
	for message: Dictionary in messages:
		_track(message)
	return messages


## O que roda antes de ler as mensagens (o servidor local, a rede). Para as filhas.
func _pump() -> void:
	pass


func _track(message: Dictionary) -> void:
	match message.get("t"):
		Protocol.JOINED:
			my_id = str(message.get("you", ""))
			room_id = str(message.get("room", ""))
		Protocol.STATE:
			last_state = message
		Protocol.CLOSED:
			final = message


func send(message: Dictionary) -> void:
	if _client != null:
		_client.call("send", message)


## Verdadeiro se você é o dono da sala.
func is_owner() -> bool:
	return my_id != "" and str(last_state.get("room", {}).get("owner", "")) == my_id


## Jogada na sua vez. Leva o número da vez do último state, para um toque atrasado não
## valer na vez seguinte.
func act(action: String, amount: int) -> void:
	var seq: int = int(last_state.get("table", {}).get("seq", -1))
	send({"t": Protocol.ACT, "seq": seq, "action": action, "amount": amount})


func rebuy(accept: bool) -> void:
	send({"t": Protocol.REBUY, "accept": accept})


## Pede o histórico das mãos; a resposta chega em update() como mensagem "hands".
func history() -> void:
	send({"t": Protocol.HISTORY})


## "Voltei": deixa de estar ausente.
func back() -> void:
	send({"t": Protocol.AWAY, "on": false})


func start() -> void:
	send({"t": Protocol.START})


## Senta no primeiro lugar livre (quem está assistindo).
func sit() -> void:
	send({"t": Protocol.SIT})


## Volta com fichas guardadas: as de antes (keep) ou as iniciais.
func return_choice(keep: bool) -> void:
	send({"t": Protocol.RETURN_CHOICE, "keep": keep})


## Troca de avatar (só na sala de espera).
func set_avatar(avatar: int) -> void:
	send({"t": Protocol.PROFILE, "avatar": avatar})


## Verdadeiro enquanto a saída ainda não terminou (Wi-Fi: o anfitrião saiu e a sala
## passa para outro celular quando a mão acabar).
func pending_exit() -> bool:
	return false


## Comando do dono (pausar, expulsar, bots, encerrar).
func owner(cmd: String, extra: Dictionary = {}) -> void:
	var message: Dictionary = {"t": Protocol.OWNER, "cmd": cmd}
	message.merge(extra)
	send(message)


## Sai da mesa. Devolve o placar quando a saída encerra a sala; senão {}.
func leave() -> Dictionary:
	send({"t": Protocol.LEAVE})
	return final


## Fecha o que a sessão abriu (rede, anúncios). Chamado ao deixar a partida.
func shutdown() -> void:
	pass


## Aviso de conexão para mostrar por cima da mesa ("" = tudo bem).
func status_text() -> String:
	return ""


## Verdadeiro enquanto a mesa espera o anfitrião voltar (Wi-Fi): os relógios param.
func waiting_host() -> bool:
	return false


## Reações valem só com outras pessoas na mesa (Wi-Fi e à distância).
func has_reactions() -> bool:
	return false


## Manda uma reação (índice em Protocol.REACTIONS).
func react(index: int) -> void:
	send({"t": Protocol.REACT, "r": index})


## Senta num lugar livre (quem está assistindo); seat -1 = o primeiro livre.
func sit_at(seat: int) -> void:
	send({"t": Protocol.SIT, "seat": seat})


## Por que a sessão acabou sem placar (conexão perdida, expulso); "" se não acabou.
func failure() -> String:
	return ""


## A conexão falhou de vez (error_text diz por quê).
func failed() -> bool:
	return false


## Confirma a entrada depois da pergunta "Quer entrar e jogar?".
func confirm_join() -> void:
	confirm_seat = false


## O código da sala para mostrar na sala de espera ("" = nenhum).
func room_code() -> String:
	return ""


## Dica da sala de espera, embaixo dos lugares.
func waiting_hint() -> String:
	return ""


## Aviso quando a sala fecha antes de a partida começar.
func closed_notice() -> String:
	return "O dono fechou a sala."


## A pergunta de "Sair": [título, texto, botão de confirmar].
func leave_question() -> Array[String]:
	return ["Sair da mesa?", "A partida termina e você vê o placar.", "Sair"]


## Texto do servidor como frase: "a sala está cheia" -> "A sala está cheia.".
static func sentence(text: String) -> String:
	if text == "":
		return ""
	text = text.left(1).to_upper() + text.substr(1)
	return text if text.ends_with(".") or text.ends_with("!") else text + "."
