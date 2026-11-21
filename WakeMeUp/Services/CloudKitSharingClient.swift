import CloudKit
import Foundation
import os

enum CloudKitErrorText {
    enum Context: Equatable {
        case creatingInvite
        case backgroundSync
        case sendingAlarm
    }

    /// A launch or refresh failure must not be worded as a failed invite.
    static func alertKind(for context: Context) -> Context? {
        switch context {
        case .backgroundSync: nil
        case .creatingInvite, .sendingAlarm: context
        }
    }

    static func message(for error: Error) -> String {
        let friendly = String(localized: "sharing.cloudError")
        return "\(friendly)\n\(detail(for: error))"
    }

    /// Nil for background sync, so a refresh does not raise an alert.
    static func alertMessage(for error: Error, context: Context) -> String? {
        switch context {
        case .backgroundSync:
            return nil
        case .creatingInvite:
            return message(for: error)
        case .sendingAlarm:
            return "\(String(localized: "sharing.reachError"))\n\(detail(for: error))"
        }
    }

    static func detail(for error: Error) -> String {
        if let backend = error as? RemoteBackendError, let text = backend.errorDescription {
            return text
        }
        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }
        var lines: [String] = []
        func append(_ line: String) {
            guard !lines.contains(line) else { return }
            lines.append(line)
        }
        append("CKError \(cloudError.code.rawValue): \(cloudError.localizedDescription)")
        if let partial = cloudError.partialErrorsByItemID {
            for (identifier, itemError) in partial {
                append("\(identifier): \(detail(for: itemError))")
            }
        }
        if let underlying = cloudError.userInfo[NSUnderlyingErrorKey] as? Error, !(underlying is CKError) {
            append(underlying.localizedDescription)
        }
        return lines.joined(separator: "\n")
    }
}

enum CloudKitZoneFailure {
    static func isZoneNotFound(_ error: Error) -> Bool {
        contains(error, code: .zoneNotFound)
    }

    static func isUserDeletedZone(_ error: Error) -> Bool {
        contains(error, code: .userDeletedZone)
    }

    /// The custom zone has to be created again before any record operation can succeed.
    static func shouldRecreateZone(_ error: Error) -> Bool {
        isZoneNotFound(error) || isUserDeletedZone(error)
    }

    /// The grant record itself is not on the server yet.
    static func isMissingRecord(_ error: Error) -> Bool {
        contains(error, code: .unknownItem)
    }

    static func isZoneAlreadyExists(_ error: Error) -> Bool {
        contains(error, code: .serverRecordChanged)
    }

    private static func contains(_ error: Error, code: CKError.Code) -> Bool {
        guard let cloudError = error as? CKError else { return false }
        if cloudError.code == code { return true }
        guard cloudError.code == .partialFailure, let partial = cloudError.partialErrorsByItemID else { return false }
        return partial.values.contains { contains($0, code: code) }
    }
}

enum PrivateCloudZone {
    static let name = "WakeMeUp"

    /// Prefer the zone id CloudKit stored. `__defaultOwner__` is only the local placeholder.
    static func canonical(requested: CKRecordZone.ID, server: CKRecordZone.ID?) -> CKRecordZone.ID {
        guard let server else { return requested }
        let owner = server.ownerName
        if owner.isEmpty || owner == CKCurrentUserDefaultName {
            let zoneName = server.zoneName.isEmpty ? requested.zoneName : server.zoneName
            return CKRecordZone.ID(zoneName: zoneName, ownerName: requested.ownerName)
        }
        return server
    }
}

enum ShareRecordAddress {
    enum Database: Equatable {
        case privateDatabase
        case sharedDatabase
    }

    static func database(isOwner: Bool) -> Database {
        isOwner ? .privateDatabase : .sharedDatabase
    }

    /// Private-database record ids always use the current user. A stored owner name
    /// belongs to a share and is only valid on the shared database.
    static func zoneID(zoneName: String, storedOwnerName: String?, database: Database) -> CKRecordZone.ID {
        let name = zoneName.isEmpty ? PrivateCloudZone.name : zoneName
        switch database {
        case .privateDatabase:
            return CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)
        case .sharedDatabase:
            let stored = storedOwnerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let owner = stored.isEmpty ? CKCurrentUserDefaultName : stored
            return CKRecordZone.ID(zoneName: name, ownerName: owner)
        }
    }
}

enum ShareAccessPlan: Equatable {
    case use(ownerName: String)
    /// The share is not in the shared database yet. Accept it again from the link.
    case reaccept
    case unavailable

    /// Pick the shared-zone owner to read or write. A foreign owner is never used on the private database.
    static func decide(preferredOwner: String, sharedOwners: [String], hasInviteURL: Bool) -> ShareAccessPlan {
        let preferred = preferredOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let owners = sharedOwners
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != CKCurrentUserDefaultName }
        if !preferred.isEmpty, preferred != CKCurrentUserDefaultName, owners.contains(preferred) {
            return .use(ownerName: preferred)
        }
        if owners.count == 1, let only = owners.first {
            return .use(ownerName: only)
        }
        if hasInviteURL { return .reaccept }
        return .unavailable
    }
}

enum ContactConnectionNote: Equatable {
    /// The other phone has not published the share that lets us ring it.
    case waitingForThem
    /// Their share should be on this phone, but the shared zone was missing.
    case shareMissing

    static func note(wakeGrantID: UUID?, hostedGrantID: UUID?, unreachable: Set<UUID>) -> ContactConnectionNote? {
        let ids = [wakeGrantID, hostedGrantID].compactMap { $0 }
        if ids.contains(where: { unreachable.contains($0) }) { return .shareMissing }
        if wakeGrantID == nil { return .waitingForThem }
        return nil
    }
}

enum GrantRecordRecovery {
    /// A missing zone or a missing grant means invite creation should create them, not surface the fetch error.
    static func shouldCreateInstead(of error: Error) -> Bool {
        CloudKitZoneFailure.shouldRecreateZone(error) || CloudKitZoneFailure.isMissingRecord(error)
    }
}

enum RemoteBackendError: LocalizedError {
    case notConfigured
    case notSignedIn
    case shareURLMissing
    case missingRoot
    case shareZoneMissing(recordName: String, ownerName: String, visibleOwners: [String])
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
        case let .shareZoneMissing(recordName, ownerName, visibleOwners):
            "The iCloud share is not on this phone. record=\(recordName) owner=\(ownerName) visible=\(visibleOwners.joined(separator: ","))"
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
    private let cloudLog = Logger(subsystem: "com.grandelevas.wakemeup", category: "CloudKit")
    private let zoneLock = NSLock()
    private var cachedPrivateZoneID: CKRecordZone.ID?
    private var zoneTask: Task<CKRecordZone.ID, Error>?
    private var cachedSharedOwners: [String]?

    init(containerID: String) {
        container = CKContainer(identifier: containerID)
    }

    func requireAccount() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw RemoteBackendError.notSignedIn }
    }

    func currentUserName() async -> String? {
        do {
            try await requireAccount()
            let userID = try await container.userRecordID()
            let participant = try await container.shareParticipant(forUserRecordID: userID)
            return PersonName.formatted(participant.userIdentity.nameComponents)
        } catch {
            return nil
        }
    }

    /// Loads the shared-zone list once per refresh so later reads see shares accepted earlier in the same pass.
    func prepareForRefresh() async {
        _ = try? await sharedWakeMeUpOwners(refresh: true)
    }

    func ensureSilentSubscription() async {
        do {
            try await requireAccount()
            let zoneID = try await ensurePrivateZone()
            try await subscribe(zoneID: zoneID)
        } catch {
            // The next invite creates the zone and replaces the subscription.
        }
    }

    func createShare(for grant: ShareGrant) async throws -> (ShareGrant, CKShare) {
        try await requireAccount()
        var grant = grant
        let database = container.privateCloudDatabase
        let ensured = try await ensurePrivateZone()
        let zoneID = ShareRecordAddress.zoneID(
            zoneName: ensured.zoneName,
            storedOwnerName: ensured.ownerName,
            database: .privateDatabase
        )
        cloudLog.error("createShare private zone owner=\(zoneID.ownerName, privacy: .public) record=grant-\(grant.id.uuidString, privacy: .public)")
        do {
            return try await saveNewShare(&grant, zoneID: zoneID, database: database)
        } catch {
            // The zone was missing or the grant record was not there yet. Create it and try once more.
            guard GrantRecordRecovery.shouldCreateInstead(of: error) else { throw error }
            let ensured = try await ensurePrivateZone(resetCache: CloudKitZoneFailure.shouldRecreateZone(error))
            let zoneID = ShareRecordAddress.zoneID(
                zoneName: ensured.zoneName,
                storedOwnerName: ensured.ownerName,
                database: .privateDatabase
            )
            return try await saveNewShare(&grant, zoneID: zoneID, database: database)
        }
    }

    private func saveNewShare(
        _ grant: inout ShareGrant,
        zoneID: CKRecordZone.ID,
        database: CKDatabase
    ) async throws -> (ShareGrant, CKShare) {
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
        let savedZone = savedRoot?.recordID.zoneID ?? savedShare.recordID.zoneID
        grant.inviteCode = url.absoluteString
        grant.cloudKitRootRecordName = savedRoot?.recordID.recordName ?? rootName
        grant.cloudKitZoneName = savedZone.zoneName
        grant.cloudKitOwnerName = savedZone.ownerName
        grant.cloudKitShareRecordName = savedShare.recordID.recordName
        if let savedRoot {
            do {
                try await save(grant, commands: [], database: database, record: savedRoot)
            } catch {
                guard GrantRecordRecovery.shouldCreateInstead(of: error) else { throw error }
                let zoneID = try await ensurePrivateZone(resetCache: CloudKitZoneFailure.shouldRecreateZone(error))
                let rebuilt = CKRecord(
                    recordType: savedRoot.recordType,
                    recordID: CKRecord.ID(recordName: savedRoot.recordID.recordName, zoneID: zoneID)
                )
                try await save(grant, commands: [], database: database, record: rebuilt)
            }
        }
        try? await subscribe(zoneID: savedZone)
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
        cloudLog.error("CKAcceptSharesOperation root=\(rootID.recordName, privacy: .public) owner=\(rootID.zoneID.ownerName, privacy: .public)")
        do {
            _ = try await container.accept([metadata])
        } catch {
            // Opening the same link twice still has to record who joined.
            cloudLog.error("accept threw; checking shared zones. \(error.localizedDescription, privacy: .public)")
        }
        _ = try? await sharedWakeMeUpOwners(refresh: true)
        let root = try await fetchShared(rootID, inviteURL: inviteURL)
        guard var grant = readGrant(from: root) else { throw RemoteBackendError.missingRoot }
        let savedID = root.recordID
        grant.grantee = grantee
        grant.state = .active
        grant.cloudKitRootRecordName = savedID.recordName
        grant.cloudKitZoneName = savedID.zoneID.zoneName
        grant.cloudKitOwnerName = savedID.zoneID.ownerName
        grant.inviteCode = inviteURL?.absoluteString ?? grant.inviteCode
        try await save(grant, commands: readCommands(from: root), database: container.sharedCloudDatabase, record: root)
        return grant
    }

    func refresh(_ grant: ShareGrant, asOwner: Bool) async throws -> (ShareGrant, [RemoteAlarmCommand]) {
        try await requireAccount()
        let database = asOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let root = try await fetchRecord(try recordID(for: grant, database: database), in: database, inviteURL: inviteURL(for: grant))
        guard var updated = readGrant(from: root) else { throw RemoteBackendError.missingRoot }
        let zoneID = root.recordID.zoneID
        updated.cloudKitRootRecordName = root.recordID.recordName
        updated.cloudKitZoneName = zoneID.zoneName
        updated.cloudKitOwnerName = zoneID.ownerName
        updated.inviteCode = grant.inviteCode
        updated.cloudKitShareRecordName = updated.cloudKitShareRecordName ?? grant.cloudKitShareRecordName
        if asOwner, !InviteLinkPolicy.allowsAnyoneWithLink(grantState: updated.state) {
            await closePublicLink(on: root, grant: updated, database: database)
        }
        return (updated, readCommands(from: root))
    }

    func publishReturnInvite(_ url: URL, on grant: ShareGrant) async throws {
        try await requireAccount()
        try await mutate(grant: grant, database: container.sharedCloudDatabase, alter: { stored in
            stored.returnInviteURL = url.absoluteString
        }, change: { $0 })
    }

    func updateInviteeName(_ name: String, on grant: ShareGrant) async throws {
        guard PersonName.nonempty(name) != nil else { return }
        try await requireAccount()
        try await mutate(grant: grant, database: container.privateCloudDatabase, alter: { stored in
            stored.inviteeName = name
        }, change: { $0 })
    }

    func appendWakeReport(_ report: WakeReport, on grant: ShareGrant) async throws {
        try await requireAccount()
        try await mutate(grant: grant, database: container.sharedCloudDatabase, alter: { stored in
            var reports = stored.wakeReports ?? []
            if let index = reports.firstIndex(where: { $0.commandID == report.commandID }) {
                if reports[index].status == .up, report.status == .asleep { return }
                reports[index] = report
            } else {
                reports.append(report)
            }
            stored.wakeReports = reports
        }, change: { $0 })
    }

    func updateOwnName(_ name: String, on grant: ShareGrant, asOwner: Bool) async throws {
        guard PersonName.nonempty(name) != nil else { return }
        try await requireAccount()
        let database = asOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        try await mutate(grant: grant, database: database, alter: { stored in
            if asOwner {
                stored.owner.displayName = name
            } else if stored.grantee != nil {
                stored.grantee?.displayName = name
            }
        }, change: { $0 })
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

    /// Saves a voice clip next to the shared root. Record type `WMVoice`, field `audio` (Asset).
    func saveVoice(file: URL, recordName: String, grant: ShareGrant, asOwner: Bool) async throws {
        try await requireAccount()
        let database = asOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        if database.databaseScope == .private {
            _ = try await ensurePrivateZone()
        }
        var rootID = try recordID(for: grant, database: database)
        if database.databaseScope != .private {
            rootID = await resolvedSharedID(proposed: rootID)
        }
        let voice = CKRecord(recordType: "WMVoice", recordID: CKRecord.ID(recordName: recordName, zoneID: rootID.zoneID))
        voice["audio"] = CKAsset(fileURL: file)
        voice.parent = CKRecord.Reference(recordID: rootID, action: .none)
        do {
            _ = try await database.save(voice)
        } catch {
            if database.databaseScope != .private,
               CloudKitZoneFailure.shouldRecreateZone(error),
               let url = inviteURL(for: grant) {
                let root = try await reopenShare(url)
                let rebuilt = CKRecord(recordType: "WMVoice", recordID: CKRecord.ID(recordName: recordName, zoneID: root.zoneID))
                rebuilt["audio"] = CKAsset(fileURL: file)
                rebuilt.parent = CKRecord.Reference(recordID: root, action: .none)
                _ = try await database.save(rebuilt)
                return
            }
            guard database.databaseScope == .private, CloudKitZoneFailure.shouldRecreateZone(error) else { throw error }
            _ = try await ensurePrivateZone(resetCache: true)
            let zoneID = ShareRecordAddress.zoneID(
                zoneName: PrivateCloudZone.name,
                storedOwnerName: nil,
                database: .privateDatabase
            )
            let rebuilt = CKRecord(recordType: "WMVoice", recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
            rebuilt["audio"] = CKAsset(fileURL: file)
            rebuilt.parent = CKRecord.Reference(recordID: CKRecord.ID(recordName: rootID.recordName, zoneID: zoneID), action: .none)
            _ = try await database.save(rebuilt)
        }
    }

    func voiceFile(named recordName: String, grant: ShareGrant, asOwner: Bool) async throws -> URL? {
        try await requireAccount()
        let database = asOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let zoneID = try recordID(for: grant, database: database).zoneID
        let record = try await fetchRecord(
            CKRecord.ID(recordName: recordName, zoneID: zoneID),
            in: database,
            inviteURL: inviteURL(for: grant)
        )
        guard let asset = record["audio"] as? CKAsset else { return nil }
        return asset.fileURL
    }

    func revoke(_ grant: ShareGrant) async throws {
        try await requireAccount()
        var revoked = grant
        revoked.state = .revoked
        let root = try await fetchRecord(try recordID(for: grant, database: container.privateCloudDatabase), in: container.privateCloudDatabase)
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
            guard let share = try await fetchRecord(shareID, in: database) as? CKShare else { return }
            guard share.publicPermission != .none else { return }
            share.publicPermission = .none
            _ = try await database.save(share)
        } catch {
            // The grant state is already saved. The next refresh tries again while it is active.
        }
    }

    /// Silent subscription. A visible alert here fires for every zone write, including an invite being accepted.
    private func subscribe(zoneID: CKRecordZone.ID) async throws {
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "wakemeup-zone")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        try? await container.privateCloudDatabase.deleteSubscription(withID: subscription.subscriptionID)
        _ = try await container.privateCloudDatabase.save(subscription)
    }

    private func mutate(
        grant: ShareGrant,
        database: CKDatabase,
        alter: (inout ShareGrant) -> Void = { _ in },
        change: ([RemoteAlarmCommand]) -> [RemoteAlarmCommand]
    ) async throws {
        var attempt = 0
        while attempt < 3 {
            attempt += 1
            let root = try await fetchRecord(try recordID(for: grant, database: database), in: database, inviteURL: inviteURL(for: grant))
            guard var stored = readGrant(from: root) else { throw RemoteBackendError.missingRoot }
            stored.cloudKitRootRecordName = root.recordID.recordName
            stored.cloudKitZoneName = root.recordID.zoneID.zoneName
            stored.cloudKitOwnerName = root.recordID.zoneID.ownerName
            stored.inviteCode = grant.inviteCode
            stored.cloudKitShareRecordName = stored.cloudKitShareRecordName ?? grant.cloudKitShareRecordName
            alter(&stored)
            let commands = change(readCommands(from: root))
            do {
                try await save(stored, commands: commands, database: database, record: root)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 {
                continue
            }
        }
    }

    private func ensurePrivateZone(resetCache: Bool = false) async throws -> CKRecordZone.ID {
        if resetCache {
            clearZoneCache()
        }
        zoneLock.lock()
        if let cachedPrivateZoneID {
            zoneLock.unlock()
            return cachedPrivateZoneID
        }
        if let zoneTask {
            zoneLock.unlock()
            return try await zoneTask.value
        }
        let task = Task { try await self.createOrFetchPrivateZone() }
        zoneTask = task
        zoneLock.unlock()
        do {
            let zoneID = try await task.value
            let currentUser = ShareRecordAddress.zoneID(
                zoneName: zoneID.zoneName,
                storedOwnerName: nil,
                database: .privateDatabase
            )
            zoneLock.lock()
            cachedPrivateZoneID = currentUser
            zoneTask = nil
            zoneLock.unlock()
            return currentUser
        } catch {
            zoneLock.lock()
            zoneTask = nil
            zoneLock.unlock()
            throw error
        }
    }

    private func clearZoneCache() {
        zoneLock.lock()
        cachedPrivateZoneID = nil
        zoneTask = nil
        zoneLock.unlock()
    }

    /// Fetch the zone CloudKit already has. If it is missing, create it and keep the id the server returns.
    private func createOrFetchPrivateZone() async throws -> CKRecordZone.ID {
        let requested = CKRecordZone.ID(zoneName: PrivateCloudZone.name, ownerName: CKCurrentUserDefaultName)
        do {
            return try await fetchZone(matching: requested)
        } catch {
            guard CloudKitZoneFailure.shouldRecreateZone(error) else { throw error }
        }
        do {
            let created = try await saveZone(requested)
            if created.ownerName == CKCurrentUserDefaultName {
                if let fetched = try? await fetchZone(matching: created) {
                    return fetched
                }
            }
            return created
        } catch {
            guard CloudKitZoneFailure.isZoneAlreadyExists(error) else { throw error }
            return try await fetchZone(matching: requested)
        }
    }

    private func fetchZone(matching requested: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordZonesOperation(recordZoneIDs: [requested])
            operation.qualityOfService = .userInitiated
            let box = ZoneSaveBox()
            operation.perRecordZoneResultBlock = { _, result in
                switch result {
                case let .success(zone):
                    box.setSaved(zone.zoneID)
                case let .failure(error):
                    box.setFailure(error)
                }
            }
            operation.fetchRecordZonesResultBlock = { result in
                if let saved = box.saved {
                    continuation.resume(returning: PrivateCloudZone.canonical(requested: requested, server: saved))
                    return
                }
                if let failure = box.failure {
                    continuation.resume(throwing: failure)
                    return
                }
                switch result {
                case .success:
                    continuation.resume(throwing: CKError(.zoneNotFound))
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }

    private func saveZone(_ requested: CKRecordZone.ID) async throws -> CKRecordZone.ID {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordZonesOperation(
                recordZonesToSave: [CKRecordZone(zoneID: requested)],
                recordZoneIDsToDelete: nil
            )
            operation.qualityOfService = .userInitiated
            let box = ZoneSaveBox()
            operation.perRecordZoneSaveBlock = { _, result in
                switch result {
                case let .success(zone):
                    box.setSaved(zone.zoneID)
                case let .failure(error):
                    if CloudKitZoneFailure.isZoneAlreadyExists(error) {
                        box.setSaved(requested)
                    } else {
                        box.setFailure(error)
                    }
                }
            }
            operation.modifyRecordZonesResultBlock = { result in
                if let saved = box.saved {
                    continuation.resume(returning: PrivateCloudZone.canonical(requested: requested, server: saved))
                    return
                }
                if let failure = box.failure {
                    continuation.resume(throwing: failure)
                    return
                }
                switch result {
                case .success:
                    continuation.resume(returning: requested)
                case let .failure(error):
                    if CloudKitZoneFailure.isZoneAlreadyExists(error) {
                        continuation.resume(returning: requested)
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            container.privateCloudDatabase.add(operation)
        }
    }

    private func fetchRecord(_ id: CKRecord.ID, in database: CKDatabase, inviteURL: URL? = nil) async throws -> CKRecord {
        if database.databaseScope != .private {
            return try await fetchShared(id, inviteURL: inviteURL)
        }
        let storedOwner = id.zoneID.ownerName
        if storedOwner != CKCurrentUserDefaultName {
            cloudLog.error("private fetch refused foreign owner \(storedOwner, privacy: .public) for \(id.recordName, privacy: .public); using \(CKCurrentUserDefaultName, privacy: .public)")
        }
        _ = try await ensurePrivateZone()
        let recordID = CKRecord.ID(recordName: id.recordName, zoneID: privateRecordZoneID())
        cloudLog.error("private fetch \(recordID.recordName, privacy: .public) zone=\(recordID.zoneID.zoneName, privacy: .public) owner=\(recordID.zoneID.ownerName, privacy: .public)")
        do {
            return try await database.record(for: recordID)
        } catch {
            guard CloudKitZoneFailure.shouldRecreateZone(error) else { throw error }
            cloudLog.error("private zone missing; creating it and retrying \(recordID.recordName, privacy: .public)")
            _ = try await ensurePrivateZone(resetCache: true)
            return try await database.record(for: recordID)
        }
    }

    /// Shared-database reads use a zone that is actually in `allRecordZones()`. A missing zone is accepted again from the invite link.
    private func fetchShared(_ id: CKRecord.ID, inviteURL: URL?, didReaccept: Bool = false) async throws -> CKRecord {
        let resolved = await resolvedSharedID(proposed: id)
        cloudLog.error("shared fetch \(resolved.recordName, privacy: .public) owner=\(resolved.zoneID.ownerName, privacy: .public) reaccept=\(didReaccept, privacy: .public)")
        do {
            return try await container.sharedCloudDatabase.record(for: resolved)
        } catch {
            cloudLog.error("shared fetch failed \(resolved.recordName, privacy: .public) owner=\(resolved.zoneID.ownerName, privacy: .public) \(error.localizedDescription, privacy: .public)")
            if !didReaccept,
               CloudKitZoneFailure.shouldRecreateZone(error),
               let inviteURL,
               InviteLinkPolicy.isCloudShare(inviteURL) {
                let root = try await reopenShare(inviteURL)
                return try await fetchShared(root, inviteURL: inviteURL, didReaccept: true)
            }
            guard CloudKitZoneFailure.shouldRecreateZone(error) else { throw error }
            let owners = (try? await sharedWakeMeUpOwners(refresh: true)) ?? []
            throw RemoteBackendError.shareZoneMissing(
                recordName: resolved.recordName,
                ownerName: resolved.zoneID.ownerName,
                visibleOwners: owners
            )
        }
    }

    private func resolvedSharedID(proposed: CKRecord.ID) async -> CKRecord.ID {
        let owners = (try? await sharedWakeMeUpOwners()) ?? []
        let plan = ShareAccessPlan.decide(
            preferredOwner: proposed.zoneID.ownerName,
            sharedOwners: owners,
            hasInviteURL: false
        )
        cloudLog.error("shared zones [\(owners.joined(separator: ","), privacy: .public)] preferred=\(proposed.zoneID.ownerName, privacy: .public) plan=\(String(describing: plan), privacy: .public)")
        guard case let .use(owner) = plan else { return proposed }
        return CKRecord.ID(
            recordName: proposed.recordName,
            zoneID: CKRecordZone.ID(zoneName: proposed.zoneID.zoneName, ownerName: owner)
        )
    }

    private func sharedWakeMeUpOwners(refresh: Bool = false) async throws -> [String] {
        if !refresh, let cachedSharedOwners { return cachedSharedOwners }
        let zones = try await container.sharedCloudDatabase.allRecordZones()
        let owners = zones.map(\.zoneID).filter { $0.zoneName == PrivateCloudZone.name }.map(\.ownerName)
        cachedSharedOwners = owners
        return owners
    }

    /// CKFetchShareMetadata plus CKAcceptSharesOperation. Used when the shared zone list does not contain the inviter's zone.
    private func reopenShare(_ url: URL) async throws -> CKRecord.ID {
        cloudLog.error("CKFetchShareMetadata + CKAcceptSharesOperation")
        let metadata = try await container.shareMetadata(for: url)
        guard let rootID = metadata.hierarchicalRootRecordID else { throw RemoteBackendError.missingRoot }
        do {
            _ = try await container.accept([metadata])
        } catch {
            cloudLog.error("re-accept threw \(error.localizedDescription, privacy: .public)")
        }
        let owners = (try? await sharedWakeMeUpOwners(refresh: true)) ?? []
        cloudLog.error("after re-accept root=\(rootID.recordName, privacy: .public) owner=\(rootID.zoneID.ownerName, privacy: .public) zones=[\(owners.joined(separator: ","), privacy: .public)]")
        return rootID
    }

    private func inviteURL(for grant: ShareGrant) -> URL? {
        guard let url = InviteLinkPolicy.url(from: grant.inviteCode), InviteLinkPolicy.isCloudShare(url) else { return nil }
        return url
    }

    private func privateRecordZoneID() -> CKRecordZone.ID {
        ShareRecordAddress.zoneID(zoneName: PrivateCloudZone.name, storedOwnerName: nil, database: .privateDatabase)
    }

    private func save(
        _ grant: ShareGrant,
        commands: [RemoteAlarmCommand],
        database: CKDatabase,
        record: CKRecord
    ) async throws {
        write(grant, commands: commands, to: record)
        if database.databaseScope != .private {
            _ = try await database.save(record)
            return
        }
        _ = try await ensurePrivateZone()
        let zoneID = privateRecordZoneID()
        let prepared = record.recordID.zoneID == zoneID ? record : cloned(record, zoneID: zoneID)
        do {
            _ = try await database.save(prepared)
        } catch {
            guard CloudKitZoneFailure.shouldRecreateZone(error) else { throw error }
            _ = try await ensurePrivateZone(resetCache: true)
            _ = try await database.save(cloned(prepared, zoneID: privateRecordZoneID()))
        }
    }

    private func cloned(_ record: CKRecord, zoneID: CKRecordZone.ID) -> CKRecord {
        let copy = CKRecord(
            recordType: record.recordType,
            recordID: CKRecord.ID(recordName: record.recordID.recordName, zoneID: zoneID)
        )
        for key in record.allKeys() {
            copy[key] = record[key]
        }
        if let parent = record.parent {
            copy.parent = CKRecord.Reference(
                recordID: CKRecord.ID(recordName: parent.recordID.recordName, zoneID: zoneID),
                action: parent.action
            )
        }
        return copy
    }

    private func recordID(for grant: ShareGrant, database: CKDatabase) throws -> CKRecord.ID {
        guard let name = grant.cloudKitRootRecordName else { throw RemoteBackendError.missingRoot }
        let scope: ShareRecordAddress.Database = database.databaseScope == .private ? .privateDatabase : .sharedDatabase
        if scope == .sharedDatabase, grant.cloudKitOwnerName?.isEmpty != false {
            throw RemoteBackendError.missingRoot
        }
        let zoneName = grant.cloudKitZoneName ?? PrivateCloudZone.name
        let zoneID = ShareRecordAddress.zoneID(
            zoneName: zoneName,
            storedOwnerName: grant.cloudKitOwnerName,
            database: scope
        )
        return CKRecord.ID(recordName: name, zoneID: zoneID)
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

private final class ZoneSaveBox: @unchecked Sendable {
    private let lock = NSLock()
    private var savedID: CKRecordZone.ID?
    private var failureError: Error?

    var saved: CKRecordZone.ID? {
        lock.lock()
        defer { lock.unlock() }
        return savedID
    }

    var failure: Error? {
        lock.lock()
        defer { lock.unlock() }
        return failureError
    }

    func setSaved(_ id: CKRecordZone.ID) {
        lock.lock()
        savedID = id
        lock.unlock()
    }

    func setFailure(_ error: Error) {
        lock.lock()
        failureError = error
        lock.unlock()
    }
}
