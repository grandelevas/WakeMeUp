import XCTest
@testable import WakeMeUp

final class SchedulingTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    func testWednesdayMorningIsWednesday() {
        let now = date(year: 2026, month: 11, day: 18, hour: 10, minute: 0)
        XCTAssertEqual(Weekday.from(date: now, calendar: calendar), .wednesday)
    }

    func testOneTimeLaterToday() {
        let now = date(year: 2026, month: 11, day: 18, hour: 10, minute: 0)
        let next = NextFireDate.wallClock(hour: 11, minute: 15, repeatDays: [], from: now, calendar: calendar)
        XCTAssertEqual(next, date(year: 2026, month: 11, day: 18, hour: 11, minute: 15))
    }

    func testOneTimeRollsToTomorrowWhenTimeHasPassed() {
        let now = date(year: 2026, month: 11, day: 18, hour: 10, minute: 0)
        let next = NextFireDate.wallClock(hour: 9, minute: 0, repeatDays: [], from: now, calendar: calendar)
        XCTAssertEqual(next, date(year: 2026, month: 11, day: 19, hour: 9, minute: 0))
    }

    func testExactCurrentMinuteWaitsUntilTomorrow() {
        let now = date(year: 2026, month: 11, day: 18, hour: 10, minute: 0)
        let next = NextFireDate.wallClock(hour: 10, minute: 0, repeatDays: [], from: now, calendar: calendar)
        XCTAssertEqual(next, date(year: 2026, month: 11, day: 19, hour: 10, minute: 0))
    }

    func testWeekdaysSkipTheWeekend() {
        let fridayEvening = date(year: 2026, month: 11, day: 20, hour: 18, minute: 0)
        let next = NextFireDate.wallClock(
            hour: 9,
            minute: 0,
            repeatDays: RepeatPatternClassifier.weekdays,
            from: fridayEvening,
            calendar: calendar
        )
        XCTAssertEqual(next, date(year: 2026, month: 11, day: 23, hour: 9, minute: 0))
        XCTAssertEqual(Weekday.from(date: next!, calendar: calendar), .monday)
    }

    func testRepeatPatternNames() {
        XCTAssertEqual(RepeatPatternClassifier.classify([]), .never)
        XCTAssertEqual(RepeatPatternClassifier.classify(Weekday.allCases), .everyDay)
        XCTAssertEqual(RepeatPatternClassifier.classify(Array(RepeatPatternClassifier.weekdays)), .weekdays)
        XCTAssertEqual(RepeatPatternClassifier.classify([.sunday, .saturday]), .weekends)
        XCTAssertEqual(RepeatPatternClassifier.classify([.monday]), .custom)
    }

    func testEveryDayPresetTurnsAllDaysOnAndClearsThemAgain() {
        XCTAssertEqual(RepeatPatternClassifier.toggle(.everyDay, in: []), Set(Weekday.allCases))
        XCTAssertEqual(RepeatPatternClassifier.toggle(.everyDay, in: [.monday]), Set(Weekday.allCases))
        XCTAssertEqual(RepeatPatternClassifier.toggle(.everyDay, in: Set(Weekday.allCases)), [])
        XCTAssertEqual(RepeatPatternClassifier.selectedPreset(Set(Weekday.allCases)), .everyDay)
        XCTAssertNil(RepeatPatternClassifier.selectedPreset([.monday]))
    }

    func testWeekdayPresetReplacesTheSelectionAndClearsAnExactMatch() {
        XCTAssertEqual(RepeatPatternClassifier.toggle(.weekdays, in: []), RepeatPatternClassifier.weekdays)
        XCTAssertEqual(
            RepeatPatternClassifier.toggle(.weekdays, in: Set(Weekday.allCases)),
            RepeatPatternClassifier.weekdays
        )
        XCTAssertEqual(RepeatPatternClassifier.toggle(.weekdays, in: RepeatPatternClassifier.weekdays), [])
        XCTAssertEqual(RepeatPatternClassifier.selectedPreset(RepeatPatternClassifier.weekdays), .weekdays)
        XCTAssertNil(RepeatPatternClassifier.selectedPreset(RepeatPatternClassifier.weekdays.union([.saturday])))
    }

    func testWeekendPresetReplacesTheSelectionAndClearsAnExactMatch() {
        XCTAssertEqual(RepeatPatternClassifier.toggle(.weekends, in: []), RepeatPatternClassifier.weekends)
        XCTAssertEqual(
            RepeatPatternClassifier.toggle(.weekends, in: [.monday, .saturday]),
            RepeatPatternClassifier.weekends
        )
        XCTAssertEqual(RepeatPatternClassifier.toggle(.weekends, in: RepeatPatternClassifier.weekends), [])
        XCTAssertEqual(RepeatPatternClassifier.selectedPreset(RepeatPatternClassifier.weekends), .weekends)
    }

    func testWeekdayOrderFollowsTheLocaleFirstWeekday() {
        var unitedStates = Calendar(identifier: .gregorian)
        unitedStates.locale = Locale(identifier: "en_US")
        XCTAssertEqual(Weekday.ordered(calendar: unitedStates).first, .sunday)

        var poland = Calendar(identifier: .gregorian)
        poland.locale = Locale(identifier: "pl_PL")
        XCTAssertEqual(Weekday.ordered(calendar: poland).first, .monday)
        XCTAssertEqual(
            Weekday.sorted([.sunday, .monday, .wednesday], calendar: poland),
            [.monday, .wednesday, .sunday]
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

final class ClockFormatTests: XCTestCase {
    func testUnitedStatesUsesTwelveHourClock() {
        let parts = ClockFormat.parts(hour: 15, minute: 5, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(parts.time, "3:05")
        XCTAssertTrue(parts.period.localizedCaseInsensitiveContains("pm"))
    }

    func testPolandUsesTwentyFourHourClock() {
        let parts = ClockFormat.parts(hour: 15, minute: 5, locale: Locale(identifier: "pl_PL"))
        XCTAssertEqual(parts.time, "15:05")
        XCTAssertEqual(parts.period, "")
    }
}

final class AlarmLibraryTests: XCTestCase {
    func testGroupSwitchRemembersWhichAlarmsWereOn() {
        var library = AlarmLibrary()
        let group = library.addGroup(name: "Work")
        library.upsert(alarm(hour: 7, group: group.id, enabled: true))
        library.upsert(alarm(hour: 8, group: group.id, enabled: false))
        library.setGroupEnabled(false, groupID: group.id)
        XCTAssertFalse(library.groups[0].isEnabled)
        XCTAssertTrue(library.alarms.allSatisfy { $0.isEnabled == false })
        XCTAssertEqual(library.alarms.first { $0.schedule.hour == 7 }?.resumeWhenGroupEnables, true)
        XCTAssertEqual(library.alarms.first { $0.schedule.hour == 8 }?.resumeWhenGroupEnables, false)

        library.setGroupEnabled(true, groupID: group.id)
        XCTAssertEqual(library.alarms.first { $0.schedule.hour == 7 }?.isEnabled, true)
        XCTAssertEqual(library.alarms.first { $0.schedule.hour == 8 }?.isEnabled, false)
        XCTAssertTrue(library.alarms.allSatisfy { $0.resumeWhenGroupEnables == nil })
    }

    func testAlarmAddedToDisabledGroupStaysOffUntilTheGroupReturns() {
        var library = AlarmLibrary()
        let group = library.addGroup(name: "Work")
        library.setGroupEnabled(false, groupID: group.id)
        library.upsert(alarm(hour: 6, group: group.id, enabled: true))
        let stored = library.alarms[0]
        XCTAssertFalse(stored.isEnabled)
        XCTAssertEqual(stored.resumeWhenGroupEnables, true)
        library.setGroupEnabled(true, groupID: group.id)
        XCTAssertTrue(library.alarms[0].isEnabled)
    }

    func testDeletingDisabledGroupRestoresRememberedAlarms() {
        var library = AlarmLibrary()
        let group = library.addGroup(name: "Work")
        let original = alarm(hour: 7, group: group.id, enabled: true)
        library.upsert(original)
        library.setGroupEnabled(false, groupID: group.id)
        library.deleteGroup(id: group.id)
        XCTAssertTrue(library.groups.isEmpty)
        XCTAssertNil(library.alarms[0].groupID)
        XCTAssertTrue(library.alarms[0].isEnabled)
    }

    func testIndividualToggleWhileGroupIsOffOnlyUpdatesTheMemory() {
        var library = AlarmLibrary()
        let group = library.addGroup(name: "Work")
        let item = alarm(hour: 7, group: group.id, enabled: true)
        library.upsert(item)
        library.setGroupEnabled(false, groupID: group.id)
        library.setEnabled(false, alarmID: item.id)
        XCTAssertFalse(library.alarms[0].isEnabled)
        XCTAssertEqual(library.alarms[0].resumeWhenGroupEnables, false)
        library.setGroupEnabled(true, groupID: group.id)
        XCTAssertFalse(library.alarms[0].isEnabled)
    }

    private func alarm(hour: Int, group: UUID?, enabled: Bool) -> Alarm {
        Alarm(
            id: UUID(),
            schedule: .wallClock(hour: hour, minute: 0, repeatDays: []),
            label: "\(hour)",
            soundID: "classic",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: enabled,
            groupID: group,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
    }
}

final class AlarmSyncPlanTests: XCTestCase {
    func testFirstSyncSchedulesEnabledAlarmsOnly() {
        let on = sample(enabled: true)
        let off = sample(enabled: false)
        let plan = AlarmSyncPlan.make(previous: [], current: [on, off])
        XCTAssertEqual(plan.schedule, [on.id])
        XCTAssertTrue(plan.cancel.isEmpty)
    }

    func testDisablingCancelsAndEditingReschedules() {
        let original = sample(enabled: true)
        var edited = original
        edited = Alarm(
            id: original.id,
            schedule: .wallClock(hour: 8, minute: 30, repeatDays: []),
            label: original.label,
            soundID: original.soundID,
            snoozeEnabled: original.snoozeEnabled,
            snoozeMinutes: original.snoozeMinutes,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let changed = AlarmSyncPlan.make(previous: [original], current: [edited])
        XCTAssertEqual(changed.schedule, [original.id])
        var disabled = edited
        disabled.isEnabled = false
        let off = AlarmSyncPlan.make(previous: [edited], current: [disabled])
        XCTAssertEqual(off.cancel, [original.id])
        XCTAssertTrue(off.schedule.isEmpty)
    }

    func testDeletingAnEnabledAlarmCancelsIt() {
        let alarm = sample(enabled: true)
        let plan = AlarmSyncPlan.make(previous: [alarm], current: [])
        XCTAssertEqual(plan.cancel, [alarm.id])
    }

    private func sample(enabled: Bool) -> Alarm {
        Alarm(
            id: UUID(),
            schedule: .wallClock(hour: 7, minute: 0, repeatDays: [.monday]),
            label: "Morning",
            soundID: "classic",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: enabled,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
    }
}

final class PermissionTests: XCTestCase {
    func testInviteAcceptAndRevoke() throws {
        var center = PermissionCenter()
        let owner = Participant(id: UUID(), displayName: "Maja")
        let friend = Participant(id: UUID(), displayName: "Ola")
        let invite = center.createInvite(owner: owner, now: .now, code: "ABCD2345", secret: "s")
        XCTAssertThrowsError(try center.authorize(sender: friend.id, recipient: owner.id))
        XCTAssertThrowsError(try center.accept(code: "ABCD2345", grantee: owner, now: .now)) { error in
            XCTAssertEqual(error as? PermissionError, .cannotAcceptOwnInvite)
        }
        let active = try center.accept(code: "ABCD2345", grantee: friend, now: .now)
        XCTAssertEqual(active.state, .active)
        XCTAssertEqual(try center.authorize(sender: friend.id, recipient: owner.id).id, invite.id)
        XCTAssertThrowsError(try center.authorize(sender: owner.id, recipient: friend.id))
        let revoked = try center.revoke(grantID: invite.id, by: owner.id)
        XCTAssertEqual(revoked.state, .revoked)
        XCTAssertThrowsError(try center.authorize(sender: friend.id, recipient: owner.id))
    }

    func testStrangerCannotRevoke() {
        var center = PermissionCenter()
        let owner = Participant(id: UUID(), displayName: "Maja")
        let invite = center.createInvite(owner: owner, now: .now, code: "ZZZZZZZZ", secret: "s")
        XCTAssertThrowsError(try center.revoke(grantID: invite.id, by: UUID())) { error in
            XCTAssertEqual(error as? PermissionError, .notAllowed)
        }
    }

    func testRemoteUpsertCannotOverwriteALocalAlarm() throws {
        let owner = Participant(id: UUID(), displayName: "Maja")
        let friend = Participant(id: UUID(), displayName: "Ola")
        var center = PermissionCenter()
        let invite = center.createInvite(owner: owner, now: .now, code: "CODECODE", secret: "s")
        let grant = try center.accept(code: "CODECODE", grantee: friend, now: .now)
        let local = Alarm(
            id: UUID(),
            schedule: .wallClock(hour: 6, minute: 0, repeatDays: []),
            label: "Mine",
            soundID: "classic",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        var library = AlarmLibrary(alarms: [local], groups: [])
        let attack = RemoteAlarmCommand(
            id: UUID(),
            grantID: grant.id,
            senderID: friend.id,
            recipientID: owner.id,
            action: .cancel,
            createdAt: .now,
            alarm: nil,
            alarmID: local.id,
            enabled: nil
        )
        XCTAssertThrowsError(try RemoteCommandApplier.apply(command: attack, grant: grant, library: &library)) { error in
            XCTAssertEqual(error as? ApplyError, .notOwnedBySender)
        }
        XCTAssertEqual(library.alarms.count, 1)
    }

    func testTriggerNowAndCancelRoundTrip() throws {
        let owner = Participant(id: UUID(), displayName: "Maja")
        let friend = Participant(id: UUID(), displayName: "Ola")
        var center = PermissionCenter()
        let created = center.createInvite(owner: owner, now: .now, code: "RING1234", secret: "s")
        let grant = try center.accept(code: created.inviteCode, grantee: friend, now: .now)
        let alarm = Alarm(
            id: UUID(),
            schedule: .oneShot(fireAt: Date().addingTimeInterval(3)),
            label: "Now",
            soundID: "classic",
            snoozeEnabled: false,
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
            recipientID: owner.id,
            action: .triggerNow,
            createdAt: .now,
            alarm: alarm,
            alarmID: alarm.id,
            enabled: true
        )
        var library = AlarmLibrary()
        try RemoteCommandApplier.apply(command: command, grant: grant, library: &library)
        XCTAssertEqual(library.alarms.count, 1)
        XCTAssertTrue(library.alarms[0].origin.isOwned(by: friend.id))
        XCTAssertEqual(library.alarms[0].origin.senderName, "Ola")
        let cancel = RemoteAlarmCommand(
            id: UUID(),
            grantID: grant.id,
            senderID: friend.id,
            recipientID: owner.id,
            action: .cancel,
            createdAt: .now,
            alarm: nil,
            alarmID: alarm.id,
            enabled: nil
        )
        try RemoteCommandApplier.apply(command: cancel, grant: grant, library: &library)
        XCTAssertTrue(library.alarms.isEmpty)
    }

    func testRevokedGrantRejectsCommands() throws {
        let owner = Participant(id: UUID(), displayName: "Maja")
        let friend = Participant(id: UUID(), displayName: "Ola")
        var center = PermissionCenter()
        let created = center.createInvite(owner: owner, now: .now, code: "REVOKE01", secret: "s")
        var grant = try center.accept(code: created.inviteCode, grantee: friend, now: .now)
        grant = try center.revoke(grantID: grant.id, by: friend.id)
        let command = RemoteAlarmCommand(
            id: UUID(),
            grantID: grant.id,
            senderID: friend.id,
            recipientID: owner.id,
            action: .upsert,
            createdAt: .now,
            alarm: Alarm(
                id: UUID(),
                schedule: .wallClock(hour: 1, minute: 2, repeatDays: []),
                label: "Nope",
                soundID: "classic",
                snoozeEnabled: false,
                snoozeMinutes: 9,
                isEnabled: true,
                groupID: nil,
                songLink: nil,
                origin: .local,
                resumeWhenGroupEnables: nil
            ),
            alarmID: nil,
            enabled: nil
        )
        var library = AlarmLibrary()
        XCTAssertThrowsError(try RemoteCommandApplier.apply(command: command, grant: grant, library: &library))
        XCTAssertTrue(library.alarms.isEmpty)
    }

    func testInviteCodeUsesUnambiguousAlphabet() {
        let bytes: [UInt8] = [0, 1, 10, 255]
        var index = 0
        let code = InviteCode.make(length: 4) {
            let byte = bytes[index]
            index += 1
            return byte
        }
        XCTAssertEqual(code.count, 4)
        XCTAssertTrue(code.allSatisfy { InviteCode.alphabet.contains($0) })
        XCTAssertFalse(code.contains("0"))
        XCTAssertFalse(code.contains("O"))
        XCTAssertFalse(code.contains("1"))
        XCTAssertFalse(code.contains("I"))
    }
}

final class SongLinkTests: XCTestCase {
    func testSupportedLinks() {
        XCTAssertEqual(SongLink.parse("https://open.spotify.com/track/abc")?.service, .spotify)
        XCTAssertEqual(SongLink.parse("spotify:track:abc")?.service, .spotify)
        XCTAssertEqual(SongLink.parse("https://youtu.be/dQw4w9WgXcQ")?.service, .youTube)
        XCTAssertEqual(SongLink.parse("https://music.youtube.com/watch?v=abc")?.service, .youTube)
        XCTAssertEqual(SongLink.parse("https://music.apple.com/pl/album/x/123")?.service, .appleMusic)
        XCTAssertEqual(SongLink.parse("music.apple.com/us/song/x/1")?.service, .appleMusic)
    }

    func testRejectsOtherWebsitesAndBlankText() {
        XCTAssertNil(SongLink.parse("https://example.com/song"))
        XCTAssertNil(SongLink.parse("   "))
        XCTAssertNil(SongLink.parse("not a url %%"))
    }
}

final class TrimWindowTests: XCTestCase {
    func testClampsToThirtySeconds() {
        let window = TrimWindow(start: 0, end: 45).clamped(to: 120)
        XCTAssertEqual(window?.duration ?? -1, 30, accuracy: 0.001)
    }

    func testSwapsReversedHandles() {
        let window = TrimWindow(start: 12, end: 4).clamped(to: 20)
        XCTAssertEqual(window?.start ?? -1, 4, accuracy: 0.001)
        XCTAssertEqual(window?.end ?? -1, 12, accuracy: 0.001)
    }

    func testRejectsTinyAssets() {
        XCTAssertNil(TrimWindow(start: 0, end: 1).clamped(to: 0.1))
    }

    func testNegativeStartIsPulledToZero() {
        let window = TrimWindow(start: -5, end: 8).clamped(to: 40)
        XCTAssertEqual(window?.start ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(window?.end ?? -1, 8, accuracy: 0.001)
    }
}

final class AudioTrimmerTests: XCTestCase {
    func testTrimKeepsTheSelectedSecond() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("tone.wav")
        let destination = directory.appendingPathComponent("clip.caf")
        try WAVFixture.write(to: source, seconds: 2)
        let before = try AudioTrimmer.duration(of: source)
        XCTAssertEqual(before, 2, accuracy: 0.05)
        try await AudioTrimmer.trim(source: source, window: TrimWindow(start: 0.5, end: 1.5), destination: destination)
        let after = try AudioTrimmer.duration(of: destination)
        XCTAssertEqual(after, 1, accuracy: 0.08)
    }
}

enum WAVFixture {
    static func write(to url: URL, seconds: Double, sampleRate: Int = 44_100) throws {
        let frames = Int(Double(sampleRate) * seconds)
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.append(uint32(UInt32(36 + frames * 2)))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        data.append(uint32(16))
        data.append(uint16(1))
        data.append(uint16(1))
        data.append(uint32(UInt32(sampleRate)))
        data.append(uint32(UInt32(sampleRate * 2)))
        data.append(uint16(2))
        data.append(uint16(16))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.append(uint32(UInt32(frames * 2)))
        for index in 0..<frames {
            let sample = sin(2 * Double.pi * 440 * Double(index) / Double(sampleRate))
            var value = Int16(sample * 8000).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        try data.write(to: url)
    }

    private static func uint32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }

    private static func uint16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}
