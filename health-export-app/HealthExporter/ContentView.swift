import SwiftUI

struct ContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @State private var githubToken: String = ""
    @State private var tokenSaved = false

    var body: some View {
        NavigationView {
            Form {
                Section("GitHub") {
                    SecureField("GitHub Token", text: $githubToken)
                        .autocorrectionDisabled()
                    Button("保存 Token") {
                        KeychainStore.shared.save(key: "github_token", value: githubToken)
                        tokenSaved = true
                    }
                    if tokenSaved {
                        Text("已保存").foregroundStyle(.secondary)
                    }
                }

                Section("Health 授权") {
                    Button(healthKitManager.isAuthorized ? "已授权" : "请求健康数据授权") {
                        Task { await healthKitManager.requestAuthorization() }
                    }
                    .disabled(healthKitManager.isAuthorized)
                }

                Section("同步") {
                    Button("立即同步今天的数据") {
                        Task { await healthKitManager.syncToday() }
                    }
                    Text(healthKitManager.lastSyncStatus)
                        .foregroundStyle(.secondary)
                    if let lastSyncDate = healthKitManager.lastSyncDate {
                        Text("上次同步: \(lastSyncDate.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Health Exporter")
            .onAppear {
                githubToken = KeychainStore.shared.read(key: "github_token") ?? ""
                tokenSaved = !githubToken.isEmpty
            }
        }
    }
}

#Preview {
    ContentView().environmentObject(HealthKitManager())
}
