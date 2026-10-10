import NikuCueDomain
import SwiftUI
import UniformTypeIdentifiers

/// Backup and import (docs/02 §7). The warning that the JSON is unencrypted is always visible before sharing.
/// Export: prepare the file, then a `ShareLink` presents the system share sheet (the user chooses the destination).
/// Import: Files picker → validation → preview → two-step confirmation → atomic replace → reminders off.
struct BackupView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        BackupContent(container: container)
    }
}

struct BackupContent: View {
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var vm: BackupViewModel

    init(container: AppContainer) {
        _vm = StateObject(wrappedValue: BackupViewModel(container: container))
    }

    var body: some View {
        Form {
            warningSection
            if let notice = vm.notice {
                Section {
                    Label(localizer.t(notice.key), systemImage: notice.isFailure ? "exclamationmark.triangle" : "checkmark.circle.fill")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            exportSection
            importSection
        }
        .navigationTitle(localizer.t("settings.backup"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $vm.showImporter, allowedContentTypes: [.json]) { result in
            vm.handleImport(result)
        }
        // Second step of the replace confirmation (docs/02 §7). The body recommends exporting first.
        .alert(Text(localizer.t("backup.replaceTitle")), isPresented: $vm.showReplaceConfirmation) {
            Button(localizer.t("common.confirm"), role: .destructive) {
                Task { await vm.confirmRestore() }
            }
            Button(localizer.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(localizer.t("backup.replaceBody"))
        }
        .onDisappear { vm.cleanup() }
    }

    private var warningSection: some View {
        Section {
            Label(localizer.t("backup.warning"), systemImage: "lock.open")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            if let url = vm.exportURL {
                ShareLink(item: url) {
                    Label(localizer.t("backup.export"), systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
            } else {
                Button {
                    Task { await vm.prepareExport() }
                } label: {
                    HStack(spacing: 8) {
                        Label(localizer.t("backup.export"), systemImage: "square.and.arrow.up")
                            .frame(minHeight: 44)
                        if vm.isPreparingExport {
                            ProgressView()
                        }
                    }
                }
                .disabled(vm.isPreparingExport || vm.isRestoring)
            }
        }
    }

    // MARK: Import

    private var importSection: some View {
        Section {
            Button {
                vm.showImporter = true
            } label: {
                Label(localizer.t("backup.import"), systemImage: "square.and.arrow.down")
                    .frame(minHeight: 44)
            }
            .disabled(vm.isRestoring)
            if let count = vm.previewHabitCount {
                Label(localizer.t("backup.preview", ["count": String(count)]), systemImage: "doc.text")
                    .fixedSize(horizontal: false, vertical: true)
                Text(localizer.t("backup.replaceBody"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button {
                        vm.cancelPreview()
                    } label: {
                        Text(localizer.t("common.cancel"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isRestoring)
                    // First step: opens the replace alert.
                    Button {
                        vm.requestRestore()
                    } label: {
                        Text(localizer.t("common.confirm"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isRestoring)
                }
            }
            if vm.isRestoring {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}
