import Foundation

struct Participant: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var displayName: String
}

enum GrantState: String, Codable, Equatable {
    case pending
    case active
    case revoked
}

struct ShareGrant: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var inviteCode: String
    var secret: String
    var owner: Participant
    var grantee: Participant?
    var state: GrantState
    var createdAt: Date
    var cloudKitRootRecordName: String?
    var cloudKitZoneName: String?
    var cloudKitOwnerName: String?
    var cloudKitShareRecordName: String? = nil
    /// Name the inviter typed for the other person. This stays the inviter's label.
    var inviteeName: String? = nil
    /// Share URL the invitee publishes so the inviter can wake them too.
    var returnInviteURL: String? = nil
    /// True on the share created automatically after accepting someone else's invite.
    var reciprocal: Bool? = nil
    /// The accepted grant this reciprocal share answers.
    var reciprocalForGrantID: UUID? = nil
    /// Wake-up reports the invited person wrote back onto this phone's share.
    var wakeReports: [WakeReport]? = nil

    func allows(sender: UUID, recipient: UUID) -> Bool {
        state == .active && grantee?.id == sender && owner.id == recipient
    }
}

enum PermissionError: Error, Equatable {
    case inviteNotFound
    case notPending
    case cannotAcceptOwnInvite
    case notAllowed
    case grantNotFound
}

struct PermissionCenter: Codable, Equatable {
    var grants: [ShareGrant] = []

    func grant(id: UUID) -> ShareGrant? {
        grants.first { $0.id == id }
    }

    func grant(code: String) -> ShareGrant? {
        grants.first { $0.inviteCode == code }
    }

    @discardableResult
    mutating func createInvite(
        owner: Participant,
        now: Date,
        code: String,
        secret: String
    ) -> ShareGrant {
        let grant = ShareGrant(
            id: UUID(),
            inviteCode: code,
            secret: secret,
            owner: owner,
            grantee: nil,
            state: .pending,
            createdAt: now,
            cloudKitRootRecordName: nil,
            cloudKitZoneName: nil,
            cloudKitOwnerName: nil
        )
        grants.append(grant)
        return grant
    }

    @discardableResult
    mutating func accept(code: String, grantee: Participant, now: Date) throws -> ShareGrant {
        guard let index = grants.firstIndex(where: { $0.inviteCode == code }) else {
            throw PermissionError.inviteNotFound
        }
        guard grants[index].state == .pending else { throw PermissionError.notPending }
        guard grants[index].owner.id != grantee.id else { throw PermissionError.cannotAcceptOwnInvite }
        grants[index].grantee = grantee
        grants[index].state = .active
        return grants[index]
    }

    @discardableResult
    mutating func revoke(grantID: UUID, by actor: UUID) throws -> ShareGrant {
        guard let index = grants.firstIndex(where: { $0.id == grantID }) else {
            throw PermissionError.grantNotFound
        }
        let grant = grants[index]
        let allowed = grant.owner.id == actor || grant.grantee?.id == actor
        guard allowed else { throw PermissionError.notAllowed }
        guard grant.state != .revoked else { return grant }
        grants[index].state = .revoked
        return grants[index]
    }

    func authorize(sender: UUID, recipient: UUID) throws -> ShareGrant {
        guard let grant = grants.first(where: { $0.allows(sender: sender, recipient: recipient) }) else {
            throw PermissionError.notAllowed
        }
        return grant
    }

    mutating func replace(_ grant: ShareGrant) {
        if let index = grants.firstIndex(where: { $0.id == grant.id }) {
            grants[index] = grant
        } else {
            grants.append(grant)
        }
    }

    /// Drops invites that never received an iCloud share link.
    mutating func removeUnsharedInvites() {
        grants.removeAll { $0.state == .pending && $0.cloudKitRootRecordName == nil }
    }
}

enum InviteLinkPolicy {
    /// A pending invite can be opened by anyone who has the link. After the first
    /// person accepts, or after the owner revokes it, the link stops accepting new people.
    static func allowsAnyoneWithLink(grantState: GrantState) -> Bool {
        grantState == .pending
    }

    static func url(from inviteCode: String) -> URL? {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    static func isCloudShare(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        let host = url.host?.lowercased() ?? ""
        return host == "icloud.com" || host.hasSuffix(".icloud.com")
    }

    /// Pulls an iCloud share link out of a message that also contains other words.
    static func cloudShareURL(from text: String) -> URL? {
        let pieces = text.split { $0.isWhitespace || $0 == "\n" || $0 == "\r" }
        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'“”"))
            guard let url = URL(string: String(trimmed)), isCloudShare(url) else { continue }
            return url
        }
        return nil
    }
}

enum ShareRoster {
    /// People who accepted an invite to this phone. They can set alarms here.
    static func canSetAlarmsHere(profileID: UUID, grants: [ShareGrant]) -> [ShareGrant] {
        grants.filter { $0.owner.id == profileID && $0.state != .revoked }
    }

    /// Phones this person can set, because they accepted that phone's invite.
    static func phonesICanSet(profileID: UUID, grants: [ShareGrant]) -> [ShareGrant] {
        grants.filter { $0.grantee?.id == profileID && $0.state == .active }
    }
}

enum PersonName {
    static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func formatted(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        return nonempty(PersonNameComponentsFormatter().string(from: components))
    }

    /// Name typed in Twoje imię, or the iCloud name when that field is empty.
    static func ownName(entered: String?, cloud: String?) -> String? {
        nonempty(entered) ?? nonempty(cloud)
    }

    /// Inviter-side label. The name typed while inviting wins over the name they chose.
    static func inviterLabel(inviteeName: String?, theirName: String?, generic: String) -> String {
        nonempty(inviteeName) ?? nonempty(theirName) ?? generic
    }

    static func listLabel(for grant: ShareGrant, profileID: UUID, grants: [ShareGrant], generic: String) -> String {
        if grant.owner.id == profileID {
            if grant.reciprocal == true {
                // The other person did not get a name typed on this share. Prefer the name they chose.
                return inviterLabel(inviteeName: grant.grantee?.displayName, theirName: grant.inviteeName, generic: generic)
            }
            return inviterLabel(inviteeName: grant.inviteeName, theirName: grant.grantee?.displayName, generic: generic)
        }
        if let mine = grants.first(where: { owned in
            guard owned.owner.id == profileID, owned.reciprocal != true else { return false }
            if owned.grantee?.id == grant.owner.id { return true }
            if let url = owned.returnInviteURL, url == grant.inviteCode { return true }
            return false
        }), let label = nonempty(mine.inviteeName) {
            return label
        }
        return nonempty(grant.owner.displayName) ?? generic
    }

    /// Sender name on the phone that rings: their own name, then the inviter's label.
    static func senderName(grant: ShareGrant) -> String {
        nonempty(grant.grantee?.displayName) ?? nonempty(grant.inviteeName) ?? ""
    }
}

enum MutualInvite {
    static func shouldCreateReturnShare(accepted: ShareGrant, profileID: UUID, existing: [ShareGrant]) -> Bool {
        guard accepted.grantee?.id == profileID, accepted.reciprocal != true else { return false }
        if let url = accepted.returnInviteURL, InviteLinkPolicy.url(from: url) != nil { return false }
        if existing.contains(where: { $0.reciprocalForGrantID == accepted.id }) { return false }
        return true
    }

    static func returnURLToAccept(in grants: [ShareGrant], profileID: UUID) -> URL? {
        for grant in grants where grant.owner.id == profileID && grant.reciprocal != true && grant.state != .revoked {
            guard let raw = grant.returnInviteURL,
                  let url = InviteLinkPolicy.url(from: raw),
                  InviteLinkPolicy.isCloudShare(url) else { continue }
            if grants.contains(where: { $0.inviteCode == url.absoluteString }) { continue }
            return url
        }
        return nil
    }
}

enum ShareChangeNotice {
    /// The invite just became active. The name is the inviter's label, then the joiner's own name.
    static func joinedName(previous: ShareGrant, updated: ShareGrant) -> String? {
        guard previous.state != .active, updated.state == .active else { return nil }
        return PersonName.nonempty(updated.inviteeName) ?? PersonName.nonempty(updated.grantee?.displayName)
    }
}

enum GrantRefreshMerge {
    /// Keeps local labels when a CloudKit fetch omits them. An empty fetched name does not clear them.
    static func merging(_ updated: ShareGrant, with local: ShareGrant) -> ShareGrant {
        var merged = updated
        merged.inviteCode = local.inviteCode
        if merged.cloudKitRootRecordName == nil { merged.cloudKitRootRecordName = local.cloudKitRootRecordName }
        if merged.cloudKitZoneName == nil { merged.cloudKitZoneName = local.cloudKitZoneName }
        if merged.cloudKitOwnerName == nil { merged.cloudKitOwnerName = local.cloudKitOwnerName }
        merged.cloudKitShareRecordName = merged.cloudKitShareRecordName ?? local.cloudKitShareRecordName
        if PersonName.nonempty(merged.inviteeName) == nil { merged.inviteeName = local.inviteeName }
        if InviteLinkPolicy.url(from: merged.returnInviteURL ?? "") == nil,
           InviteLinkPolicy.url(from: local.returnInviteURL ?? "") != nil {
            merged.returnInviteURL = local.returnInviteURL
        }
        if merged.reciprocal == nil { merged.reciprocal = local.reciprocal }
        if merged.reciprocalForGrantID == nil { merged.reciprocalForGrantID = local.reciprocalForGrantID }
        if merged.wakeReports == nil { merged.wakeReports = local.wakeReports }
        return merged
    }

    /// Applies the saved own name. An empty value leaves the grant unchanged.
    static func applyingOwnName(_ name: String?, to grant: ShareGrant, profileID: UUID) -> ShareGrant {
        guard let name = PersonName.nonempty(name) else { return grant }
        var copy = grant
        if copy.owner.id == profileID { copy.owner.displayName = name }
        if copy.grantee?.id == profileID { copy.grantee?.displayName = name }
        return copy
    }
}

enum InviteCode {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func make(length: Int = 8, randomByte: () -> UInt8 = { UInt8.random(in: 0...255) }) -> String {
        String((0..<length).map { _ in alphabet[Int(randomByte()) % alphabet.count] })
    }
}

enum WakeStatusKind: String, Codable, Equatable {
    case up
    case asleep
}

struct WakeReport: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var commandID: UUID
    var alarmID: UUID
    var reporterID: UUID
    var reporterName: String
    var status: WakeStatusKind
    var at: Date
}

enum WakeReportPolicy {
    static let asleepDelay: TimeInterval = 10 * 60
    /// A second snooze, without a dismissal, counts as still asleep.
    static let repeatedSnoozes = 2

    enum Outcome: Equatable {
        case up(Date)
        case asleep
        case pending
    }

    static func outcome(firedAt: Date, now: Date, snoozeCount: Int, dismissedAt: Date?) -> Outcome {
        if let dismissedAt { return .up(dismissedAt) }
        if snoozeCount >= repeatedSnoozes { return .asleep }
        if now.timeIntervalSince(firedAt) >= asleepDelay { return .asleep }
        return .pending
    }
}

enum WakeStatusNotice {
    static func text(name: String, status: WakeStatusKind, at: Date, calendar: Calendar = .current) -> String {
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = who.isEmpty ? String(localized: "sharing.someone") : who
        switch status {
        case .up:
            let parts = ClockFormat.parts(
                hour: calendar.component(.hour, from: at),
                minute: calendar.component(.minute, from: at),
                locale: .current,
                timeZone: calendar.timeZone
            )
            let time = parts.period.isEmpty ? parts.time : "\(parts.time) \(parts.period)"
            return String(format: String(localized: "sharing.wake.up"), person, time)
        case .asleep:
            return String(format: String(localized: "sharing.wake.asleep"), person)
        }
    }
}

enum WakeStatusApply {
    struct Change: Equatable {
        var commandID: UUID
        var status: WakeStatusKind
        var at: Date
        var notice: String
    }

    /// An "up" report replaces "asleep". A later "asleep" does not replace "up".
    static func changes(
        reports: [WakeReport],
        sent: [SentAlarm],
        name: (WakeReport) -> String,
        calendar: Calendar = .current
    ) -> [Change] {
        let known = Set(sent.map(\.commandID))
        var current: [UUID: WakeStatusKind] = [:]
        for alarm in sent {
            if let status = alarm.wakeStatus { current[alarm.commandID] = status }
        }
        var changes: [Change] = []
        for report in reports where known.contains(report.commandID) {
            let existing = current[report.commandID]
            if existing == .up { continue }
            if existing == report.status { continue }
            current[report.commandID] = report.status
            changes.append(Change(
                commandID: report.commandID,
                status: report.status,
                at: report.at,
                notice: WakeStatusNotice.text(name: name(report), status: report.status, at: report.at, calendar: calendar)
            ))
        }
        return changes
    }
}

enum FriendGroupRoster {
    struct Row: Equatable, Identifiable {
        var id: UUID { commandID }
        var commandID: UUID
        var name: String
        var status: WakeStatusKind?
        var statusAt: Date?
    }

    struct Section: Equatable, Identifiable {
        var id: String
        var title: String?
        var rows: [Row]
    }

    /// Groups sent alarms that share a friend group. Ungrouped alarms stay as their own rows.
    static func sections(from sent: [SentAlarm]) -> [Section] {
        let sorted = sent.sorted { $0.sentAt > $1.sentAt }
        var sections: [Section] = []
        var seenGroups: [UUID] = []
        for alarm in sorted {
            guard let groupID = alarm.friendGroupID else {
                sections.append(Section(id: alarm.commandID.uuidString, title: nil, rows: [row(alarm)]))
                continue
            }
            if let index = sections.firstIndex(where: { $0.id == groupID.uuidString }) {
                sections[index].rows.append(row(alarm))
            } else if !seenGroups.contains(groupID) {
                seenGroups.append(groupID)
                sections.append(Section(
                    id: groupID.uuidString,
                    title: alarm.friendGroupName ?? "",
                    rows: [row(alarm)]
                ))
            }
        }
        return sections
    }

    private static func row(_ alarm: SentAlarm) -> Row {
        Row(commandID: alarm.commandID, name: alarm.recipientName, status: alarm.wakeStatus, statusAt: alarm.wakeStatusAt)
    }
}

struct SharingContact: Identifiable, Equatable {
    var id: String
    var name: String
    /// The other person, once CloudKit has a participant id.
    var memberID: UUID?
    /// Grant where I can set alarms on their phone.
    var wakeGrantID: UUID?
    /// Grant I own: their invite, or the share they accepted.
    var hostedGrantID: UUID?
    var isPending: Bool
}

enum ContactRoster {
    static func contacts(profileID: UUID, grants: [ShareGrant]) -> [SharingContact] {
        var order: [String] = []
        var byKey: [String: SharingContact] = [:]
        for grant in grants where grant.state != .revoked {
            let key: String
            let memberID: UUID?
            if grant.owner.id == profileID {
                memberID = grant.grantee?.id
                key = memberID?.uuidString ?? "invite-\(grant.id.uuidString)"
            } else if grant.grantee?.id == profileID {
                memberID = grant.owner.id
                key = memberID?.uuidString ?? grant.id.uuidString
            } else {
                continue
            }
            let name = PersonName.listLabel(
                for: grant,
                profileID: profileID,
                grants: grants,
                generic: String(localized: "sharing.someone")
            )
            var contact = byKey[key] ?? SharingContact(
                id: key,
                name: name,
                memberID: memberID,
                wakeGrantID: nil,
                hostedGrantID: nil,
                isPending: false
            )
            if grant.owner.id == profileID {
                contact.hostedGrantID = grant.id
                if PersonName.nonempty(grant.inviteeName) != nil {
                    contact.name = name
                }
            } else {
                contact.wakeGrantID = grant.id
                if contact.hostedGrantID == nil {
                    contact.name = name
                }
            }
            contact.memberID = contact.memberID ?? memberID
            contact.isPending = contact.wakeGrantID == nil && grants.first { $0.id == contact.hostedGrantID }?.state == .pending
            if byKey[key] == nil { order.append(key) }
            byKey[key] = contact
        }
        return order.compactMap { byKey[$0] }
    }
}

enum RemoteCommandGate {
    struct Decision: Equatable {
        var apply: [RemoteAlarmCommand]
        var seal: [UUID]
    }

    /// Commands already stored when the connection becomes active are history.
    /// They are marked processed and never turned into alarms.
    static func partition(
        commands: [RemoteAlarmCommand],
        applied: Set<UUID>,
        sealExisting: Bool
    ) -> Decision {
        let fresh = commands.filter { !applied.contains($0.id) }
        if sealExisting {
            return Decision(apply: [], seal: fresh.map(\.id))
        }
        return Decision(apply: fresh, seal: [])
    }
}

enum RemoteAction: String, Codable, Equatable {
    case upsert
    case cancel
    case setEnabled
    case triggerNow
}

struct RemoteAlarmCommand: Codable, Equatable, Identifiable {
    var id: UUID
    var grantID: UUID
    var senderID: UUID
    var recipientID: UUID
    var action: RemoteAction
    var createdAt: Date
    var alarm: Alarm?
    var alarmID: UUID?
    var enabled: Bool?
    /// Record name of the WMVoice asset in the same zone, when this alarm has a voice message.
    var voiceRecordName: String? = nil
}

enum RemoteAlarmNotice {
    /// Visible text after a remote alarm is stored, for example "Ola ustawił Ci budzik na 6:30".
    static func text(sender: String, schedule: AlarmSchedule) -> String {
        let parts = ClockFormat.parts(
            hour: schedule.hour,
            minute: schedule.minute,
            locale: .current,
            timeZone: .current
        )
        let time = parts.period.isEmpty ? parts.time : "\(parts.time) \(parts.period)"
        let name = sender.isEmpty ? String(localized: "sharing.someone") : sender
        return String(format: String(localized: "sharing.push.scheduled"), name, time)
    }
}

enum ApplyError: Error, Equatable {
    case notAuthorized
    case missingAlarm
    case notOwnedBySender
    case invalidPayload
}

enum RemoteCommandApplier {
    static func apply(
        command: RemoteAlarmCommand,
        grant: ShareGrant,
        library: inout AlarmLibrary
    ) throws {
        guard grant.id == command.grantID,
              grant.allows(sender: command.senderID, recipient: command.recipientID) else {
            throw ApplyError.notAuthorized
        }
        let senderName = grant.grantee?.displayName ?? ""
        switch command.action {
        case .upsert, .triggerNow:
            guard var alarm = command.alarm else { throw ApplyError.invalidPayload }
            if let existing = library.alarm(alarm.id), !existing.origin.isOwned(by: command.senderID) {
                throw ApplyError.notOwnedBySender
            }
            alarm.origin = .remote(
                senderID: command.senderID,
                senderName: senderName,
                commandID: command.id
            )
            if command.action == .triggerNow {
                alarm.isEnabled = true
            }
            library.upsert(alarm)
        case .cancel:
            guard let alarmID = command.alarmID else { throw ApplyError.invalidPayload }
            guard let existing = library.alarm(alarmID) else { throw ApplyError.missingAlarm }
            guard existing.origin.isOwned(by: command.senderID) else { throw ApplyError.notOwnedBySender }
            library.delete(id: alarmID)
        case .setEnabled:
            guard let alarmID = command.alarmID, let enabled = command.enabled else {
                throw ApplyError.invalidPayload
            }
            guard let existing = library.alarm(alarmID) else { throw ApplyError.missingAlarm }
            guard existing.origin.isOwned(by: command.senderID) else { throw ApplyError.notOwnedBySender }
            library.setEnabled(enabled, alarmID: alarmID)
        }
    }
}
