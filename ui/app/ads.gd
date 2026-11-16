extends RefCounted
## Serviço de anúncios (SPEC 12). Na fase com amigos não há SDK de anúncio: o vídeo que
## antecede a recompra termina na hora e responde "assistido". Quando houver anúncio de
## verdade (a combinar antes da publicação), só este arquivo muda.


## Mostra o vídeo da recompra e chama done(assistiu) quando ele acabar.
static func rewarded(done: Callable) -> void:
	done.call_deferred(true)


## Anúncio de tela cheia entre partidas: depois do placar, antes do início ou da
## partida seguinte. Nunca durante uma mão. Hoje não mostra nada e segue na hora.
static func interstitial(done: Callable) -> void:
	done.call_deferred()
