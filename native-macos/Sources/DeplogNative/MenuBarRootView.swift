import SwiftUI

struct MenuBarRootView: View {
    @EnvironmentObject private var store: DeploymentStore
    @Namespace private var glassNamespace

    private var providerSnapshot: ProviderSnapshot {
        store.snapshot.providers[store.provider] ?? SnapshotFactory.mockSnapshot().providers[store.provider]!
    }

    private var items: [DeploymentItem] {
        providerSnapshot.items.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                header
                if let selected = store.selectedItem {
                    detail(for: selected)
                } else {
                    summary
                }
            }
            .padding(12)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECENT ACTIVITY")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .kerning(0.9)
                        .foregroundStyle(.secondary)
                    Text("Deployments")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text(relativeString(from: store.snapshot.updatedAt))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .glassEffect(in: .capsule)
            }

            providerSwitcher
        }
        .padding(.horizontal, 2)
    }

    private var providerSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(ProviderKind.allCases) { provider in
                Button {
                    withAnimation {
                        store.provider = provider
                        store.selectedItem = nil
                    }
                } label: {
                    ProviderIcon(provider: provider)
                        .frame(width: 68, height: 28)
                }
                .buttonStyle(.glass)
                .tint(store.provider == provider ? .accentColor : .clear)
                .glassEffectID(provider.id, in: glassNamespace)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var summary: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ProviderPill(provider: store.provider, mode: providerSnapshot.mode)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.provider == .vercel ? "Shipping Overview" : "Workflow Activity")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.86))
                    Text(providerSnapshot.notice)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .glassEffect(in: .rect(cornerRadius: 18))

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(items) { item in
                        Button {
                            withAnimation {
                                store.selectedItem = item
                            }
                        } label: {
                            DeploymentCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                Button("Refresh") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.glass)

                Spacer()

                Button("Open Dashboard") {
                    let url = store.provider == .vercel ? URL(string: "https://vercel.com/dashboard") : URL(string: "https://github.com/actions")
                    store.open(url)
                }
                .buttonStyle(.glass)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func detail(for item: DeploymentItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation {
                    store.selectedItem = nil
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.glass)

            HStack(spacing: 10) {
                StatusDot(status: item.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.provider == .vercel ? item.project : (item.workflowName ?? item.project))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(item.statusLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusTextColor(for: item.status))
                }
            }
            .padding(.top, 2)

            VStack(spacing: 10) {
                DetailRow(label: "Status", value: item.statusLabel)
                DetailRow(label: "Branch", value: item.branch)
                DetailRow(label: "Creator", value: item.creator)
                DetailRow(label: "Updated", value: relativeString(from: item.updatedAt))
                if item.status == .error {
                    DetailRow(label: "Failure Reason", value: item.failureReason ?? "No detailed failure reason was returned by the provider.")
                }
            }
            .padding(12)
            .glassEffect(.regular.tint(cardTint(for: item.status)), in: .rect(cornerRadius: 18))

            Button(item.provider == .vercel ? "Inspect on Vercel" : "Open on GitHub") {
                store.open(item.previewURL ?? item.externalURL)
            }
            .buttonStyle(.glassProminent)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)

            Spacer()
        }
    }
}

struct DeploymentCard: View {
    let item: DeploymentItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 32, height: 32)
                providerSymbol
                    .foregroundStyle(.primary)
                    .frame(width: 14, height: 14)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.project)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    StatusDot(status: item.status)
                    Text(statusLine)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(statusTextColor(for: item.status))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.status == .error {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red.opacity(0.6))
            } else if item.status == .ready || item.status == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green.opacity(0.8))
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(cardTint(for: item.status)), in: .rect(cornerRadius: 18))
    }

    private var providerSymbol: some View {
        ProviderIcon(provider: item.provider)
    }

    private var statusLine: String {
        switch item.status {
        case .ready, .completed:
            return "Delivered"
        case .error:
            return item.failureReason ?? "Needs attention"
        case .building, .queued, .running:
            return item.statusLabel
        case .unknown:
            return "Unknown"
        }
    }
}

struct ProviderPill: View {
    let provider: ProviderKind
    let mode: ProviderMode

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 24, height: 24)
                ProviderIcon(provider: provider)
                    .foregroundStyle(.primary)
                    .frame(width: 11, height: 11)
            }

            Text(mode == .live ? "Live" : "Mock")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(mode == .live ? Color.green : Color.orange)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassEffect(in: .capsule)
    }
}

private func statusTextColor(for status: DeploymentStatus) -> Color {
    switch status {
    case .ready, .completed:
        return .green
    case .error:
        return .red
    case .building, .queued, .running:
        return .orange
    case .unknown:
        return .secondary
    }
}

struct ProviderIcon: View {
    let provider: ProviderKind

    var body: some View {
        switch provider {
        case .vercel:
            VercelGlyph()
                .fill(style: FillStyle())
        case .github:
            GitHubGlyph()
        }
    }
}

struct GitHubGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)

            Circle()
                .fill(Color.black.opacity(0.78))
                .frame(width: 10.5, height: 10.5)

            HStack(spacing: 4.8) {
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: 2.1, height: 4.8)
                    .rotationEffect(.degrees(-26))
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: 2.1, height: 4.8)
                    .rotationEffect(.degrees(26))
            }
            .offset(y: -4.7)

            HStack(spacing: 3.4) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 1.4, height: 1.4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 1.4, height: 1.4)
            }
            .offset(y: -0.8)

            RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                .fill(Color.white)
                .frame(width: 5.5, height: 3.8)
                .offset(y: 3.2)
        }
        .compositingGroup()
    }
}

struct VercelGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct StatusDot: View {
    let status: DeploymentStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .padding(.top, 3)
    }

    private var color: Color {
        switch status {
        case .building, .queued, .running:
            Color.orange
        case .ready, .completed:
            Color.mint
        case .error:
            Color.red
        case .unknown:
            Color.gray
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func cardTint(for status: DeploymentStatus) -> Color {
    switch status {
    case .ready, .completed:
        return .green.opacity(0.15)
    case .error:
        return .red.opacity(0.15)
    case .building, .queued, .running:
        return .orange.opacity(0.12)
    case .unknown:
        return .clear
    }
}

func relativeString(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: .now)
}
