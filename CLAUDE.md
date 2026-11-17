# CLAUDE.md — Ghost

Ghost es una app nativa de barra de menú para macOS que mantiene el Mac despierto
(CPU, red, descargas, servidores) mientras permite apagar la pantalla al instante
("Modo Ghost"). Swift + SwiftUI + AppKit + IOKit, compilada con Swift Package Manager.
**No necesita Xcode.app**: bastan las Command Line Tools.

La mayoría de quienes abran este repo con Claude Code solo querrán **instalarla**.
Suelen ser personas no técnicas: habla en su idioma (español por defecto), sin jerga,
y no les pidas que abran Xcode ni editen archivos.

---

## Si el usuario pide "instálame esto" / "instala Ghost"

"Ghost" aquí es **esta app de macOS** (github.com/MagdaIG/ghost), no la plataforma de
blogs Ghost ni `ghost-cli` de npm. No uses npm ni Homebrew para instalarla.

Sigue estos pasos en orden. `install.sh` es idempotente y **no interactivo**: nunca pide
contraseña ni se queda esperando entrada, así que puedes ejecutarlo directamente.

1. **Comprueba que es un Mac** — `uname -s` debe ser `Darwin` y `sw_vers -productVersion` ≥ 14.
   Si no es macOS 14+, explica que Ghost requiere macOS Sonoma o posterior y detente.
2. **Instala:**
   ```bash
   ./install.sh
   ```
   (Si el repo no está clonado: `git clone https://github.com/MagdaIG/ghost.git ~/ghost && cd ~/ghost && ./install.sh`.)
   La primera compilación tarda 1–2 minutos; usa un timeout de al menos 10 minutos.
3. **Verifica:**
   ```bash
   ghost status || "/Applications/Ghost.app/Contents/Resources/ghost" status
   pmset -g assertions | grep -i ghost   # solo muestra algo si Ghost está activo
   ```
   `ghost status` debe decir "👻 Ghost" con el estado. Un estado "no despierto" es normal
   recién instalado.
4. **Explícale al usuario, en 4–5 líneas:** dónde está el icono (fantasma 👻 en la barra de menú),
   el atajo `⇧⌘G` (apaga/enciende la pantalla manteniendo el Mac despierto), que con
   `ghost on 2h` / `ghost off` lo controla desde la terminal, y ofrécele activar el inicio
   automático con `ghost login on`.
5. Si `install.sh` instaló el CLI en `~/.local/bin` (lo indica en la salida), dile que abra
   una terminal nueva para usar `ghost`.

No hagas commits, no cambies código y no instales Homebrew ni dependencias para instalar.

### Códigos de salida de `install.sh` y qué hacer

| Código | Significado | Acción |
|---|---|---|
| 0 | Instalado | Paso 3 (verificar). |
| 10 | No es macOS | Ghost solo funciona en Mac. Detente. |
| 11 | macOS < 14 | Requiere Sonoma o posterior. Detente. |
| 12 | Faltan Command Line Tools o Swift < 5.9 | El script ya abrió el instalador de Apple (`xcode-select --install`). Pide al usuario que pulse «Instalar», espere a que termine y te avise; luego vuelve a ejecutar `./install.sh`. Si Swift es antiguo: que actualice macOS/CLT en Actualización de software. |
| 13 | Falló compilación/empaquetado | Lee `dist/build.log`. Ver tabla de problemas. |
| 14 | Falló copia/firma/apertura | Lee el mensaje; ver tabla de problemas. |

### Comandos que requieren contraseña (sudo)

Tu terminal no puede escribir contraseñas. **Nunca** ejecutes `sudo` esperando una
contraseña. Si hace falta, pide al usuario que lo ejecute él mismo escribiendo en el
prompt de Claude Code el comando con el prefijo `!` (por ejemplo
`! sudo xcodebuild -license accept`) y que te avise cuando termine.

### Problemas conocidos

| Síntoma (en la salida o en `dist/build.log`) | Solución |
|---|---|
| `xcrun: error: invalid active developer path` | `xcode-select --install` y reintentar. |
| Menciona `license` / `Agreeing to the Xcode` | El usuario ejecuta `! sudo xcodebuild -license accept`. |
| `SDK is not supported by the compiler`, `could not build module 'Foundation'`, `redefinition of module` | CLT desactualizadas o mezcladas con Xcode: el usuario ejecuta `! sudo rm -rf /Library/Developer/CommandLineTools` y luego `xcode-select --install`. Si tiene Xcode.app: `! sudo xcode-select -s /Applications/Xcode.app`. |
| Errores raros de caché o "module compiled with a different version" | `rm -rf .build dist && ./install.sh` |
| `/Applications no es escribible` | El script instala en `~/Applications` automáticamente; está bien. |
| `No se pudo reemplazar /Applications/Ghost.app` | Pertenece a otro usuario: `! sudo rm -rf /Applications/Ghost.app` y reintentar. |
| El atajo ⇧⌘G no hace nada | Otra app lo usa (Ajustes de Ghost lo avisa) → cambiarlo en Ajustes. O hay "Entrada segura" activa (campo de contraseña, Terminal con *Secure Keyboard Entry*). Ghost **no** necesita permiso de Accesibilidad: no lo pidas. |
| La pantalla se enciende sola justo tras apagarla | Movimiento del ratón/trackpad. Ghost ya espera a que se suelten las teclas; pide no tocar el ratón ~1 s. |
| Al despertar pide contraseña | Es la pantalla de bloqueo de macOS (Ajustes › Pantalla de bloqueo › "Solicitar contraseña"). Ghost no la toca; los procesos siguieron funcionando. |
| Con tapa cerrada el Mac se duerme | Esperado sin monitor externo + corriente: macOS no permite evitarlo con aserciones de usuario. Ver README › Limitaciones. |
| `ghost: command not found` | Abrir terminal nueva, o usar `/Applications/Ghost.app/Contents/Resources/ghost`. |

### Desinstalar
```bash
./uninstall.sh          # app, CLI, PATH e inicio automático
./uninstall.sh --purge  # además borra las preferencias
```
Si sale con código 1 lista comandos `sudo` pendientes: pásaselos al usuario con prefijo `!`.

---

## Desarrollo

```bash
swift build                       # debug
swift build -c release            # release (lo que usa install.sh)
./install.sh --no-launch          # reempaquetar e instalar sin abrir
.build/debug/Ghost                # ejecutar sin bundle (URL scheme y login item no funcionan así)
log stream --predicate 'process == "Ghost"'   # logs (NSLog)
pmset -g assertions               # ver la aserción "Ghost: …"
```

No hay suite de tests: verifica con `swift build` y con el ciclo real
`./install.sh` → `ghost on 1m` → `pmset -g assertions | grep Ghost` → `ghost sleep` →
`ghost wake` → `ghost off`.

### Arquitectura (`Sources/Ghost/`)

| Archivo | Responsabilidad |
|---|---|
| `GhostApp.swift` | `@main`, `AppDelegate`, `NSStatusItem` + `NSPopover`, ventana de ajustes, menú principal (⌘C/⌘V), URL scheme `ghost://`. |
| `GhostController.swift` | Cerebro. Estado publicado, temporizador, triggers (apps/CPU/red), protección de batería, Modo Ghost, `reconcile()` (única fuente de verdad de la aserción) y archivo de estado para el CLI. |
| `GhostPowerManager.swift` | IOKit: aserción `PreventUserIdleSystemSleep`, `pmset displaysleepnow` (+ fallback `IORequestIdle`), `IOPMAssertionDeclareUserActivity` para despertar, lectura de batería (`IOPS*`), muestreo de CPU (`host_statistics`) y red (`getifaddrs`). |
| `GhostHotkeyManager.swift` | Atajo global con Carbon `RegisterEventHotKey` (consume la tecla, sin permisos TCC) y `GhostShortcut`. |
| `BlackCurtainManager.swift` | Ventanas negras a nivel salvapantallas en todas las pantallas. |
| `GhostMenuBarView.swift` | Popover SwiftUI y `GhostIcon` (fantasma de la barra de menú dibujado con `NSBezierPath` a partir de `AppIcon.svg`). |
| `GhostSettingsView.swift` | `GhostSettings` (UserDefaults), ventana de ajustes, grabador de atajos, login item (`SMAppService`). |
| `Resources/Info.plist` | Excluido de SwiftPM; `install.sh` lo copia a `Ghost.app/Contents/`. |
| `bin/ghost` | CLI en bash 3.2 (el de macOS). Envía `open -g ghost://…` y lee `~/Library/Application Support/Ghost/status`. |
| `Assets/AppIcon.svg` | Fuente del icono (diseño original). Tras editarlo: `rsvg-convert -w 1024 -h 1024 Assets/AppIcon.svg -o Assets/AppIcon.png`. |
| `Assets/AppIcon.png` | Icono 1024 px; `install.sh` lo convierte a `AppIcon.icns` con `sips` + `iconutil`. **No uses SF Symbols para el icono de la app**: su licencia lo prohíbe (en la UI sí están permitidos). |

### Reglas del proyecto

- **Solo frameworks de Apple.** No añadas dependencias SwiftPM.
- **Sin App Sandbox** y firma **ad-hoc** (`codesign --sign -`). No añadas entitlements.
- **No uses CGEventTap ni APIs que requieran permisos TCC** (Accesibilidad / Monitorización
  de entrada): con firma ad-hoc el permiso se invalida en cada recompilación.
- **Nunca crees `PreventUserIdleDisplaySleep`**: rompería la idea de "pantalla apagable".
- Swift tools 5.9, macOS 14+. Todo el estado de UI vive en clases `@MainActor`; las vistas
  se anotan `@MainActor` para compilar igual con SDKs de Xcode 15 y 16.
- `bin/ghost` debe seguir siendo compatible con bash 3.2 (sin `mapfile`, sin arrays asociativos).
- Si añades un comando: implementarlo en `GhostController.handle(url:)` (o en
  `AppDelegate.handle` si es de app), en `bin/ghost`, y documentarlo en README.
- Interfaz en español.
