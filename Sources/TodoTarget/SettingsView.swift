import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TodoTargetCore

extension CSVImportError {
    /// Plain words for the user, with the line number.
    var userMessage: String {
        switch self {
        case .missingHeader:
            return "The file is empty. The first line must name the columns: group, title, and an optional url."
        case .missingColumn(let name):
            return "The first line has no \"\(name)\" column. The columns are group, title, and an optional url."
        case .emptyTitle(let line):
            return "Line \(line) has no title. Every row needs a title."
        case .invalidURL(let line):
            return "The link on line \(line) is not valid. Links must start with http:// or https://."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var backup: BackupCoordinator
    @State private var email = ""
    @State private var urlDraft = ""
    @State private var keyDraft = ""
    @State private var drafts: [UUID: String] = [:]
    @State private var keepPosition = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Goals (top one is the first priority)") {
                ForEach(Array(model.data.goals.enumerated()), id: \.element.id) { index, goal in
                    goalRow(index: index, goal: goal)
                }
                Toggle("Keep list position when importing again", isOn: $keepPosition)
            }
            Section("General") {
                Toggle("Start at login", isOn: Binding(
                    get: { model.data.settings.launchAtLogin },
                    set: { setLogin($0) }))
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Backup (optional)") {
                // Saved on Return or "Save connection", not per keystroke.
                TextField("Supabase URL", text: $urlDraft).onSubmit(saveConnection)
                TextField("Supabase anon key", text: $keyDraft).onSubmit(saveConnection)
                Button("Save connection", action: saveConnection).disabled(!connectionChanged)
                TextField("Email", text: $email)
                HStack {
                    Button("Send sign-in link") { saveConnection(); Task { await backup.sendSignInLink(email: email) } }
                    Button("Backup now") { Task { await backup.backupNow() } }.disabled(!backup.signedIn)
                    Button("Restore from backup") { Task { await backup.restore() } }.disabled(!backup.signedIn)
                }
                Text(backup.status.isEmpty ? "Backup is off until you enter a URL and key." : backup.status)
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            urlDraft = model.data.settings.supabaseURL ?? ""
            keyDraft = model.data.settings.supabaseAnonKey ?? ""
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func goalRow(index: Int, goal: Goal) -> some View {
        HStack {
            Text("\(index + 1)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 14)
            TextField("Goal name", text: Binding(
                get: { drafts[goal.id] ?? goal.name },
                set: { drafts[goal.id] = $0; applyNames() }))
            Text(goal.items.isEmpty ? "No list" : "\(goal.position)/\(goal.items.count)")
                .font(.callout).foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
            Button("Import list…") { importList(for: goal) }
            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0).help("Move up")
            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == model.data.goals.count - 1).help("Move down")
        }
    }

    private var connectionChanged: Bool {
        urlDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (model.data.settings.supabaseURL ?? "")
            || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (model.data.settings.supabaseAnonKey ?? "")
    }

    private func saveConnection() {
        backup.applyConnection(url: urlDraft, key: keyDraft)
        urlDraft = model.data.settings.supabaseURL ?? ""
        keyDraft = model.data.settings.supabaseAnonKey ?? ""
    }

    private func displayName(_ id: UUID) -> String {
        drafts[id] ?? model.data.goals.first(where: { $0.id == id })?.name ?? ""
    }

    private func currentOrder() -> [UUID] { model.data.goals.map(\.id) }

    private func applyNames() {
        let order = currentOrder()
        model.updateGoals(names: order.map(displayName), order: order)
    }

    private func move(_ index: Int, by delta: Int) {
        var order = currentOrder()
        let target = index + delta
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        model.updateGoals(names: order.map(displayName), order: order)
    }

    private func importList(for goal: Goal) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a CSV file with the columns group, title, url"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            try model.importList(goalID: goal.id, csv: text, keepPosition: keepPosition)
        } catch let e as CSVImportError {
            alert(title: "Could not import the list", message: e.userMessage)
        } catch {
            alert(title: "Could not read the file", message: "The file could not be read as UTF-8 text.")
        }
    }

    private func setLogin(_ on: Bool) {
        model.updateSettings { $0.launchAtLogin = on }
        guard LaunchAtLogin.isBundled else {
            loginError = on ? "Start at login works only from the installed app, not from a development run." : nil
            return
        }
        do { try LaunchAtLogin.set(on); loginError = nil }
        catch { loginError = "Could not change the login item: \(error.localizedDescription)" }
    }

    private func alert(title: String, message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.alertStyle = .warning
        a.runModal()
    }
}
