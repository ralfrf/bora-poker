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

const TEST_PROFILE: String = "user://perfil_teste_config.cfg"


func test_settings_round_trip() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile: Profile = Profile.new()
	profile.load_file(TEST_PROFILE)
	assert_true(profile.sound and profile.vibration, "som e vibração ligados no começo")
	assert_false(profile.four_color, "baralho de 2 cores no começo")
	profile.set_nick("Rafa")
	profile.sound = false
	profile.vibration = false
	profile.four_color = true
	profile.avatar = 9
	assert_true(profile.save(), "salvou")
	var again: Profile = Profile.new()
	again.load_file(TEST_PROFILE)
	assert_false(again.sound, "som desligado guardado")
	assert_false(again.vibration, "vibração desligada guardada")
	assert_true(again.four_color, "4 cores guardado")
	assert_eq(again.avatar, 9, "o último dos 10 avatares")
	assert_false(Prefs.sound, "ao ler, as configurações entram em vigor")
	assert_true(Prefs.four_color)
	again.sound = true
	again.vibration = true
	again.four_color = false
	again.apply()
	assert_true(Prefs.sound and Prefs.vibration and not Prefs.four_color, "apply devolve")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))


func test_avatar_count_matches_server() -> void:
	assert_eq(Paint.AVATAR_COUNT, Room.AVATARS, "a tela desenha todos os avatares do servidor")
	assert_eq(Paint.AVATAR_NAMES.size(), Paint.AVATAR_COUNT)


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
