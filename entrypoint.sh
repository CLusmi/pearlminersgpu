#!/usr/bin/env bash
# Lance le mineur choisi avec les variables d'environnement du template.
#
#   MINER        srbminer (defaut) | bzminer
#   COIN         pearl (defaut) | quantus | autre nom d'algorithme (passe tel quel)
#                ALGO est accepte a la place de COIN (ex. ALGO=pearlhash)
#   POOL         adresse:port de la pool (obligatoire)
#   WALLET       adresse du wallet (obligatoire)
#   WORKER       nom du worker (facultatif)
#   PASS         mot de passe pool (facultatif)
#   EXTRA_ARGS   options supplementaires passees telles quelles au mineur
#   RESTART_DELAY  secondes avant relance si le mineur s'arrete (defaut 10)
#   DRY_RUN=1    affiche la commande sans lancer le mineur
#
# Avec des arguments (docker run image --help), le mineur choisi est lance
# directement avec ces arguments ; une commande (bash, nvidia-smi) est executee.
set -uo pipefail

MINERS_DIR=/opt/miners

log() { echo "[pearlminersgpu] $*"; }
die() { echo "[pearlminersgpu] ERREUR: $*" >&2; exit 1; }

miner=$(echo "${MINER:-srbminer}" | tr '[:upper:]' '[:lower:]')
case "$miner" in
  srb|srbminer|srbminer-multi) miner=srbminer;  bin="$MINERS_DIR/srbminer/SRBMiner-MULTI" ;;
  bz|bzminer)                  miner=bzminer;   bin="$MINERS_DIR/bzminer/bzminer" ;;
  *) die "MINER=${MINER} inconnu. Valeurs possibles : srbminer, bzminer." ;;
esac
[[ -x "$bin" ]] || die "binaire introuvable : $bin"

# Mode direct : arguments passes au conteneur.
if [[ $# -gt 0 ]]; then
  if [[ "$1" != -* ]] && command -v "$1" >/dev/null 2>&1; then
    exec "$@"
  fi
  exec "$bin" "$@"
fi

log "Versions installees : $(tr '\n' ' ' < "$MINERS_DIR/VERSIONS")"

# --- Parametres -------------------------------------------------------------
coin=$(echo "${COIN:-${ALGO:-pearl}}" | tr '[:upper:]' '[:lower:]')
[[ "$coin" == pearlhash || "$coin" == prl ]] && coin=pearl

[[ -n "${POOL:-}" ]]   || die "POOL est obligatoire (ex. POOL=prl.kryptex.network:7048)."
[[ -n "${WALLET:-}" ]] || die "WALLET est obligatoire."
worker="${WORKER:-}"
pass="${PASS:-}"
extra=()
[[ -n "${EXTRA_ARGS:-}" ]] && read -r -a extra <<< "$EXTRA_ARGS"

# Nom de l'algorithme dans le vocabulaire de chaque mineur.
algo_for() {
  case "$1:$coin" in
    srbminer:pearl) echo pearlhash ;;
    *:pearl)        echo pearl ;;
    *)              echo "$coin" ;;
  esac
}
algo=$(algo_for "$miner")

# --- Ligne de commande ------------------------------------------------------
cmd=("$bin")
logfile=""
case "$miner" in
  srbminer)
    pool="${POOL#stratum+tcp://}"
    # SRBMiner n'ecrit rien sur la sortie standard hors terminal : on passe par
    # son fichier de log, recopie dans les logs du conteneur plus bas.
    logfile="$PWD/srbminer.log"
    cmd+=(--disable-cpu --algorithm "$algo" --pool "$pool" --wallet "$WALLET" --log-file "$logfile")
    [[ -n "$worker" ]] && cmd+=(--worker "$worker")
    [[ -n "$pass" ]]   && cmd+=(--password "$pass")
    ;;
  bzminer)
    pool="$POOL"
    [[ "$pool" == *://* ]] || pool="stratum+tcp://$pool"
    # --nvidia : seules les cartes NVIDIA minent (pas de minage CPU).
    # -o log   : journal en texte simple, lisible dans les logs du conteneur.
    cmd+=(-a "$algo" -p "$pool" -w "$WALLET" --nvidia -o log)
    [[ -n "$worker" ]] && cmd+=(--worker "$worker")
    [[ -n "$pass" ]]   && cmd+=(--pass "$pass")
    ;;
esac
cmd+=("${extra[@]}")

log "Commande : ${cmd[*]}"
if [[ "${DRY_RUN:-0}" == 1 ]]; then
  exit 0
fi

if ! ls /dev/nvidia* >/dev/null 2>&1 && [[ ! -e /usr/lib/x86_64-linux-gnu/libcuda.so.1 ]]; then
  log "ATTENTION : aucun GPU NVIDIA visible dans le conteneur (lancer avec --gpus all)."
fi

# --- Lancement avec relance automatique ------------------------------------
child=0
tailer=0
if [[ -n "$logfile" && ! -t 1 ]]; then
  : > "$logfile"
  tail -n0 -F "$logfile" 2>/dev/null &
  tailer=$!
fi

stop() {
  log "Arret demande, fermeture du mineur..."
  [[ $child -ne 0 ]] && kill -TERM "$child" 2>/dev/null && wait "$child"
  [[ $tailer -ne 0 ]] && kill "$tailer" 2>/dev/null
  exit 0
}
trap stop TERM INT

delay="${RESTART_DELAY:-10}"
while true; do
  "${cmd[@]}" &
  child=$!
  wait "$child"
  code=$?
  child=0
  log "Le mineur s'est arrete (code $code). Relance dans ${delay}s."
  sleep "$delay" &
  wait $!
done
