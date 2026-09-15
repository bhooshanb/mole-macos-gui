import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case clean = "Clean"
    case apps = "Apps"
    case optimize = "Optimize"
    case analyze = "Analyze"
    case status = "Status"

    var id: String { rawValue }

    var keyboardShortcut: KeyEquivalent {
        switch self {
        case .clean: return "1"
        case .apps: return "2"
        case .optimize: return "3"
        case .analyze: return "4"
        case .status: return "5"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .clean: return "Clean: free disk space by removing caches, logs, and trash"
        case .apps: return "Apps: uninstall applications and remove leftovers"
        case .optimize: return "Optimize: refresh system caches and services"
        case .analyze: return "Analyze: explore disk usage visually"
        case .status: return "Status: live system health monitoring"
        }
    }
}

/// Top pill navigation shared by the whole app.
/// Selected item renders as the light pill from the reference screenshots.
struct TopNavigationBar: View {
    @Binding var selection: AppSection
    @FocusState private var focusedSection: AppSection?

    var body: some View {
        HStack(spacing: 18) {
            MoleSilhouette(color: MoleTheme.accent)
                .frame(width: 34, height: 24)
                .accessibilityLabel("Mole")

            HStack(spacing: 4) {
                ForEach(AppSection.allCases) { section in
                    navButton(section)
                }
            }
            .padding(4)
            .background(
                Capsule().fill(MoleTheme.fillSubtle)
            )
            .overlay(
                Capsule().strokeBorder(MoleTheme.border, lineWidth: 1)
            )

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
    }

    private func navButton(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            Text(section.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.black.opacity(0.85) : MoleTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Group {
                        if isSelected {
                            Capsule().fill(MoleTheme.fillSelected)
                        } else if focusedSection == section {
                            Capsule().fill(MoleTheme.fillSubtle)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .focused($focusedSection, equals: section)
        .keyboardShortcut(section.keyboardShortcut, modifiers: [])
        .accessibilityLabel("\(section.rawValue) section")
        .accessibilityHint(section.accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Root view: owns section switching and wires the view models.
struct ContentView: View {
    @StateObject private var appModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(appModel: AppViewModel) {
        _appModel = StateObject(wrappedValue: appModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Headroom for the traffic lights now that the title bar is gone.
            TopNavigationBar(selection: $appModel.section)
                .padding(.top, 14)

            Divider().overlay(MoleTheme.border)

            ZStack {
                GlassTheme.windowBackground.ignoresSafeArea()
                sectionView
                    .id(appModel.section)
                    .transition(.opacity)
            }
        }
        .background(GlassTheme.windowBackground)
        // Follow the system appearance (Apple guideline: respect light/dark).
        .preferredColorScheme(nil)
        .environmentObject(appModel)
        .onAppear {
            appModel.onAppear()
            // Install the menu bar monitor at launch (respecting Settings).
            MenuBarStatusItemController.shared.install(appModel: appModel)
        }
        .onChange(of: scenePhase) { _, phase in
            appModel.scenePhaseChanged(phase)
        }
        .sheet(isPresented: $appModel.showingHistory) {
            HistorySheet()
        }
        .sheet(isPresented: $appModel.showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appModel.showingWelcome) {
            WelcomeView()
                .interactiveDismissDisabled()
        }
        .overlay {
            if let error = appModel.bannerError {
                ErrorBanner(error: error) { appModel.bannerError = nil }
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appModel.bannerError)
    }

    @ViewBuilder
    private var sectionView: some View {
        switch appModel.section {
        case .clean: CleanView(viewModel: appModel.cleanViewModel)
        case .apps: AppsView(viewModel: appModel.appsViewModel)
        case .optimize: OptimizeView(viewModel: appModel.optimizeViewModel)
        case .analyze: AnalyzeView(viewModel: appModel.analyzeViewModel)
        case .status: StatusView(viewModel: appModel.statusViewModel)
        }
    }
}

/// Top-level state container shared across sections.
@MainActor
final class AppViewModel: ObservableObject {
    @Published var section: AppSection = .clean
    @Published var showingHistory = false
    @Published var showingSettings = false
    @Published var showingWelcome = false
    @Published var bannerError: MoleUserError?

    let cleanViewModel: CleanViewModel
    let appsViewModel: AppsViewModel
    let optimizeViewModel: OptimizeViewModel
    let analyzeViewModel: AnalyzeViewModel
    let statusViewModel: StatusViewModel
    let client: MoleClient

    private var didFirstAppear = false

    init(client: MoleClient = MoleClient()) {
        self.client = client
        cleanViewModel = CleanViewModel(client: client)
        appsViewModel = AppsViewModel(client: client)
        optimizeViewModel = OptimizeViewModel(client: client)
        analyzeViewModel = AnalyzeViewModel(client: client)
        statusViewModel = StatusViewModel(client: client)
    }

    func onAppear() {
        guard !didFirstAppear else { return }
        didFirstAppear = true
        if MolePreferences.shared.isFirstLaunch {
            showingWelcome = true
            MolePreferences.shared.isFirstLaunch = false
        }
        statusViewModel.startMonitoring()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            statusViewModel.startMonitoring()
        case .background, .inactive:
            statusViewModel.pauseMonitoring()
        @unknown default:
            break
        }
    }

    func openHistory() { showingHistory = true }
    func openSettings() { showingSettings = true }
}
