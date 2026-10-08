import SwiftUI
import UsageCore

@main
struct AgentsUsageMonitorApp: App {
    @State private var store = UsageStore()
    @State private var launchAtLogin = LaunchAtLogin()

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(store: store, launchAtLogin: launchAtLogin)
        } label: {
            MenuBarLabel(items: store.menuBarItems)
        }
        .menuBarExtraStyle(.window)
    }
}

struct UsagePanel: View {
    let store: UsageStore
    let launchAtLogin: LaunchAtLogin
    @State private var dragging: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.visibleProviders, id: \.id) { p in
                VStack(alignment: .leading, spacing: 12) {
                    ProviderSection(provider: p, state: store.states[p.id] ?? .loading, retryAt: store.retryAt[p.id])
                    Divider()
                }
                .contentShape(Rectangle())
                .opacity(dragging == p.id ? 0.4 : 1)
                .onDrag {
                    dragging = p.id
                    return NSItemProvider(object: p.id as NSString)
                }
                .onDrop(of: [.text], delegate: ReorderDropDelegate(target: p.id, dragging: $dragging, store: store))
            }
            if let err = launchAtLogin.error {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack {
                if store.isRefreshing {
                    ProgressView().controlSize(.mini)
                    Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
                } else if let t = store.lastRefresh {
                    Text("Updated \(t, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Refresh") { Task { await store.refresh() } }
                        .keyboardShortcut("r")
                        .disabled(store.isRefreshing)
                    Toggle("Open at Login", isOn: Binding(get: { launchAtLogin.isEnabled },
                                                          set: { launchAtLogin.set($0) }))
                    Section("Show") {
                        ForEach(store.orderedProviders, id: \.id) { p in
                            Toggle(p.name, isOn: Binding(get: { store.layout.isVisible(p.id) },
                                                         set: { store.setVisible(p.id, $0) }))
                                .disabled(!store.layout.canToggle(p.id))
                        }
                    }
                    Divider()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// Live-reorders providers as a dragged section passes over another one.
struct ReorderDropDelegate: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let store: UsageStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.15)) { store.move(dragging, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

struct ProviderSection: View {
    let provider: any UsageProvider
    let state: ProviderState
    var retryAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProviderIcon(providerID: provider.id).frame(width: 16, height: 16)
                Text(provider.name).font(.headline)
                if let plan = state.usage?.plan {
                    Text(plan).font(.caption).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if case .loading = state { ProgressView().controlSize(.mini) }
            }
            if let usage = state.usage {
                ForEach(usage.windows) { WindowRow(window: $0) }
            }
            if case .failed(let msg, _, let last, let at) = state {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(msg)
                        if let retryAt, retryAt > Date() {
                            Text("Next attempt in \(retryAt, style: .relative).")
                        }
                        if last != nil, let at {
                            Text("Showing last known values from \(at, style: .relative) ago.")
                        }
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WindowRow: View {
    let window: UsageWindow

    private var tint: Color {
        switch window.usedPercent {
        case ..<60: .green
        case ..<85: .yellow
        default: .red
        }
    }

    @State private var isHovering = false

    var body: some View {
        let expected = window.expectedPercent()
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label).font(.subheadline)
                Spacer()
                if let d = window.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
                Text("\(Int(window.usedPercent.rounded()))%").font(.subheadline).monospacedDigit()
            }
            UsageBar(used: window.usedPercent, expected: isHovering ? expected : nil, tint: tint)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
            if isHovering, let expected {
                Text(paceDescription(expected: expected)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else if let r = window.resetsAt {
                Text("Resets \(r, style: .relative)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func paceDescription(expected: Double) -> String {
        let diff = Int((window.usedPercent - expected).rounded())
        let pace = diff == 0 ? "right on pace" : diff > 0 ? "\(diff)% ahead of pace" : "\(-diff)% under pace"
        return "Even pace: \(Int(expected.rounded()))% by now · \(pace)"
    }
}

/// Usage bar with an optional even-pace marker.
struct UsageBar: View {
    let used: Double
    let expected: Double?
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: w * min(used, 100) / 100)
                if let expected {
                    Rectangle()
                        .fill(.primary)
                        .frame(width: 2)
                        .offset(x: min(max(w * expected / 100 - 1, 0), w - 2))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.15), value: expected)
    }
}
