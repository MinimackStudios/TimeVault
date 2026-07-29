import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(shortVersion) (Build \($0))" } ?? "Version \(shortVersion)"
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                .accessibilityLabel("TimeVault icon")

            VStack(spacing: 5) {
                Text("TimeVault")
                    .font(.title.bold())
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("A read-only macOS utility for monitoring Time Machine protection, browsing snapshots, and comparing backup history when needed.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 12) {
                AboutFeatureRow(icon: "rectangle.3.group", title: "Monitor protection", detail: "Review backup activity, local snapshots, and startup-disk capacity.")
                AboutFeatureRow(icon: "folder", title: "Browse snapshots", detail: "Explore accessible backup snapshots and compare backup history.")
                AboutFeatureRow(icon: "arrow.left.and.right", title: "Compare history", detail: "See added, removed, and modified files when you need detail.")
                AboutFeatureRow(icon: "lock.shield", title: "Read-only by design", detail: "Backup data is never modified, restored, or deleted.")
            }
            .frame(maxWidth: 380, alignment: .leading)

            Divider()

            Text("Built with Swift and SwiftUI for macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(30)
        .frame(minWidth: 560, idealWidth: 560, minHeight: 650, idealHeight: 650)
    }
}

private struct AboutFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
