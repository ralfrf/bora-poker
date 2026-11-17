extends "res://tests/test_case.gd"
## Peças do app que têm regra (SPEC 11.3 e 11.4): configurações guardadas no perfil,
## sons sintetizados, exemplos do ranking das mãos e o número de avatares.

const Profile := preload("res://ui/app/profile.gd")
const Prefs := preload("res://ui/app/prefs.gd")
const Sfx := preload("res://ui/app/sfx.gd")
const HandRanking := preload("res://ui/widgets/hand_ranking.gd")
const Paint := preload("res://ui/widgets/paint.gd")
const Evaluator := preload("res://engine/hand_evaluator.gd")
const Cards := preload("res://engine/cards.gd")
const Room := preload("res://server/room.gd")
const AvatarStrip := preload("res://ui/widgets/avatar_strip.gd")

const TEST_PROFILE: String = "user://perfil_teste_config.cfg"


func test_settings_round_trip() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile: Profile = Profile.new()
	profile.load_file(TEST_PROFILE)
	assert_true(profile.sound and profile.vibration, "som e vibração ligados no começo")
	profile.set_nick("Rafa")
	profile.sound = false
	profile.vibration = false
	profile.avatar = 9
	assert_true(profile.save(), "salvou")
	var again: Profile = Profile.new()
	again.load_file(TEST_PROFILE)
	assert_false(again.sound, "som desligado guardado")
	assert_false(again.vibration, "vibração desligada guardada")
	assert_eq(again.avatar, 9, "o último dos 10 avatares")
	assert_false(Prefs.sound, "ao ler, as configurações entram em vigor")
	again.sound = true
	again.vibration = true
	again.apply()
	assert_true(Prefs.sound and Prefs.vibration, "apply devolve")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))


func test_avatar_count_matches_server() -> void:
	assert_eq(Paint.AVATAR_COUNT, Room.AVATARS, "a tela desenha todos os avatares do servidor")
	assert_eq(Paint.AVATAR_NAMES.size(), Paint.FREE_AVATARS)
	# A grade dos retratos tem uma casa para cada avatar exclusivo.
	var photos: Image = Image.load_from_file(ProjectSettings.globalize_path(Paint.PHOTOS_PATH))
	assert_true(photos != null, "imagem dos retratos presente")
	var rows: int = ceili(float(Paint.PHOTO_AVATARS) / Paint.PHOTO_COLUMNS)
	assert_eq(photos.get_width(), int(Paint.PHOTO_CELL) * Paint.PHOTO_COLUMNS)
	assert_eq(photos.get_height(), int(Paint.PHOTO_CELL) * rows)
	assert_true(Paint.is_photo(Paint.FREE_AVATARS) and not Paint.is_photo(Paint.FREE_AVATARS - 1))


## A fileira do perfil: arrastar rola até os exclusivos sem escolher nada; tocar escolhe.
func test_avatar_strip_drags_and_taps() -> void:
	var strip: AvatarStrip = AvatarStrip.new(40.0, 0)
	strip.size = Vector2(400, strip.cell())
	var chosen: Array[int] = []
	strip.picked.connect(func(index: int) -> void: chosen.append(index))
	assert_true(strip.max_offset() > 0.0, "os exclusivos ficam além da borda")
	assert_true(strip.index_at(390.0) < Paint.FREE_AVATARS, "no começo só aparecem os grátis")
	# Arrasto longo para a esquerda: rola até o fim e não escolhe.
	_finger(strip, true, 380.0)
	for x: float in [370.0, 300.0, 100.0, -2000.0]:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = Vector2(x, 20)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		strip._gui_input(motion)
	_finger(strip, false, -2000.0)
	assert_eq(strip.offset, strip.max_offset(), "rolou até o último")
	assert_eq(chosen.size(), 0, "arrastar não escolhe")
	# Toque no último avatar, agora à vista.
	_finger(strip, true, 390.0)
	_finger(strip, false, 392.0)
	assert_eq(chosen, [Paint.AVATAR_COUNT - 1] as Array[int], "tocar escolhe o exclusivo")
	assert_eq(strip.selected, Paint.AVATAR_COUNT - 1)
	# Reabrir com um exclusivo escolhido mostra esse avatar.
	var again: AvatarStrip = AvatarStrip.new(40.0, Paint.AVATAR_COUNT - 1)
	again.size = Vector2(400, again.cell())
	again.reveal(again.selected)
	assert_eq(again.index_at(390.0), Paint.AVATAR_COUNT - 1, "o escolhido fica à vista")
	strip.free()
	again.free()


func _finger(strip: AvatarStrip, down: bool, x: float) -> void:
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = down
	press.position = Vector2(x, 20)
	strip._gui_input(press)


func test_sounds_are_synthesized() -> void:
	for sound_name: String in Sfx.NAMES:
		var wav: AudioStreamWAV = Sfx.stream(sound_name)
		assert_true(wav != null and wav.data.size() > 2000, "som %s pronto" % sound_name)
		assert_eq(wav.mix_rate, Sfx.RATE)
		assert_true(wav.get_length() < 1.5, "som %s curto" % sound_name)
		var peak: int = 0
		for i in range(0, wav.data.size(), 2):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		assert_true(peak > 3000 and peak < 32767, "som %s audível e sem estourar" % sound_name)


## Cada exemplo do ranking é mesmo a mão que diz ser, e as cartas destacadas são as
## que formam a combinação.
func test_ranking_examples_are_right() -> void:
	assert_eq(HandRanking.HANDS.size(), 10)
	for i in HandRanking.HANDS.size():
		var entry: Array = HandRanking.HANDS[i]
		assert_eq(int(entry[0]), i, "em ordem, da mais fraca à mais forte")
		var cards: Array[int] = Cards.list_from_text(entry[2])
		assert_eq(cards.size(), 5)
		var score: int = Evaluator.score(cards)
		assert_eq(Evaluator.category(score), int(entry[0]),
			"exemplo de %s" % Evaluator.CATEGORY_NAMES[int(entry[0])])
		var counts: String = entry[3]
		var ranks: Dictionary = {}
		for k in 5:
			if counts[k] == "1":
				ranks[Cards.rank(cards[k])] = true
		# As cartas apagadas não repetem valor das destacadas (senão também contariam).
		for k in 5:
			if counts[k] == "0" and int(entry[0]) != Evaluator.HIGH_CARD:
				assert_false(ranks.has(Cards.rank(cards[k])),
					"carta apagada fora da combinação em %s" % entry[2])
