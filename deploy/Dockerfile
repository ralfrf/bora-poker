# Bora Poker sem tela em Linux, com o binário oficial do Godot. O comando padrão sobe o
# servidor de salas à distância na porta PORT; os testes rodam trocando o comando.
#
#   docker build -f deploy/Dockerfile -t bora-poker-testes .
#   docker run --rm -p 10000:10000 --memory=512m --memory-swap=512m --cpus=0.1 bora-poker-testes
#   docker run --rm --memory=512m --memory-swap=512m --cpus=0.1 bora-poker-testes godot --headless --path /app -s res://tests/run_tests.gd

FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
ARG GODOT_RELEASE=${GODOT_VERSION}-stable
ARG GODOT_ZIP=Godot_v${GODOT_RELEASE}_linux.x86_64.zip
ARG GODOT_URL=https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}
# Soma SHA-512 do arquivo acima, copiada da lista oficial do release. Fica fixa aqui
# para a imagem recusar um binário trocado. Ao mudar a versão, atualize as duas.
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
 && curl -fsSLO "${GODOT_URL}/${GODOT_ZIP}" \
 && echo "${GODOT_SHA512}  ${GODOT_ZIP}" | sha512sum -c - \
 && unzip -q "${GODOT_ZIP}" \
 && mv "Godot_v${GODOT_RELEASE}_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot \
 && rm -rf /tmp/*

RUN useradd --create-home jogo
WORKDIR /app
COPY --chown=jogo:jogo project.godot ./
COPY --chown=jogo:jogo engine ./engine
COPY --chown=jogo:jogo server ./server
COPY --chown=jogo:jogo net ./net
COPY --chown=jogo:jogo bots ./bots
# A tela também entra: os testes do Wi-Fi e das telas carregam ui/.
COPY --chown=jogo:jogo ui ./ui
COPY --chown=jogo:jogo tests ./tests
# O servidor de salas e a prova da hospedagem (eco WebSocket e página de teste, com os
# testes rodando ao lado: godot --headless --path /app -s res://deploy/prova.gd).
COPY --chown=jogo:jogo deploy/remote_server.gd deploy/prova.gd ./deploy/
RUN chown jogo:jogo /app
USER jogo
ENV PORT=10000
EXPOSE 10000

CMD ["godot", "--headless", "--path", "/app", "-s", "res://deploy/remote_server.gd"]
