import CloudKit
import Foundation

enum CloudKitErrorText {
    static func message(for error: Error) -> String {
        let friendly = String(localized: "sharing.cloudError")
        return "\(friendly)\n\(detail(for: error))"
    }

    static func detail(for error: Error) -> String {
        if let backend = error as? RemoteBackendError, let text = backend.errorDescription {
            return text
        }
        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }
        var lines = ["CKError \(cloudError.code.rawValue): \(cloudError.localizedDescription)"]
        if let partial = cloudError.partialErrorsByItemID {
            for (identifier, itemError) in partial {
                lines.append("\(identifier): \(detail(for: itemError))")
            }
        }
        if let underlying = cloudError.userInfo[NSUnderlyingErrorKey] as? Error, !(underlying is CKError) {
            lines.append(underlying.localizedDescription)
        }
        return lines.joined(separator: "\n")
    }
}

enum RemoteBackendError: LocalizedError {
    case notConfigured
    case notSignedIn
    case shareURLMissing
    case missingRoot
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "CloudKit is not configured. Set CloudKitContainerID in WakeMeUpConfig.plist."
        case .notSignedIn:
            String(localized: "sharing.signIn")
        case .shareURLMissing:
            String(localized: "sharing.cloudError") + "\n" + "The saved share had no URL."
        case .missingRoot:
            "The shared alarm record is missing."
        case let .underlying(message):
            message
        }
    }
}

/// Private-database CloudKit share. The phone that rings owns the zone.
/// The invited person writes commands onto the root record. No query indexes
/// are required because every read is by record ID. A zone subscription asks
/// iOS to wake the owner when the record changes. That wake is best-effort.
final class CloudKitSharingClient {
    let container: CKContainer

    init(containerID: String) {
        container = CKContainer(identifier: containerID)
    }

    func requireAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw RemoteBackendError.notSignedIn }
    }

    func createShare(for grant: ShareGrant) async throws -> (ShareGrant, CKShare) {
        try await requireAccount()
        var grant = grant
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "WakeMeUp", ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        } catch let error as CKError where error.code == .serverRecordChanged {
            // The custom zone already exists. Shares cannot live in _defaultZone.
        }
        let rootName = "grant-\(grant.id.uuidString)"
        let rootID = CKRecord.ID(recordName: rootName, zoneID: zoneID)
        let root = CKRecord(recordType: "WMRoot", recordID: rootID)
        write(grant, commands: [], to: root)
        let share = CKShare(rootRecord: root)
        // One share per person. The link stays open until that person accepts.
        share.publicPermission = .readWrite
        share[CKShare.SystemFieldKey.title] = "Wakito" as NSString
        let (saveResults, _) = try await database.modifyRecords(saving: [root, share], deleting: [], savePolicy: .allKeys)
        var savedShare: CKShare?
        var savedRoot: CKRecord?
        var failures: [Error] = []
        for result in saveResults.values {
            switch result {
            case let .success(record):
                if let saved = record as? CKShare {
                    savedShare = saved
                } else {
                    savedRoot = record
                }
            case let .failure(error):
                failures.append(error)
            }
        }
        if let error = failures.first {
            throw error
        }
        // url is filled only on the share the server returns, not the local CKShare.
        guard let savedShare, let url = savedShare.url else {
            throw RemoteBackendError.shareURLMissing
        }
        grant.inviteCode = url.absoluteString
        grant.cloudKitRootRecordName = rootName
        grant.cloudKitZoneName = zoneID.zoneName
        grant.cloudKitOwnerName = zoneID.ownerName
        grant.cloudKitShareRecordName = savedShare.recordID.recordName
        if let savedRoot {
            try? await save(grant, commands: [], database: database, record: savedRoot)
        }
        try? await subscribe(zoneID: zoneID)
        return (grant, savedShare)
    }

    func accept(url: URL, grantee: Participant) async throws -> ShareGrant {
        try await requireAccount()
        let metadata = try await container.shareMetadata(for: url)
        return try await accept(metadata: metadata, grantee: grantee, inviteURL: url)
    }

    func accept(metadata: CKShare.Metadata, grantee: Participant) async throws -> ShareGrant {
        try await requireAccount()
        return try await accept(metadata: metadata, grantee: grantee, inviteURL: metadata.share.url)
    }

    private func accept(metadata: CKShare.Metadata, grantee: Participant, inviteURL: URL?) async throws -> ShareGrant {
        guard let rootID = metadata.hierarchicalRootRecordID else {
            throw RemoteBackendError.missingRoot
        }
        do {
            _ = try await container.accept([metadata])
        } catch {
            // Opening the same link twice still has to record who joined.
            guard (try? await container.sharedCloudDatabase.record(for: rootID)) != nil else {
                throw error
            }
        }
        let root = try await container.sharedCloudDatabase.record(for: rootID)
        guard var grant = readGrant(from: root) else { throw RemoteBackendError.missingRoot }
        grant.grantee = grantee
        grant.state = .active
        grant.cloudKitRootRecordName = rootID.recordName
        grant.cloudKitZoneName = rootID.zoneID.zoneName
        grant.cloudKitOwnerName = rootID.zoneID.ownerName
        grant.inviteCode = inviteURL?.absoluteString ?? grant.inviteCode
        try await save(grant, commands: readCommands(from: root), database: container.sharedCloudDatabase, record: root)
        return grant
    }

    func refresh(_ grant: ShareGrant, asOwner: Bool) async throws -> (ShareGrant, [RemoteAlarmCommand]) {
        try await requireAccount()
        let database = asOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let root = try await database.record(for: try recordID(for: grant))
        guard var updated = readGrant(from: root) else { throw RemoteBackendError.missingRoot }
        updated.cloudKitRootRecordName = grant.cloudKitRootRecordName
        updated.cloudKitZoneName = grant.cloudKitZoneName
        updated.cloudKitOwnerName = grant.cloudKitOwnerName
        updated.inviteCode = grant.inviteCode
        updated.cloudKitShareRecordName = updated.cloudKitShareRecordName ?? grant.cloudKitShareRecordName
        if asOwner, !InviteLinkPolicy.allowsAnyoneWithLink(grantState: updated.state) {
            await closePublicLink(on: root, grant: updated, database: database)
        }
        return (updated, readCommands(from: root))
    }

    func append(command: RemoteAlarmCommand, grant: ShareGrant, asOwner: Bool) async throws {
        try await requireAccount()
        let database = asOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        try await mutate(grant: grant, database: database) { commands in
            var commands = commands
            commands.removeAll { $0.id == command.id }
            commands.append(command)
            return commands
        }
    }

    func revoke(_ grant: ShareGrant) async throws {
        try await requireAccount()
        var revoked = grant
        revoked.state = .revoked
        let root = try await container.privateCloudDatabase.record(for: try recordID(for: grant))
        try await save(revoked, commands: readCommands(from: root), database: container.privateCloudDatabase, record: root)
        await closePublicLink(on: root, grant: revoked, database: container.privateCloudDatabase)
    }

    /// Stops new people from joining. People who already accepted keep their access.
    private func closePublicLink(on root: CKRecord, grant: ShareGrant, database: CKDatabase) async {
        let shareID: CKRecord.ID
        if let reference = root.share {
            shareID = reference.recordID
        } else if let name = grant.cloudKitShareRecordName {
            shareID = CKRecord.ID(recordName: name, zoneID: root.recordID.zoneID)
        } else {
            return
        }
        do {
            guard let share = try await database.record(for: shareID) as? CKShare else { return }
            guard share.publicPermission != .none else { return }
            share.publicPermission = .none
            _ = try await database.save(share)
        } catch {
            // The grant state is already saved. The next refresh tries again while it is active.
        }
    }

    private func subscribe(zoneID: CKRecordZone.ID) async throws {
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "wakemeup-zone")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.alertLocalizationKey = "sharing.push.generic"
        info.soundName = "default"
        subscription.notificationInfo = info
        try? await container.privateCloudDatabase.deleteSubscription(withID: subscription.subscriptionID)
        _ = try await container.privateCloudDatabase.save(subscription)
    }

    private func mutate(
        grant: ShareGrant,
        database: CKDatabase,
        change: ([RemoteAlarmCommand]) -> [RemoteAlarmCommand]
    ) async throws {
        var attempt = 0
        while attempt < 3 {
            attempt += 1
            let root = try await database.record(for: try recordID(for: grant))
            guard let current = readGrant(from: root) else { throw RemoteBackendError.missingRoot }
            var stored = current
            stored.cloudKitRootRecordName = grant.cloudKitRootRecordName
            stored.cloudKitZoneName = grant.cloudKitZoneName
            stored.cloudKitOwnerName = grant.cloudKitOwnerName
            stored.inviteCode = grant.inviteCode
            stored.cloudKitShareRecordName = stored.cloudKitShareRecordName ?? grant.cloudKitShareRecordName
            let commands = change(readCommands(from: root))
            do {
                try await save(stored, commands: commands, database: database, record: root)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 {
                continue
            }
        }
    }

    private func save(
        _ grant: ShareGrant,
        commands: [RemoteAlarmCommand],
        database: CKDatabase,
        record: CKRecord
    ) async throws {
        write(grant, commands: commands, to: record)
        _ = try await database.save(record)
    }

    private func recordID(for grant: ShareGrant) throws -> CKRecord.ID {
        guard let name = grant.cloudKitRootRecordName,
              let zone = grant.cloudKitZoneName,
              let owner = grant.cloudKitOwnerName else {
            throw RemoteBackendError.missingRoot
        }
        return CKRecord.ID(recordName: name, zoneID: CKRecordZone.ID(zoneName: zone, ownerName: owner))
    }

    private func write(_ grant: ShareGrant, commands: [RemoteAlarmCommand], to record: CKRecord) {
        if let grantJSON = try? json(grant) {
            record["grantJSON"] = grantJSON as NSString
        }
        if let commandsJSON = try? json(commands) {
            record["commandsJSON"] = commandsJSON as NSString
        }
    }

    private func readGrant(from record: CKRecord) -> ShareGrant? {
        guard let text = record["grantJSON"] as? String else { return nil }
        return try? decode(ShareGrant.self, from: text)
    }

    private func readCommands(from record: CKRecord) -> [RemoteAlarmCommand] {
        guard let text = record["commandsJSON"] as? String else { return [] }
        return (try? decode([RemoteAlarmCommand].self, from: text)) ?? []
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(text.utf8))
    }
}
