import AppKit
import SwiftUI

/// Icono de estado (barra de menú y cabecera del popover): un fantasma dibujado a partir de
/// la silueta de `Assets/AppIcon.svg`. Es una imagen *template*, así que macOS la colorea
/// solo según el modo claro/oscuro y el estado del botón.
///
/// - Inactivo: contorno con ojos abiertos (el botón además aparece atenuado).
/// - Mac despierto: fantasma relleno con ojos abiertos.
/// - Modo Ghost: fantasma relleno con los ojos cerrados (pantalla apagada, Mac vivo).
/// - Pausa por batería baja: SF Symbol `battery.25percent`.
enum GhostIcon {
    enum State { case idle, awake, ghost, lockout }

    static func state(isAwake: Bool, ghostMode: Bool, lockout: Bool) -> State {
        if lockout { return .lockout }
        if ghostMode { return .ghost }
        if isAwake { return .awake }
        return .idle
    }

    /// Imagen template de 18×18 pt.
    static func image(for state: State) -> NSImage {
        if state == .lockout {
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let image = NSImage(systemSymbolName: "battery.25percent", accessibilityDescription: "Ghost")?
                .withSymbolConfiguration(configuration) ?? NSImage()
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            drawGhost(state)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ghost"
        return image
    }

    // MARK: Dibujo

    /// Escala la silueta del SVG (x 322…702, y 296…792) a 16 pt de alto, centrada en 18×18.
    private static let scale: CGFloat = 16 / 496
    private static let origin = NSPoint(x: (18 - 380 * scale) / 2, y: 1)

    private static func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: origin.x + (x - 322) * scale, y: origin.y + (y - 296) * scale)
    }

    private static func bodyPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(322, 528))
        path.curve(to: point(512, 296), controlPoint1: point(322, 398), controlPoint2: point(406, 296))
        path.curve(to: point(702, 528), controlPoint1: point(618, 296), controlPoint2: point(702, 398))
        path.line(to: point(702, 748))
        // Tres ondas en la base (medias elipses rx 63.33, ry 44), de derecha a izquierda.
        let rx: CGFloat = 63.33, ry: CGFloat = 44, top: CGFloat = 748, k: CGFloat = 0.5523
        for cx in [638.67, 512, 385.33] as [CGFloat] {
            path.curve(to: point(cx, top + ry),
                       controlPoint1: point(cx + rx, top + k * ry),
                       controlPoint2: point(cx + k * rx, top + ry))
            path.curve(to: point(cx - rx, top),
                       controlPoint1: point(cx - k * rx, top + ry),
                       controlPoint2: point(cx - rx, top + k * ry))
        }
        path.close()
        return path
    }

    private static let eyeCenters = [point(450, 515), point(574, 515)]

    private static func openEyes() -> NSBezierPath {
        let path = NSBezierPath()
        for center in eyeCenters {
            path.appendOval(in: NSRect(x: center.x - 1, y: center.y - 1.35, width: 2, height: 2.7))
        }
        return path
    }

    /// Ojos cerrados "‿ ‿" como en el icono de la app.
    private static func closedEyes() -> NSBezierPath {
        let path = NSBezierPath()
        for center in eyeCenters {
            let half: CGFloat = 1.35, dip: CGFloat = 1.2
            let start = NSPoint(x: center.x - half, y: center.y - dip / 2)
            let end = NSPoint(x: center.x + half, y: center.y - dip / 2)
            let control = NSPoint(x: center.x, y: center.y - dip / 2 + dip * 2)
            path.move(to: start)
            path.curve(to: end,
                       controlPoint1: NSPoint(x: start.x + (control.x - start.x) * 2 / 3,
                                              y: start.y + (control.y - start.y) * 2 / 3),
                       controlPoint2: NSPoint(x: end.x + (control.x - end.x) * 2 / 3,
                                              y: end.y + (control.y - end.y) * 2 / 3))
        }
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        return path
    }

    private static func drawGhost(_ state: State) {
        NSColor.black.set()
        let body = bodyPath()
        switch state {
        case .idle:
            body.lineWidth = 1.3
            body.lineJoinStyle = .round
            body.stroke()
            openEyes().fill()
        case .awake, .ghost:
            body.fill()
            // Los ojos se recortan del relleno para que se vea el fondo de la barra.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            if state == .awake { openEyes().fill() } else { closedEyes().stroke() }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        case .lockout:
            break
        }
    }
}

@MainActor
struct GhostMenuBarView: View {
    @ObservedObject var controller: GhostController
    @ObservedObject var settings: GhostSettings
    let openSettings: () -> Void
    let quit: () -> Void

    private let cardFill = Color.white.opacity(0.06)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            awakeCard
            ghostModeButton
            timerSection
            if !controller.triggerReasons.isEmpty {
                triggerChips
            }
            if let notice = controller.notice {
                noticeView(notice)
            }
            statsRow
            Divider().opacity(0.4)
            footer
        }
        .padding(16)
        .frame(width: 320)
        .preferredColorScheme(.dark)
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(controller.isAwake ? Color.white.opacity(0.16) : cardFill)
                    .frame(width: 40, height: 40)
                Image(nsImage: GhostIcon.image(for: GhostIcon.state(isAwake: controller.isAwake,
                                                                    ghostMode: controller.ghostModeActive,
                                                                    lockout: controller.batteryLockout)))
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Ghost")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(controller.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let end = controller.sessionEndsAt {
                Text(end, style: .timer)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: Mantener despierto

    private var awakeCard: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mantener Mac despierto")
                    .font(.system(size: 13, weight: .medium))
                Text("El sistema no dormirá; la pantalla sí puede apagarse")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { controller.manualAwake },
                set: { $0 ? controller.enable(.indefinite) : controller.disable() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill))
    }

    // MARK: Modo Ghost

    private var ghostModeButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: { controller.toggleGhostMode() }) {
                HStack(spacing: 10) {
                    Image(systemName: controller.ghostModeActive ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(controller.ghostModeActive ? "Salir del Modo Ghost" : "Activar Modo Ghost")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(settings.hotkey.display)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .foregroundStyle(.white)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(white: 0.24), Color(white: 0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Text(settings.useBlackCurtain
                 ? "Cubre las pantallas con negro; el Mac sigue trabajando."
                 : "Apaga la pantalla al instante; el Mac sigue trabajando.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
    }

    // MARK: Temporizador

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEMPORIZADOR")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(GhostDuration.presets) { duration in
                    let selected = controller.manualAwake && controller.selectedDuration == duration
                    Button {
                        selected ? controller.disable() : controller.enable(duration)
                    } label: {
                        Text(duration.shortLabel)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color.black : Color.white.opacity(0.9))
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.white.opacity(0.92) : cardFill)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(duration.minutes == nil ? "Sin límite" : "Mantener despierto \(duration.shortLabel)")
                }
            }
        }
    }

    // MARK: Triggers y avisos

    private var triggerChips: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            ForEach(controller.triggerReasons, id: \.self) { reason in
                Text(reason)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(cardFill))
            }
            Spacer(minLength: 0)
        }
    }

    private func noticeView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                controller.notice = nil
            } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Estadísticas en vivo

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(symbol: "cpu",
                 value: controller.cpuUsage.map { String(format: "%.0f%%", $0) } ?? "—")
            Spacer()
            stat(symbol: "arrow.up.arrow.down",
                 value: controller.networkKBps.map(GhostFormat.rate) ?? "—")
            Spacer()
            stat(symbol: batterySymbol,
                 value: controller.battery.percent.map { "\($0)%" } ?? "AC")
        }
        .padding(.horizontal, 4)
    }

    private var batterySymbol: String {
        if !controller.battery.hasBattery { return "powerplug.fill" }
        return controller.battery.isOnAC ? "battery.100percent.bolt" : "battery.50percent"
    }

    private func stat(symbol: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
        }
    }

    // MARK: Pie

    private var footer: some View {
        HStack {
            Button("Ajustes…", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button("Salir de Ghost", action: quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
