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
    @State private var addingFriendGroup = false
    @State private var expandedContactID: String?
    @State private var contactPendingDelete: SharingContact?
    @State private var groupingMemberID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                if !model.suppressPermissionBanner {
                    Section {
                        Text(model.usesCloudKit ? "sharing.cloudBanner" : "sharing.previewBanner")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ownNameSection
                if model.showsSimulatedPreview && !model.suppressPermissionBanner {
                    previewSection
                } else if !model.showsSimulatedPreview {
                    cloudSection
                }
                if !model.showsSimulatedPreview {
                    friendGroupSection
                }
                contactSection
            }
            .refreshable {
                await model.refreshRemote()
            }
            .navigationTitle("sharing.title")
            .onAppear {
                if model.suppressPermissionBanner, expandedContactID == nil {
                    expandedContactID = contacts.first?.id
                }
                guard model.selectedTab == .sharing else { return }
                Task { await model.refreshRemote() }
            }
            .onChange(of: model.selectedTab) { _, tab in
                guard tab == .sharing else { return }
                Task { await model.refreshRemote() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    OpenSettingsLink()
                }
            }
            .sheet(isPresented: $inviting) { inviteSheet }
            .sheet(isPresented: $addingFriendGroup) { friendGroupSheet }
            .sheet(isPresented: groupMemberPresented) { addToGroupSheet }
            .confirmationDialog(
                "sharing.delete.title",
                isPresented: deletePresented,
                titleVisibility: .visible
            ) {
                Button("sharing.delete.confirm", role: .destructive) {
                    guard let contact = contactPendingDelete else { return }
                    if let id = contact.hostedGrantID {
                        Task { await model.revoke(grantID: id) }
                    }
                    if let id = contact.wakeGrantID {
                        Task { await model.revoke(grantID: id) }
                    }
                    contactPendingDelete = nil
                }
                Button("sharing.cancel", role: .cancel) { contactPendingDelete = nil }
            } message: {
                Text("sharing.delete.message")
            }
            .sheet(isPresented: $editingOwnName, onDismiss: {
                Task { await model.commitOwnName() }
            }) { ownNameSheet }
            .sheet(isPresented: renamePresented) { renameSheet }
            .sheet(isPresented: voicePresented) {
                if let voiceGrantID {
                    VoiceMessageSheet { url in
                        let id = voiceGrantID
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

    private var friendGroupSection: some View {
        Section("sharing.friendGroups") {
            if model.snapshot.friendGroups.isEmpty {
                Text("sharing.friendGroups.empty").foregroundStyle(.secondary)
            }
            ForEach(model.snapshot.friendGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name).font(.body)
                    Text(memberNames(group))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("sharing.friendGroups.alarm") {
                        Task { await model.sendToFriendGroup(id: group.id) }
                    }
                    .buttonStyle(.borderless)
                    Button("sharing.friendGroups.delete", role: .destructive) {
                        model.deleteFriendGroup(id: group.id)
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                }
            }
            Button("sharing.friendGroups.add") { addingFriendGroup = true }
                .buttonStyle(.borderless)
                .disabled(!GroupButtonPolicy.canAddGroup(contactCount: contacts.count))
        }
    }

    private func memberNames(_ group: FriendGroup) -> String {
        let names = group.memberIDs.compactMap { id in
            outgoing.first { $0.owner.id == id }.map {
                PersonName.listLabel(for: $0, profileID: model.profile.id, grants: model.grants, generic: $0.owner.displayName)
            }
        }
        return names.joined(separator: ", ")
    }

    private var friendGroupSheet: some View {
        FriendGroupEditor(people: outgoing) { name, ids in
            model.createFriendGroup(name: name, memberIDs: ids)
            addingFriendGroup = false
        } onCancel: {
            addingFriendGroup = false
        }
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

    private var contacts: [SharingContact] {
        ContactRoster.contacts(profileID: model.profile.id, grants: model.grants)
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { contactPendingDelete != nil }, set: { if !$0 { contactPendingDelete = nil } })
    }

    private var groupMemberPresented: Binding<Bool> {
        Binding(get: { groupingMemberID != nil }, set: { if !$0 { groupingMemberID = nil } })
    }

    private var contactSection: some View {
        Section("sharing.contacts") {
            if contacts.isEmpty {
                Text("sharing.none").foregroundStyle(.secondary)
            }
            ForEach(contacts) { contact in
                let paused = CollaborationPause.isPaused(contact: contact, profileID: model.profile.id, grants: model.grants)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            expandedContactID = expandedContactID == contact.id ? nil : contact.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name)
                                    if paused {
                                        Text("sharing.paused")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if contact.isPending {
                                        Text("sharing.pending")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: expandedContactID == contact.id ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.borderless)
                        ContactPauseTile(paused: paused) {
                            Task { await model.setCollaborationPaused(!paused, for: contact) }
                        }
                    }
                    if expandedContactID == contact.id {
                        HStack(alignment: .top, spacing: 8) {
                            ContactActionTile(
                                title: "sharing.wakeNow",
                                systemImage: "sun.max.fill",
                                disabled: paused || !ContactActionPolicy.canWake(contact)
                            ) {
                                guard let id = contact.wakeGrantID else { return }
                                Task { await model.sendToPhone(grantID: id, immediately: true) }
                            }
                            ContactActionTile(
                                title: "sharing.setAlarm",
                                systemImage: "alarm.fill",
                                disabled: paused || !ContactActionPolicy.canWake(contact)
                            ) {
                                guard let id = contact.wakeGrantID else { return }
                                model.editAlarm(forContactGrant: id)
                            }
                            ContactActionTile(
                                title: "sharing.addToGroup",
                                systemImage: "person.badge.plus",
                                disabled: !ContactActionPolicy.canAddToGroup(contact)
                            ) {
                                groupingMemberID = contact.memberID
                            }
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("sharing.delete.confirm", role: .destructive) {
                        contactPendingDelete = contact
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("sharing.rename") { beginRename(contact) }
                        .tint(.indigo)
                }
            }
        }
    }

    private func beginRename(_ contact: SharingContact) {
        let grantID = contact.hostedGrantID ?? contact.wakeGrantID
        guard let grantID else { return }
        renameDraft = contact.name == String(localized: "sharing.someone") ? "" : contact.name
        renamingGrantID = grantID
    }

    private var addToGroupSheet: some View {
        NavigationStack {
            Form {
                if model.snapshot.friendGroups.isEmpty {
                    Text("sharing.friendGroups.empty")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.snapshot.friendGroups) { group in
                    Button(group.name) {
                        if let groupingMemberID {
                            model.addMember(groupingMemberID, toGroup: group.id)
                        }
                        self.groupingMemberID = nil
                    }
                }
            }
            .navigationTitle("sharing.addToGroup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sharing.cancel") { groupingMemberID = nil }
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

private struct ContactPauseTile: View {
    @Environment(\.appAccent) private var appAccent
    let paused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.body.weight(.semibold))
                Group {
                    if paused {
                        Text("sharing.resume")
                    } else {
                        Text("sharing.pause")
                    }
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .foregroundStyle(appAccent)
            .frame(minWidth: 64, minHeight: 52)
            .padding(.horizontal, 6)
            .background(appAccent.opacity(paused ? 0.28 : 0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(paused ? LocalizedStringKey("sharing.resume") : LocalizedStringKey("sharing.pause")))
        .accessibilityIdentifier(paused ? "contact-resume" : "contact-pause")
    }
}

private struct ContactActionTile: View {
    @Environment(\.appAccent) private var appAccent
    let title: LocalizedStringKey
    let systemImage: String
    var disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(disabled ? Color.secondary : appAccent)
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .background(
                (disabled ? Color.secondary.opacity(0.12) : appAccent.opacity(0.16)),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
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
                    VoiceRecorderPanel(
                        recorder: recorder,
                        preview: preview,
                        help: "sharing.voice.help",
                        onUse: { _ in },
                        onClear: { recorder.discard() }
                    )
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

private struct FriendGroupEditor: View {
    let people: [ShareGrant]
    var onSave: (String, [UUID]) -> Void
    var onCancel: () -> Void
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                TextField("sharing.friendGroups.name", text: $name)
                Section("sharing.friendGroups.members") {
                    if people.isEmpty {
                        Text("sharing.friendGroups.nobody")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(people) { grant in
                        let person = grant.owner.id
                        Button {
                            if selected.contains(person) { selected.remove(person) } else { selected.insert(person) }
                        } label: {
                            HStack {
                                Text(PersonName.listLabel(for: grant, profileID: model.profile.id, grants: model.grants, generic: grant.owner.displayName))
                                Spacer()
                                if selected.contains(person) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("sharing.friendGroups.add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sharing.cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sharing.done") { onSave(name, Array(selected)) }
                        .disabled(PersonName.nonempty(name) == nil || selected.isEmpty)
                }
            }
        }
    }
}
