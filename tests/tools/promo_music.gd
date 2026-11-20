extends RefCounted
## Trilhas de fundo do vídeo de divulgação, sintetizadas aqui mesmo (sem arquivo de fora).
## Tocam em laço.
##   "lounge": 4 compassos em lá menor (Lá menor, Fá, Dó, Sol), com acordes suaves,
##             arpejo, baixo e bateria leve.
##   "classica": trio de jazz de cassino em suingue (Rém9, Sol13, Dómaj9, Lá7b9), com
##             contrabaixo andando, piano, vibrafone e prato de condução.
##   "cassino": jazz-funk de filme de cassino em ré menor, 128 BPM (Rém7, Rém7, Solm7,
##             Lá7b9), com metais em ataques curtos, baixo de oitavas, caixa e chimbal.

const RATE: int = 44100
const BPM: float = 112.0
const BARS: int = 4
## Acordes (notas MIDI) e a fundamental do baixo de cada compasso.
const CHORDS: Array = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
const ROOTS: Array[int] = [45, 41, 48, 43]


static func stream(style: String = "lounge") -> AudioStreamWAV:
	if style == "classica":
		return _classic()
	if style == "cassino":
		return _casino()
	return _lounge()


static func _lounge() -> AudioStreamWAV:
	var beat: float = 60.0 / BPM
	var total: int = int(round(beat * 4.0 * BARS * RATE))
	var mix: PackedFloat32Array = PackedFloat32Array()
	mix.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for bar in BARS:
		var chord: Array = CHORDS[bar]
		var start: float = bar * 4.0 * beat
		# Acorde suave o compasso inteiro.
		for note: int in chord:
			_tone(mix, start, beat * 4.0, _freq(note), 0.045, 0.25, 0.4, 2)
		# Arpejo em semicolcheias, uma oitava acima.
		var order: Array[int] = [0, 1, 2, 1]
		for k in 16:
			var note: int = int(chord[order[k % 4]]) + 12
			_pluck(mix, start + k * beat / 4.0, 0.45, _freq(note), 0.05, 0.11)
		# Baixo em colcheias: fundamental e oitava.
		for k in 8:
			var note: int = ROOTS[bar] + (12 if k % 2 == 1 else 0)
			_pluck(mix, start + k * beat / 2.0, 0.4, _freq(note), 0.2, 0.16)
		# Bateria: bumbo no 1 e no 3, palma no 2 e no 4, chimbal nos contratempos.
		for k in 4:
			var at: float = start + k * beat
			if k % 2 == 0:
				_kick(mix, at)
			else:
				_noise(mix, at, 0.18, 0.12, 0.07, rng)
			_noise(mix, at + beat / 2.0, 0.06, 0.05, 0.018, rng)
	return _wav(_master(mix))


const JAZZ_BPM: float = 96.0
## Vozes do piano (sem a fundamental, como no jazz), o contrabaixo andando (uma nota
## por tempo, com aproximação cromática para o acorde seguinte) e o vibrafone.
const JAZZ_CHORDS: Array = [[53, 57, 60, 64], [53, 59, 64, 69], [52, 55, 59, 62],
	[55, 58, 61, 64]]
const JAZZ_BASS: Array = [[38, 41, 45, 44], [43, 47, 50, 49], [48, 52, 55, 46],
	[45, 49, 52, 39]]
const JAZZ_VIBES: Array = [[69, 72], [71, 69], [67, 64], [67, 70]]


static func _classic() -> AudioStreamWAV:
	var beat: float = 60.0 / JAZZ_BPM
	var swing: float = beat * 2.0 / 3.0
	var total: int = int(round(beat * 4.0 * BARS * RATE))
	var mix: PackedFloat32Array = PackedFloat32Array()
	mix.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	for bar in BARS:
		var start: float = bar * 4.0 * beat
		# Contrabaixo: semínimas, som cheio e redondo.
		for k in 4:
			_upright(mix, start + k * beat, beat * 1.1, _freq(int(JAZZ_BASS[bar][k])))
		# Piano: acorde no 1 e no "e" do 2 (levada Charleston), tocado de leve.
		for at: float in [start, start + beat + swing]:
			for note: int in JAZZ_CHORDS[bar]:
				_epiano(mix, at + rng.randf_range(0.0, 0.012), 0.9, _freq(note), 0.045)
		# Vibrafone: duas notas longas por compasso.
		for k in 2:
			_vibes(mix, start + k * 2.0 * beat, 1.9, _freq(int(JAZZ_VIBES[bar][k])))
		# Prato de condução em suingue e o chimbal fechando no 2 e no 4.
		for k in 4:
			var at: float = start + k * beat
			_ride(mix, at, 0.05 if k % 2 == 0 else 0.065, rng)
			if k % 2 == 1:
				_ride(mix, at + swing, 0.035, rng)
				_noise(mix, at, 0.05, 0.05, 0.012, rng)
	return _wav(_master(mix))


const CASINO_BPM: float = 128.0
const CASINO_CHORDS: Array = [[57, 60, 62, 65], [57, 60, 62, 65], [55, 58, 62, 65],
	[55, 58, 61, 64]]
const CASINO_ROOTS: Array[int] = [38, 38, 43, 45]
## Baixo em colcheias, em semitons acima da fundamental.
const CASINO_BASS: Array[int] = [0, 0, 12, 0, 10, 0, 12, 7]
## Tempos (em batidas) dos ataques dos metais; o último compasso aperta para voltar.
const CASINO_STABS: Array = [[0.5, 1.75, 3.5], [0.5, 1.75, 3.5], [0.5, 1.75, 3.5],
	[0.5, 1.5, 2.5, 3.5]]


static func _casino() -> AudioStreamWAV:
	var beat: float = 60.0 / CASINO_BPM
	var total: int = int(round(beat * 4.0 * BARS * RATE))
	var mix: PackedFloat32Array = PackedFloat32Array()
	mix.resize(total)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 23
	for bar in BARS:
		var start: float = bar * 4.0 * beat
		for k in 8:
			var note: int = CASINO_ROOTS[bar] + CASINO_BASS[k]
			_pluck(mix, start + k * beat / 2.0, beat * 0.45, _freq(note), 0.22, 0.09)
		for at: float in CASINO_STABS[bar]:
			for note: int in CASINO_CHORDS[bar]:
				_brass(mix, start + at * beat, beat * 0.4, _freq(note))
		# Bumbo no 1, no 3 e no "e" do 3; caixa no 2 e no 4; chimbal em semicolcheias.
		for at: float in [0.0, 2.0, 2.5]:
			_kick(mix, start + at * beat)
		for at: float in [1.0, 3.0]:
			_snare(mix, start + at * beat, rng)
		for k in 16:
			_noise(mix, start + k * beat / 4.0, 0.05, 0.05 if k % 2 == 0 else 0.028, 0.012,
				rng)
	return _wav(_master(mix))


## Metais sintetizados: série harmônica quase de serra, ataque curto e brilho que fecha.
static func _brass(mix: PackedFloat32Array, at: float, length: float, freq: float) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	for j in int((length + 0.08) * RATE):
		var t: float = float(j) / RATE
		var env: float = minf(t / 0.015, 1.0) * exp(-t / 0.25)
		if t > length:
			env *= maxf(0.0, 1.0 - (t - length) / 0.08)
		var bright: float = exp(-t / 0.12)
		var v: float = 0.0
		for h in range(1, 7):
			v += sin(TAU * freq * h * t) / h * (1.0 if h <= 2 else bright)
		mix[(first + j) % n] += v * env * 0.035


## Caixa: estalo de ruído com um corpo grave curto.
static func _snare(mix: PackedFloat32Array, at: float, rng: RandomNumberGenerator) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	for j in int(0.2 * RATE):
		var t: float = float(j) / RATE
		var v: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.06) * 0.22 			+ sin(TAU * 190.0 * t) * exp(-t / 0.04) * 0.2
		mix[(first + j) % n] += v


## Normaliza e arredonda os picos.
static func _master(mix: PackedFloat32Array) -> PackedFloat32Array:
	var peak: float = 0.001
	for i in mix.size():
		peak = maxf(peak, absf(mix[i]))
	for i in mix.size():
		mix[i] = tanh(mix[i] / peak * 1.1) * 0.85
	return mix


## Contrabaixo: ataque rápido, corpo grave e decaimento lento.
static func _upright(mix: PackedFloat32Array, at: float, length: float, freq: float) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	for j in int(length * RATE):
		var t: float = float(j) / RATE
		var env: float = minf(t / 0.008, 1.0) * exp(-t / 0.45)
		if t > length - 0.06:
			env *= maxf(0.0, (length - t) / 0.06)
		var v: float = sin(TAU * freq * t) + 0.45 * sin(TAU * freq * 2.0 * t) * exp(-t / 0.1) 			+ 0.15 * sin(TAU * freq * 3.0 * t) * exp(-t / 0.05)
		mix[(first + j) % n] += v * env * 0.26


## Piano elétrico suave: fundamental com um brilho que some rápido e um tremolo leve.
static func _epiano(mix: PackedFloat32Array, at: float, length: float, freq: float,
		amp: float) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	for j in int(length * RATE):
		var t: float = float(j) / RATE
		var env: float = minf(t / 0.005, 1.0) * exp(-t / 0.5)
		var v: float = sin(TAU * freq * t) + 0.5 * sin(TAU * freq * 2.0 * t) * exp(-t / 0.08) 			+ 0.2 * sin(TAU * freq * 4.0 * t) * exp(-t / 0.03)
		v *= 1.0 + 0.08 * sin(TAU * 4.5 * t)
		mix[(first + j) % n] += v * env * amp


## Vibrafone: som puro com o tremolo do motor e um parcial agudo no ataque.
static func _vibes(mix: PackedFloat32Array, at: float, length: float, freq: float) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	for j in int(length * RATE):
		var t: float = float(j) / RATE
		var env: float = minf(t / 0.004, 1.0) * exp(-t / 0.9)
		var v: float = sin(TAU * freq * t) + 0.25 * sin(TAU * freq * 4.0 * t) * exp(-t / 0.06)
		v *= 0.8 + 0.2 * sin(TAU * 5.5 * t)
		mix[(first + j) % n] += v * env * 0.055


## Prato de condução: parciais metálicos fora da série harmônica e um pouco de ruído.
static func _ride(mix: PackedFloat32Array, at: float, amp: float,
		rng: RandomNumberGenerator) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	var partials: Array[float] = [3127.0, 4211.0, 5387.0, 6803.0, 8120.0]
	var last: float = 0.0
	for j in int(0.6 * RATE):
		var t: float = float(j) / RATE
		var v: float = 0.0
		for f: float in partials:
			v += sin(TAU * f * t)
		var white: float = rng.randf_range(-1.0, 1.0)
		v = v * 0.12 + (white - last) * 0.5
		last = white
		mix[(first + j) % n] += v * exp(-t / 0.22) * minf(t / 0.002, 1.0) * amp


static func _freq(note: int) -> float:
	return 440.0 * pow(2.0, (note - 69) / 12.0)


## Nota sustentada (acorde): ataque, sustentação e soltura no fim, com harmônicos leves.
static func _tone(mix: PackedFloat32Array, at: float, length: float, freq: float, amp: float,
		attack: float, release: float, harmonics: int) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	var count: int = int((length + release) * RATE)
	for j in count:
		var t: float = float(j) / RATE
		var env: float = minf(t / attack, 1.0)
		if t > length:
			env *= maxf(0.0, 1.0 - (t - length) / release)
		var v: float = 0.0
		for h in range(1, harmonics + 1):
			v += sin(TAU * freq * h * t * (1.0 + 0.002 * h)) / (h * h)
		mix[(first + j) % n] += v * env * amp


## Nota beliscada (arpejo e baixo): começa forte e some em decay segundos.
static func _pluck(mix: PackedFloat32Array, at: float, length: float, freq: float, amp: float,
		decay: float) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	var count: int = int(length * RATE)
	for j in count:
		var t: float = float(j) / RATE
		var env: float = exp(-t / decay) * minf(t / 0.004, 1.0)
		var v: float = sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t)
		mix[(first + j) % n] += v * env * amp


static func _kick(mix: PackedFloat32Array, at: float) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	var phase: float = 0.0
	for j in int(0.3 * RATE):
		var t: float = float(j) / RATE
		var freq: float = 45.0 + 75.0 * exp(-t / 0.04)
		phase += TAU * freq / RATE
		mix[(first + j) % n] += sin(phase) * exp(-t / 0.12) * 0.45


## Ruído curto e agudo (palma e chimbal).
static func _noise(mix: PackedFloat32Array, at: float, length: float, amp: float, decay: float,
		rng: RandomNumberGenerator) -> void:
	var n: int = mix.size()
	var first: int = int(at * RATE)
	var last: float = 0.0
	for j in int(length * RATE):
		var t: float = float(j) / RATE
		var white: float = rng.randf_range(-1.0, 1.0)
		mix[(first + j) % n] += (white - last) * exp(-t / decay) * amp
		last = white


static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	return wav
