#!/usr/bin/env bash
# Installe / met à jour / désinstalle la caméra Prusa Connect sur le Pi.
# Idempotent : peut être relancé autant de fois que nécessaire (après un git pull par ex.).
#
#   sudo ./install.sh                 installe ou met à jour (garde la config existante)
#   sudo ./install.sh --token XXXX    idem + enregistre le token Prusa Connect
#   sudo ./install.sh --uninstall     supprime le service et les fichiers installés
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_USER="${PRUSA_CAM_USER:-${SUDO_USER:-root}}"
BIN=/usr/local/bin/prusa-cam.sh
ENV_FILE=/etc/prusa-cam.env
UNIT=/etc/systemd/system/prusa-cam.service

TOKEN=""
UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --token) TOKEN="${2:?--token attend une valeur}"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; exit 1 ;;
  esac
done

if [ "$UNINSTALL" -eq 1 ]; then
  systemctl disable --now prusa-cam 2>/dev/null || true
  rm -f "$UNIT" "$BIN"
  systemctl daemon-reload
  echo "Désinstallé. Config conservée dans $ENV_FILE (à supprimer à la main si besoin)."
  exit 0
fi

echo "==> Dépendances"
if ! command -v curl >/dev/null || ! command -v rpicam-still >/dev/null; then
  apt-get update
  apt-get install -y curl
  command -v rpicam-still >/dev/null || apt-get install -y rpicam-apps-lite
fi

echo "==> Script"
install -m 755 "$REPO_DIR/pi/prusa-cam.sh" "$BIN"

echo "==> Configuration"
if [ ! -f "$ENV_FILE" ]; then
  install -m 600 "$REPO_DIR/pi/prusa-cam.env.example" "$ENV_FILE"
  echo "    $ENV_FILE créé depuis l'exemple"
fi
if [ -n "$TOKEN" ]; then
  sed -i "s|^PRUSA_TOKEN=.*|PRUSA_TOKEN=$TOKEN|" "$ENV_FILE"
  echo "    token enregistré"
fi

echo "==> Service (utilisateur : $RUN_USER)"
usermod -aG video "$RUN_USER" 2>/dev/null || true
sed "s/__USER__/$RUN_USER/" "$REPO_DIR/pi/prusa-cam.service" > "$UNIT"
systemctl daemon-reload

if grep -q '^PRUSA_TOKEN=.\+' "$ENV_FILE"; then
  systemctl enable prusa-cam >/dev/null
  systemctl restart prusa-cam
  echo "==> OK, service démarré. Logs : journalctl -u prusa-cam -f"
else
  echo "==> Pas encore de token : relance avec  sudo ./install.sh --token <TOKEN>"
fi
