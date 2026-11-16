extends RefCounted
## Sons e vibração (SPEC 11.4). Os sons são sintetizados aqui mesmo, na primeira vez
## que tocam: nenhum arquivo de áudio, nada de licença de terceiros. Sem música.
##
##   carta:   estalo curto de papel (cartas distribuídas e abertas na mesa)
##   ficha:   duas fichas batendo (apostas e pote)
##   vitoria: arpejo de sinos (você ganhou o pote)
##   vez:     dois toques suaves (chegou a sua vez)
##   batida:  duas batidas secas na mesa (alguém passou)
##   desiste: cartas deslizando e caindo no feltro (alguém desistiu)
##
## A vibração usa Input.vibrate_handheld, do próprio Godot, que existe no Android e no
## iPhone. Os dois respeitam as configurações (ui/app/prefs.gd).

const Prefs := preload("res://ui/app/prefs.gd")

const CARD: String = "carta"
const CHIP: String = "ficha"
const WIN: String = "vitoria"
const TURN: String = "vez"
const KNOCK: String = "batida"
const FOLD: String = "desiste"
const NAMES: Array[String] = [CARD, CHIP, WIN, TURN, KNOCK, FOLD]

const RATE: int = 22050
const VOICES: int = 8

static var _streams: Dictionary = {}
static var _players: Array[AudioStreamPlayer] = []
static var _next: int = 0


## Toca um som agora ou depois de delay segundos.
static func play(sound_name: String, delay: float = 0.0, volume_db: float = 0.0) -> void:
	if not Prefs.sound:
		return
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if delay > 0.0:
		tree.create_timer(delay).timeout.connect(play.bind(sound_name, 0.0, volume_db))
		return
	var player: AudioStreamPlayer = _voice(tree.root)
	if player == null:
		return
	player.stream = stream(sound_name)
	player.volume_db = volume_db
	player.play()


## Vibra o celular por ms milissegundos (no computador não faz nada).
static func vibrate(ms: int) -> void:
	if Prefs.vibration and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## O som pronto (sintetizado e guardado na primeira vez).
static func stream(sound_name: String) -> AudioStreamWAV:
	if not _streams.has(sound_name):
		_streams[sound_name] = _make(_samples(sound_name))
	return _streams[sound_name]


static func _voice(root: Node) -> AudioStreamPlayer:
	if _players.is_empty() or not is_instance_valid(_players[0]):
		_players.clear()
		for i in VOICES:
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.process_mode = Node.PROCESS_MODE_ALWAYS
			root.add_child(player)
			_players.append(player)
	# Uma voz livre; se todas estiverem tocando, a mais antiga dá lugar.
	for i in VOICES:
		var player: AudioStreamPlayer = _players[(_next + i) % VOICES]
		if not player.playing:
			_next = (_next + i + 1) % VOICES
			return player
	var oldest: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	return oldest


static func _samples(sound_name: String) -> PackedFloat32Array:
	match sound_name:
		CARD:
			return _card()
		CHIP:
			return _chip()
		WIN:
			return _win()
		TURN:
			return _turn()
		KNOCK:
			return _knock()
		FOLD:
			return _fold()
	return PackedFloat32Array()


## Passar: duas batidas na mesa. Um "toc" seco de madeira: um sopro curto de ruído
## passa por ressonâncias largas e abafadas (180, 420 e 950 Hz), que não ficam tocando
## (tons puros longos soam como bambu ou cano), mais um corpo grave bem curto.
static func _knock() -> PackedFloat32Array:
	var n: int = int(RATE * 0.26)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 31
	# [frequência, largura da banda em Hz, volume]: banda larga = some rápido.
	var bands: Array = [[180.0, 70.0, 1.0], [420.0, 140.0, 0.8], [950.0, 380.0, 0.45]]
	for hit: Array in [[0.0, 1.0], [0.115, 0.8]]:
		var start: int = int(float(hit[0]) * RATE)
		var gain: float = hit[1]
		var excite: PackedFloat32Array = PackedFloat32Array()
		excite.resize(n - start)
		for i in excite.size():
			var t: float = float(i) / RATE
			excite[i] = rng.randf_range(-1.0, 1.0) * exp(-t / 0.0035)
		var mix: PackedFloat32Array = PackedFloat32Array()
		mix.resize(excite.size())
		for band: Array in bands:
			var r: float = exp(-PI * float(band[1]) / RATE)
			var a1: float = -2.0 * r * cos(TAU * float(band[0]) / RATE)
			var a2: float = r * r
			# Ganho igual no centro de cada banda, para nenhuma dominar.
			var norm: float = 2.0 * sin(TAU * float(band[0]) / RATE)
			var y1: float = 0.0
			var y2: float = 0.0
			for i in excite.size():
				var y: float = (1.0 - r) * excite[i] - a1 * y1 - a2 * y2
				y2 = y1
				y1 = y
				mix[i] += y * float(band[2]) * norm
		for i in mix.size():
			var t: float = float(i) / RATE
			var body: float = 0.25 * sin(TAU * 130.0 * t) * exp(-t / 0.014) * minf(t / 0.001, 1.0)
			out[start + i] += (mix[i] * 4.0 + body) * gain
	return _normalized(out, 0.85)


## O mesmo som com o pico em peak.
static func _normalized(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top: float = 0.0
	for v: float in samples:
		top = maxf(top, absf(v))
	if top > 0.0:
		for i in samples.size():
			samples[i] *= peak / top
	return samples


## Desistir: as duas cartas jogadas no monte. Um "fwip" curto de papel e, logo depois,
## um tapinha leve e seco quando elas assentam.
static func _fold() -> PackedFloat32Array:
	var n: int = int(RATE * 0.17)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 47
	var low: float = 0.0
	var band: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.3              # corta os graves
		band += ((noise - low) - band) * 0.5    # e o chiado mais agudo
		# Fwip: sobe em 15 ms e some até os 70 ms.
		var swish: float = smoothstep(0.0, 0.015, t) * (1.0 - smoothstep(0.03, 0.07, t))
		var v: float = band * swish * 0.4
		# Tapinha das cartas assentando, aos 75 ms.
		var ts: float = t - 0.075
		if ts >= 0.0:
			v += band * 0.9 * minf(ts / 0.001, 1.0) * exp(-ts / 0.009)
			v += 0.08 * sin(TAU * 900.0 * ts) * exp(-ts / 0.006)
		out[i] = v
	return out


## Estalo de carta: ruído com graves cortados, ataque rápido e queda curta.
static func _card() -> PackedFloat32Array:
	var n: int = int(RATE * 0.09)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var low: float = 0.0
	var smooth: float = 0.0
	for i in n:
		var t: float = float(i) / RATE
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.12          # o que sobra abaixo de ~400 Hz
		smooth += ((noise - low) - smooth) * 0.55   # tira o chiado mais agudo
		var env: float = minf(t / 0.003, 1.0) * exp(-t / 0.018)
		out[i] = smooth * env * 0.9
	return out


## Duas fichas batendo: tons metálicos agudos que somem rápido, mais um clique.
static func _chip() -> PackedFloat32Array:
	var n: int = int(RATE * 0.16)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 23
	for hit: Array in [[0.0, 1.0, 1.0], [0.045, 0.7, 1.06]]:
		var start: float = hit[0]
		var gain: float = hit[1]
		var pitch: float = hit[2]
		for i in n:
			var t: float = float(i) / RATE - start
			if t < 0.0:
				continue
			var v: float = 0.0
			v += sin(TAU * 3150.0 * pitch * t) * exp(-t / 0.014)
			v += 0.6 * sin(TAU * 4720.0 * pitch * t) * exp(-t / 0.009)
			v += 0.35 * sin(TAU * 6300.0 * pitch * t) * exp(-t / 0.006)
			if t < 0.002:
				v += rng.randf_range(-1.0, 1.0) * (1.0 - t / 0.002)
			out[i] += v * gain * 0.32
	return out


## Vitória: dó, mi, sol e dó agudo em sinos, um depois do outro.
static func _win() -> PackedFloat32Array:
	var n: int = int(RATE * 1.1)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var notes: Array[float] = [1046.5, 1318.5, 1568.0, 2093.0]
	for k in notes.size():
		var start: float = k * 0.085
		var f: float = notes[k]
		for i in n:
			var t: float = float(i) / RATE - start
			if t < 0.0:
				continue
			var env: float = minf(t / 0.004, 1.0)
			var v: float = sin(TAU * f * t) * exp(-t / 0.32)
			v += 0.25 * sin(TAU * f * 2.76 * t) * exp(-t / 0.11)
			out[i] += v * env * 0.2
	return out


## Sua vez: dois toques suaves subindo.
static func _turn() -> PackedFloat32Array:
	var n: int = int(RATE * 0.6)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	for note: Array in [[0.0, 880.0], [0.12, 1318.5]]:
		var start: float = note[0]
		var f: float = note[1]
		for i in n:
			var t: float = float(i) / RATE - start
			if t < 0.0:
				continue
			var env: float = minf(t / 0.006, 1.0) * exp(-t / 0.16)
			out[i] += (sin(TAU * f * t) + 0.18 * sin(TAU * f * 2.0 * t)) * env * 0.3
	return out


## Amostras de -1 a 1 viram um AudioStreamWAV de 16 bits, mono.
## Picos acima de PEAK são trazidos para PEAK, para nenhum som estourar.
static func _make(samples: PackedFloat32Array) -> AudioStreamWAV:
	const PEAK: float = 0.9
	var peak: float = 0.0
	for v: float in samples:
		peak = maxf(peak, absf(v))
	var gain: float = PEAK / peak if peak > PEAK else 1.0
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
