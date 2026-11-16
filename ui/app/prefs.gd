extends RefCounted
## As configurações em vigor (SPEC 11.3), lidas por quem toca som, vibra ou desenha
## as cartas. Quem manda nelas é o perfil (ui/app/profile.gd), que as grava no celular
## e as copia para cá com apply().

static var sound: bool = true
static var vibration: bool = true
