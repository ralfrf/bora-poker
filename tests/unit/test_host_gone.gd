extends "res://tests/test_case.gd"
## Anfitrião some sem tocar em "Sair" (SPEC 6.4), com WebSocket de verdade nesta máquina:
## o app dele fica parado mais de 10 s e ele desiste da mão; o Android fecha o app e ele
## volta pela sala gravada, com a mesma mão; passa de 2 minutos e cada celular encerra
## com o placar calculado do último state.

const WifiGame := preload("res://ui/app/wifi_game.gd")
const Protocol := preload("res://server/protocol.gd")

const FAST: Dictionary = {"hand_gap_ms": 0, "showdown_gap_ms": 0, "bot_min_ms": 0,
	"bot_max_ms": 0, "bot_evaluations": 120}
const TEST_UDP_PORT: int = 47895
const SAVE: String = "user://teste_sala_wifi.json"

var _seed: int = 0


func _next_seed() -> int:
	_seed += 1
	return _seed


func _spin(step: Callable, done: Callable, ms: int = 3000) -> bool:
	var until: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		step.call()
		if done.call():
			return true
		OS.delay_msec(2)
	return false


func _host(udp: int) -> WifiGame:
	var host: WifiGame = WifiGame.new()
	var options: Dictionary = {"format": "classic", "seats": 4, "turn_seconds": 0, "bots": []}
	if not host.host("Ana", 1, "dev-a", options, FAST, _next_seed,
			["127.0.0.1"] as Array[String], 0, udp):
		return null
	return host


## Os convidados jogam sozinhos (passam ou pagam); o anfitrião só joga se host_plays.
func _stepper(games: Array, host_plays: Array) -> Callable:
	return func() -> void:
		for game: WifiGame in games:
			for message: Dictionary in game.update():
				if message["t"] != Protocol.STATE:
					continue
				var you: Dictionary = message["you"]
				if you.has("legal") and (not game.is_host or host_plays[0]):
					game.act("check" if you["legal"]["can_check"] else "call", 0)


func _my_entry(game: WifiGame) -> Dictionary:
	for entry: Dictionary in game.last_state.get("table", {}).get("seats", []):
		if entry["id"] == game.my_id:
			return entry
	return {}


func _host_turn(host: WifiGame) -> bool:
	return host.last_state.get("you", {}).has("legal")


func test_host_stall_over_10s_folds_hand() -> void:
	_seed = 8000
	var host: WifiGame = _host(TEST_UDP_PORT)
	assert_true(host != null, "abriu a sala")
	if host == null:
		return
	var bia: WifiGame = WifiGame.new()
	bia.join("127.0.0.1", host.port, "Bia", 2, "dev-b")
	var games: Array = [host, bia]
	var host_plays: Array = [false]
	var step: Callable = _stepper(games, host_plays)
	assert_true(_spin(step, func() -> bool: return bia.my_id != "", 4000), "Bia entrou")
	host.start()
	assert_true(_spin(step, func() -> bool: return _host_turn(host), 4000), "vez do anfitrião")
	var hand: int = int(host.last_state["table"]["hand"])
	# Parada curta (até 10 s): não conta.
	host.simulate_stall(8000)
	_spin(step, func() -> bool: return false, 100)
	assert_true(_host_turn(host), "parada de 8 s não tira a vez")
	host.simulate_stall(15000)
	var folded: Callable = func() -> bool:
		return _my_entry(host).get("folded", false) or int(host.last_state["table"]["hand"]) != hand
	assert_true(_spin(step, folded, 3000), "parada de 15 s: desistiu")
	assert_true(host.status_text().contains("desistiu"), "o anfitrião é avisado")
	assert_eq(host.final, {}, "a sala continua")
	host_plays[0] = true
	var before: int = int(host.last_state["table"]["hand"])
	assert_true(_spin(step, func() -> bool: return int(host.last_state["table"]["hand"]) >= before + 2,
		6000), "a partida segue")
	host.shutdown()
	bia.shutdown()


func test_host_comes_back_from_saved_room() -> void:
	_seed = 8100
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	var host: WifiGame = _host(TEST_UDP_PORT + 1)
	assert_true(host != null, "abriu a sala")
	if host == null:
		return
	host.save_path = SAVE
	var bia: WifiGame = WifiGame.new()
	bia.join("127.0.0.1", host.port, "Bia", 2, "dev-b")
	var games: Array = [host, bia]
	var host_plays: Array = [false]
	var step: Callable = _stepper(games, host_plays)
	assert_true(_spin(step, func() -> bool: return bia.my_id != "", 4000), "Bia entrou")
	host.start()
	assert_true(_spin(step, func() -> bool: return _host_turn(host), 4000), "vez do anfitrião")
	host.app_paused()
	var saved: Dictionary = WifiGame.read_save(SAVE)
	assert_false(saved.is_empty(), "a sala ficou gravada no celular do anfitrião")
	if saved.is_empty():
		host.shutdown()
		bia.shutdown()
		return
	assert_true(saved["room"]["table"]["hand"] != null, "com a mão em andamento")
	var hand: int = int(host.last_state["table"]["hand"])
	var host_id: String = host.my_id
	var bia_id: String = bia.my_id
	# O Android fecha o app: o servidor some. Bia fica "Aguardando o anfitrião…".
	host.save_path = ""
	host.shutdown()
	games.erase(host)
	assert_true(_spin(step, func() -> bool: return bia.waiting_host(), 8000), "Bia espera")
	assert_true(bia.status_text().contains("Aguardando o anfitrião"), bia.status_text())
	var back: WifiGame = WifiGame.new()
	back.save_path = SAVE
	assert_true(back.resume(saved, 30000, FAST, _next_seed, ["127.0.0.1"] as Array[String],
		TEST_UDP_PORT + 2), "voltou à sala: " + back.error_text)
	games.push_front(back)
	var reunited: Callable = func() -> bool:
		return back.my_id == host_id and bia.link == WifiGame.Link.ONLINE \
			and int(bia.last_state.get("table", {}).get("seq", 0)) > 0
	assert_true(_spin(step, reunited, 8000), "o anfitrião voltou como ele mesmo e Bia reconectou")
	assert_eq(bia.my_id, bia_id, "Bia continua a mesma")
	assert_true(_my_entry(back).get("folded", false) or int(back.last_state["table"]["hand"]) != hand,
		"fora mais de 10 s: desistiu da mão")
	host_plays[0] = true
	assert_true(_spin(step, func() -> bool: return int(back.last_state["table"]["hand"]) >= hand + 2,
		6000), "a partida segue")
	back.shutdown()
	assert_false(FileAccess.file_exists(SAVE), "ao acabar, o arquivo da sala é apagado")
	bia.shutdown()


func test_guest_gives_up_with_computed_score() -> void:
	_seed = 8200
	var host: WifiGame = _host(TEST_UDP_PORT + 3)
	assert_true(host != null, "abriu a sala")
	if host == null:
		return
	var bia: WifiGame = WifiGame.new()
	bia.wait_host_ms = 1500
	bia.join("127.0.0.1", host.port, "Bia", 2, "dev-b")
	var games: Array = [host, bia]
	var host_plays: Array = [false]
	var step: Callable = _stepper(games, host_plays)
	assert_true(_spin(step, func() -> bool: return bia.my_id != "", 4000), "Bia entrou")
	host.start()
	var ready: Callable = func() -> bool:
		return _host_turn(host) and str(bia.last_state.get("room", {}).get("host", "")) == host.my_id
	assert_true(_spin(step, ready, 4000), "vez do anfitrião (Bia sabe quem é o anfitrião)")
	host.shutdown()
	games.erase(host)
	var closed: Array = []
	var watch: Callable = func() -> void:
		for message: Dictionary in bia.update():
			if message["t"] == Protocol.CLOSED:
				closed.append(message)
	assert_true(_spin(watch, func() -> bool: return not closed.is_empty(), 8000),
		"sem o anfitrião, Bia encerra a sala")
	if closed.is_empty():
		bia.shutdown()
		return
	assert_eq(closed[0]["reason"], Protocol.R_HOST_GONE)
	assert_eq(closed[0]["scoreboard"].size(), 2, "placar com os dois")
	var sum: int = 0
	for row: Dictionary in closed[0]["scoreboard"]:
		sum += int(row["net"])
	assert_eq(sum, 0, "o placar fecha")
	assert_eq(bia.failure(), "O anfitrião não voltou.")
	bia.shutdown()


func test_host_away_over_2_minutes_ends_room() -> void:
	_seed = 8300
	var host: WifiGame = _host(TEST_UDP_PORT + 4)
	assert_true(host != null, "abriu a sala")
	if host == null:
		return
	var bia: WifiGame = WifiGame.new()
	bia.join("127.0.0.1", host.port, "Bia", 2, "dev-b")
	var games: Array = [host, bia]
	var step: Callable = _stepper(games, [false])
	assert_true(_spin(step, func() -> bool: return bia.my_id != "", 4000), "Bia entrou")
	host.start()
	assert_true(_spin(step, func() -> bool: return _host_turn(host), 4000), "vez do anfitrião")
	host.simulate_stall(WifiGame.RECONNECT_MS + 5000)
	_spin(step, func() -> bool: return not host.final.is_empty(), 1000)
	assert_eq(host.final.get("reason"), Protocol.R_HOST_GONE, "o anfitrião vê o mesmo placar")
	host.shutdown()
	bia.shutdown()
