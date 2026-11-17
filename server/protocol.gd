extends RefCounted
## Nomes das mensagens do protocolo (SPEC 9.1). Toda mensagem é um dicionário JSON com
## o tipo no campo "t". Valores sempre em centavos inteiros; cartas são inteiros de 0 a 51.

const VERSION: int = 2   ## 2: protocolo enxuto (server/wire.gd)

# Do app para o servidor.
const HELLO: String = "hello"               ## {v, nick, avatar, device}
const LIST_ROOMS: String = "list_rooms"     ## {}
const CREATE_ROOM: String = "create_room"   ## {options}
const JOIN_ROOM: String = "join_room"       ## {room, spectate, password?} (spectate só na sala de
                                            ## espera; password: sala com senha, à distância)
const LEAVE: String = "leave"               ## {}
const START: String = "start"               ## {} (só o dono)
const ACT: String = "act"                   ## {seq, action, amount}
const REBUY: String = "rebuy"               ## {accept}
const SIT: String = "sit"                   ## {seat} (seat é opcional)
const AWAY: String = "away"                 ## {on}: verdadeiro = ausente, falso = "Voltei"
const HISTORY: String = "history"           ## {}: pede o histórico das mãos
const OWNER: String = "owner"               ## {cmd, ...} (só o dono)
const PING: String = "ping"                 ## {}: batimento, a cada 2 s na rede
const RETURN_CHOICE: String = "return_choice"   ## {keep}: volta com as fichas de antes ou as iniciais
const PROFILE: String = "profile"           ## {avatar}: troca o avatar (só na sala de espera)
const REACT: String = "react"               ## {r}: reação (índice em REACTIONS), só quem está sentado
# Reservada para a próxima etapa.
const RESUME_ROOM: String = "resume_room"       ## etapa 5: devolver o resumo da sala

# Do servidor para o app.
const WELCOME: String = "welcome"   ## {v, nick}
const ROOMS: String = "rooms"       ## {rooms: [{id, name, format, seats, players, phase, keep_open,
                                    ##   owner, small_blind, big_blind, level_minutes, locked, open}]}
const JOINED: String = "joined"     ## {room, you, resumed}: resumed = retomou o lugar de antes
const STATE: String = "state"       ## {room, table, you, events}: a sala e a mesa vistas por quem recebe.
                                    ## you.return_offer {before, initial, seat, can_initial}: oferta de volta (SPEC 6.2)
const LEFT: String = "left"         ## {reason}: "left" ou "kicked"
const CLOSED: String = "closed"     ## {reason, scoreboard, podium}
const ERROR: String = "error"       ## {code, text}
const PONG: String = "pong"         ## {}
const HANDS: String = "hands"       ## {hands}: as últimas mãos, da mais recente (server/hand_log.gd)
const MOVE: String = "move"         ## {ip, port, room, nick, snapshot?}: Wi-Fi, a sala passa para o celular de nick;
                                    ## só ele recebe o snapshot (com os códigos dos aparelhos)
const REACTION: String = "reaction" ## {seat, r}: alguém reagiu; vai a todos, fora do state
# Reservada para a próxima etapa.
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
const E_FULL: String = "full"              ## servidor sem vagas: o app mostra "Em manutenção" (SPEC 9.3)
const E_PASSWORD: String = "password"      ## sala com senha: faltou, errou ou espera (wait_ms)

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
const R_HOST_GONE: String = "host_gone" ## Wi-Fi: o anfitrião sumiu e não voltou; placar calculado
                                        ## em cada celular a partir do último state (net/host_lost.gd)

## Reações prontas (SPEC 11.2): as REACTION_FACES primeiras são carinhas desenhadas pelo
## jogo (ui/widgets/reaction_view.gd); as outras são frases. Sem texto livre.
const REACTIONS: Array[String] = ["feliz", "risada", "uau", "bravo", "triste", "legal",
	"Boa mão!", "Blefou!", "Vai logo!", "Que sorte!", "Bem jogado!", "Foi mal!"]
const REACTION_FACES: int = 6
## Intervalo mínimo entre duas reações da mesma pessoa (limite de frequência).
const REACTION_GAP_MS: int = 2500


static func error(code: String, text: String) -> Dictionary:
	return {"t": ERROR, "code": code, "text": text}
