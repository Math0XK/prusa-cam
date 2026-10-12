#!/usr/bin/env bash
# Envoie une photo de la caméra du Pi vers Prusa Connect toutes les INTERVAL secondes.
# Config lue depuis /etc/prusa-cam.env (voir prusa-cam.env.example).
set -u

: "${PRUSA_TOKEN:?PRUSA_TOKEN manquant dans /etc/prusa-cam.env}"
INTERVAL="${INTERVAL:-10}"
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
QUALITY="${QUALITY:-80}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
# Identifiant stable et unique de cette caméra (dérivé de la machine si non fourni)
FINGERPRINT="${FINGERPRINT:-$(sha256sum /etc/machine-id | cut -c1-32)}"

URL="https://connect.prusa3d.com/c/snapshot"
SNAP="/dev/shm/prusa-cam.jpg"   # en RAM, épargne la carte SD

while true; do
  start=$(date +%s)

  # shellcheck disable=SC2086
  if rpicam-still -n --immediate -t 1 \
       --width "$WIDTH" --height "$HEIGHT" -q "$QUALITY" $EXTRA_ARGS \
       -o "$SNAP" >/dev/null 2>&1; then
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 \
      -X PUT "$URL" \
      -H "accept: */*" \
      -H "content-type: image/jpg" \
      -H "fingerprint: $FINGERPRINT" \
      -H "token: $PRUSA_TOKEN" \
      --data-binary "@$SNAP")
    case "$code" in
      2??) ;;
      *) echo "Envoi refusé ou échoué (HTTP $code)" ;;
    esac
  else
    echo "Échec de la capture (caméra détectée ? essayer: rpicam-hello --list-cameras)"
  fi

  elapsed=$(( $(date +%s) - start ))
  wait=$(( INTERVAL - elapsed ))
  [ "$wait" -lt 1 ] && wait=1
  sleep "$wait"
done
