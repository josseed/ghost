<p align="center">
  <img src="Assets/AppIcon.png" width="160" alt="Icono de Ghost: un fantasma con los ojos cerrados">
</p>

<h1 align="center">Ghost</h1>

<p align="center"><strong>Tu Mac sigue trabajando. La pantalla, no.</strong></p>

Ghost es una app minimalista para la barra de menú de macOS que mantiene el Mac despierto
(descargas, servidores, compilaciones, backups, renders…) mientras te deja **apagar la
pantalla al instante** con un atajo. Ahorras energía y proteges los paneles OLED / Mini-LED
cuando el equipo trabaja en segundo plano todo el día.

Como Caffeine o Amphetamine, pero con "modo fantasma": sistema despierto + pantalla apagada.

- 🪶 100 % nativa (Swift, SwiftUI, AppKit, IOKit). Sin dependencias, sin telemetría, sin red.
- 🔓 No pide permisos de Accesibilidad.
- 🛠️ Se instala sin Xcode: solo hacen falta las Command Line Tools gratuitas de Apple.

---

## Instalación en 1 paso (con Claude Code)

Abre Claude Code en una carpeta cualquiera y pega:

```
Instálame Ghost desde github.com/MagdaIG/ghost
```

Claude clonará el repositorio en `~/ghost`, leerá sus instrucciones (`CLAUDE.md`), compilará
la app, la firmará localmente, la copiará a `/Applications`, instalará el comando `ghost` y
la abrirá. Si falta algo (por ejemplo las herramientas de desarrollo de Apple), te dirá
exactamente qué pulsar.

> **Incluye siempre `MagdaIG/ghost`.** Si dices solo "instala ghost", Claude podría
> confundirlo con *Ghost*, la plataforma de blogs (`npm install ghost-cli`), que no tiene
> nada que ver.
>
> Si ya tienes el repositorio abierto en Claude Code, basta con decir: **"Instálame esto"**.

### Qué hace (y qué no) el instalador

- Compila el código fuente de este repositorio en tu Mac; no descarga binarios.
- Solo escribe en `/Applications/Ghost.app` (o `~/Applications`), en `/usr/local/bin/ghost`
  (o `~/.local/bin/ghost`) y en `~/Library/Application Support/Ghost`.
- Nunca pide tu contraseña ni envía datos a internet. Ghost no tiene telemetría ni
  conexiones de red.
- Todo se revierte con `./uninstall.sh`.

## Instalación manual

Requisitos: macOS 14 Sonoma o posterior.

```bash
xcode-select --install          # solo si nunca instalaste las Command Line Tools
git clone https://github.com/MagdaIG/ghost.git
cd ghost
./install.sh
```

Opciones: `--no-launch` (no abrir al terminar), `--no-cli` (no instalar el comando `ghost`),
`--user` (instalar en `~/Applications`).

---

## Uso

Busca el **fantasma** en la barra de menú:

| Icono | Estado |
|---|---|
| Contorno con ojos abiertos (atenuado) | Inactivo: el Mac duerme con normalidad |
| Relleno con ojos abiertos | Mac despierto (la pantalla puede apagarse) |
| Relleno con ojos cerrados | Modo Ghost: despierto y con la pantalla apagada |
| Batería baja | En pausa por batería baja |

- **Clic**: abre el panel (interruptor, Modo Ghost, temporizador, estado en vivo).
- **Clic derecho**: activa/desactiva "mantener despierto".
- **⌥ + clic**: entra o sale del Modo Ghost.

### Atajo global: `⇧⌘G`

- Con la pantalla encendida → mantiene el Mac despierto y **apaga la pantalla**.
- Con la pantalla apagada → **la enciende** y sale del Modo Ghost.

La tecla nunca llega a la app que tengas delante. Puedes cambiar el atajo en Ajustes.

### Temporizador

15 min, 30 min, 1 h, 2 h, 4 h o sin límite, con cuenta atrás en el panel. Al terminar,
el Mac vuelve a su reposo normal.

### Triggers inteligentes (Ajustes)

- **Apps**: mantener despierto mientras Docker, Xcode, tu cliente de torrent, etc. estén abiertos.
- **CPU**: mientras el uso supere un umbral (10–100 %).
- **Red**: mientras el tráfico supere un umbral (100 KB/s – 10 MB/s).

CPU y red se mantienen 60 s después de bajar del umbral para no cortar una descarga
irregular.

### Protección de batería

Si el MacBook está desenchufado y la batería baja del umbral (20 % por defecto), Ghost se
desactiva solo y el Mac vuelve a poder dormir.

### Cortina negra

Una alternativa a apagar la pantalla: cubre todas las pantallas con negro puro. Útil con
**Compartir Pantalla / VNC** (apagar el panel puede cortar la imagen remota) o con monitores
externos que no obedecen al apagado. Sales con el atajo, `Esc` o doble clic.

---

## Terminal

```bash
ghost on              # despierto sin límite
ghost on 2h           # durante 2 horas (también: 30, 45m, 1h30m)
ghost sleep           # Modo Ghost: apaga la pantalla ya
ghost curtain         # Modo Ghost con cortina negra
ghost wake            # enciende la pantalla
ghost off             # vuelve al reposo normal
ghost status          # estado (añade --json para scripts)
ghost login on|off    # abrir Ghost al iniciar sesión
ghost settings        # abrir ajustes
ghost quit            # cerrar Ghost
```

Ejemplo: `ghost on 3h && ghost sleep` antes de irte a comer con una descarga en curso.

### URL scheme y app Atajos

Todo está disponible como URL, así que puedes usarlo desde la app **Atajos** (acción
«Abrir URLs»), Raycast, Alfred, Stream Deck, etc.:

```
ghost://on            ghost://on?minutes=90     ghost://on?hours=2
ghost://off           ghost://toggle            ghost://sleep
ghost://wake          ghost://curtain           ghost://toggle-ghost
ghost://settings      ghost://quit
```

En Atajos también puedes usar «Ejecutar script de shell» con `/usr/local/bin/ghost sleep`.

---

## Cómo funciona

macOS decide cuándo dormir según *aserciones de energía*. Ghost solo mantiene una:

| Aserción | Efecto | Ghost |
|---|---|---|
| `PreventUserIdleSystemSleep` | El sistema no duerme por inactividad | ✅ la crea |
| `PreventUserIdleDisplaySleep` | La pantalla no se apaga | ❌ nunca |

Así la pantalla sigue apagándose según tus ajustes, y además Ghost puede apagarla al
momento con `pmset displaysleepnow` (o, como alternativa, `IORequestIdle` de IOKit). Para
encenderla usa `IOPMAssertionDeclareUserActivity`, que no envía pulsaciones falsas a
ninguna app. Compruébalo tú mismo:

```bash
pmset -g assertions | grep Ghost
```

Si Ghost se cierra o falla, macOS libera la aserción automáticamente: nunca deja tu Mac
"atascado" sin dormir.

## Limitaciones

- **Tapa cerrada**: sin monitor externo, macOS duerme al cerrar la tapa y ninguna app puede
  evitarlo con aserciones normales. Con monitor externo + corriente (+ teclado/ratón), el
  modo clamshell nativo de macOS funciona, y Ghost mantiene el sistema despierto.
- **Pantalla de bloqueo**: si tienes "Solicitar contraseña al apagar la pantalla", al
  despertar verás el bloqueo. Tus procesos siguen funcionando igualmente.
- **Entrada segura**: mientras haya un campo de contraseña activo (o Terminal con *Secure
  Keyboard Entry*), macOS bloquea todos los atajos globales, incluido el de Ghost.
- **Brillo**: la cortina negra no cambia el brillo del panel (requeriría APIs privadas),
  pero en OLED / Mini-LED el negro puro apaga los píxeles o zonas.

## Desinstalar

```bash
./uninstall.sh            # quita la app, el comando, el PATH y el inicio automático
./uninstall.sh --purge    # además borra tus ajustes
```

## Desarrollo

```bash
swift build               # compila (debug)
./install.sh --no-launch  # empaqueta e instala
```

Estructura, reglas y solución de problemas en [CLAUDE.md](CLAUDE.md).

## Licencia

MIT — ver [LICENSE](LICENSE).
