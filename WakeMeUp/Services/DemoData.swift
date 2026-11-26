import Foundation

enum DemoData {
    static let profileID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    static let akhiID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000010")!
    static let mamaID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000011")!
    static let olaID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
    static let tomekID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000012")!
    static let weekdaysID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!
    static let weekendID = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
    static let lovedOneAlarmID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000010")!
    static let ringingAlarmID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000011")!
    static let voiceSoundID = "voice-demo-akhi"
    static let videoID = "video-demo-akhi"

    static func make(now: Date = Date(), calendar: Calendar = .current) -> LibrarySnapshot {
        let profile = Participant(id: profileID, displayName: String(localized: "demo.me"))
        let akhi = Participant(id: akhiID, displayName: "Akhi")
        let mama = Participant(id: mamaID, displayName: "Mama")
        let ola = Participant(id: olaID, displayName: "Ola")
        let tomek = Participant(id: tomekID, displayName: "Tomek")
        let weekdays = AlarmGroup(id: weekdaysID, name: String(localized: "demo.weekdays"), isEnabled: true, symbol: "briefcase")
        let weekend = AlarmGroup(id: weekendID, name: String(localized: "demo.weekend"), isEnabled: true, symbol: "sun.max")
        let morning = alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
            hour: 6, minute: 30,
            days: [.monday, .tuesday, .wednesday, .thursday, .friday],
            label: String(localized: "demo.morning"),
            soundID: "rise",
            groupID: weekdays.id,
            song: "https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl"
        )
        let work = alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000002")!,
            hour: 7, minute: 0,
            days: [.monday, .tuesday, .wednesday, .thursday, .friday],
            label: String(localized: "demo.work"),
            soundID: "classic",
            groupID: weekdays.id
        )
        let sleepIn = alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!,
            hour: 9, minute: 0,
            days: [.saturday, .sunday],
            label: String(localized: "demo.sleepIn"),
            soundID: "bell",
            groupID: weekend.id
        )
        let loved = alarm(
            id: lovedOneAlarmID,
            hour: 6, minute: 40,
            days: [.monday, .tuesday, .wednesday, .thursday, .friday],
            label: "Akhi",
            soundID: voiceSoundID,
            groupID: weekdays.id,
            note: String(localized: "demo.note.akhi"),
            videoFileID: videoID
        )
        var fromAkhi = alarm(
            id: ringingAlarmID,
            hour: 6, minute: 45,
            days: [.monday, .tuesday, .wednesday, .thursday, .friday],
            label: "Akhi",
            soundID: voiceSoundID,
            note: String(localized: "demo.note.akhi"),
            videoFileID: videoID
        )
        fromAkhi.origin = .remote(senderID: akhi.id, senderName: akhi.displayName, commandID: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000011")!)
        var fromMama = alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000012")!,
            hour: 21, minute: 30,
            days: Weekday.allCases,
            label: "Mama",
            soundID: "chime",
            snooze: false,
            note: String(localized: "demo.note.mama")
        )
        fromMama.origin = .remote(senderID: mama.id, senderName: mama.displayName, commandID: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000012")!)
        let grants = [akhi, mama, ola, tomek].enumerated().map { index, friend in
            ShareGrant(
                id: UUID(uuidString: String(format: "EEEEEEEE-0000-0000-0000-%012d", index + 1))!,
                inviteCode: "DEMO-\(friend.displayName)",
                secret: "demo",
                owner: friend,
                grantee: profile,
                state: .active,
                createdAt: now,
                cloudKitRootRecordName: nil,
                cloudKitZoneName: nil,
                cloudKitOwnerName: nil,
                inviteeName: friend.displayName
            )
        }
        let sent = [
            sentAlarm(id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!, hour: 5, minute: 45, label: String(localized: "demo.sent.ola"), recipient: ola, now: now),
            sentAlarm(id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!, hour: 7, minute: 15, label: String(localized: "demo.sent.tomek"), recipient: tomek, now: now)
        ]
        return LibrarySnapshot(
            library: AlarmLibrary(
                alarms: [loved, morning, work, sleepIn, fromAkhi, fromMama],
                groups: [weekdays, weekend]
            ),
            permissions: PermissionCenter(grants: grants),
            customSounds: [
                CustomSound(id: voiceSoundID, displayName: "Akhi", filename: "\(voiceSoundID).wav")
            ],
            profile: profile,
            simulatedFriend: ola,
            appliedCommandIDs: [],
            pendingOutbox: [],
            sentAlarms: sent,
            calendarAlarms: calendarAlarms(now: now, calendar: calendar)
        )
    }

    static func lovedOneDraft(in snapshot: LibrarySnapshot) -> AlarmDraft {
        if let alarm = snapshot.library.alarm(lovedOneAlarmID) {
            return AlarmDraft(alarm: alarm)
        }
        return .makeNew()
    }

    static func napSession(now: Date = .now) -> NapSession {
        let length = 10
        let remaining: TimeInterval = 8 * 60 + 24
        return NapSession(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000099")!,
            startedAt: now.addingTimeInterval(-TimeInterval(length * 60) + remaining),
            minutes: length,
            fireAt: now.addingTimeInterval(remaining),
            soundID: "sleepy"
        )
    }

    private static func calendarAlarms(now: Date, calendar: Calendar) -> [CalendarAlarm] {
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let year = parts.year ?? 2026
        let month = parts.month ?? 11
        let today = parts.day ?? 1
        return [
            CalendarAlarm(
                id: UUID(uuidString: "ABABABAB-0000-0000-0000-000000000001")!,
                year: year, month: month, day: today,
                hour: 8, minute: 15,
                repeatRule: .once,
                label: String(localized: "demo.calendar.breakfast"),
                soundID: "rise",
                snoozeEnabled: true,
                snoozeMinutes: 9,
                isEnabled: true,
                note: String(localized: "demo.note.akhi")
            ),
            CalendarAlarm(
                id: UUID(uuidString: "ABABABAB-0000-0000-0000-000000000002")!,
                year: year, month: month, day: min(3, days(in: month, year: year, calendar: calendar)),
                hour: 18, minute: 0,
                repeatRule: .yearly,
                label: String(localized: "demo.calendar.birthday"),
                soundID: "bells",
                snoozeEnabled: false,
                snoozeMinutes: 9,
                isEnabled: true,
                note: nil
            ),
            CalendarAlarm(
                id: UUID(uuidString: "ABABABAB-0000-0000-0000-000000000003")!,
                year: year, month: month, day: min(12, days(in: month, year: year, calendar: calendar)),
                hour: 16, minute: 30,
                repeatRule: .monthly,
                label: String(localized: "demo.calendar.mama"),
                soundID: "chime",
                snoozeEnabled: true,
                snoozeMinutes: 9,
                isEnabled: true,
                note: String(localized: "demo.note.mama")
            ),
            CalendarAlarm(
                id: UUID(uuidString: "ABABABAB-0000-0000-0000-000000000004")!,
                year: year, month: month, day: min(20, days(in: month, year: year, calendar: calendar)),
                hour: 7, minute: 0,
                repeatRule: .weekly,
                label: String(localized: "demo.calendar.yoga"),
                soundID: "dawn",
                snoozeEnabled: true,
                snoozeMinutes: 9,
                isEnabled: true,
                note: nil
            )
        ]
    }

    private static func days(in month: Int, year: Int, calendar: Calendar) -> Int {
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        return calendar.range(of: .day, in: .month, for: start)?.count ?? 28
    }

    private static func alarm(
        id: UUID,
        hour: Int,
        minute: Int,
        days: [Weekday],
        label: String,
        soundID: String,
        snooze: Bool = true,
        groupID: UUID? = nil,
        song: String? = nil,
        note: String? = nil,
        videoFileID: String? = nil
    ) -> Alarm {
        Alarm(
            id: id,
            schedule: .wallClock(hour: hour, minute: minute, repeatDays: days),
            label: label,
            soundID: soundID,
            snoozeEnabled: snooze,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: groupID,
            songLink: song.flatMap(SongLink.parse),
            note: note,
            videoFileID: videoFileID,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
    }

    private static func sentAlarm(id: UUID, hour: Int, minute: Int, label: String, recipient: Participant, now: Date) -> SentAlarm {
        SentAlarm(
            alarm: alarm(id: id, hour: hour, minute: minute, days: [.monday, .tuesday, .wednesday, .thursday, .friday], label: label, soundID: "classic"),
            recipientID: recipient.id,
            recipientName: recipient.displayName,
            sentAt: now,
            commandID: id
        )
    }
}
