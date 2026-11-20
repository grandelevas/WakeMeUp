import SwiftUI

struct SharingView: View {
    @Environment(AppModel.self) private var model
    @State private var remoteTime = Date()
    @State private var inviting = false
    @State private var inviteeDraft = ""
    @State private var editingOwnName = false
    @State private var ownNameDraft = ""
    @State private var renamingGrantID: UUID?
    @State private var renameDraft = ""
    @State private var voiceGrantID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.usesCloudKit ? "sharing.cloudBanner" : "sharing.previewBanner")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ownNameSection
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
            .sheet(isPresented: $inviting) { inviteSheet }
            .sheet(isPresented: $editingOwnName, onDismiss: {
                Task { await model.commitOwnName() }
            }) { ownNameSheet }
            .sheet(isPresented: renamePresented) { renameSheet }
            .sheet(isPresented: voicePresented) {
                if let voiceGrantID {
                    VoiceMessageSheet { url in
                        guard let id = voiceGrantID else { return }
                        self.voiceGrantID = nil
                        Task { await model.sendToPhone(grantID: id, immediately: false, voiceFile: url) }
                    } onCancel: {
                        self.voiceGrantID = nil
                    }
                }
            }
        }
        .accessibilityIdentifier("sharing-screen")
    }

    private var voicePresented: Binding<Bool> {
        Binding(get: { voiceGrantID != nil }, set: { if !$0 { voiceGrantID = nil } })
    }

    private var renamePresented: Binding<Bool> {
        Binding(
            get: { renamingGrantID != nil },
            set: { if !$0 { renamingGrantID = nil } }
        )
    }

    private var ownNameSection: some View {
        Section("sharing.yourName") {
            if model.ownName.isEmpty {
                Button("sharing.addOwnName") {
                    ownNameDraft = ""
                    editingOwnName = true
                }
                .accessibilityIdentifier("sharing-own-name")
            } else {
                HStack {
                    Text(model.ownName)
                        .accessibilityIdentifier("sharing-own-name")
                    Spacer()
                    Button("sharing.edit") {
                        ownNameDraft = model.ownName
                        editingOwnName = true
                    }
                }
            }
            Text("sharing.ownName.help")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if model.needsOwnName {
                Text("sharing.needOwnName")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var ownNameSheet: some View {
        NavigationStack {
            Form {
                TextField("sharing.yourName", text: $ownNameDraft)
                    .textInputAutocapitalization(.words)
                    .onChange(of: ownNameDraft) { _, newValue in
                        model.rename(newValue)
                    }
            }
            .navigationTitle("sharing.yourName")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("sharing.done") { editingOwnName = false }
                }
            }
        }
    }

    private var inviteSheet: some View {
        NavigationStack {
            Form {
                TextField("sharing.inviteeName", text: $inviteeDraft)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("sharing.whoTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sharing.cancel") { inviting = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sharing.continue") {
                        let typed = inviteeDraft
                        Task {
                            if await model.createCloudInvite(inviteeName: typed) {
                                inviteeDraft = ""
                                inviting = false
                            } else if model.needsOwnName {
                                inviting = false
                            }
                        }
                    }
                    .disabled(PersonName.nonempty(inviteeDraft) == nil)
                }
            }
        }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                TextField("sharing.inviteeName", text: $renameDraft)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("sharing.rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sharing.cancel") { renamingGrantID = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sharing.done") {
                        guard let grantID = renamingGrantID else { return }
                        let typed = renameDraft
                        renamingGrantID = nil
                        Task { await model.renamePerson(grantID: grantID, to: typed) }
                    }
                    .disabled(PersonName.nonempty(renameDraft) == nil)
                }
            }
        }
    }

    private var incoming: [ShareGrant] {
        ShareRoster.canSetAlarmsHere(profileID: model.profile.id, grants: model.grants)
    }

    private var outgoing: [ShareGrant] {
        ShareRoster.phonesICanSet(profileID: model.profile.id, grants: model.grants)
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
                inviteeDraft = ""
                inviting = true
            }
            if let status = model.shareStatus {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(status)
                        .font(.subheadline)
                }
                .accessibilityIdentifier("sharing-status")
            }
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
                    if grant.owner.id == model.profile.id,
                       grant.state == .pending,
                       InviteLinkPolicy.url(from: grant.inviteCode) != nil {
                        Button("sharing.copyLink") {
                            model.copyInviteLink(grantID: grant.id)
                        }
                        .font(.footnote)
                    }
                    Button("sharing.rename") {
                        let label = otherName(in: grant)
                        renameDraft = label == String(localized: "sharing.someone") ? "" : label
                        renamingGrantID = grant.id
                    }
                    .font(.footnote)
                    if grant.grantee?.id == model.profile.id && model.usesCloudKit {
                        Button("sharing.schedule") {
                            voiceGrantID = grant.id
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
        PersonName.listLabel(
            for: grant,
            profileID: model.profile.id,
            grants: model.grants,
            generic: String(localized: "sharing.someone")
        )
    }

    private func stateName(_ state: GrantState) -> String {
        switch state {
        case .pending: String(localized: "sharing.pending")
        case .active: String(localized: "sharing.active")
        case .revoked: String(localized: "sharing.revoked")
        }
    }
}

private struct VoiceMessageSheet: View {
    var onSend: (URL?) -> Void
    var onCancel: () -> Void
    @State private var recorder = VoiceClipRecorder()
    @State private var preview = SoundPreviewPlayer()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("sharing.voice.help")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if recorder.isRecording {
                        Button("sharing.voice.stop") { recorder.stop() }
                    } else if recorder.fileURL == nil {
                        Button("sharing.voice.record") {
                            do { try recorder.record() } catch {
                                recorder.discard()
                            }
                        }
                    } else {
                        Button("sharing.voice.preview") {
                            if let url = recorder.fileURL {
                                preview.play(id: "voice-draft", url: url, cap: VoiceClipPolicy.maxSeconds)
                            }
                        }
                        Button("sharing.voice.rerecord") {
                            preview.stop()
                            recorder.discard()
                        }
                    }
                }
            }
            .navigationTitle("sharing.voice.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sharing.cancel") {
                        preview.stop()
                        recorder.discard()
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sharing.voice.send") {
                        preview.stop()
                        recorder.stop()
                        onSend(recorder.fileURL)
                    }
                    .disabled(recorder.isRecording)
                }
            }
        }
        .onDisappear { recorder.stop() }
    }
}
