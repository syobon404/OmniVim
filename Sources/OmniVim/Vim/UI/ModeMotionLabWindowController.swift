#if DEBUG
import AppKit
import SwiftUI

@MainActor
final class ModeMotionLabWindowController: NSWindowController {
    init() {
        let rootView = ModeMotionLabView()
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "OmniVim Motion Lab"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 700))
        window.minSize = NSSize(width: 820, height: 620)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private enum LabMode: String, CaseIterable, Identifiable {
    case normal
    case insert
    case hint

    var id: Self { self }

    var glyph: String {
        switch self {
        case .normal: "N"
        case .insert: "I"
        case .hint: "H"
        }
    }

    var label: String { rawValue.uppercased() }

    var detail: String {
        switch self {
        case .normal: "j + k"
        case .insert: "typing"
        case .hint: "12 targets"
        }
    }

    var accent: Color {
        switch self {
        case .normal: Color(red: 0.49, green: 1, blue: 0.70)
        case .insert: Color(red: 0.43, green: 0.84, blue: 1)
        case .hint: Color(red: 1, green: 0.82, blue: 0.38)
        }
    }
}

private enum LabMaterial: String, CaseIterable, Identifiable {
    case regular = "Regular"
    case clearStudy = "Clear study"

    var id: Self { self }

    var material: Material {
        switch self {
        case .regular: .regularMaterial
        case .clearStudy: .ultraThinMaterial
        }
    }
}

private enum LabPreset: String, CaseIterable, Identifiable {
    case subtle = "Subtle"
    case expressive = "Expressive"

    var id: Self { self }
}

private struct ModeMotionLabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    @State private var mode: LabMode = .insert
    @State private var material: LabMaterial = .regular
    @State private var preset: LabPreset = .subtle
    @State private var compact = false
    @State private var pillOpacity = 1.0
    @State private var pillScale = 1.0
    @State private var focusOnRight = false
    @State private var insertCompactTask: Task<Void, Never>?
    @State private var loopTask: Task<Void, Never>?
    @State private var slowMotion = false
    @State private var loopEnabled = false

    @State private var stiffness = 260.0
    @State private var damping = 24.0
    @State private var transitionDuration = 0.16
    @State private var tintStrength = 0.14
    @State private var bloomRadius = 14.0

    private var spring: Animation {
        let animation: Animation = reduceMotion
            ? .easeOut(duration: min(transitionDuration, 0.12))
            : .interpolatingSpring(
                mass: 1,
                stiffness: stiffness,
                damping: damping,
                initialVelocity: 0
            )
        return slowMotion && !reduceMotion ? animation.speed(0.32) : animation
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                header
                preview
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            controls
                .frame(width: 272)
                .padding(24)
                .background(Color.black.opacity(0.2))
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.06, blue: 0.11),
                    Color(red: 0.06, green: 0.09, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.dark)
        .onChange(of: preset) { applyPreset($0) }
        .onChange(of: loopEnabled) { enabled in
            enabled ? startLoop() : stopLoop()
        }
        .onDisappear {
            insertCompactTask?.cancel()
            loopTask?.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("OMNIVIM / MOTION LAB")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.56, green: 1, blue: 0.82))
            Text("Liquid state transitions")
                .font(.system(size: 30, weight: .semibold))
            Text("Motion happens at mode boundaries, never on ordinary keystrokes.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Label(
                nativeGlassAvailable ? "macOS 26 native Liquid Glass" : "Legacy material fallback",
                systemImage: nativeGlassAvailable ? "sparkles" : "square.stack.3d.up"
            )
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(nativeGlassAvailable ? LabMode.normal.accent : .secondary)
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.39, green: 0.28, blue: 0.63),
                        Color(red: 0.03, green: 0.40, blue: 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                editorWindow
                    .padding(22)

                hintLabels

                pill
                    .position(
                        x: focusOnRight ? proxy.size.width * 0.72 : proxy.size.width * 0.42,
                        y: proxy.size.height * 0.80
                    )
                    .opacity(pillOpacity)
                    .scaleEffect(pillScale)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
        .frame(minHeight: 430)
    }

    private var editorWindow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color.red.opacity(0.9)).frame(width: 10, height: 10)
                Circle().fill(Color.yellow.opacity(0.9)).frame(width: 10, height: 10)
                Circle().fill(Color.green.opacity(0.9)).frame(width: 10, height: 10)
                Spacer()
                Text("Mode behavior")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.48))
                Spacer()
                Color.clear.frame(width: 44, height: 1)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.white.opacity(0.72))

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.4))
                    sidebarRow("Mode behavior", selected: true)
                    sidebarRow("Focus rules", selected: false)
                    sidebarRow("Hint targets", selected: false)
                    Spacer()
                }
                .padding(14)
                .frame(width: 150)
                .background(Color(red: 0.86, green: 0.91, blue: 0.96))

                VStack(alignment: .leading, spacing: 14) {
                    Text("State follows focus.")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(Color(red: 0.08, green: 0.18, blue: 0.27))
                    Text("The mode belongs to the editable control—not the application.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.48))
                    Divider().opacity(0.5)
                    Text("• Entering an editable field starts in Insert.")
                    Text("• Hold j, then press k to return to Normal.")
                    Text("• Hint labels appear only over actionable targets.")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.58))
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.96, green: 0.98, blue: 1))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }

    private func sidebarRow(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 11, weight: selected ? .semibold : .regular))
            .foregroundStyle(Color.black.opacity(selected ? 0.68 : 0.44))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(selected ? Color.white.opacity(0.75) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var pill: some View {
        if #available(macOS 26.0, *) {
            nativeLiquidGlassPill
        } else {
            legacyMaterialPill
        }
    }

    private var legacyMaterialPill: some View {
        HStack(spacing: 9) {
            nucleus

            if !compact || mode == .hint {
                Text(mode.label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))

                Divider().frame(height: 16).opacity(0.45)

                Text(mode.detail)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, compact && mode != .hint ? 8 : 11)
        .frame(height: 47)
        .background(material.material)
        .background(mode.accent.opacity(tintStrength))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
        }
        .shadow(color: mode.accent.opacity(0.14), radius: bloomRadius)
        .shadow(color: .black.opacity(0.32), radius: 18, y: 9)
        .animation(spring, value: mode)
        .animation(spring, value: compact)
    }

    @available(macOS 26.0, *)
    private var nativeLiquidGlassPill: some View {
        GlassEffectContainer(spacing: preset == .expressive ? 18 : 10) {
            HStack(spacing: preset == .expressive ? 8 : 5) {
                nucleus
                    .padding(5)
                    .glassEffect(
                        glassConfiguration(strength: 1),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .glassEffectID("nucleus", in: glassNamespace)
                    .glassEffectTransition(.matchedGeometry)

                if !compact || mode == .hint {
                    Text(mode.label)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 12)
                        .frame(height: 37)
                        .glassEffect(
                            glassConfiguration(strength: 0.48),
                            in: Capsule()
                        )
                        .glassEffectID("mode-label", in: glassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                }

                if mode == .hint {
                    Text(mode.detail)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .glassEffect(
                            glassConfiguration(strength: 0.72),
                            in: Capsule()
                        )
                        .glassEffectID("mode-detail", in: glassNamespace)
                        .glassEffectTransition(.materialize)
                } else if !compact {
                    Text(mode.detail)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 31)
                        .glassEffect(.regular, in: Capsule())
                        .glassEffectID("mode-detail", in: glassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
        }
        .shadow(color: mode.accent.opacity(0.18), radius: bloomRadius)
        .shadow(color: .black.opacity(0.30), radius: 18, y: 9)
        .animation(spring, value: mode)
        .animation(spring, value: compact)
    }

    private var nucleus: some View {
        Text(mode.glyph)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(mode.accent)
            .frame(width: 27, height: 27)
            .background(mode.accent.opacity(0.18 + tintStrength * 0.3))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(mode.accent.opacity(0.34), lineWidth: 0.8)
            }
    }

    @available(macOS 26.0, *)
    private func glassConfiguration(strength: Double) -> Glass {
        let tint = mode.accent.opacity(tintStrength * strength)
        switch material {
        case .regular: return .regular.tint(tint)
        case .clearStudy: return .clear.tint(tint)
        }
    }

    private var nativeGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    @ViewBuilder
    private var hintLabels: some View {
        let hints: [(String, CGFloat, CGFloat)] = [
            ("A", -170, -82), ("S", 122, -102), ("D", 188, 15), ("F", -88, 64)
        ]
        ForEach(Array(hints.enumerated()), id: \.offset) { index, hint in
            Text(hint.0)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 23, height: 20)
                .background(LabMode.hint.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                .offset(x: hint.1, y: hint.2)
                .opacity(mode == .hint ? 1 : 0)
                .scaleEffect(mode == .hint ? 1 : 0.78)
                .animation(spring.delay(reduceMotion ? 0 : Double(index) * 0.014), value: mode)
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("TRANSITIONS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                VStack(spacing: 9) {
                    labButton("Insert appear", systemImage: "text.cursor") { showInsert() }
                    labButton("j + k → Normal", systemImage: "keyboard") { showNormal() }
                    labButton("f → Hint", systemImage: "scope") { showHint() }
                    labButton("Focus move", systemImage: "arrow.left.and.right") { moveFocus() }
                }

                Divider()

                VStack(alignment: .leading, spacing: 15) {
                    Picker("Preset", selection: $preset) {
                        ForEach(LabPreset.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Material", selection: $material) {
                        ForEach(LabMaterial.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    slider("Stiffness", value: $stiffness, range: 120...500, format: "%.0f")
                    slider("Damping", value: $damping, range: 10...40, format: "%.0f")
                    slider("Transition", value: $transitionDuration, range: 0.08...0.32, format: "%.2fs")
                    slider("Mode tint", value: $tintStrength, range: 0.04...0.28, format: "%.2f")
                    slider("Bloom", value: $bloomRadius, range: 0...28, format: "%.0f")

                    Toggle("Slow Motion", isOn: $slowMotion)
                    Toggle("Loop transitions", isOn: $loopEnabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        reduceMotion ? "Reduce Motion: crossfade" : "Spring motion active",
                        systemImage: reduceMotion ? "figure.walk.motion" : "waveform.path"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    Text(nativeGlassAvailable
                         ? "Native glass shapes merge, absorb, and materialize through one GlassEffectContainer. Regular remains the recommended production material."
                         : "Clear study approximates a highly translucent material. Production should prefer adaptive regular glass over unknown app backgrounds.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func labButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
            Slider(value: value, in: range)
        }
    }

    private func showInsert() {
        insertCompactTask?.cancel()
        compact = false
        mode = .insert
        pillOpacity = 0
        pillScale = reduceMotion ? 1 : 0.94
        withAnimation(spring) {
            pillOpacity = 1
            pillScale = 1
        }
        insertCompactTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, mode == .insert else { return }
            withAnimation(spring) { compact = true }
        }
    }

    private func showNormal() {
        insertCompactTask?.cancel()
        compact = false
        withAnimation(spring) {
            mode = .normal
            pillScale = reduceMotion ? 1 : 0.965
        }
        guard !reduceMotion else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            withAnimation(spring) { pillScale = 1 }
        }
    }

    private func showHint() {
        insertCompactTask?.cancel()
        compact = false
        withAnimation(spring) {
            mode = .hint
            pillScale = 1
        }
    }

    private func moveFocus() {
        insertCompactTask?.cancel()
        withAnimation(.easeOut(duration: min(transitionDuration, 0.10))) {
            pillOpacity = 0
            pillScale = reduceMotion ? 1 : 0.96
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(min(transitionDuration, 0.10) * 1_000_000_000))
            focusOnRight.toggle()
            withAnimation(.easeOut(duration: min(transitionDuration, 0.14))) {
                pillOpacity = 1
                pillScale = 1
            }
        }
    }

    private func applyPreset(_ preset: LabPreset) {
        switch preset {
        case .subtle:
            stiffness = 260
            damping = 24
            transitionDuration = 0.16
            tintStrength = 0.14
            bloomRadius = 14
        case .expressive:
            stiffness = 175
            damping = 14
            transitionDuration = 0.24
            tintStrength = 0.22
            bloomRadius = 24
        }
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                showInsert()
                await loopPause(1.4)
                guard !Task.isCancelled else { break }
                showNormal()
                await loopPause(1.1)
                guard !Task.isCancelled else { break }
                showHint()
                await loopPause(1.5)
                guard !Task.isCancelled else { break }
                moveFocus()
                await loopPause(1.1)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func loopPause(_ seconds: Double) async {
        let multiplier = slowMotion && !reduceMotion ? 2.4 : 1
        try? await Task.sleep(nanoseconds: UInt64(seconds * multiplier * 1_000_000_000))
    }
}
#endif
