import CloudKit
import Foundation
import Observation
import UIKit
import UserNotifications

enum AppTab: Hashable {
    case alarms
    case sharing
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
    var ringingAlarmID: UUID?
    var showGroups = false
    var selectedTab: AppTab = .alarms
    var authorization: AlarmAccessState = .unknown
    var notificationAllowed = false
    var scheduleFailure: String?
    var lastError: String?
    var shareURL: URL?
    var shareMessage = ""
    var shareStatus: String?
    var friendDraftName = ""
    var remoteLabel = ""
    var remoteHour = 7
    var remoteMinute = 0
    let suppressPermissionBanner: Bool

    private let store: LibraryStore
    private let coordinator: AlarmCoordinator
    private let cloudKit: CloudKitSharingClient?
    private var started = false

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

    var ringingAlarm: Alarm? {
        guard let ringingAlarmID else { return nil }
        return snapshot.library.alarm(ringingAlarmID)
    }

    init(store: LibraryStore? = nil, cloudKit explicitCloudKit: CloudKitSharingClient? = nil, screenshot: Bool? = nil) {
        let store = store ?? LibraryStore(url: LibraryStore.applicationSupportURL())
        self.store = store
        let screenshot = screenshot ?? LaunchConfiguration.seedDemo
        suppressPermissionBanner = screenshot
        let loaded = store.load() ?? LibrarySnapshot.empty(
            profile: Participant(id: UUID(), displayName: "")
        )
        snapshot = screenshot ? DemoData.make() : loaded
        coordinator = AlarmCoordinator()
        if let explicitCloudKit {
            cloudKit = explicitCloudKit
        } else if AppConfig.activatesCloudKit && !screenshot {
            cloudKit = CloudKitSharingClient(containerID: AppConfig.cloudKitContainerID)
        } else {
            cloudKit = nil
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
            editor = snapshot.library.alarms.first.map { AlarmDraft(alarm: $0) } ?? .makeNew()
        case .groups:
            showGroups = true
        case .sharing:
            selectedTab = .sharing
        case .ringing:
            ringingAlarmID = snapshot.library.alarms.first?.id
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
        authorization = coordinator.accessState()
        notificationAllowed = await coordinator.notificationStatus() == .authorized
        await reschedule(requestAccess: false)
        if let handoff = LaunchHandoff.consume() {
            ringingAlarmID = handoff.alarmID
            await UIApplication.shared.open(handoff.songURL)
        }
        Task { await refreshRemote() }
        await coordinator.observeAlerting { [weak self] id in
            self?.ringingAlarmID = id
        }
    }

    func allowAlarms() async {
        authorization = await coordinator.requestAccess()
        notificationAllowed = await coordinator.notificationStatus() == .authorized
        await reschedule(requestAccess: false)
    }

    func addAlarm() {
        editor = .makeNew()
    }

    func edit(_ alarm: Alarm) {
        editor = AlarmDraft(alarm: alarm)
    }

    func save(draft: AlarmDraft) {
        guard let alarm = draft.makeAlarm() else {
            lastError = String(localized: "song.invalid")
            return
        }
        update { $0.library.upsert(alarm) }
        editor = nil
        Task { await reschedule(requestAccess: true) }
    }

    func delete(alarmID: UUID) {
        update { $0.library.delete(id: alarmID) }
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update { $0.profile.displayName = trimmed }
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
            lastError = String(localized: "sound.unreadable")
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
                snoozeMinutes: 9,
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
            lastError = String(localized: "error.generic")
        }
    }

    func createCloudInvite() async {
        guard let cloudKit else {
            lastError = RemoteBackendError.notConfigured.errorDescription
            return
        }
        let owner = snapshot.profile
        let draft = ShareGrant(
            id: UUID(),
            inviteCode: "",
            secret: UUID().uuidString,
            owner: owner,
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: nil,
            cloudKitZoneName: nil,
            cloudKitOwnerName: nil
        )
        do {
            let (shared, _) = try await cloudKit.createShare(for: draft)
            update {
                $0.permissions.removeUnsharedInvites()
                $0.permissions.replace(shared)
            }
            presentInvite(shared.inviteCode)
        } catch {
            update { $0.permissions.removeUnsharedInvites() }
            lastError = CloudKitErrorText.message(for: error)
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
        await acceptInvite {
            guard let cloudKit else { throw RemoteBackendError.notConfigured }
            return try await AsyncDeadline.run(seconds: 30) {
                try await cloudKit.accept(metadata: metadata, grantee: self.namedProfile)
            }
        }
    }

    func acceptShareLink(_ url: URL) async {
        guard InviteLinkPolicy.isCloudShare(url) else {
            lastError = String(localized: "sharing.badLink")
            return
        }
        await acceptInvite {
            guard let cloudKit else { throw RemoteBackendError.notConfigured }
            return try await AsyncDeadline.run(seconds: 30) {
                try await cloudKit.accept(url: url, grantee: self.namedProfile)
            }
        }
    }

    private var namedProfile: Participant {
        var person = snapshot.profile
        if person.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            person.displayName = String(localized: "sharing.someone")
        }
        return person
    }

    private func acceptInvite(_ work: () async throws -> ShareGrant) async {
        shareStatus = String(localized: "sharing.accepting")
        selectedTab = .sharing
        defer { shareStatus = nil }
        do {
            let grant = try await work()
            update { $0.permissions.replace(grant) }
            await refreshRemote()
        } catch is AsyncDeadlineError {
            lastError = String(localized: "sharing.timedOut")
        } catch is CancellationError {
            return
        } catch {
            lastError = CloudKitErrorText.message(for: error)
        }
    }

    func refreshRemote() async {
        guard let cloudKit else { return }
        let grants = snapshot.permissions.grants.filter { $0.cloudKitRootRecordName != nil && $0.state != .revoked }
        var refreshFailure: String?
        for grant in grants {
            let asOwner = grant.owner.id == snapshot.profile.id
            let updatedGrant: ShareGrant
            let commands: [RemoteAlarmCommand]
            do {
                (updatedGrant, commands) = try await cloudKit.refresh(grant, asOwner: asOwner)
            } catch {
                refreshFailure = CloudKitErrorText.message(for: error)
                continue
            }
            let updated = updatedGrant
            var library = snapshot.library
            var applied = snapshot.appliedCommandIDs
            var notices: [String] = []
            for command in commands where !applied.contains(command.id) {
                if updated.state == .active {
                    if (command.action == .upsert || command.action == .triggerNow), let alarm = command.alarm {
                        let sender = updated.grantee?.displayName ?? ""
                        notices.append(RemoteAlarmNotice.text(sender: sender, schedule: alarm.schedule))
                    }
                    try? RemoteCommandApplier.apply(command: command, grant: updated, library: &library)
                }
                applied.append(command.id)
            }
            if !notices.isEmpty {
                Task { await postRemoteNotices(notices) }
            }
            update {
                $0.permissions.replace(updated)
                $0.library = library
                $0.appliedCommandIDs = applied
            }
        }
        if let refreshFailure {
            lastError = refreshFailure
        }
        await reschedule(requestAccess: false)
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

    func sendToPhone(grantID: UUID, immediately: Bool) async {
        guard let grant = snapshot.permissions.grant(id: grantID), let cloudKit else { return }
        let alarm = Alarm(
            id: UUID(),
            schedule: immediately
                ? .oneShot(fireAt: Date().addingTimeInterval(3))
                : .wallClock(hour: remoteHour, minute: remoteMinute, repeatDays: []),
            label: remoteLabel,
            soundID: SoundCatalog.defaultID,
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let command = RemoteAlarmCommand(
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
        do {
            _ = try snapshot.permissions.authorize(sender: snapshot.profile.id, recipient: grant.owner.id)
            try await cloudKit.append(command: command, grant: grant, asOwner: false)
            if !immediately {
                let sent = SentAlarm(
                    alarm: alarm,
                    recipientID: grant.owner.id,
                    recipientName: grant.owner.displayName,
                    sentAt: command.createdAt,
                    commandID: command.id
                )
                update { $0.sentAlarms.append(sent) }
            }
        } catch {
            lastError = error.localizedDescription
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
            lastError = error.localizedDescription
        }
    }

    func stopRinging() async {
        guard let id = ringingAlarmID else { return }
        await coordinator.stop(id: id)
        ringingAlarmID = nil
    }

    func snoozeRinging() async {
        guard let alarm = ringingAlarm else { return }
        await coordinator.snooze(alarm, customSounds: snapshot.customSounds)
        ringingAlarmID = nil
    }

    func playSong(of alarm: Alarm) async {
        guard let link = alarm.songLink else { return }
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
            ringingAlarmID = id
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
            if let alarmID { ringingAlarmID = alarmID }
            if let song = info["song"] as? String, let url = URL(string: song) {
                await coordinator.stop(id: alarmID ?? UUID())
                await UIApplication.shared.open(url)
            }
        case NotificationAction.snooze:
            if let alarmID, let alarm = snapshot.library.alarm(alarmID) {
                await coordinator.snooze(alarm, customSounds: snapshot.customSounds)
            }
        case NotificationAction.stop, UNNotificationDismissActionIdentifier:
            if let alarmID { await coordinator.stop(id: alarmID) }
        default:
            if let alarmID { ringingAlarmID = alarmID }
        }
    }

    func dismissRinging() {
        ringingAlarmID = nil
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

    private func reschedule(requestAccess: Bool) async {
        guard !suppressPermissionBanner else { return }
        if requestAccess {
            authorization = await coordinator.requestAccess()
        } else {
            authorization = coordinator.accessState()
        }
        if let failure = await coordinator.sync(
            alarms: snapshot.library.alarms,
            customSounds: snapshot.customSounds
        ) {
            scheduleFailure = String(format: String(localized: "settings.systemAlarm.failed"), failure)
        } else {
            scheduleFailure = nil
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
