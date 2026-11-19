import SwiftUI

struct SharingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var remoteTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.usesCloudKit ? "sharing.cloudBanner" : "sharing.previewBanner")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("sharing.yourName") {
                    TextField("sharing.yourName", text: $name)
                        .onSubmit { model.rename(name) }
                }
                if model.showsSimulatedPreview {
                    previewSection
                } else {
                    cloudSection
                }
                grantSection(title: "sharing.peopleWhoCanWakeMe", grants: incoming)
                grantSection(title: "sharing.phonesICanWake", grants: outgoing)
            }
            .navigationTitle("sharing.title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("settings.title")
                }
                if !model.showsSimulatedPreview {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("sharing.refresh") {
                            Task { await model.refreshRemote() }
                        }
                    }
                }
            }
            .onAppear {
                if name.isEmpty { name = model.profile.displayName }
            }
        }
        .accessibilityIdentifier("sharing-screen")
    }

    private var incoming: [ShareGrant] {
        model.grants.filter { $0.owner.id == model.profile.id && $0.state != .revoked }
    }

    private var outgoing: [ShareGrant] {
        model.grants.filter { $0.grantee?.id == model.profile.id && $0.state == .active }
    }

    private var previewSection: some View {
        Section("sharing.simulatedFriend") {
            if let friend = model.simulatedFriend {
                Text(String(format: String(localized: "sharing.actAs"), friend.displayName))
                    .font(.headline)
                Text("sharing.actAs.help")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("sharing.label", text: Binding(
                    get: { model.remoteLabel },
                    set: { model.remoteLabel = $0 }
                ))
                DatePicker("alarm.label", selection: $remoteTime, displayedComponents: .hourAndMinute)
                    .onChange(of: remoteTime) { _, newValue in
                        let calendar = Calendar.current
                        model.remoteHour = calendar.component(.hour, from: newValue)
                        model.remoteMinute = calendar.component(.minute, from: newValue)
                    }
                Button("sharing.schedule") { model.ringFromSimulatedFriend(immediately: false) }
                Button("sharing.ringNow") { model.ringFromSimulatedFriend(immediately: true) }
            } else {
                TextField("sharing.friendName", text: Binding(
                    get: { model.friendDraftName },
                    set: { model.friendDraftName = $0 }
                ))
                Button("sharing.addFriend") { model.addSimulatedFriend() }
            }
        }
    }

    private var cloudSection: some View {
        Section("sharing.invite") {
            Text("sharing.cloudSteps")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("sharing.invite") {
                Task { await model.createCloudInvite() }
            }
            TextField("sharing.enterCode", text: Binding(
                get: { model.pastedInvite },
                set: { model.pastedInvite = $0 }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button("sharing.accept") {
                Task { await model.acceptPastedInvite() }
            }
            .disabled(model.pastedInvite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private func grantSection(title: LocalizedStringKey, grants: [ShareGrant]) -> some View {
        Section(title) {
            if grants.isEmpty {
                Text("sharing.none").foregroundStyle(.secondary)
            }
            ForEach(grants) { grant in
                VStack(alignment: .leading, spacing: 6) {
                    Text(otherName(in: grant))
                        .font(.body)
                    Text(stateName(grant.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if grant.grantee?.id == model.profile.id && model.usesCloudKit {
                        Button("sharing.schedule") {
                            Task { await model.sendToPhone(grantID: grant.id, immediately: false) }
                        }
                        Button("sharing.ringNow") {
                            Task { await model.sendToPhone(grantID: grant.id, immediately: true) }
                        }
                    }
                    Button("sharing.revoke", role: .destructive) {
                        Task { await model.revoke(grantID: grant.id) }
                    }
                    .font(.footnote)
                }
            }
        }
    }

    private func otherName(in grant: ShareGrant) -> String {
        if grant.owner.id == model.profile.id {
            return grant.grantee?.displayName ?? String(localized: "sharing.pending")
        }
        return grant.owner.displayName
    }

    private func stateName(_ state: GrantState) -> String {
        switch state {
        case .pending: String(localized: "sharing.pending")
        case .active: String(localized: "sharing.active")
        case .revoked: String(localized: "sharing.revoked")
        }
    }
}
