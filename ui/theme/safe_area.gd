extends RefCounted
## Área útil da tela, sem o furo da câmera. No celular deitado o furo fica num dos
## lados, e só esse lado perde a faixa; ao girar o celular, a faixa troca de lado.
## Quem usa confere de tempos em tempos (changed) e se reorganiza.

## Retângulo útil dentro de um controle que ocupa a tela inteira.
static func content(control: Control) -> Rect2:
	var rect: Rect2 = Rect2(Vector2.ZERO, control.size)
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var window: Vector2i = DisplayServer.window_get_size()
		if window.x > 0 and window.y > 0:
			var k: float = control.size.x / window.x
			var left: float = safe.position.x * k
			var right: float = maxf(window.x - safe.end.x, 0.0) * k
			rect = Rect2(left, 0, control.size.x - left - right, control.size.y)
	return rect


## A área segura atual do sistema (no computador, a janela inteira).
static func current() -> Rect2i:
	if OS.has_feature("mobile"):
		return DisplayServer.get_display_safe_area()
	return Rect2i()
