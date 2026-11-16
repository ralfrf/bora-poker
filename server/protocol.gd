extends RefCounted
## Nomes das mensagens do protocolo (SPEC 9.1). Toda mensagem é um dicionário JSON com
## o tipo no campo "t". Valores sempre em centavos inteiros; cartas são inteiros de 0 a 51.

const VERSION: int = 1

# Do app para o servidor.
const HELLO: String = "hello"               ## {v, nick, avatar, device}
const LIST_ROOMS: String = "list_rooms"     ## {}
const CREATE_ROOM: String = "create_room"   ## {options}
const JOIN_ROOM: String = "join_room"       ## {room, spectate}
const LEAVE: String = "leave"               ## {}
const START: String = "start"               ## {} (só o dono)
const ACT: String = "act"                   ## {seq, action, amount}
const REBUY: String = "rebuy"               ## {accept}
const SIT: String = "sit"                   ## {seat} (seat é opcional)
const AWAY: String = "away"                 ## {on}: verdadeiro = ausente, falso = "Voltei"
const OWNER: String = "owner"               ## {cmd, ...} (só o dono)
const PING: String = "ping"                 ## {}
# Reservadas para as próximas etapas.
const REACT: String = "react"                   ## etapa 4: reação
const RETURN_CHOICE: String = "return_choice"   ## etapa 4: escolha de fichas na volta
const RESUME_ROOM: String = "resume_room"       ## etapa 5: devolver o resumo da sala

# Do servidor para o app.
const WELCOME: String = "welcome"   ## {v, nick}
const ROOMS: String = "rooms"       ## {rooms: [{id, name, format, seats, players, phase, keep_open}]}
const JOINED: String = "joined"     ## {room, you}
const STATE: String = "state"       ## {room, table, you, events}: a sala e a mesa vistas por quem recebe
const LEFT: String = "left"         ## {reason}: "left" ou "kicked"
const CLOSED: String = "closed"     ## {reason, scoreboard, podium}
const ERROR: String = "error"       ## {code, text}
const PONG: String = "pong"         ## {}
# Reservadas para as próximas etapas.
const REACTION: String = "reaction"           ## etapa 4
const RETURN_OFFER: String = "return_offer"   ## etapa 4
const SUMMARY: String = "summary"             ## etapa 5: resumo assinado

# Comandos do dono (campo "cmd" de OWNER).
const CMD_PAUSE: String = "pause"
const CMD_RESUME: String = "resume"
const CMD_KICK: String = "kick"               ## {id}
const CMD_ADD_BOT: String = "add_bot"         ## {level}
const CMD_REMOVE_BOT: String = "remove_bot"   ## {id}
const CMD_SETTINGS: String = "settings"       ## {small_blind, big_blind, turn_seconds}
const CMD_CLOSE: String = "close"

# Códigos de erro (campo "code" de ERROR). O texto que acompanha já vem em português.
const E_VERSION: String = "version"           ## o app mostra "Atualize o app"
const E_BAD_MESSAGE: String = "bad_message"   ## mensagem malformada ou desconhecida
const E_NO_HELLO: String = "no_hello"         ## falta a apresentação
const E_NO_ROOM: String = "no_room"           ## sala inexistente ou fora de uma sala
const E_REFUSED: String = "refused"           ## pedido recusado; o texto diz por quê

# Fases da sala.
const LOBBY: String = "lobby"
const PLAYING: String = "playing"
const ENDED: String = "closed"

# Motivos de LEFT e de CLOSED.
const R_LEFT: String = "left"
const R_KICKED: String = "kicked"
const R_OWNER: String = "owner"         ## o dono encerrou a sala
const R_FINISHED: String = "finished"   ## a partida acabou
const R_EMPTY: String = "empty"         ## não sobrou nenhum humano


static func error(code: String, text: String) -> Dictionary:
	return {"t": ERROR, "code": code, "text": text}
