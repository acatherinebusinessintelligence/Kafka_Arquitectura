#!/usr/bin/env bash
# Kafka Podman Lab Helper
# `up` ahora crea el tópico automáticamente (AUTO_TOPIC=1) y puede producir mensajes (AUTO_PRODUCE=N).
set -Eeuo pipefail

NET="${NET:-kafka-lab_default}"
ZK_IMAGE="${ZK_IMAGE:-docker.io/confluentinc/cp-zookeeper:7.5.0}"
KAFKA_IMAGE="${KAFKA_IMAGE:-docker.io/confluentinc/cp-kafka:7.5.0}"

TOPIC="${TOPIC:-transacciones}"
PARTITIONS="${PARTITIONS:-4}"
RF="${RF:-3}"
MIN_ISR="${MIN_ISR:-2}"

AUTO_TOPIC="${AUTO_TOPIC:-1}"
AUTO_PRODUCE="${AUTO_PRODUCE:-0}"

PORT1="${PORT1:-9092}"
PORT2="${PORT2:-9093}"
PORT3="${PORT3:-9094}"
ZK_PORT="${ZK_PORT:-2181}"

log() { printf "\033[1;34m[+]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[x]\033[0m %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Necesito '$1' instalado"; }

ensure_network() {
  if podman network exists "$NET"; then
    log "Red '$NET' OK"
  else
    log "Creando red '$NET'"
    podman network create "$NET" >/dev/null
  fi
}

up_zk() {
  log "Levantando Zookeeper en $NET (puerto host ${ZK_PORT})"
  podman run --replace --name=zookeeper -d --net "$NET" --network-alias zookeeper     -p "${ZK_PORT}:2181"     -e ZOOKEEPER_CLIENT_PORT=2181     -e ZOOKEEPER_TICK_TIME=2000     "$ZK_IMAGE" >/dev/null
}

up_kafka() {
  local id="$1" hostport="$2" name="kafka${id}" alias="kafka${id}"
  log "Levantando ${name} (BROKER_ID=${id}, puerto host ${hostport})"
  podman run --replace --name="${name}" -d --net "$NET" --network-alias "${alias}" -p "${hostport}:9092"     -e KAFKA_BROKER_ID="${id}"     -e KAFKA_ZOOKEEPER_CONNECT="zookeeper:2181"     -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP="PLAINTEXT:PLAINTEXT,INTERNAL:PLAINTEXT"     -e KAFKA_LISTENERS="PLAINTEXT://0.0.0.0:9092,INTERNAL://0.0.0.0:29092"     -e KAFKA_ADVERTISED_LISTENERS="PLAINTEXT://localhost:${hostport},INTERNAL://${alias}:29092"     -e KAFKA_INTER_BROKER_LISTENER_NAME="INTERNAL"     -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR="${RF}"     -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR="${RF}"     -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR="${MIN_ISR}"     -e KAFKA_MIN_INSYNC_REPLICAS="${MIN_ISR}"     "$KAFKA_IMAGE" >/dev/null
}

wait_brokers() {
  log "Esperando a que /brokers/ids muestre [1, 2, 3] ..."
  for i in $(seq 1 60); do
    if podman ps --format '{{.Names}}' | grep -q '^kafka1$'; then
      if podman exec kafka1 bash -lc "zookeeper-shell zookeeper:2181 ls /brokers/ids | tail -n1 | grep -E '\\[1, 2, 3\\]'" >/dev/null 2>&1; then
        log "Brokers registrados en ZK: [1, 2, 3]"
        return 0
      fi
    fi
    sleep 2
  done
  warn "No vi [1, 2, 3] en el tiempo esperado; continúa igual."
}

cmd_up() {
  ensure_network
  up_zk
  up_kafka 1 "${PORT1}"
  up_kafka 2 "${PORT2}"
  up_kafka 3 "${PORT3}"
  wait_brokers
  if [ "${AUTO_TOPIC}" != "0" ]; then
    log "AUTO_TOPIC=1 → creando tópico '${TOPIC}' (p=${PARTITIONS}, rf=${RF})"
    cmd_topic "${TOPIC}" || warn "No se pudo crear/descubrir el tópico '${TOPIC}'"
  fi
  if [ "${AUTO_PRODUCE}" -gt 0 ] 2>/dev/null; then
    log "AUTO_PRODUCE=${AUTO_PRODUCE} → produciendo mensajes de ejemplo"
    cmd_produce "${AUTO_PRODUCE}" || warn "Producción automática falló"
  fi
}

cmd_verify() {
  log "Contenedores:"
  podman ps --format "{{.Names}}\t{{.Networks}}\t{{.Status}}\t{{.Ports}}"
  if podman ps --format '{{.Names}}' | grep -q '^kafka1$'; then
    log "DNS a zookeeper desde kafka1:"
    podman exec -it kafka1 bash -lc 'getent hosts zookeeper || echo NO-RESUELVE'
    log "Brokers en ZK:"
    podman exec -it kafka1 bash -lc 'zookeeper-shell zookeeper:2181 ls /brokers/ids || true'
  fi
}

cmd_topic() {
  local topic="${1:-$TOPIC}"
  log "Creando tópico '${topic}' (p=${PARTITIONS}, rf=${RF}) si no existe..."
  podman exec -it kafka1 bash -lc    "kafka-topics --create --if-not-exists --topic '${topic}' --partitions ${PARTITIONS} --replication-factor ${RF} --bootstrap-server kafka1:29092"
  log "Descripción:"
  podman exec -it kafka1 bash -lc "kafka-topics --describe --topic '${topic}' --bootstrap-server kafka1:29092"
}

cmd_produce() {
  local n="${1:-12}" topic="${TOPIC}"
  log "Produciendo ${n} mensajes a '${topic}' (RoundRobin partitioner)"
  podman exec -i kafka1 bash -lc     "kafka-console-producer --bootstrap-server kafka1:29092 --topic '${topic}'      --producer-property acks=all      --producer-property partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner" <<EOF
$(seq -f "msg-%g" 1 "${n}")
EOF
  log "Offsets latest:"
  podman exec -it kafka1 bash -lc     "kafka-run-class kafka.tools.GetOffsetShell --broker-list kafka1:29092 --topic '${topic}' --time -1"
}

cmd_consume_begin() {
  local group="${1:-grupo2}" topic="${TOPIC}" timeout="${TIMEOUT:-20000}"
  log "Consumiendo '${topic}' con grupo '${group}' desde el inicio (timeout ${timeout}ms)"
  podman exec -it kafka3 bash -lc     "kafka-console-consumer --bootstrap-server kafka3:29092 --topic '${topic}'      --group '${group}' --from-beginning --timeout-ms ${timeout}"
}

cmd_tail() {
  local group="${1:-grupo2}" topic="${TOPIC}" timeout="${TIMEOUT:-20000}"
  log "Tail '${topic}' con grupo '${group}' (latest, solo nuevos)"
  podman exec -it kafka3 bash -lc     "kafka-console-consumer --bootstrap-server kafka3:29092 --topic '${topic}'      --group '${group}' --timeout-ms ${timeout}"
}

kill_group_consumers() {
  local group="$1"
  for B in kafka1 kafka2 kafka3; do
    podman exec "$B" bash -lc "pkill -f 'kafka-console-consumer.*--group ${group}' || true" >/dev/null 2>&1 || true
  done
}

cmd_reset() {
  local group="${1:-grupo2}" topic="${2:-$TOPIC}"
  log "Asegurando que el grupo '${group}' esté inactivo..."
  kill_group_consumers "${group}"
  sleep 1
  log "Rebobinando offsets de '${group}' en tópico '${topic}' a earliest (todas las particiones conocidas)"
  podman exec -it kafka1 bash -lc     "kafka-consumer-groups --bootstrap-server kafka1:29092      --group '${group}' --topic '${topic}'      --reset-offsets --to-earliest --execute"
  log "Offsets del grupo tras reset:"
  podman exec -it kafka1 bash -lc     "kafka-consumer-groups --bootstrap-server kafka1:29092      --describe --group '${group}' --offsets"
}

cmd_offsets() {
  local group="${1:-grupo2}"
  log "Offsets/LAG del grupo '${group}':"
  podman exec -it kafka1 bash -lc     "kafka-consumer-groups --bootstrap-server kafka1:29092      --describe --group '${group}' --offsets"
}

cmd_status() {
  podman ps --format "{{.Names}}\t{{.Networks}}\t{{.Status}}\t{{.Ports}}"
}

cmd_down() {
  log "Eliminando contenedores (zookeeper, kafka1..3)"
  podman rm -f kafka1 kafka2 kafka3 zookeeper >/dev/null 2>&1 || true
}

usage() {
  cat <<USAGE
Uso: $0 <comando> [args]

Comandos:
  up                 Levanta red/zk/kafka1..3, espera [1,2,3] y (AUTO_TOPIC=1) crea '${TOPIC}'
  verify             Muestra estado de red, DNS y /brokers/ids
  topic [TOPIC]      Crea y describe el tópico (default: ${TOPIC})
  produce [N]        Produce N mensajes round-robin (default: 12)
  consume [GROUP]    Consume desde el inicio con GROUP (default: grupo2)
  reset [GROUP] [TOPIC]
                     Rebobina offsets de GROUP a earliest (default topic: ${TOPIC})
  offsets [GROUP]    Describe offsets/lag del GROUP (default: grupo2)
  tail [GROUP]       Consume solo nuevos mensajes (latest) con GROUP (default: grupo2)
  status             Lista contenedores activos
  down               Elimina contenedores

Variables por env:
  NET=${NET}  TOPIC=${TOPIC}  PARTITIONS=${PARTITIONS}  RF=${RF}  MIN_ISR=${MIN_ISR}
  ZK_IMAGE=${ZK_IMAGE}  KAFKA_IMAGE=${KAFKA_IMAGE}
  AUTO_TOPIC=${AUTO_TOPIC}  AUTO_PRODUCE=${AUTO_PRODUCE}
  PORT1=${PORT1} PORT2=${PORT2} PORT3=${PORT3} ZK_PORT=${ZK_PORT}
USAGE
}

main() {
  need podman
  local cmd="${1:-}"; shift || true
  case "${cmd:-}" in
    up) cmd_up ;;
    verify) cmd_verify ;;
    topic) cmd_topic "$@" ;;
    produce) cmd_produce "${1:-}" ;;
    consume) cmd_consume_begin "${1:-}" ;;
    reset) cmd_reset "${1:-}" "${2:-}" ;;
    offsets) cmd_offsets "${1:-}" ;;
    tail) cmd_tail "${1:-}" ;;
    status) cmd_status ;;
    down) cmd_down ;;
    ""|-h|--help|help) usage ;;
    *) err "Comando desconocido: ${cmd}"; usage; exit 2 ;;
  esac
}

main "$@"
