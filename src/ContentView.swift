import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .opacity(0.26)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                controls
                appList
                footer
            }
            .padding(18)
        }
        .frame(minWidth: 560, minHeight: 680)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("content_enable"))
                        .font(.headline)
                        .foregroundStyle(Color(nsColor: .labelColor))

                    Text(appState.mutedSummary)
                        .font(.subheadline)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                Spacer()

                Toggle("", isOn: $appState.muteEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                TextField(L("content_search"), text: $appState.searchText)
                    .textFieldStyle(.roundedBorder)

                Button(L("content_refresh")) {
                    appState.refreshApps()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: .systemGray))
            }
        }
        .padding(14)
        .background(.gray.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.gray.opacity(0.35), lineWidth: 1)
        )
    }

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(appState.filteredApps) { app in
                    AppRow(
                        app: app,
                        isMuted: appState.isSelected(bundleID: app.bundleID),
                        onToggle: { isSelected in
                            appState.setSelection(for: app.bundleID, isSelected: isSelected)
                        }
                    )
                }

                if appState.filteredApps.isEmpty {
                    Text(L("content_no_apps"))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .padding(.top, 24)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.statusMessage)
                .font(.footnote)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            if let errorText = appState.errorMessage {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct AppRow: View {
    let app: RunningAppSummary
    let isMuted: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .foregroundStyle(Color(nsColor: .labelColor))

                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isMuted }, set: onToggle))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(12)
        .background(.gray.opacity(isMuted ? 0.28 : 0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.gray.opacity(isMuted ? 0.45 : 0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var icon: some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: "app.fill")
                .font(.title3)
                .foregroundStyle(.gray)
                .frame(width: 30, height: 30)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
