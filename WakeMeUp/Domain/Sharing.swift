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
