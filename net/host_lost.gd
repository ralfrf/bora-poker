extends RefCounted
## Wi-Fi, o anfitrião sumiu e não voltou em 2 minutos (SPEC 6.4): cada celular encerra a
## sala por conta própria e mostra o placar calculado a partir do último state público
## que recebeu. O que o anfitrião apostou na mão interrompida é dividido entre quem
## ainda estava nela; os demais recebem as apostas de volta.
##
## room.score já traz o placar como se a mão fosse cancelada (as apostas de cada um
## contam nas fichas dele); aqui só se tira do anfitrião o que ele apostou e se reparte.

const Protocol := preload("res://server/protocol.gd")
const Table := preload("res://engine/table.gd")


## A mensagem closed calculada (motivo host_gone), ou {} se o state não tem placar
## (sala de espera, ou state vazio).
static func final_from(state: Dictionary, host_id: String) -> Dictionary:
	var room: Dictionary = state.get("room", {})
	var table: Dictionary = state.get("table", {})
	var rows: Array = (room.get("score", []) as Array).duplicate(true)
	if room.get("phase", "") != Protocol.PLAYING or rows.is_empty():
		return {}
	var deltas: Dictionary = {}   # id -> fichas a mais ou a menos
	if table.get("live", false):
		var host_total: int = 0
		var takers: Array[String] = []
		for entry: Dictionary in table.get("seats", []):
			if str(entry.get("id", "")) == host_id:
				host_total = int(entry.get("total", 0))
			elif entry.get("in_hand", false) and not entry.get("folded", false):
				takers.append(str(entry.get("id", "")))
		if host_total > 0 and not takers.is_empty():
			deltas[host_id] = -host_total
			var share: int = host_total / takers.size()
			var rest: int = host_total % takers.size()
			for i in takers.size():
				deltas[takers[i]] = share + (1 if i < rest else 0)
	for row: Dictionary in rows:
		var delta: int = int(deltas.get(str(row.get("id", "")), 0))
		row["chips"] = int(row.get("chips", 0)) + delta
		row["net"] = int(row.get("net", 0)) + delta
	var tournament: bool = table.get("format", "") == Table.TOURNAMENT
	Table.sort_scoreboard(rows, tournament)
	var podium: Array = []
	if tournament:
		for row: Dictionary in rows:
			if int(row["place"]) >= 1 and int(row["place"]) <= 3:
				podium.append({"place": row["place"], "seat": row["seat"], "id": row["id"],
					"nick": row.get("nick", "")})
	return {"t": Protocol.CLOSED, "reason": Protocol.R_HOST_GONE, "scoreboard": rows,
		"podium": podium}
