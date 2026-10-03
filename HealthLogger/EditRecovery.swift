import SwiftUI

/// An edit whose correction was saved but whose original couldn't be deleted, with what went wrong.
struct IncompleteEdit: Identifiable {
    let edit: PendingEdit
    let message: String

    var id: UUID { edit.id }

    /// Nil unless the error is from an edit that's part done, which then needs this rather than a plain alert.
    init?(_ error: Error) {
        guard case .originalRemains(let edit, _) = error as? EditError else { return nil }
        self.edit = edit
        message = error.localizedDescription
    }
}

extension View {
    /// After an edit whose original couldn't be deleted, offers to try deleting it again (without saving the
    /// correction again) or to leave it for later, when History offers it again. Calls `onDone` either way.
    func incompleteEditAlert(_ incomplete: Binding<IncompleteEdit?>, onDone: @escaping () -> Void) -> some View {
        modifier(IncompleteEditAlert(incomplete: incomplete, onDone: onDone))
    }
}

private struct IncompleteEditAlert: ViewModifier {
    @Binding var incomplete: IncompleteEdit?
    let onDone: () -> Void

    @Environment(HealthStore.self) private var health

    func body(content: Content) -> some View {
        content.alert("Couldn't Remove Original", isPresented: .constant(incomplete != nil), presenting: incomplete) { shown in
            Button("Try Again") { retry(shown.edit) }
            Button("Later", role: .cancel) {
                incomplete = nil
                onDone()
            }
        } message: {
            Text($0.message)
        }
    }

    private func retry(_ edit: PendingEdit) {
        incomplete = nil
        Task {
            do {
                try await health.finishEdit(edit)
                onDone()
            } catch {
                incomplete = IncompleteEdit(EditError.originalRemains(edit, error))
            }
        }
    }
}

/// Edits that didn't finish, so the original and the correction are both listed, each with a way to remove the
/// original or to keep both. Shows nothing when every edit finished.
struct UnfinishedEditsSection: View {
    let onError: (String) -> Void

    @Environment(HealthStore.self) private var health

    var body: some View {
        let edits = health.unfinishedEdits
        if !edits.isEmpty {
            Section {
                ForEach(edits) { edit in
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("Your edit of \(edit.title) didn't finish")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        .font(.headline)
                        Text("The corrected entry was saved, but the original is still in Health, so both are listed.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Remove Original") { finish(edit) }
                                .buttonStyle(.borderedProminent)
                            Button("Keep Both") { health.keepBoth(edit) }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func finish(_ edit: PendingEdit) {
        Task {
            do {
                try await health.finishEdit(edit)
            } catch {
                onError(error.healthMessage)
            }
        }
    }
}
