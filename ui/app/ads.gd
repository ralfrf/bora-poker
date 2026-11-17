extends RefCounted
## Serviço de anúncios (SPEC 12). Na fase com amigos não há SDK de anúncio: o vídeo que
## antecede a recompra termina na hora e responde "assistido". Quando houver anúncio de
## verdade (a combinar antes da publicação), só este arquivo muda.


## Vídeo com recompensa: na recompra e ao voltar à mesa depois de sair (quem só
## reconectou não vê). O jogador escolhe ver (regra do AdMob) e pode fechar; fechou antes
## do fim, done(false) e nada acontece. Sem anúncio para mostrar (sem internet, sem
## anúncio disponível ou sem SDK), done(true) na hora: ninguém fica preso.
static func rewarded(done: Callable) -> void:
	done.call_deferred(true)


## Intervalo mínimo entre dois anúncios de tela cheia, para o "Jogar de novo" (que já
## mostra um) não emendar com o da sala de espera.
const INTERSTITIAL_GAP_MS: int = 120000

static var _last_interstitial: int = -INTERSTITIAL_GAP_MS


## Anúncio de tela cheia: depois do placar e logo ao entrar numa sala de espera (pedido
## do dono, 17/11/2026). Na sala de espera é uma imagem que dá para pular em poucos
## segundos, não um vídeo longo (bloco de anúncios só de imagem no AdMob). Nunca durante
## uma mão nem ao abrir o app. Hoje não mostra nada e segue na hora.
static func interstitial(done: Callable) -> void:
	if interstitial_ready():
		_last_interstitial = Time.get_ticks_msec()
	done.call_deferred()


## Um anúncio de tela cheia apareceria agora? (Há serviço e passou o intervalo mínimo.)
static func interstitial_ready() -> bool:
	return available() and Time.get_ticks_msec() - _last_interstitial >= INTERSTITIAL_GAP_MS


## Há anúncio de verdade para mostrar? Hoje não (sem SDK); as telas só oferecem o
## anúncio quando houver.
static func available() -> bool:
	return false
