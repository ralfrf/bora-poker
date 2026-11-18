extends RefCounted
## Serviço de compras da Loja (SPEC 12). Ainda não há plugin de pagamentos: a loja do
## celular não responde, não há preço e nada se compra. Quando o plugin entrar (Google
## Play Billing, a combinar com o dono), só este arquivo muda; a tela e as contas
## (ui/app/store_catalog.gd) continuam as mesmas.
##
## Para o plugin, lembrar: confirmar cada compra (acknowledge) em até 3 dias, senão a
## Play devolve o dinheiro; restaurar pela lista de compras da conta (queryPurchasesAsync,
## que traz a data de cada uma, para contar o prazo sem anúncios); o preço mostrado é o
## texto pronto que a loja informa (com o "R$"), nunca um número do código.


## Há loja de verdade para comprar? Hoje não (sem plugin): a Loja mostra os níveis com
## os botões travados e o aviso do Beta.
static func available() -> bool:
	return false


## Pede os preços dos produtos. done(prices): {código do produto: "R$ 4,99"}; produto sem
## preço fica de fora. Hoje responde vazio.
static func prices(_ids: Array[String], done: Callable) -> void:
	done.call_deferred({})


## Compra um produto. done(ok, purchases): ok verdadeiro se a compra foi paga e
## confirmada; purchases é a lista atualizada (como em restore). Desistiu ou deu erro:
## ok falso e nada muda. Hoje sempre falso.
static func buy(_id: String, done: Callable) -> void:
	done.call_deferred(false, [])


## Lê de novo as compras desta conta (botão "Restaurar compras" e ao abrir a Loja).
## done(purchases): [{"id": código do produto, "time": data da compra em segundos}].
## Hoje responde vazio.
static func restore(done: Callable) -> void:
	done.call_deferred([])
