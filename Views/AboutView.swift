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
                .accessibilityLabel("Time Machine Analyzer icon")

            VStack(spacing: 5) {
                Text("Time Machine Analyzer")
                    .font(.title.bold())
                Text(version)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("A read-only macOS utility for exploring local Time Machine backup snapshots and understanding what changed between them.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 12) {
                AboutFeatureRow(icon: "clock.arrow.circlepath", title: "Compare snapshots", detail: "See added, removed, and modified files.")
                AboutFeatureRow(icon: "chart.bar.xaxis", title: "Understand changes", detail: "Review logical size totals and folder impact.")
                AboutFeatureRow(icon: "lock.shield", title: "Read-only by design", detail: "Backup data is never modified, restored, or deleted.")
                AboutFeatureRow(icon: "externaldrive", title: "Works with local backups", detail: "Browse accessible Time Machine snapshots on mounted drives.")
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
        .frame(width: 560, height: 680)
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
