import SwiftUI

struct RootView: View {
    @Bindable private var appState = AppState.shared

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet.rectangle") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .sheet(isPresented: $appState.showReminder) {
            ReminderView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: GoEvent.self, inMemory: true)
}
