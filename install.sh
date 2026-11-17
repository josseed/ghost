#!/usr/bin/env bash
# =============================================================================
#  Ghost — instalador
#  Compila con SwiftPM (solo Command Line Tools), arma Ghost.app, la firma ad-hoc,
#  la instala en /Applications, enlaza el comando `ghost` y abre la app.
#
#  Uso:  ./install.sh [--no-launch] [--no-cli] [--user] [--help]
#
#  Es NO interactivo (apto para Claude Code y CI). Nunca pide contraseña: si
#  /usr/local/bin no es escribible y no hay sudo sin contraseña, instala el CLI en
#  ~/.local/bin y lo añade al PATH.
#
#  Códigos de salida:
#    0  OK                         12  faltan Command Line Tools / Swift antiguo
#    2  argumento inválido         13  falló la compilación o el empaquetado
#   10  no es macOS                14  falló la instalación o la firma
#   11  macOS anterior a 14
# =============================================================================
set -euo pipefail

APP_NAME="Ghost"
BUNDLE_ID="dev.ghost.Ghost"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$ROOT/dist"
STAGED_APP="$DIST_DIR/$APP_NAME.app"
BUILD_LOG="$DIST_DIR/build.log"
PROC_PATTERN="$APP_NAME.app/Contents/MacOS/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PATH_MARKER_BEGIN="# >>> ghost cli >>>"
PATH_MARKER_END="# <<< ghost cli <<<"

LAUNCH=1
INSTALL_CLI=1
INSTALL_DIR="${GHOST_INSTALL_DIR:-/Applications}"

# ---------------------------------------------------------------------------
# Salida
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_STEP=$'\033[1;35m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[1;31m'; C_DIM=$'\033[2m'; C_END=$'\033[0m'
else
  C_STEP=""; C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_END=""
fi
step() { printf '\n%s▸ %s%s\n' "$C_STEP" "$*" "$C_END"; }
ok()   { printf '  %s✔%s %s\n' "$C_OK" "$C_END" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$C_WARN" "$C_END" "$*"; }
info() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_END"; }
die()  { local code="$1"; shift; printf '\n%s✖ %s%s\n' "$C_ERR" "$*" "$C_END" >&2; exit "$code"; }

usage() {
  sed -n '3,17p' "$0" | sed -E 's/^# ?//'
}

for arg in "$@"; do
  case "$arg" in
    --no-launch) LAUNCH=0 ;;
    --no-cli) INSTALL_CLI=0 ;;
    --user) INSTALL_DIR="$HOME/Applications" ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Argumento desconocido: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

printf '%s\n' "${C_STEP}👻 Instalando Ghost${C_END}"

# ---------------------------------------------------------------------------
# 1. Comprobaciones previas
# ---------------------------------------------------------------------------
step "Comprobando el sistema"

[ "$(uname -s)" = "Darwin" ] || die 10 "Ghost solo funciona en macOS."

OS_VERSION="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VERSION%%.*}"
if [ "$OS_MAJOR" -lt 14 ]; then
  die 11 "Ghost requiere macOS 14 Sonoma o superior (este Mac tiene macOS $OS_VERSION)."
fi
ok "macOS $OS_VERSION ($(uname -m))"

if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  die 12 "Faltan las Command Line Tools de Xcode.
   Se ha abierto el instalador de Apple: pulsa «Instalar», espera a que termine
   (5-10 min) y vuelve a ejecutar ./install.sh"
fi
ok "Herramientas de desarrollo: $(xcode-select -p)"

SWIFT_VERSION="$(xcrun swift --version 2>&1 | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
if [ -n "$SWIFT_VERSION" ]; then
  SWIFT_MAJOR="${SWIFT_VERSION%%.*}"
  SWIFT_MINOR="${SWIFT_VERSION#*.}"
  if [ "$SWIFT_MAJOR" -lt 5 ] || { [ "$SWIFT_MAJOR" -eq 5 ] && [ "$SWIFT_MINOR" -lt 9 ]; }; then
    die 12 "Se necesita Swift 5.9 o superior (tienes $SWIFT_VERSION).
   Actualiza las Command Line Tools desde Ajustes del Sistema › General › Actualización de software,
   o ejecuta: softwareupdate --list"
  fi
  ok "Swift $SWIFT_VERSION"
else
  warn "No se pudo leer la versión de Swift; se intentará compilar igualmente."
fi

# ---------------------------------------------------------------------------
# 2. Compilación
# ---------------------------------------------------------------------------
step "Compilando Ghost en modo release (la primera vez tarda 1-2 min)"
mkdir -p "$DIST_DIR"
: > "$BUILD_LOG"

explain_build_failure() {
  if grep -qiE "license|agreeing to the xcode" "$BUILD_LOG"; then
    info "Causa probable: la licencia de Xcode no está aceptada."
    info "Solución: sudo xcodebuild -license accept   (y vuelve a ejecutar ./install.sh)"
  elif grep -qiE "SDK is not supported by the compiler|could not build module|failed to build module|redefinition of module" "$BUILD_LOG"; then
    info "Causa probable: las Command Line Tools no coinciden con la versión de macOS."
    info "Solución: sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
  elif grep -qiE "invalid active developer path|xcrun: error" "$BUILD_LOG"; then
    info "Causa probable: ruta de herramientas de desarrollo rota."
    info "Solución: xcode-select --install   o   sudo xcode-select --reset"
  elif grep -qiE "no space left" "$BUILD_LOG"; then
    info "Causa probable: disco lleno. Libera espacio y reintenta."
  else
    info "Revisa el log completo: $BUILD_LOG"
    info "Si el error menciona la caché de compilación: rm -rf \"$ROOT/.build\" y reintenta."
  fi
}

if ! swift build -c release --package-path "$ROOT" 2>&1 | tee -a "$BUILD_LOG"; then
  explain_build_failure
  die 13 "La compilación falló."
fi
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"
[ -x "$BIN_DIR/$APP_NAME" ] || die 13 "No se encontró el ejecutable compilado en $BIN_DIR/$APP_NAME"
ok "Binario: $BIN_DIR/$APP_NAME"

# ---------------------------------------------------------------------------
# 3. Empaquetado de Ghost.app
# ---------------------------------------------------------------------------
step "Empaquetando $APP_NAME.app"
rm -rf "$STAGED_APP"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$STAGED_APP/Contents/MacOS/$APP_NAME"
chmod 755 "$STAGED_APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Sources/Ghost/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
printf 'APPL????' > "$STAGED_APP/Contents/PkgInfo"
cp "$ROOT/bin/ghost" "$STAGED_APP/Contents/Resources/ghost"
chmod 755 "$STAGED_APP/Contents/Resources/ghost"

plutil -lint "$STAGED_APP/Contents/Info.plist" >/dev/null || die 13 "Info.plist inválido."
ok "Estructura del bundle e Info.plist"

# Icono: Assets/AppIcon.png (1024 px) → AppIcon.icns con sips + iconutil (incluidos en macOS).
make_icns() {
  local source_png="$ROOT/Assets/AppIcon.png"
  local iconset
  [ -f "$source_png" ] || return 1
  iconset="$(mktemp -d "${TMPDIR:-/tmp}/ghost-icon.XXXXXX")/AppIcon.iconset"
  mkdir -p "$iconset"
  local size
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null || return 1
    sips -z $((size * 2)) $((size * 2)) "$source_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null || return 1
  done
  iconutil -c icns "$iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns" || return 1
  rm -rf "$(dirname "$iconset")"
}

if make_icns >>"$BUILD_LOG" 2>&1; then
  ok "Icono de la app"
else
  warn "No se pudo crear el icono (se usará el genérico). Detalles en $BUILD_LOG"
fi

# ---------------------------------------------------------------------------
# 4. Instalación
# ---------------------------------------------------------------------------
step "Instalando en $INSTALL_DIR"

if pgrep -f "$PROC_PATTERN" >/dev/null 2>&1; then
  info "Cerrando la instancia de Ghost en ejecución…"
  open -g "ghost://quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -f "$PROC_PATTERN" >/dev/null 2>&1 || break
    sleep 0.25
  done
  pkill -f "$PROC_PATTERN" >/dev/null 2>&1 || true
fi

if [ "$INSTALL_DIR" = "/Applications" ] && [ ! -w "/Applications" ]; then
  warn "/Applications no es escribible por este usuario; se instalará en ~/Applications."
  INSTALL_DIR="$HOME/Applications"
fi
mkdir -p "$INSTALL_DIR" || die 14 "No se pudo crear $INSTALL_DIR"
DEST_APP="$INSTALL_DIR/$APP_NAME.app"

if [ -e "$DEST_APP" ]; then
  rm -rf "$DEST_APP" || die 14 "No se pudo reemplazar $DEST_APP (¿pertenece a otro usuario?).
   Bórrala a mano desde el Finder o ejecuta: sudo rm -rf \"$DEST_APP\""
fi
ditto "$STAGED_APP" "$DEST_APP" || die 14 "No se pudo copiar Ghost.app a $INSTALL_DIR"
xattr -cr "$DEST_APP" 2>/dev/null || true
ok "Copiado a $DEST_APP"

step "Firmando (ad-hoc, local)"
codesign --force --deep --sign - "$DEST_APP" >>"$BUILD_LOG" 2>&1 || die 14 "codesign falló. Detalles en $BUILD_LOG"
codesign --verify --deep --strict "$DEST_APP" >>"$BUILD_LOG" 2>&1 || die 14 "La verificación de la firma falló. Detalles en $BUILD_LOG"
ok "Firma ad-hoc verificada (sin App Sandbox; acceso completo a IOKit)"

if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
  ok "URL scheme ghost:// registrado"
fi

# ---------------------------------------------------------------------------
# 5. Comando `ghost`
# ---------------------------------------------------------------------------
CLI_SOURCE="$DEST_APP/Contents/Resources/ghost"
CLI_INSTALLED=""

is_our_link() {
  [ -L "$1" ] && case "$(readlink "$1")" in *"$APP_NAME.app/Contents/Resources/ghost") return 0 ;; *) return 1 ;; esac
}

can_use_target() {
  # Libre, o ya es nuestro enlace.
  [ ! -e "$1" ] && [ ! -L "$1" ] && return 0
  is_our_link "$1"
}

ensure_local_bin_in_path() {
  case ":$PATH:" in *":$HOME/.local/bin:"*) return 0 ;; esac
  local rc="$HOME/.zshrc"
  case "${SHELL:-}" in */bash) rc="$HOME/.bash_profile" ;; esac
  if ! grep -qF "$PATH_MARKER_BEGIN" "$rc" 2>/dev/null; then
    {
      printf '\n%s\n' "$PATH_MARKER_BEGIN"
      printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"'
      printf '%s\n' "$PATH_MARKER_END"
    } >> "$rc"
    info "Añadido ~/.local/bin al PATH en $rc (abre una terminal nueva para usar 'ghost')."
  fi
}

install_cli() {
  local target="/usr/local/bin/ghost"

  if can_use_target "$target"; then
    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
      ln -sf "$CLI_SOURCE" "$target" && CLI_INSTALLED="$target" && return 0
    fi
    if sudo -n true 2>/dev/null; then
      sudo mkdir -p /usr/local/bin && sudo ln -sf "$CLI_SOURCE" "$target" && CLI_INSTALLED="$target" && return 0
    fi
    if [ -t 0 ] && [ -t 1 ]; then
      info "Se necesita tu contraseña de administrador para crear $target"
      if sudo mkdir -p /usr/local/bin && sudo ln -sf "$CLI_SOURCE" "$target"; then
        CLI_INSTALLED="$target"
        return 0
      fi
    fi
  else
    warn "$target ya existe y no pertenece a Ghost; no se modifica."
  fi

  local fallback="$HOME/.local/bin/ghost"
  mkdir -p "$HOME/.local/bin"
  if can_use_target "$fallback"; then
    ln -sf "$CLI_SOURCE" "$fallback"
    CLI_INSTALLED="$fallback"
    ensure_local_bin_in_path
    info "Para usar /usr/local/bin/ghost en su lugar: sudo ln -sf \"$CLI_SOURCE\" /usr/local/bin/ghost"
    return 0
  fi
  warn "$fallback ya existe y no pertenece a Ghost; el CLI no se instaló."
  return 1
}

if [ "$INSTALL_CLI" -eq 1 ]; then
  step "Instalando el comando 'ghost'"
  if install_cli; then
    ok "CLI: $CLI_INSTALLED → $CLI_SOURCE"
  else
    warn "Puedes usarlo directamente con: \"$CLI_SOURCE\" status"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Arranque y verificación
# ---------------------------------------------------------------------------
if [ "$LAUNCH" -eq 1 ]; then
  step "Abriendo Ghost"
  open "$DEST_APP" || die 14 "No se pudo abrir $DEST_APP"
  started=0
  for _ in $(seq 1 40); do
    if pgrep -f "$PROC_PATTERN" >/dev/null 2>&1 && [ -f "$HOME/Library/Application Support/Ghost/status" ]; then
      started=1
      break
    fi
    sleep 0.25
  done
  if [ "$started" -eq 1 ]; then
    ok "Ghost está en ejecución (busca el fantasma 👻 en la barra de menú)"
    echo
    "$CLI_SOURCE" status || true
  else
    warn "Ghost no respondió a tiempo. Comprueba la barra de menú o ejecuta: open \"$DEST_APP\""
  fi
fi

cat <<EOF

${C_OK}✔ Ghost instalado.${C_END}
  App      : $DEST_APP
  Atajo    : ⇧⌘G  (apaga / enciende la pantalla manteniendo el Mac despierto)
  Terminal : ghost on 2h · ghost sleep · ghost wake · ghost off · ghost status
  Inicio   : ghost login on   (abrir Ghost al iniciar sesión)
  Quitar   : ./uninstall.sh
EOF
