extends "res://tests/test_case.gd"
## Filtro dos apelidos (SPEC 4.4): palavrões e discurso de ódio barrados, mesmo
## disfarçados, sem barrar nomes e apelidos comuns.

const NickFilter := preload("res://server/nick_filter.gd")
const Room := preload("res://server/room.gd")
const Roster := preload("res://bots/roster.gd")
const Profile := preload("res://ui/app/profile.gd")

const TEST_PROFILE: String = "user://teste_perfil_filtro.cfg"


func test_nick_filter_blocks_swearing_in_disguise() -> void:
	for nick: String in ["Porra", "PORRA", "poooorra", "p0rr4", "Caralho", "c a r a l h o",
			"car.alho", "Karalhoo", "fdp", "F.D.P", "Puta", "put4", "Cu", "c u", "Cuzão",
			"VaiTomarNoCu", "MeuCaralho", "Arrombado", "Filho da Puta", "Fodase",
			"Buceta", "Merda", "Merdinha", "Fuck", "fuckboy", "Bitch", "Putaria", "Otário"]:
		assert_true(NickFilter.blocked(nick), "barrado: " + nick)


func test_nick_filter_blocks_hate() -> void:
	for nick: String in ["Hitler", "H1tl3r", "AdolfHitler", "Nazi", "Nazista", "NeoNazi",
			"Heil", "Sieg Heil", "Führer", "Lobo1488", "14 88", "Ariano 卐", "WhitePower",
			"Ku Klux Klan", "Auschwitz", "Crioulo", "Macaco Imundo", "Preto Sujo",
			"Nigga", "Nigger", "Ching Chong", "Viado", "Bicha", "Traveco", "Sapatão",
			"Boiola", "Faggot", "Retardado", "Estuprador", "Pedófilo", "MataGay",
			"Judeu Sujo", "Facista33", "Fascista", "FASCISMO", "Supremacista", "Racista", "Machista", "M4ch1st4",
			"Machismo", "Misógino", "Homofóbico", "Transfóbica", "Xenófobo"]:
		assert_true(NickFilter.blocked(nick), "barrado: " + nick)


func test_nick_filter_keeps_common_names() -> void:
	for nick: String in ["Ana", "Anna", "Cuca", "Jacu", "Paulo", "Paulinha", "Pinto",
			"Computador", "Viaduto", "Desviado", "Boston", "Pica-Pau", "Picasso", "Rolando",
			"Cornélio", "Nazaré", "Nazira", "Neguinho", "Shitake", "Scunthorpe", "Esmeralda",
			"Escobar", "Bicharada", "Fodor Jr", "Rafa 88", "Zé 2014", "João 2", "Jogador",
			"kkkkk", "Mãe", "Fascinante", "Fascínio", "Face", "Graça", "Machado", "Macho", "Homero", "Poker Face", "All-in Ana", "Dona Cida", "Lu", "Tião"]:
		assert_false(NickFilter.blocked(nick), "aceito: " + nick)
	for entry: Array in Roster.NAMES:
		assert_false(NickFilter.blocked(entry[0]), "nome de bot: " + str(entry[0]))
	assert_false(NickFilter.blocked(""), "vazio não é barrado (vira Jogador antes)")


func test_server_replaces_blocked_nick() -> void:
	assert_eq(Room.clean_nick("Caralho"), Room.DEFAULT_NICK, "barrado vira Jogador")
	assert_eq(Room.clean_nick("  Hitler  "), Room.DEFAULT_NICK)
	assert_eq(Room.clean_nick("Cuca"), "Cuca")
	assert_true(Room.nick_blocked(" viado\n"))
	assert_false(Room.nick_blocked("Viaduto"))
	# O corte em 16 letras vem antes do filtro: vale o que vai aparecer.
	assert_eq(Room.clean_nick("Abcdefghijklmnop Hitler"), "Abcdefghijklmnop")


func test_profile_refuses_blocked_nick() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile: Profile = Profile.new()
	profile.load_file(TEST_PROFILE)
	profile.set_nick("Porra")
	assert_true(profile.is_new(), "apelido barrado não é salvo")
	# Apelido barrado gravado por uma versão antiga: o app pede outro ao abrir.
	var file: ConfigFile = ConfigFile.new()
	file.set_value("perfil", "apelido", "Nazista")
	file.save(TEST_PROFILE)
	var old: Profile = Profile.new()
	old.load_file(TEST_PROFILE)
	assert_true(old.is_new(), "pede outro apelido")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
