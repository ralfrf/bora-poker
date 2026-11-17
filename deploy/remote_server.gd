extends SceneTree
## Servidor de salas à distância, sem tela (SPEC 10). No Render:
##   godot --headless --path /app -s res://deploy/remote_server.gd
## Escuta na porta da variável PORT (padrão 10000). A lógica fica em
## net/remote_host.gd.

const RemoteHost := preload("res://net/remote_host.gd")

const DEFAULT_PORT: int = 10000
## Com gente conectada, cada mensagem espera no máximo uns 33 ms; sem ninguém, o laço
## quase para (parado, os 60 quadros por segundo da prova gastavam ~7% da CPU).
const FPS_BUSY: int = 30
const FPS_IDLE: int = 5

var _host: RemoteHost = null


func _initialize() -> void:
	Engine.max_fps = FPS_IDLE
	var port: int = DEFAULT_PORT
	if OS.get_environment("PORT").is_valid_int():
		port = OS.get_environment("PORT").to_int()
	_host = RemoteHost.new()
	var err: Error = _host.listen(port)
	print("servidor: ouvindo na porta %d (%s)" % [port, error_string(err)])
	if not _host.summary.configured:
		print("servidor: sem %s; as salas não voltam depois de um reinício" % RemoteHost.SECRET_ENV)
	if err != OK:
		quit(1)


func _process(_delta: float) -> bool:
	_host.tick()
	Engine.max_fps = FPS_BUSY if _host.busy() else FPS_IDLE
	return false
