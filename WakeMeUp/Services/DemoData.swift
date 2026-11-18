import Foundation

enum DemoData {
    static func make(now: Date = Date()) -> LibrarySnapshot {
        let profile = Participant(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            displayName: String(localized: "demo.me")
        )
        let friend = Participant(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
            displayName: String(localized: "demo.friend")
        )
        let weekdays = AlarmGroup(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            name: String(localized: "demo.weekdays"),
            isEnabled: true,
            symbol: "briefcase"
        )
        let weekend = AlarmGroup(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!,
            name: String(localized: "demo.weekend"),
            isEnabled: true,
            symbol: "sun.max"
        )
        let morning = Alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
            schedule: .wallClock(hour: 6, minute: 30, repeatDays: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            label: String(localized: "demo.morning"),
            soundID: "rise",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: weekdays.id,
            songLink: SongLink.parse("https://open.spotify.com/track/11dFghVXANMlKmJXsNCbNl"),
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let work = Alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000002")!,
            schedule: .wallClock(hour: 7, minute: 0, repeatDays: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            label: String(localized: "demo.work"),
            soundID: "classic",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: weekdays.id,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let sleepIn = Alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!,
            schedule: .wallClock(hour: 9, minute: 0, repeatDays: [.saturday, .sunday]),
            label: String(localized: "demo.sleepIn"),
            soundID: "bell",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: weekend.id,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let windDown = Alarm(
            id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000004")!,
            schedule: .wallClock(
                hour: 22,
                minute: 30,
                repeatDays: Weekday.allCases
            ),
            label: String(localized: "demo.windDown"),
            soundID: "chime",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: false,
            groupID: nil,
            songLink: nil,
            origin: .remote(senderID: friend.id, senderName: friend.displayName, commandID: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!),
            resumeWhenGroupEnables: nil
        )
        let grant = ShareGrant(
            id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!,
            inviteCode: "OLA-DEMO",
            secret: "demo",
            owner: profile,
            grantee: friend,
            state: .active,
            createdAt: now,
            cloudKitRootRecordName: nil,
            cloudKitZoneName: nil,
            cloudKitOwnerName: nil
        )
        return LibrarySnapshot(
            library: AlarmLibrary(alarms: [morning, work, sleepIn, windDown], groups: [weekdays, weekend]),
            permissions: PermissionCenter(grants: [grant]),
            customSounds: [],
            profile: profile,
            simulatedFriend: friend,
            appliedCommandIDs: [],
            pendingOutbox: []
        )
    }
}
