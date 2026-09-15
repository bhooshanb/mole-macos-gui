import SwiftUI

struct AppsView: View {
    @ObservedObject var viewModel: AppsViewModel
    @StateObject private var updatesModel: UpdatesStartupViewModel
    @State private var subTab: AppSubTab = .uninstall

    init(viewModel: AppsViewModel) {
        self.viewModel = viewModel
        _updatesModel = StateObject(wrappedValue: UpdatesStartupViewModel(client: viewModel.client))
    }

    var body: some View {
        VStack(spacing: 0) {
            SubTabBar(selection: $subTab)
            Divider().overlay(MoleTheme.border)

            switch subTab {
            case .uninstall:
                UninstallPane(viewModel: viewModel)
            case .updates:
                UpdatesPane(viewModel: updatesModel)
            case .startup:
                StartupPane(viewModel: updatesModel)
            }
        }
        .background(MoleTheme.background)
        .onAppear { viewModel.loadIfNeeded() }
        .accessibilityLabel("Apps")
    }
}

enum AppSubTab: String, CaseIterable, Identifiable {
    case uninstall = "Uninstall"
    case updates = "Updates"
    case startup = "Startup"
    var id: String { rawValue }
}

struct SubTabBar: View {
    @Binding var selection: AppSubTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppSubTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Group {
                                if selection == tab {
                                    Capsule().fill(Color.white.opacity(0.14))
                                }
                            }
                        )
                        .foregroundStyle(selection == tab ? MoleTheme.textPrimary : MoleTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
            Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Apps sections")
    }
}

struct UninstallPane: View {
    @ObservedObject var viewModel: AppsViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search apps", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .frame(maxWidth: 280)
                    .accessibilityLabel("Search installed applications")
                Spacer()
                Button {
                    viewModel.load()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh app list")
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 12)

            switch viewModel.phase {
            case .idle, .loading:
                Spacer()
                ProgressView("Scanning installed applications…")
                    .controlSize(.large)
                Spacer()
            case .failed(let message):
                Spacer()
                ErrorStateView(error: viewModel.lastError ?? MoleUserError(kind: .generic(message))) {
                    viewModel.load()
                }
                Spacer()
            case .loaded, .planning, .cleaning, .complete:
                if viewModel.filteredApps.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "No applications found",
                        message: "Mole did not find uninstallable apps on this Mac.")
                    Spacer()
                } else {
                    appList
                }
            }

            bottomBar
        }
        .sheet(isPresented: $viewModel.showConfirmation) {
            UninstallConfirmationSheet(viewModel: viewModel)
        }
        .overlay {
            if case .complete(let message) = viewModel.phase {
                CompletionToast(message: message) {
                    viewModel.dismissError()
                }
            }
        }
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.filteredApps, id: \.uninstallName) { app in
                    AppRow(
                        app: app,
                        isSelected: viewModel.selectedApps.contains(app.uninstallName),
                        isExpanded: viewModel.expandedApp == app.uninstallName,
                        onToggle: { viewModel.toggleSelection(app) },
                        onExpand: {
                            viewModel.expandedApp =
                                viewModel.expandedApp == app.uninstallName ? nil : app.uninstallName
                        })
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 16)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Text("\(viewModel.selectedCount) app\(viewModel.selectedCount == 1 ? "" : "s") selected")
                .font(.system(size: 13))
                .foregroundStyle(MoleTheme.textSecondary)
            Spacer()
            Button {
                viewModel.requestRemove()
            } label: {
                Text(viewModel.selectedCount > 0 ? "Remove \(viewModel.selectedCount)" : "Remove")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(viewModel.selectedCount > 0 ? MoleTheme.danger : Color.white.opacity(0.1)))
                    .foregroundStyle(viewModel.selectedCount > 0 ? .white : MoleTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedCount == 0 || viewModel.phase == .cleaning)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityHint("Fetches Mole's uninstall plan, then asks for confirmation")
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 12)
        .background(MoleTheme.panel)
    }
}

struct AppRow: View {
    let app: AppInventoryItem
    let isSelected: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onExpand: () -> Void

    @State private var appIcon: NSImage?

    var body: some View {
        MoleCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Select \(app.name) for removal")

                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 30, height: 30)
                            .cornerRadius(7)
                    } else {
                        Image(systemName: "app.dashed")
                            .frame(width: 30, height: 30)
                            .foregroundStyle(MoleTheme.textTertiary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MoleTheme.textPrimary)
                        Text(app.bundleID)
                            .font(MoleTheme.mono)
                            .foregroundStyle(MoleTheme.textTertiary)
                    }

                    Spacer()

                    if app.source == "Homebrew" {
                        Text("Homebrew")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(MoleTheme.infoBlue.opacity(0.16)))
                            .foregroundStyle(MoleTheme.infoBlue)
                    }

                    Text(app.size)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(MoleTheme.textSecondary)
                        .frame(width: 80, alignment: .trailing)

                    Button {
                        onExpand()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MoleTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Details for \(app.name)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture { onExpand() }

                if isExpanded {
                    Divider().overlay(MoleTheme.border)
                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Application", app.path)
                        detailRow("Bundle ID", app.bundleID)
                        detailRow("Uninstall name", app.uninstallName)
                        detailRow("Source", app.source)
                        detailRow("Reported size", app.size)
                        Text("Choose “Remove” to preview the exact file plan with mo uninstall --dry-run. Mole keeps shared data when other installed apps still use it, and routes removal through the Trash unless told otherwise.")
                            .font(.system(size: 11))
                            .foregroundStyle(MoleTheme.textTertiary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear { loadIcon() }
        .accessibilityElement(children: .contain)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MoleTheme.textTertiary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(MoleTheme.mono)
                .foregroundStyle(MoleTheme.textSecondary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func loadIcon() {
        guard appIcon == nil else { return }
        let path = app.path + "/Contents/Resources/AppIcon.icns"
        if let image = NSImage(contentsOfFile: path) {
            appIcon = image
            return
        }
        // Fall back to Workspace icon.
        DispatchQueue.global(qos: .utility).async {
            let icon = NSWorkspace.shared.icon(forFile: app.path)
            DispatchQueue.main.async {
                appIcon = icon
            }
        }
    }
}

struct UninstallConfirmationSheet: View {
    @ObservedObject var viewModel: AppsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MoleTheme.caution)
                Text("Confirm Uninstall")
                    .font(.system(size: 17, weight: .bold))
            }

            if let plan = viewModel.plan {
                Text("Mole will remove “\(plan.appName)” and the associated files below. Files go to the Trash and can be recovered until it is emptied.")
                    .font(.system(size: 13))
                    .foregroundStyle(MoleTheme.textSecondary)

                MoleCard {
                    VStack(alignment: .leading, spacing: 8) {
                        if let total = plan.totalSize {
                            summaryRow("Total size", total)
                        }
                        summaryRow("Files", "\(plan.files.count)")
                        summaryRow("Mode", plan.dryRun ? "Preview" : "Trash (recoverable)")
                    }
                }

                SectionLabel(text: "Files to be removed")
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if plan.files.isEmpty {
                            Text("Mole reported no removable files for this app.")
                                .font(.system(size: 12))
                                .foregroundStyle(MoleTheme.textTertiary)
                        }
                        ForEach(plan.files) { file in
                            HStack(alignment: .top) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(MoleTheme.healthy)
                                    .padding(.top, 2)
                                Text(file.path)
                                    .font(MoleTheme.mono)
                                    .textSelection(.enabled)
                                Spacer()
                                if let size = file.size {
                                    Text(size)
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(MoleTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView("Loading Mole's uninstall plan…")
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Remove", role: .destructive) {
                    dismiss()
                    viewModel.performUninstall()
                }
                .buttonStyle(.borderedProminent)
                .tint(MoleTheme.danger)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.plan == nil)
            }
        }
        .padding(24)
        .frame(width: 560, height: 540)
        .background(MoleTheme.panel)
        .accessibilityLabel("Uninstall confirmation")
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(MoleTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MoleTheme.textPrimary)
        }
    }
}

// MARK: - Updates pane (real Homebrew data)

struct UpdatesPane: View {
    @ObservedObject var viewModel: UpdatesStartupViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("App updates via Homebrew")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MoleTheme.textPrimary)
                    Text("Mole delegates cask updates to Homebrew, so this list reflects `brew outdated --cask` exactly.")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
                Spacer()
                Button {
                    viewModel.loadUpdates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh updates")
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 12)

            switch viewModel.updatesPhase {
            case .idle, .loading:
                Spacer()
                ProgressView("Checking Homebrew for outdated casks…")
                    .controlSize(.large)
                Spacer()
            case .failed(let message):
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(MoleTheme.caution)
                    Text("Could not read Homebrew data")
                        .font(.system(size: 15, weight: .semibold))
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MoleTheme.textTertiary)
                        .lineLimit(3)
                    Button("Retry") { viewModel.loadUpdates() }
                        .buttonStyle(.bordered)
                }
                Spacer()
            case .loaded:
                if viewModel.brewMissing {
                    Spacer()
                    EmptyStateView(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Homebrew not installed",
                        message: "Install Homebrew to see and run cask updates here. Apps installed outside Homebrew update through their own mechanisms.")
                    Spacer()
                } else if viewModel.outdatedCasks.isEmpty {
                    Spacer()
                    EmptyStateView(
                        icon: "checkmark.circle.fill",
                        title: "Everything is up to date",
                        message: "No outdated Homebrew casks found.")
                    Spacer()
                } else {
                    updatesList
                }
            }

            if let result = viewModel.lastUpgradeResult {
                Divider().overlay(MoleTheme.border)
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(MoleTheme.infoBlue)
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundStyle(MoleTheme.textSecondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 10)
                .background(MoleTheme.panel)
            }
        }
    }

    private var updatesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.outdatedCasks) { cask in
                    UpdateRow(cask: cask, viewModel: viewModel)
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 16)
        }
    }
}

struct UpdateRow: View {
    let cask: HomebrewCaskUpdate
    @ObservedObject var viewModel: UpdatesStartupViewModel

    var body: some View {
        MoleCard(padding: 0) {
            HStack(spacing: 12) {
                Image(systemName: "app.badge.arrow.down")
                    .font(.system(size: 15))
                    .foregroundStyle(MoleTheme.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cask.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MoleTheme.textPrimary)
                    HStack(spacing: 4) {
                        Text(cask.installedVersions?.last ?? "?")
                            .strikethrough()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                        Text(cask.currentVersion ?? "latest")
                            .foregroundStyle(MoleTheme.healthy)
                    }
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(MoleTheme.textTertiary)
                }
                Spacer()
                if cask.pinned == true {
                    Text("pinned")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MoleTheme.caution.opacity(0.16)))
                        .foregroundStyle(MoleTheme.caution)
                }
                if viewModel.upgradingCask == cask.name {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Update") { viewModel.upgrade(cask) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MoleTheme.accent)
                        .accessibilityLabel("Update \(cask.name) to \(cask.currentVersion ?? "latest")")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Startup pane (real launch agents + login items)

struct StartupPane: View {
    @ObservedObject var viewModel: UpdatesStartupViewModel
    @State private var showingSystemAgents = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Startup items")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MoleTheme.textPrimary)
                    Text("Launch agents run at login. Mole audits these in the Optimize pass; removal stays with the CLI and System Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(MoleTheme.textTertiary)
                }
                Spacer()
                Picker("Show", selection: $showingSystemAgents) {
                    Text("Login-time agents").tag(false)
                    Text("Login items").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button {
                    viewModel.loadStartup()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh startup items")
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 12)

            switch viewModel.startupPhase {
            case .idle, .loading:
                Spacer()
                ProgressView("Reading startup configuration…")
                    .controlSize(.large)
                Spacer()
            case .failed(let message):
                Spacer()
                Text(message)
                    .foregroundStyle(MoleTheme.textSecondary)
                Spacer()
            case .loaded:
                if showingSystemAgents {
                    loginItemsList
                } else {
                    launchAgentsList
                }
            }
        }
    }

    private var launchAgentsList: some View {
        Group {
            if viewModel.userAgents.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "person.crop.rectangle.stack",
                    title: "No user launch agents",
                    message: "Nothing is registered in ~/Library/LaunchAgents.")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.userAgents) { agent in
                            LaunchAgentRow(agent: agent)
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var loginItemsList: some View {
        Group {
            if viewModel.loginItemsUnavailable {
                Spacer()
                EmptyStateView(
                    icon: "lock.shield",
                    title: "Login items unavailable",
                    message: "macOS denied automation access to System Events. Grant access in System Settings → Privacy & Security → Automation, then refresh.")
                Spacer()
            } else if viewModel.loginItems.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "person.crop.rectangle.stack",
                    title: "No login items",
                    message: "No classic login items are registered for your account.")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.loginItems, id: \.self) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle")
                                    .foregroundStyle(MoleTheme.accent)
                                    .frame(width: 30)
                                Text(item)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(MoleTheme.textPrimary)
                                Spacer()
                                Text("Login item")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(MoleTheme.infoBlue.opacity(0.16)))
                                    .foregroundStyle(MoleTheme.infoBlue)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: MoleTheme.cardRadius, style: .continuous)
                                    .fill(MoleTheme.card))
                            .overlay(
                                RoundedRectangle(cornerRadius: MoleTheme.cardRadius, style: .continuous)
                                    .strokeBorder(MoleTheme.border, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

struct LaunchAgentRow: View {
    let agent: LaunchAgentInfo

    var body: some View {
        MoleCard(padding: 0) {
            HStack(spacing: 12) {
                Image(systemName: agent.disabled ? "pause.circle" : "play.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(agent.disabled ? MoleTheme.textTertiary : MoleTheme.healthy)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MoleTheme.textPrimary)
                    Text(agent.program ?? agent.path)
                        .font(MoleTheme.mono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(MoleTheme.textTertiary)
                }
                Spacer()
                if agent.disabled {
                    Text("disabled")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MoleTheme.caution.opacity(0.16)))
                        .foregroundStyle(MoleTheme.caution)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Launch agent \(agent.label)\(agent.disabled ? ", disabled" : "")")
    }
}

// MARK: - Shared small views

struct PlaceholderPane: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(MoleTheme.textTertiary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MoleTheme.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            MoleSilhouette(color: MoleTheme.textTertiary.opacity(0.5))
                .frame(width: 90, height: 60)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MoleTheme.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textSecondary)
        }
    }
}

struct ErrorStateView: View {
    let error: MoleUserError
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 38))
                .foregroundStyle(MoleTheme.danger)
            Text(error.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MoleTheme.textPrimary)
            Text(error.message)
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Text(error.recoverySuggestion)
                .font(.system(size: 12))
                .foregroundStyle(MoleTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(MoleTheme.accent)
            }
        }
    }
}

struct CompletionToast: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MoleTheme.healthy)
                Text(message)
                    .font(.system(size: 13))
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderless)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(MoleTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MoleTheme.border))
            .padding(24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel("Completed: \(message)")
    }
}

struct ErrorBanner: View {
    let error: MoleUserError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MoleTheme.caution)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title).font(.system(size: 13, weight: .semibold))
                Text(error.recoverySuggestion).font(.system(size: 11))
                    .foregroundStyle(MoleTheme.textSecondary)
            }
            Spacer()
            Button("Dismiss") { onDismiss() }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(MoleTheme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MoleTheme.borderStrong))
        .shadow(color: .black.opacity(0.4), radius: 12)
        .padding(.horizontal, 60)
        .accessibilityLabel("Error: \(error.title). \(error.message)")
    }
}
