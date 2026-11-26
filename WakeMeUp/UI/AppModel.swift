import CloudKit
import Foundation
import Observation
import UIKit
import UserNotifications

struct UserFacingError: Equatable {
    var summary: String
    var detail: String
}

enum AppTab: Hashable {
    case nap
    case alarms
    case sharing
    case calendar
    case achievements
}

@MainActor
enum AppRuntime {
    static var model: AppModel?
    private static var pendingShare: CKShare.Metadata?

    private static var pendingURL: URL?

    static func acceptWhenReady(_ metadata: CKShare.Metadata) async {
        pendingShare = metadata
        await model?.acceptPendingShare()
    }

    static func acceptURLWhenReady(_ url: URL) async {
        guard InviteLinkPolicy.isCloudShare(url) else { return }
        if let model {
            await model.acceptShareLink(url)
        } else {
            pendingURL = url
        }
    }

    static func takePendingShare() -> CKShare.Metadata? {
        let metadata = pendingShare
        pendingShare = nil
        return metadata
    }

    static func takePendingURL() -> URL? {
        let url = pendingURL
        pendingURL = nil
        return url
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: LibrarySnapshot
    var editor: AlarmDraft?
    /// When set, saving the editor sends the alarm to this grant instead of storing it locally.
    var editorRecipientGrantID: UUID?
    var ringingAlarmID: UUID?
    private var heldRingingAlarm: Alarm?
    var showGroups = false
    var selectedTab: AppTab = .alarms
    var authorization: AlarmAccessState = .unknown
    var notificationAllowed = false
    var scheduleFailure: String?
    var presentedError: UserFacingError?
    var statusNotice: String?
    /// Grants whose shared zone was missing on the last refresh or send.
    var unreachableGrantIDs: Set<UUID> = []
    var shareURL: URL?
    var shareMessage = ""
    var shareStatus: String?
    var needsOwnName = false
    var friendDraftName = ""
    var remoteLabel = ""
    var remoteHour = 7
    var remoteMinute = 0
    let suppressPermissionBanner: Bool

    private let store: LibraryStore
    private let coordinator: AlarmCoordinator
    private let cloudKit: CloudKitSharingClient?
    private let ownNames = OwnNameStore(
        local: UserDefaultsStringStore(defaults: .standard),
        cloud: UbiquitousStringStore(store: .default)
    )
    private var started = false
    private var refreshing = false
    private var acceptingReturn = false
    /// Grants whose commands already on the server must not become alarms.
    private var grantsToSeal: Set<UUID> = []
    private var heldShare: CKShare.Metadata?
    private var heldURL: URL?
    private var wakeCheck: Task<Void, Never>?
    private var publishingWake = false
    private var wakePublishAgain = false

    var ownName: String {
        let stored = ownNames.load()
        if let name = PersonName.nonempty(stored) { return name }
        return PersonName.nonempty(snapshot.profile.displayName) ?? ""
    }

    var library: AlarmLibrary { snapshot.library }
    var usesCloudKit: Bool { cloudKit != nil }

    /// Release and TestFlight never show the on-device friend. Debug builds use it only until CloudKit is on.
    var showsSimulatedPreview: Bool {
        #if DEBUG
        cloudKit == nil
        #else
        false
        #endif
    }
    var profile: Participant { snapshot.profile }
    var simulatedFriend: Participant? { snapshot.simulatedFriend }
    var grants: [ShareGrant] { snapshot.permissions.grants }
    var customSounds: [CustomSound] { snapshot.customSounds }
    var calendarAlarms: [CalendarAlarm] { snapshot.calendarAlarms }
    var napMinutes: Int = NapSettings.defaultMinutes
    var napSoundID: String = SoundCatalog.defaultID
    var defaultSnoozeMinutes: Int = DefaultSnooze.fallback
    /// Local nap timer. The Nap tab reads this directly. It is not an entry in the alarm list.
    var napSession: NapSession?

    var ringingAlarm: Alarm? {
        guard let ringingAlarmID else { return nil }
        if let alarm = snapshot.library.alarm(ringingAlarmID) { return alarm }
        if let calendar = snapshot.calendarAlarms.first(where: { $0.id == ringingAlarmID }) {
            return calendar.alarmForScheduling(now: .now, calendar: .current)
        }
        if heldRingingAlarm?.id == ringingAlarmID { return heldRingingAlarm }
        return nil
    }

    init(store: LibraryStore? = nil, cloudKit explicitCloudKit: CloudKitSharingClient? = nil, screenshot: Bool? = nil) {
        let store = store ?? LibraryStore(url: LibraryStore.applicationSupportURL())
        self.store = store
        napMinutes = NapSettings.minutes(in: .standard)
        napSoundID = NapSettings.soundID(in: .standard)
        defaultSnoozeMinutes = DefaultSnooze.minutes(in: .standard)
        napSession = NapSessionStore.load(from: .standard, now: .now)
        let screenshot = screenshot ?? LaunchConfiguration.seedDemo
        suppressPermissionBanner = screenshot
        let loaded = store.load() ?? LibrarySnapshot.empty(
            profile: Participant(id: UUID(), displayName: "")
        )
        if screenshot && LaunchConfiguration.storeScreenshots {
            DemoMedia.install()
            snapshot = DemoData.storeSnapshot()
        } else if screenshot {
            snapshot = DemoData.make()
        } else {
            snapshot = loaded
        }
        coordinator = AlarmCoordinator()
        if let explicitCloudKit {
            cloudKit = explicitCloudKit
        } else if AppConfig.activatesCloudKit && !screenshot {
            cloudKit = CloudKitSharingClient(containerID: AppConfig.cloudKitContainerID)
        } else {
            cloudKit = nil
        }
        if !screenshot {
            restoreOwnName()
        }
        AppRuntime.model = self
        Task {
            await acceptPendingShare()
            if let url = AppRuntime.takePendingURL() {
                await acceptShareLink(url)
            }
        }
        friendDraftName = String(localized: "demo.friend")
        remoteLabel = String(localized: "demo.morning")
        switch LaunchConfiguration.screen {
        case .editor:
            editor = DemoData.lovedOneDraft(in: snapshot)
        case .groups:
            showGroups = true
        case .sharing:
            selectedTab = .sharing
        case .ringing:
            ringingAlarmID = DemoData.ringingAlarmID
            heldRingingAlarm = snapshot.library.alarm(DemoData.ringingAlarmID)
        case .nap:
            selectedTab = .nap
            let session = DemoData.napSession()
            napMinutes = session.minutes
            napSession = session
        case .calendar:
            selectedTab = .calendar
        case .achievements:
            selectedTab = .achievements
        case .alarms:
            break
        }
    }

    static func preview() -> AppModel {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wakemeup-preview.json")
        return AppModel(store: LibraryStore(url: url), cloudKit: nil, screenshot: true)
    }

    func start() async {
        guard !started else { return }
        started = true
        guard !suppressPermissionBanner else { return }
        update { $0.permissions.removeUnsharedInvites() }
        dropSelfAuthoredAlarms()
        await removeNapsFromAlarmList()
        retireOneTimeAlarms()
        retireCalendarAlarms()
        authorization = coordinator.accessState()
        notificationAllowed = await coordinator.notificationStatus() == .authorized
        await reschedule(requestAccess: false)
        await restoreNapAlarm()
        if let ids = coordinator.alertingIDs() {
            applyAlerting(ids)
        }
        if let handoff = LaunchHandoff.consume() {
            presentResolved(handoff.alarmID)
            await UIApplication.shared.open(handoff.songURL)
        }
        Task { await refreshRemote() }
        Task { await cloudKit?.ensureSilentSubscription() }
        Task { await publishDueWakeReports() }
        await coordinator.observeAlerting { [weak self] ids in
            self?.applyAlerting(ids)
        }
    }

    /// Reads AlarmKit again after the app returns from the background.
    func reconcileRingingWithSystem() {
        guard let ids = coordinator.alertingIDs() else { return }
        applyAlerting(ids)
    }

    func allowAlarms() async {
        authorization = await coordinator.requestAccess()
        notificationAllowed = await coordinator.notificationStatus() == .authorized
        await reschedule(requestAccess: false)
    }

    func addAlarm() {
        editorRecipientGrantID = nil
        editor = .makeNew(snoozeMinutes: defaultSnoozeMinutes)
    }

    func edit(_ alarm: Alarm) {
        editorRecipientGrantID = nil
        editor = AlarmDraft(alarm: alarm)
    }

    func closeEditor() {
        editor = nil
        editorRecipientGrantID = nil
    }

    func editAlarm(forContactGrant grantID: UUID) {
        editorRecipientGrantID = grantID
        editor = .makeNew(snoozeMinutes: defaultSnoozeMinutes)
    }

    func installLocalVoice(_ url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent
        let name = stem.hasPrefix("voice-") ? stem : "voice-\(UUID().uuidString)"
        guard let sound = try? VoiceFiles.install(from: url, soundID: name) else { return nil }
        update {
            $0.customSounds.removeAll { $0.id == sound.id }
            $0.customSounds.append(sound)
        }
        return sound.id
    }

    func installVideo(from url: URL) async -> String? {
        let id = VideoMessagePolicy.makeID()
        do {
            return try await VideoFiles.install(from: url, id: id)
        } catch {
            report(summary: String(localized: "video.unreadable"))
            return nil
        }
    }

    func removeVideo(_ id: String) {
        VideoFiles.remove(id: id)
    }

    func removeLocalVoice(_ soundID: String) {
        let filename = snapshot.customSounds.first { $0.id == soundID }?.filename
        update { $0.customSounds.removeAll { $0.id == soundID } }
        if let filename {
            VoiceFiles.remove(relativeFilename: filename)
        }
    }

    func save(draft: AlarmDraft) {
        guard let alarm = draft.makeAlarm() else {
            report(summary: String(localized: "song.invalid"))
            return
        }
        let recipient = editorRecipientGrantID
        editor = nil
        editorRecipientGrantID = nil
        if let recipient {
            let voice = voiceFile(for: alarm.soundID)
            Task { await sendToPhone(grantID: recipient, immediately: false, voiceFile: voice, prepared: alarm) }
            return
        }
        update { $0.library.upsert(alarm) }
        Task { await reschedule(requestAccess: true) }
    }

    private func voiceFile(for soundID: String) -> URL? {
        guard soundID.hasPrefix("voice-") else { return nil }
        return SoundFiles.previewURL(for: soundID, customSounds: snapshot.customSounds)
    }

    func delete(alarmID: UUID) {
        if napSession?.id == alarmID || NapSettings.activeAlarmID(in: .standard) == alarmID {
            clearNapSession()
        }
        update { $0.library.delete(id: alarmID) }
        Task { await reschedule(requestAccess: false) }
    }

    func setNapMinutes(_ minutes: Int) {
        let clamped = NapSettings.clamped(minutes)
        napMinutes = clamped
        NapSettings.setMinutes(clamped, in: .standard)
    }

    func setDefaultSnoozeMinutes(_ minutes: Int) {
        let clamped = DefaultSnooze.clamped(minutes)
        defaultSnoozeMinutes = clamped
        DefaultSnooze.setMinutes(clamped, in: .standard)
    }

    func setNapSoundID(_ id: String) {
        let sound = id.isEmpty ? SoundCatalog.defaultID : id
        napSoundID = sound
        NapSettings.setSoundID(sound, in: .standard)
    }

    var activeNapFireDate: Date? {
        guard let napSession, napSession.isRunning(at: .now) else { return nil }
        return napSession.fireAt
    }

    @discardableResult
    func startNap(now: Date = .now) async -> String? {
        if let previous = napSession {
            await coordinator.cancelStandalone(id: previous.id)
        }
        let session = NapSession.make(minutes: napMinutes, soundID: napSoundID, now: now)
        napSession = session
        NapSessionStore.save(session, to: .standard)
        NapSettings.setActiveAlarmID(nil, in: .standard)
        await removeNapsFromAlarmList()
        await reschedule(requestAccess: true)
        if let failure = await coordinator.scheduleStandalone(session.alarm(), customSounds: snapshot.customSounds) {
            scheduleFailure = failure
            return NapFailure.message(authorization: authorization, scheduleFailure: failure) ?? failure
        }
        if let message = NapFailure.message(authorization: authorization, scheduleFailure: nil) {
            scheduleFailure = message
            return message
        }
        scheduleFailure = nil
        return nil
    }

    func cancelNap() async {
        let id = napSession?.id
        clearNapSession()
        if let id {
            await coordinator.cancelStandalone(id: id)
        }
    }

    private func clearNapSession() {
        napSession = nil
        NapSessionStore.save(nil, to: .standard)
        NapSettings.setActiveAlarmID(nil, in: .standard)
    }

    private func removeNapsFromAlarmList() async {
        let legacyID = NapSettings.activeAlarmID(in: .standard)
        let cancelIDs = NapListCleanup.idsToCancel(
            in: snapshot.library.alarms,
            sessionID: napSession?.id,
            legacyID: legacyID
        )
        let cleaned = NapListCleanup.removing(from: snapshot.library.alarms, sessionID: napSession?.id)
        if cleaned != snapshot.library.alarms {
            update { $0.library.alarms = cleaned }
        }
        for id in cancelIDs {
            await coordinator.cancelStandalone(id: id)
        }
    }

    private func restoreNapAlarm() async {
        guard let napSession, napSession.isRunning(at: .now) else { return }
        if let failure = await coordinator.scheduleStandalone(napSession.alarm(), customSounds: snapshot.customSounds) {
            scheduleFailure = failure
        }
    }

    func addSpokenAlarm(at date: Date) async {
        let alarm = SpokenAlarm.make(at: date, snoozeMinutes: defaultSnoozeMinutes)
        update { $0.library.upsert(alarm) }
        await reschedule(requestAccess: true)
    }

    @discardableResult
    func wakeContact(named name: String) async -> Bool {
        let contacts = ContactRoster.contacts(profileID: snapshot.profile.id, grants: snapshot.permissions.grants)
        guard let contact = SpokenContactMatch.match(name: name, contacts: contacts),
              let grantID = contact.wakeGrantID else { return false }
        await sendToPhone(grantID: grantID, immediately: true)
        return true
    }

    func saveCalendarAlarm(_ alarm: CalendarAlarm) {
        update {
            if let index = $0.calendarAlarms.firstIndex(where: { $0.id == alarm.id }) {
                $0.calendarAlarms[index] = alarm
            } else {
                $0.calendarAlarms.append(alarm)
            }
        }
        Task { await reschedule(requestAccess: true) }
    }

    func deleteCalendarAlarm(_ id: UUID) {
        update { $0.calendarAlarms.removeAll { $0.id == id } }
        Task { await reschedule(requestAccess: false) }
    }

    func toggle(alarmID: UUID) {
        guard let alarm = snapshot.library.alarm(alarmID) else { return }
        update { $0.library.setEnabled(!alarm.isEnabled, alarmID: alarmID) }
        Task { await reschedule(requestAccess: true) }
    }

    func toggle(groupID: UUID) {
        guard let group = snapshot.library.group(groupID) else { return }
        update { $0.library.setGroupEnabled(!group.isEnabled, groupID: groupID) }
        Task { await reschedule(requestAccess: true) }
    }

    func renameAlarm(_ alarmID: UUID, to label: String) {
        update { $0.library.rename(alarmID: alarmID, to: label) }
        Task { await reschedule(requestAccess: false) }
    }

    func renameCustomSound(_ soundID: String, to name: String) {
        update {
            guard let sounds = SoundLibraryEdit.renamed($0.customSounds, id: soundID, to: name) else { return }
            $0.customSounds = sounds
        }
    }

    func deleteCustomSound(_ soundID: String) {
        let filename = snapshot.customSounds.first { $0.id == soundID }?.filename
        guard snapshot.customSounds.contains(where: { $0.id == soundID }) else { return }
        update {
            $0.customSounds = SoundLibraryEdit.removed($0.customSounds, id: soundID)
            $0.library.alarms = SoundLibraryEdit.clearing(soundID, in: $0.library.alarms)
            for index in $0.sentAlarms.indices where $0.sentAlarms[index].alarm.soundID == soundID {
                $0.sentAlarms[index].alarm.soundID = SoundCatalog.defaultID
            }
        }
        if let filename {
            VoiceFiles.remove(relativeFilename: filename)
        }
        Task { await reschedule(requestAccess: false) }
    }

    func applyBulk(_ patch: BulkAlarmPatch, to alarmIDs: Set<UUID>) {
        guard !alarmIDs.isEmpty else { return }
        update { $0.library.apply(patch, to: alarmIDs) }
        Task { await reschedule(requestAccess: true) }
    }

    func setCollaborationPaused(_ paused: Bool, for contact: SharingContact) async {
        let now = Date()
        let actor = snapshot.profile.id
        let ids = [contact.hostedGrantID, contact.wakeGrantID].compactMap { $0 }
        var written: [ShareGrant] = []
        update { snapshot in
            for id in ids {
                guard var grant = snapshot.permissions.grant(id: id) else { continue }
                grant.collaborationPaused = paused
                grant.collaborationPausedAt = now
                grant.collaborationPausedBy = actor
                snapshot.permissions.replace(grant)
                written.append(grant)
            }
        }
        if let cloudKit {
            for grant in written where grant.cloudKitRootRecordName != nil {
                let asOwner = grant.owner.id == actor
                try? await cloudKit.setCollaborationPause(paused, at: now, by: actor, on: grant, asOwner: asOwner)
            }
        }
        await reschedule(requestAccess: false)
    }

    func setSound(_ soundID: String, for alarmIDs: Set<UUID>) {
        guard !alarmIDs.isEmpty else { return }
        update { $0.library.setSound(soundID, alarmIDs: alarmIDs) }
        Task { await reschedule(requestAccess: true) }
    }

    func setSound(_ soundID: String, forGroup groupID: UUID) {
        let ids = Set(snapshot.library.alarms(in: groupID).map(\.id))
        setSound(soundID, for: ids)
    }

    func moveGroup(_ sourceID: UUID, before targetID: UUID) {
        update { $0.library.moveGroup(sourceID, before: targetID) }
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        update { $0.library.moveGroups(from: source, to: destination) }
    }

    func createGroup(name: String, symbol: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { _ = $0.library.addGroup(name: trimmed, symbol: symbol) }
    }

    func updateGroup(id: UUID, name: String, symbol: String) {
        update { $0.library.updateGroup(id: id, name: name, symbol: symbol) }
    }

    func moveAlarm(_ alarmID: UUID, to groupID: UUID?) {
        let before = snapshot.library.alarm(alarmID)
        update { $0.library.moveAlarm(alarmID, to: groupID) }
        guard snapshot.library.alarm(alarmID) != before else { return }
        Task { await reschedule(requestAccess: true) }
    }

    func deleteGroup(id: UUID) {
        update { $0.library.deleteGroup(id: id) }
        Task { await reschedule(requestAccess: false) }
    }

    func rename(_ name: String) {
        ownNames.save(name)
        let stored = ownNames.load()
        guard let saved = PersonName.nonempty(stored) else { return }
        guard saved != snapshot.profile.displayName else {
            needsOwnName = false
            return
        }
        update { snapshot in
            snapshot.profile.displayName = saved
            for index in snapshot.permissions.grants.indices {
                snapshot.permissions.grants[index] = GrantRefreshMerge.applyingOwnName(
                    saved,
                    to: snapshot.permissions.grants[index],
                    profileID: snapshot.profile.id
                )
            }
        }
        needsOwnName = false
    }

    func commitOwnName() async {
        await pushOwnName()
        await continueHeldAcceptIfNeeded()
        await acceptReturnInvitesIfNeeded()
    }

    func importSound(source: URL, window: TrimWindow, name: String) async -> String? {
        do {
            let directory = try SoundFiles.librarySoundsDirectory()
            let id = UUID().uuidString
            let destination = directory.appendingPathComponent("\(id).caf")
            try await AudioTrimmer.trim(source: source, window: window, destination: destination)
            let sound = CustomSound(id: id, displayName: name, filename: "\(id).caf")
            update { $0.customSounds.append(sound) }
            return id
        } catch {
            report(summary: String(localized: "sound.unreadable"))
            return nil
        }
    }

    func addSimulatedFriend() {
        let name = friendDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let friend = Participant(id: UUID(), displayName: name)
        update { snapshot in
            snapshot.simulatedFriend = friend
            let invite = snapshot.permissions.createInvite(
                owner: snapshot.profile,
                now: .now,
                code: InviteCode.make(),
                secret: UUID().uuidString
            )
            _ = try? snapshot.permissions.accept(code: invite.inviteCode, grantee: friend, now: .now)
        }
    }

    func ringFromSimulatedFriend(immediately: Bool) {
        guard let friend = snapshot.simulatedFriend else { return }
        do {
            let grant = try snapshot.permissions.authorize(sender: friend.id, recipient: snapshot.profile.id)
            let alarm = Alarm(
                id: UUID(),
                schedule: immediately
                    ? .oneShot(fireAt: Date().addingTimeInterval(3))
                    : .wallClock(hour: remoteHour, minute: remoteMinute, repeatDays: []),
                label: remoteLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                soundID: SoundCatalog.defaultID,
                snoozeEnabled: true,
                snoozeMinutes: defaultSnoozeMinutes,
                isEnabled: true,
                groupID: nil,
                songLink: nil,
                origin: .local,
                resumeWhenGroupEnables: nil
            )
            let command = RemoteAlarmCommand(
                id: UUID(),
                grantID: grant.id,
                senderID: friend.id,
                recipientID: snapshot.profile.id,
                action: immediately ? .triggerNow : .upsert,
                createdAt: .now,
                alarm: alarm,
                alarmID: alarm.id,
                enabled: true
            )
            var library = snapshot.library
            try RemoteCommandApplier.apply(command: command, grant: grant, library: &library)
            update { $0.library = library }
            Task { await reschedule(requestAccess: true) }
        } catch {
            report(summary: String(localized: "error.generic"))
        }
    }

    @discardableResult
    func createCloudInvite(inviteeName: String) async -> Bool {
        guard let cloudKit else {
            report(summary: RemoteBackendError.notConfigured.errorDescription ?? String(localized: "error.generic"))
            return false
        }
        guard let label = PersonName.nonempty(inviteeName) else { return false }
        guard let me = await identityForSharing() else {
            needsOwnName = true
            selectedTab = .sharing
            return false
        }
        needsOwnName = false
        var draft = ShareGrant(
            id: UUID(),
            inviteCode: "",
            secret: UUID().uuidString,
            owner: Participant(id: me.id, displayName: me.displayName),
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: nil,
            cloudKitZoneName: nil,
            cloudKitOwnerName: nil
        )
        draft.inviteeName = label
        do {
            let (shared, _) = try await cloudKit.createShare(for: draft)
            update {
                $0.permissions.removeUnsharedInvites()
                $0.permissions.replace(shared)
            }
            presentInvite(shared.inviteCode)
            return true
        } catch {
            update { $0.permissions.removeUnsharedInvites() }
            reportCloud(error)
            return false
        }
    }

    func copyInviteLink(grantID: UUID) {
        guard let grant = snapshot.permissions.grant(id: grantID),
              let url = InviteLinkPolicy.url(from: grant.inviteCode) else { return }
        UIPasteboard.general.string = url.absoluteString
    }

    func presentInvite(_ inviteCode: String) {
        guard let url = InviteLinkPolicy.url(from: inviteCode) else { return }
        shareMessage = String(localized: "sharing.inviteMessage")
        shareURL = url
    }

    func acceptPendingShare() async {
        guard let metadata = AppRuntime.takePendingShare() else { return }
        await acceptCloudShare(metadata)
    }

    func acceptCloudShare(_ metadata: CKShare.Metadata) async {
        guard let me = await identityForSharing() else {
            heldShare = metadata
            needsOwnName = true
            selectedTab = .sharing
            return
        }
        needsOwnName = false
        await acceptInvite {
            guard let cloudKit else { throw RemoteBackendError.notConfigured }
            return try await AsyncDeadline.run(seconds: 30) {
                try await cloudKit.accept(metadata: metadata, grantee: me)
            }
        }
    }

    func acceptShareLink(_ url: URL) async {
        guard InviteLinkPolicy.isCloudShare(url) else {
            report(summary: String(localized: "sharing.badLink"))
            return
        }
        guard let me = await identityForSharing() else {
            heldURL = url
            needsOwnName = true
            selectedTab = .sharing
            return
        }
        needsOwnName = false
        await acceptInvite {
            guard let cloudKit else { throw RemoteBackendError.notConfigured }
            return try await AsyncDeadline.run(seconds: 30) {
                try await cloudKit.accept(url: url, grantee: me)
            }
        }
    }

    private func acceptInvite(_ work: () async throws -> ShareGrant) async {
        shareStatus = String(localized: "sharing.accepting")
        selectedTab = .sharing
        defer { shareStatus = nil }
        do {
            let grant = try await work()
            update { $0.permissions.replace(grant) }
            grantsToSeal.insert(grant.id)
            await refreshRemote()
        } catch is AsyncDeadlineError {
            report(summary: String(localized: "sharing.timedOut"))
        } catch is CancellationError {
            return
        } catch {
            reportCloud(error)
        }
    }

    func refreshRemote() async {
        guard let cloudKit, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        dropSelfAuthoredAlarms()
        retireOneTimeAlarms()
        retireCalendarAlarms()
        await cloudKit.prepareForRefresh()
        await createMissingReturnShares()
        await publishMissingReturnLinks()
        let grants = snapshot.permissions.grants.filter { $0.cloudKitRootRecordName != nil && $0.state != .revoked }
        for grant in grants {
            let asOwner = grant.owner.id == snapshot.profile.id
            let updatedGrant: ShareGrant
            let commands: [RemoteAlarmCommand]
            do {
                (updatedGrant, commands) = try await cloudKit.refresh(grant, asOwner: asOwner)
            } catch {
                if ShareFailureKind.isShareNotFound(error) {
                    update { $0.permissions.grants.removeAll { $0.id == grant.id } }
                } else {
                    unreachableGrantIDs.insert(grant.id)
                }
                continue
            }
            unreachableGrantIDs.remove(grant.id)
            var updated = GrantRefreshMerge.merging(updatedGrant, with: grant)
            updated = GrantRefreshMerge.applyingOwnName(ownNames.load(), to: updated, profileID: snapshot.profile.id)
            var library = snapshot.library
            var applied = snapshot.appliedCommandIDs
            var notices: [String] = []
            if asOwner, let joined = ShareChangeNotice.joinedName(previous: grant, updated: updated) {
                notices.append(String(format: String(localized: "sharing.push.joined"), joined))
            }
            let sealExisting = grantsToSeal.contains(grant.id) || (grant.state != .active && updated.state == .active)
            grantsToSeal.remove(grant.id)
            let decision = RemoteCommandGate.partition(
                commands: commands,
                applied: Set(applied),
                sealExisting: sealExisting
            )
            applied.append(contentsOf: decision.seal)
            var newSounds: [CustomSound] = []
            for command in decision.apply {
                var command = command
                let mine = snapshot.profile.id
                guard IncomingCommandPolicy.shouldApply(command: command, profileID: mine) else {
                    applied.append(command.id)
                    continue
                }
                var grantsNow = snapshot.permissions.grants
                if let index = grantsNow.firstIndex(where: { $0.id == updated.id }) {
                    grantsNow[index] = updated
                }
                if CollaborationPause.isPaused(profileID: mine, otherID: command.senderID, grants: grantsNow) {
                    applied.append(command.id)
                    continue
                }
                if updated.state == .active {
                    if var alarm = command.alarm, let videoID = command.videoRecordName {
                        if let file = try? await cloudKit.videoFile(named: videoID, grant: grant, asOwner: asOwner),
                           let installed = try? await VideoFiles.install(from: file, id: videoID) {
                            alarm.videoFileID = installed
                        } else {
                            alarm.videoFileID = nil
                        }
                        command.alarm = alarm
                    }
                    if var alarm = command.alarm, command.voiceRecordName != nil {
                        let voiceID = command.voiceRecordName ?? ""
                        var installed = false
                        if let file = try? await cloudKit.voiceFile(named: voiceID, grant: grant, asOwner: asOwner),
                           let sound = try? VoiceFiles.install(from: file, soundID: voiceID) {
                            newSounds.append(sound)
                            installed = true
                        }
                        alarm.soundID = VoiceClipPolicy.soundID(installed: installed, voiceID: voiceID)
                        command.alarm = alarm
                    }
                    if command.action == .triggerNow, var alarm = command.alarm {
                        alarm = WakeNowSchedule.applying(to: alarm, processedAt: .now)
                        command.alarm = alarm
                    }
                    if var alarm = command.alarm {
                        alarm = OneTimeAlarmExpiry.stamped(alarm, now: .now, calendar: .current)
                        command.alarm = alarm
                    }
                    if (command.action == .upsert || command.action == .triggerNow), let alarm = command.alarm {
                        notices.append(RemoteAlarmNotice.text(sender: PersonName.senderName(grant: updated), schedule: alarm.schedule))
                    }
                    try? RemoteCommandApplier.apply(command: command, grant: updated, library: &library)
                }
                applied.append(command.id)
            }
            let wakeChanges = asOwner
                ? WakeStatusApply.changes(reports: updated.wakeReports ?? [], sent: snapshot.sentAlarms) { report in
                    if updated.grantee?.id == report.reporterID, let label = PersonName.nonempty(updated.inviteeName) {
                        return label
                    }
                    return report.reporterName
                }
                : []
            notices.append(contentsOf: wakeChanges.map(\.notice))
            if !notices.isEmpty {
                Task { await postRemoteNotices(notices) }
            }
            update {
                $0.permissions.replace(updated)
                $0.library = library
                $0.appliedCommandIDs = applied
                for change in wakeChanges {
                    guard let index = $0.sentAlarms.firstIndex(where: { $0.commandID == change.commandID }) else { continue }
                    $0.sentAlarms[index].wakeStatus = change.status
                    $0.sentAlarms[index].wakeStatusAt = change.at
                }
                for sound in newSounds where !$0.customSounds.contains(where: { $0.id == sound.id }) {
                    $0.customSounds.append(sound)
                }
            }
        }
        await reschedule(requestAccess: false)
        await acceptReturnInvitesIfNeeded()
    }

    private func createMissingReturnShares() async {
        for grant in snapshot.permissions.grants where grant.state != .revoked {
            try? await createReturnShareIfNeeded(for: grant)
        }
    }

    func report(summary: String, detail: String = "") {
        presentedError = UserFacingError(summary: summary, detail: detail)
    }

    func reportCloud(_ error: Error) {
        let summary: String
        switch ShareFailureKind.classify(error) {
        case .shareLinkGone:
            summary = String(localized: "sharing.connection.linkGone")
        case .zoneMissing:
            summary = String(localized: "sharing.connection.missing")
        case .notSignedIn:
            summary = String(localized: "sharing.signIn")
        case .network:
            summary = String(localized: "sharing.connection.network")
        case .timedOut:
            summary = String(localized: "sharing.timedOut")
        case .other:
            summary = String(localized: "sharing.connection.failed")
        }
        presentedError = UserFacingError(summary: summary, detail: CloudKitErrorText.detail(for: error))
    }

    func renamePerson(grantID: UUID, to name: String) async {
        guard let label = PersonName.nonempty(name) else { return }
        guard let grant = snapshot.permissions.grant(id: grantID) else { return }
        let targetID: UUID
        if grant.owner.id == snapshot.profile.id {
            targetID = grant.id
        } else if let mine = snapshot.permissions.grants.first(where: {
            $0.owner.id == snapshot.profile.id && ($0.grantee?.id == grant.owner.id || $0.returnInviteURL == grant.inviteCode)
        }) {
            targetID = mine.id
        } else {
            return
        }
        guard var target = snapshot.permissions.grant(id: targetID) else { return }
        target.inviteeName = label
        update { $0.permissions.replace(target) }
        if let cloudKit, target.cloudKitRootRecordName != nil, target.owner.id == snapshot.profile.id {
            try? await cloudKit.updateInviteeName(label, on: target)
        }
    }

    func revoke(grantID: UUID) async {
        guard let existing = snapshot.permissions.grant(id: grantID) else { return }
        var revoked: ShareGrant?
        update { snapshot in
            revoked = try? snapshot.permissions.revoke(grantID: grantID, by: snapshot.profile.id)
        }
        guard let revoked, let cloudKit, existing.cloudKitRootRecordName != nil, existing.owner.id == snapshot.profile.id else {
            return
        }
        try? await cloudKit.revoke(revoked)
    }

    func createFriendGroup(name: String, memberIDs: [UUID]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !memberIDs.isEmpty else { return }
        update {
            $0.friendGroups.append(FriendGroup(id: UUID(), name: trimmed, memberIDs: memberIDs))
        }
    }

    func deleteFriendGroup(id: UUID) {
        update { $0.friendGroups.removeAll { $0.id == id } }
    }

    func sendToFriendGroup(id: UUID) async {
        guard let group = snapshot.friendGroups.first(where: { $0.id == id }) else { return }
        let grants = snapshot.permissions.grants.filter {
            $0.state == .active && $0.grantee?.id == snapshot.profile.id && group.memberIDs.contains($0.owner.id)
        }
        for grant in grants {
            await sendToPhone(grantID: grant.id, immediately: false, friendGroup: group)
        }
    }

    func addMember(_ memberID: UUID, toGroup groupID: UUID) {
        update {
            guard let index = $0.friendGroups.firstIndex(where: { $0.id == groupID }) else { return }
            if !$0.friendGroups[index].memberIDs.contains(memberID) {
                $0.friendGroups[index].memberIDs.append(memberID)
            }
        }
    }

    func sendToPhone(
        grantID: UUID,
        immediately: Bool,
        voiceFile: URL? = nil,
        friendGroup: FriendGroup? = nil,
        prepared: Alarm? = nil
    ) async {
        guard let grant = snapshot.permissions.grant(id: grantID), let cloudKit else { return }
        if grant.collaborationPaused == true {
            return
        }
        if let other = grant.owner.id == snapshot.profile.id ? grant.grantee?.id : grant.owner.id,
           CollaborationPause.isPaused(profileID: snapshot.profile.id, otherID: other, grants: snapshot.permissions.grants) {
            return
        }
        var alarm = prepared ?? Alarm(
            id: UUID(),
            schedule: immediately
                ? .oneShot(fireAt: Date().addingTimeInterval(3))
                : .wallClock(hour: remoteHour, minute: remoteMinute, repeatDays: []),
            label: remoteLabel,
            soundID: SoundCatalog.defaultID,
            snoozeEnabled: true,
            snoozeMinutes: defaultSnoozeMinutes,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        var voiceName: String?
        var installed: CustomSound?
        var voiceWarning: String?
        var voiceDetail = ""
        if let voiceFile {
            if alarm.soundID.hasPrefix("voice-") {
                voiceName = alarm.soundID
            } else {
                let name = "voice-\(UUID().uuidString)"
                if let sound = try? VoiceFiles.install(from: voiceFile, soundID: name) {
                    alarm.soundID = sound.id
                    voiceName = name
                    installed = sound
                }
            }
            let attemptedVoice = voiceName
            var uploaded = false
            if let attemptedVoice {
                do {
                    try await cloudKit.saveVoice(file: voiceFile, recordName: attemptedVoice, grant: grant, asOwner: false)
                    uploaded = true
                } catch {
                    voiceDetail = CloudKitErrorText.detail(for: error)
                }
            }
            let payload = OutgoingVoice.payload(soundID: alarm.soundID, voiceName: attemptedVoice, uploaded: uploaded)
            alarm.soundID = payload.soundID
            voiceName = payload.voiceRecordName
            if payload.warn {
                installed = nil
                voiceWarning = String(localized: "sharing.voice.skipped")
            }
        }
        var videoName: String?
        var videoWarning: String?
        var videoDetail = ""
        if let videoID = alarm.videoFileID, let videoFile = VideoFiles.url(id: videoID) {
            var uploaded = false
            do {
                try await cloudKit.saveVideo(file: videoFile, recordName: videoID, grant: grant, asOwner: false)
                uploaded = true
            } catch {
                videoDetail = CloudKitErrorText.detail(for: error)
            }
            let payload = OutgoingVideo.payload(recordName: videoID, uploaded: uploaded)
            videoName = payload.recordName
            if payload.warn {
                alarm.videoFileID = nil
                videoWarning = String(localized: "video.skipped")
            }
        }
        var command = RemoteAlarmCommand(
            id: UUID(),
            grantID: grant.id,
            senderID: snapshot.profile.id,
            recipientID: grant.owner.id,
            action: immediately ? .triggerNow : .upsert,
            createdAt: .now,
            alarm: alarm,
            alarmID: alarm.id,
            enabled: true
        )
        command.voiceRecordName = voiceName
        command.videoRecordName = videoName
        do {
            _ = try snapshot.permissions.authorize(sender: snapshot.profile.id, recipient: grant.owner.id)
            try await cloudKit.append(command: command, grant: grant, asOwner: false)
            if let voiceWarning {
                report(summary: voiceWarning, detail: voiceDetail)
            } else if let videoWarning {
                report(summary: videoWarning, detail: videoDetail)
            } else if immediately {
                statusNotice = String(localized: "sharing.wakeNow.soon")
            }
            if !immediately {
                let sent = SentAlarm(
                    alarm: alarm,
                    recipientID: grant.owner.id,
                    recipientName: PersonName.listLabel(
                        for: grant,
                        profileID: snapshot.profile.id,
                        grants: snapshot.permissions.grants,
                        generic: grant.owner.displayName
                    ),
                    sentAt: command.createdAt,
                    commandID: command.id,
                    friendGroupID: friendGroup?.id,
                    friendGroupName: friendGroup?.name
                )
                update {
                    if let installed { $0.customSounds.append(installed) }
                    $0.sentAlarms.append(sent)
                }
            }
        } catch {
            unreachableGrantIDs.insert(grantID)
            let kind = ShareFailureKind.classify(error)
            if kind == .shareLinkGone {
                update { $0.permissions.grants.removeAll { $0.id == grantID } }
                report(summary: String(localized: "sharing.connection.gone"), detail: CloudKitErrorText.detail(for: error))
            } else {
                reportCloud(error)
            }
        }
    }

    /// Drops a sent alarm from this phone and asks the other phone to cancel it.
    func deleteSentAlarm(commandID: UUID) async {
        guard let sent = snapshot.sentAlarms.first(where: { $0.commandID == commandID }) else { return }
        let senderID = snapshot.profile.id
        update { $0.sentAlarms.removeAll { $0.commandID == commandID } }
        guard let cloudKit,
              let grant = snapshot.permissions.grants.first(where: {
                  $0.state == .active && $0.owner.id == sent.recipientID && $0.grantee?.id == senderID
              }) else {
            return
        }
        let command = RemoteAlarmCommand(
            id: UUID(),
            grantID: grant.id,
            senderID: senderID,
            recipientID: sent.recipientID,
            action: .cancel,
            createdAt: .now,
            alarm: nil,
            alarmID: sent.alarm.id,
            enabled: nil
        )
        do {
            _ = try snapshot.permissions.authorize(sender: senderID, recipient: sent.recipientID)
            try await cloudKit.append(command: command, grant: grant, asOwner: false)
        } catch {
            unreachableGrantIDs.insert(grant.id)
            reportCloud(error)
        }
    }

    func stopRinging() async {
        guard let id = ringingAlarmID else { return }
        noteRemoteAlarmDismissed(id)
        await coordinator.stop(id: id)
        ringingAlarmID = nil
    }

    func snoozeRinging() async {
        guard let alarm = ringingAlarm else { return }
        noteRemoteAlarmSnoozed(alarm.id)
        await coordinator.snooze(alarm, customSounds: snapshot.customSounds)
        ringingAlarmID = nil
    }

    func playSong(of alarm: Alarm) async {
        guard let link = alarm.songLink else { return }
        noteRemoteAlarmDismissed(alarm.id)
        await coordinator.stop(id: alarm.id)
        ringingAlarmID = nil
        await UIApplication.shared.open(link.url)
    }

    func handle(url: URL) {
        if InviteLinkPolicy.isCloudShare(url) {
            Task { await acceptShareLink(url) }
            return
        }
        guard url.scheme?.lowercased() == "wakemeup" else {
            if SongLink.parse(url.absoluteString) != nil {
                UIApplication.shared.open(url)
            }
            return
        }
        if let id = UUID(uuidString: url.lastPathComponent) {
            presentResolved(id)
        }
        if let song = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "song" })?
            .value,
           let songURL = URL(string: song) {
            UIApplication.shared.open(songURL)
        }
    }

    func handleNotification(_ response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let alarmID = (info["alarmID"] as? String).flatMap(UUID.init(uuidString:))
        switch response.actionIdentifier {
        case NotificationAction.playSong:
            if let alarmID { presentResolved(alarmID) }
            if let song = info["song"] as? String, let url = URL(string: song) {
                await coordinator.stop(id: alarmID ?? UUID())
                await UIApplication.shared.open(url)
            }
        case NotificationAction.snooze:
            if let alarmID, let alarm = snapshot.library.alarm(alarmID) {
                noteRemoteAlarmSnoozed(alarmID)
                await coordinator.snooze(alarm, customSounds: snapshot.customSounds)
            }
        case NotificationAction.stop, UNNotificationDismissActionIdentifier:
            if let alarmID {
                noteRemoteAlarmDismissed(alarmID)
                await coordinator.stop(id: alarmID)
            }
        default:
            if let alarmID { presentResolved(alarmID) }
        }
    }

    func dismissRinging() {
        guard ringingAlarmID != nil || heldRingingAlarm != nil else { return }
        if let id = ringingAlarmID {
            noteRemoteAlarmDismissed(id)
            retireOneTimeAlarms(rungIDs: [id])
            retireCalendarAlarms(rungIDs: [id])
        }
        ringingAlarmID = nil
        heldRingingAlarm = nil
        Task { await reschedule(requestAccess: false) }
    }

    private func postRemoteNotices(_ notices: [String]) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        for text in notices {
            let content = UNMutableNotificationContent()
            content.title = "Wakito"
            content.body = text
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "remote-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func dropSelfAuthoredAlarms() {
        let profileID = snapshot.profile.id
        let cleaned = SelfAlarmCleanup.removingSelfAuthored(from: snapshot.library.alarms, profileID: profileID)
        guard cleaned.count != snapshot.library.alarms.count else { return }
        update { $0.library.alarms = cleaned }
    }

    private func retireOneTimeAlarms(rungIDs: Set<UUID> = []) {
        let result = OneTimeAlarmExpiry.partition(
            alarms: snapshot.library.alarms,
            sent: snapshot.sentAlarms,
            now: .now,
            calendar: .current,
            rungIDs: rungIDs
        )
        let changed = result.alarms != snapshot.library.alarms || result.sent != snapshot.sentAlarms
        guard changed else { return }
        update {
            $0.library.alarms = result.alarms
            $0.sentAlarms = result.sent
        }
    }

    private func presentResolved(_ id: UUID) {
        var ids = coordinator.alertingIDs() ?? []
        ids.insert(id)
        applyAlerting(ids)
    }

    private func applyAlerting(_ ids: Set<UUID>) {
        let previousID = ringingAlarmID
        let hadNap = napSession != nil
        let next = RingingOverlay.apply(
            alerting: ids,
            state: RingingOverlayState(ringingID: ringingAlarmID, held: heldRingingAlarm, nap: napSession),
            now: .now,
            libraryAlarm: { self.snapshot.library.alarm($0) },
            calendarAlarm: { id in
                self.snapshot.calendarAlarms.first { $0.id == id }?
                    .alarmForScheduling(now: .now, calendar: .current)
            }
        )
        let started = next.ringingID != nil && next.ringingID != previousID
        ringingAlarmID = next.presentedAlarm(
            libraryAlarm: { self.snapshot.library.alarm($0) },
            calendarAlarm: { id in
                self.snapshot.calendarAlarms.first { $0.id == id }?
                    .alarmForScheduling(now: .now, calendar: .current)
            }
        ) == nil ? nil : next.ringingID
        heldRingingAlarm = ringingAlarmID == nil ? nil : next.held
        if hadNap, next.nap == nil {
            clearNapSession()
        }
        guard started, let id = ringingAlarmID else { return }
        noteRemoteAlarmFired(id)
        retireOneTimeAlarms(rungIDs: [id])
        retireCalendarAlarms(rungIDs: [id])
    }

    private func retireCalendarAlarms(rungIDs: Set<UUID> = []) {
        let kept = CalendarFire.keeping(snapshot.calendarAlarms, now: .now, calendar: .current, rungIDs: rungIDs)
        guard kept != snapshot.calendarAlarms else { return }
        update { $0.calendarAlarms = kept }
    }

    private func reschedule(requestAccess: Bool) async {
        guard !suppressPermissionBanner else { return }
        if requestAccess {
            authorization = await coordinator.requestAccess()
        } else {
            authorization = coordinator.accessState()
        }
        let listed = CollaborationPause.alarmsForSync(
            snapshot.library.alarms,
            profileID: snapshot.profile.id,
            grants: snapshot.permissions.grants
        )
        let calendar = CalendarFire.scheduled(snapshot.calendarAlarms, now: .now, calendar: .current)
        if let failure = await coordinator.sync(
            alarms: listed + calendar,
            customSounds: snapshot.customSounds
        ) {
            scheduleFailure = String(format: String(localized: "settings.systemAlarm.failed"), failure)
        } else {
            scheduleFailure = nil
        }
    }

    func noteRemoteAlarmFired(_ id: UUID, at date: Date = .now) {
        guard let alarm = snapshot.library.alarm(id),
              case let .remote(senderID, _, commandID) = alarm.origin else { return }
        guard !snapshot.wakeTracking.contains(where: { $0.alarmID == id }) else { return }
        update {
            $0.wakeTracking.append(WakeTracking(
                alarmID: id,
                commandID: commandID,
                senderID: senderID,
                firedAt: date,
                snoozeCount: 0,
                dismissedAt: nil,
                reported: nil
            ))
        }
        Task { await publishDueWakeReports() }
    }

    func noteRemoteAlarmSnoozed(_ id: UUID) {
        guard snapshot.library.alarm(id)?.origin.isFromSomeoneElse == true else { return }
        update {
            guard let index = $0.wakeTracking.firstIndex(where: { $0.alarmID == id }) else { return }
            $0.wakeTracking[index].snoozeCount += 1
        }
        Task { await publishDueWakeReports() }
    }

    func noteRemoteAlarmDismissed(_ id: UUID, at date: Date = .now) {
        guard let alarm = snapshot.library.alarm(id),
              case let .remote(senderID, _, commandID) = alarm.origin else { return }
        update {
            if let index = $0.wakeTracking.firstIndex(where: { $0.alarmID == id }) {
                $0.wakeTracking[index].dismissedAt = date
            } else {
                $0.wakeTracking.append(WakeTracking(
                    alarmID: id,
                    commandID: commandID,
                    senderID: senderID,
                    firedAt: date,
                    snoozeCount: 0,
                    dismissedAt: date,
                    reported: nil
                ))
            }
        }
        Task { await publishDueWakeReports() }
    }

    private func publishDueWakeReports(now: Date = .now) async {
        if publishingWake {
            wakePublishAgain = true
            return
        }
        publishingWake = true
        defer {
            publishingWake = false
            if wakePublishAgain {
                wakePublishAgain = false
                Task { await publishDueWakeReports() }
            }
        }
        for tracking in snapshot.wakeTracking {
            let outcome = WakeReportPolicy.outcome(
                firedAt: tracking.firedAt,
                now: now,
                snoozeCount: tracking.snoozeCount,
                dismissedAt: tracking.dismissedAt
            )
            switch outcome {
            case .pending:
                continue
            case let .up(at):
                guard tracking.reported != .up else { continue }
                await sendWakeReport(tracking, status: .up, at: at)
            case .asleep:
                guard tracking.reported == nil else { continue }
                await sendWakeReport(tracking, status: .asleep, at: now)
            }
        }
        scheduleWakeCheck(now: now)
    }

    private func sendWakeReport(_ tracking: WakeTracking, status: WakeStatusKind, at date: Date) async {
        let name = await identityForSharing()?.displayName ?? snapshot.profile.displayName
        let report = WakeReport(
            id: UUID(),
            commandID: tracking.commandID,
            alarmID: tracking.alarmID,
            reporterID: snapshot.profile.id,
            reporterName: name,
            status: status,
            at: date
        )
        if let cloudKit {
            guard let grant = snapshot.permissions.grants.first(where: {
                $0.state == .active && $0.owner.id == tracking.senderID && $0.grantee?.id == snapshot.profile.id && $0.cloudKitRootRecordName != nil
            }) else { return }
            do {
                try await cloudKit.appendWakeReport(report, on: grant)
            } catch {
                unreachableGrantIDs.insert(grant.id)
                return
            }
        }
        update {
            guard let index = $0.wakeTracking.firstIndex(where: { $0.alarmID == tracking.alarmID }) else { return }
            $0.wakeTracking[index].reported = status
        }
    }

    private func scheduleWakeCheck(now: Date = .now) {
        wakeCheck?.cancel()
        let deadlines = snapshot.wakeTracking.compactMap { tracking -> Date? in
            guard tracking.reported == nil, tracking.dismissedAt == nil else { return nil }
            return tracking.firedAt.addingTimeInterval(WakeReportPolicy.asleepDelay)
        }
        guard let next = deadlines.min() else { return }
        let remaining = next.timeIntervalSince(now)
        let delay = remaining > 0 ? remaining : 60
        wakeCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.publishDueWakeReports()
        }
    }

    private func restoreOwnName() {
        if ownNames.load().isEmpty, let legacy = PersonName.nonempty(snapshot.profile.displayName) {
            ownNames.save(legacy)
        }
        guard let stored = PersonName.nonempty(ownNames.load()), stored != snapshot.profile.displayName else { return }
        snapshot.profile.displayName = stored
        if !suppressPermissionBanner {
            store.save(snapshot)
        }
    }

    /// Twoje imię when it is saved, otherwise the iCloud name. Nil when both are empty.
    private func identityForSharing() async -> Participant? {
        if let entered = PersonName.nonempty(ownNames.load()) {
            return Participant(id: snapshot.profile.id, displayName: entered)
        }
        let cloud = await cloudKit?.currentUserName()
        guard let name = PersonName.ownName(entered: nil, cloud: cloud) else { return nil }
        return Participant(id: snapshot.profile.id, displayName: name)
    }

    private func continueHeldAcceptIfNeeded() async {
        guard await identityForSharing() != nil else { return }
        if let metadata = heldShare {
            heldShare = nil
            await acceptCloudShare(metadata)
        } else if let url = heldURL {
            heldURL = nil
            await acceptShareLink(url)
        }
    }

    private func createReturnShareIfNeeded(for grant: ShareGrant) async throws {
        guard let cloudKit else { return }
        let existing = snapshot.permissions.grants
        guard MutualInvite.shouldCreateReturnShare(accepted: grant, profileID: snapshot.profile.id, existing: existing) else {
            return
        }
        guard let me = await identityForSharing() else { return }
        shareStatus = String(localized: "sharing.linking")
        var draft = ShareGrant(
            id: UUID(),
            inviteCode: "",
            secret: UUID().uuidString,
            owner: Participant(id: me.id, displayName: me.displayName),
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: nil,
            cloudKitZoneName: nil,
            cloudKitOwnerName: nil
        )
        draft.inviteeName = PersonName.nonempty(grant.owner.displayName)
        draft.reciprocal = true
        draft.reciprocalForGrantID = grant.id
        let (shared, _) = try await cloudKit.createShare(for: draft)
        update { $0.permissions.replace(shared) }
        guard let url = InviteLinkPolicy.url(from: shared.inviteCode) else { return }
        try await cloudKit.publishReturnInvite(url, on: grant)
        var published = grant
        published.returnInviteURL = url.absoluteString
        update { $0.permissions.replace(published) }
    }

    private func publishMissingReturnLinks() async {
        guard let cloudKit else { return }
        let me = snapshot.profile.id
        for back in snapshot.permissions.grants where back.reciprocal == true && back.owner.id == me && back.state != .revoked {
            guard let url = InviteLinkPolicy.url(from: back.inviteCode),
                  let originalID = back.reciprocalForGrantID,
                  var original = snapshot.permissions.grant(id: originalID),
                  InviteLinkPolicy.url(from: original.returnInviteURL ?? "") == nil else { continue }
            do {
                try await cloudKit.publishReturnInvite(url, on: original)
                original.returnInviteURL = url.absoluteString
                unreachableGrantIDs.remove(original.id)
                update { $0.permissions.replace(original) }
            } catch {
                unreachableGrantIDs.insert(original.id)
            }
        }
    }

    private func acceptReturnInvitesIfNeeded() async {
        guard !acceptingReturn, let cloudKit else { return }
        guard let url = MutualInvite.returnURLToAccept(in: snapshot.permissions.grants, profileID: snapshot.profile.id) else {
            return
        }
        guard let me = await identityForSharing() else { return }
        acceptingReturn = true
        defer { acceptingReturn = false }
        let previousStatus = shareStatus
        shareStatus = String(localized: "sharing.linking")
        defer { shareStatus = previousStatus }
        do {
            let grant = try await AsyncDeadline.run(seconds: 30) {
                try await cloudKit.accept(url: url, grantee: me)
            }
            update { $0.permissions.replace(grant) }
            grantsToSeal.insert(grant.id)
        } catch {
            // The contact stays on the waiting note until the return share can be accepted.
        }
    }

    private func pushOwnName() async {
        guard let cloudKit, let name = PersonName.nonempty(ownNames.load()) else { return }
        for grant in snapshot.permissions.grants where grant.cloudKitRootRecordName != nil && grant.state != .revoked {
            let asOwner = grant.owner.id == snapshot.profile.id
            guard asOwner || grant.grantee?.id == snapshot.profile.id else { continue }
            try? await cloudKit.updateOwnName(name, on: grant, asOwner: asOwner)
        }
    }

    private func update(_ body: (inout LibrarySnapshot) -> Void) {
        var copy = snapshot
        body(&copy)
        snapshot = copy
        if !suppressPermissionBanner {
            store.save(copy)
        }
    }

    private func updateInvite() -> ShareGrant {
        var created: ShareGrant?
        update { snapshot in
            created = snapshot.permissions.createInvite(
                owner: snapshot.profile,
                now: .now,
                code: InviteCode.make(),
                secret: UUID().uuidString
            )
        }
        return created ?? snapshot.permissions.grants.last!
    }
}
