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
            guard owned.owner.id == profileID else { return false }
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
