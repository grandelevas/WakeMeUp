import AVFoundation
import CloudKit
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

    func testOneSoundAppliesToChosenAlarmsOnly() {
        var library = AlarmLibrary()
        let first = alarm(hour: 6, group: nil, enabled: true)
        let second = alarm(hour: 7, group: nil, enabled: true)
        let third = alarm(hour: 8, group: nil, enabled: true)
        library.upsert(first)
        library.upsert(second)
        library.upsert(third)
        library.setSound("bell", alarmIDs: [first.id, second.id])
        XCTAssertEqual(library.alarm(first.id)?.soundID, "bell")
        XCTAssertEqual(library.alarm(second.id)?.soundID, "bell")
        XCTAssertEqual(library.alarm(third.id)?.soundID, "classic")
    }

    func testListMoveReordersGroupsByOffset() {
        var library = AlarmLibrary()
        let morning = library.addGroup(name: "Morning")
        let work = library.addGroup(name: "Work")
        let night = library.addGroup(name: "Night")
        library.moveGroups(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(library.groups.map(\.id), [night.id, morning.id, work.id])
        XCTAssertEqual(library.groups.map(\.sortIndex), [0, 1, 2])
    }

    func testGroupSelectionCircleSelectsAndClearsEveryAlarm() {
        let first = UUID()
        let second = UUID()
        XCTAssertEqual(GroupSelection.mark(alarmIDs: [first, second], selected: []), .none)
        let all = GroupSelection.toggle(alarmIDs: [first, second], selected: [])
        XCTAssertEqual(GroupSelection.mark(alarmIDs: [first, second], selected: all), .all)
        let partial = GroupSelection.toggle(alarmIDs: [second], selected: all)
        XCTAssertEqual(GroupSelection.mark(alarmIDs: [first, second], selected: partial), .partial)
        XCTAssertEqual(GroupSelection.toggle(alarmIDs: [], selected: partial), partial)
    }

    func testGroupOrderSurvivesRelaunchAndAMove() throws {
        let first = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!
        let saved = """
        {"alarms":[],"groups":[
          {"id":"\(first.uuidString)","name":"Weekdays","isEnabled":true,"symbol":"folder"},
          {"id":"\(second.uuidString)","name":"Weekend","isEnabled":true,"symbol":"sun.max"}
        ]}
        """
        var library = try JSONDecoder().decode(AlarmLibrary.self, from: Data(saved.utf8))
        library.normalizeGroupOrder()
        XCTAssertEqual(library.groups.map(\.name), ["Weekdays", "Weekend"])
        XCTAssertEqual(library.groups.map(\.sortIndex), [0, 1])
        library.moveGroup(second, before: first)
        XCTAssertEqual(library.groups.map(\.name), ["Weekend", "Weekdays"])
        let data = try JSONEncoder().encode(library)
        var loaded = try JSONDecoder().decode(AlarmLibrary.self, from: data)
        loaded.normalizeGroupOrder()
        XCTAssertEqual(loaded.groups.map(\.name), ["Weekend", "Weekdays"])
    }

    func testCollapsedGroupsStayCollapsed() {
        let name = "wakito.tests.group-expansion"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let id = UUID()
        XCTAssertTrue(GroupExpansionStore.isExpanded(id, defaults: defaults))
        GroupExpansionStore.setExpanded(false, id: id, defaults: defaults)
        XCTAssertFalse(GroupExpansionStore.isExpanded(id, defaults: defaults))
        GroupExpansionStore.setExpanded(true, id: id, defaults: defaults)
        XCTAssertTrue(GroupExpansionStore.isExpanded(id, defaults: defaults))
    }

    func testRenamingAGroupKeepsItsAlarms() {
        var library = AlarmLibrary()
        let group = library.addGroup(name: "Work", symbol: "folder")
        library.upsert(alarm(hour: 7, group: group.id, enabled: true))
        library.updateGroup(id: group.id, name: "  Office ", symbol: "briefcase")
        XCTAssertEqual(library.group(group.id)?.name, "Office")
        XCTAssertEqual(library.group(group.id)?.symbol, "briefcase")
        XCTAssertEqual(library.alarms[0].groupID, group.id)
        XCTAssertTrue(library.alarms[0].isEnabled)
    }

    func testMovingAnAlarmIntoADisabledGroupTurnsItOffUntilTheGroupReturns() {
        var library = AlarmLibrary()
        let group = library.addGroup(name: "Work")
        let item = alarm(hour: 7, group: nil, enabled: true)
        library.upsert(item)
        library.setGroupEnabled(false, groupID: group.id)
        library.moveAlarm(item.id, to: group.id)
        XCTAssertEqual(library.alarms[0].groupID, group.id)
        XCTAssertFalse(library.alarms[0].isEnabled)
        XCTAssertEqual(library.alarms[0].resumeWhenGroupEnables, true)
        library.moveAlarm(item.id, to: nil)
        XCTAssertNil(library.alarms[0].groupID)
        XCTAssertTrue(library.alarms[0].isEnabled)
        XCTAssertNil(library.alarms[0].resumeWhenGroupEnables)
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

    func testRemoteAlarmsLeaveTheLocalSections() {
        var library = AlarmLibrary()
        let group = library.addGroup(name: "Work")
        let ownGrouped = alarm(hour: 7, group: group.id, enabled: true)
        let ownLoose = alarm(hour: 8, group: nil, enabled: true)
        let remoteGrouped = alarm(
            hour: 9,
            group: group.id,
            enabled: true,
            origin: .remote(senderID: UUID(), senderName: "Ola", commandID: UUID())
        )
        let remoteLoose = alarm(
            hour: 10,
            group: nil,
            enabled: true,
            origin: .remote(senderID: UUID(), senderName: "Jan", commandID: UUID())
        )
        library.upsert(ownGrouped)
        library.upsert(ownLoose)
        library.upsert(remoteGrouped)
        library.upsert(remoteLoose)

        XCTAssertEqual(library.ownAlarms(in: group.id).map(\.id), [ownGrouped.id])
        XCTAssertEqual(library.ownAlarms(in: nil).map(\.id), [ownLoose.id])
        XCTAssertEqual(library.receivedFromOthers.map(\.id), [remoteGrouped.id, remoteLoose.id])
    }

    func testSnapshotWithoutSentAlarmsDecodesAsEmpty() throws {
        let profile = Participant(id: UUID(), displayName: "Maja")
        let snapshot = LibrarySnapshot.empty(profile: profile)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as! [String: Any]
        object.removeValue(forKey: "sentAlarms")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try decoder.decode(LibrarySnapshot.self, from: stripped)
        XCTAssertEqual(decoded.sentAlarms, [])
        XCTAssertEqual(decoded.profile.displayName, "Maja")

        let stored = SentAlarm(
            alarm: alarm(hour: 6, group: nil, enabled: true),
            recipientID: UUID(),
            recipientName: "Ola",
            sentAt: Date(timeIntervalSince1970: 1_700_000_000),
            commandID: UUID()
        )
        var withSent = snapshot
        withSent.sentAlarms = [stored]
        let roundTrip = try decoder.decode(LibrarySnapshot.self, from: encoder.encode(withSent))
        XCTAssertEqual(roundTrip.sentAlarms, [stored])
        XCTAssertTrue(roundTrip.library.alarms.isEmpty)
    }

    private func alarm(hour: Int, group: UUID?, enabled: Bool, origin: AlarmOrigin = .local) -> Alarm {
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
            origin: origin,
            resumeWhenGroupEnables: nil
        )
    }
}

final class ShareInviteCleanupTests: XCTestCase {
    func testFailedInviteIsNotKept() {
        var center = PermissionCenter()
        let owner = Participant(id: UUID(), displayName: "Maja")
        _ = center.createInvite(owner: owner, now: .now, code: "ABC", secret: "secret")
        center.removeUnsharedInvites()
        XCTAssertTrue(center.grants.isEmpty)
    }

    func testSavedShareIsKept() {
        var center = PermissionCenter()
        var grant = center.createInvite(owner: Participant(id: UUID(), displayName: "Maja"), now: .now, code: "ABC", secret: "s")
        grant.cloudKitRootRecordName = "grant-1"
        center.replace(grant)
        center.removeUnsharedInvites()
        XCTAssertEqual(center.grants.count, 1)
    }

    func testCloudKitErrorIncludesTheCode() {
        let error = CKError(.serverRejectedRequest)
        let text = CloudKitErrorText.message(for: error)
        XCTAssertTrue(text.contains("CKError \(CKError.Code.serverRejectedRequest.rawValue)"))
    }
}

final class SupportTenureTests: XCTestCase {
    func testMilestonesFollowTheFirstUseDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let afterFiveMonths = calendar.date(from: DateComponents(year: 2024, month: 6, day: 15))!
        XCTAssertTrue(SupportMilestone.oneMonth.isUnlocked(firstUse: start, now: afterFiveMonths, calendar: calendar))
        XCTAssertFalse(SupportMilestone.sixMonths.isUnlocked(firstUse: start, now: afterFiveMonths, calendar: calendar))
        let afterTwoYears = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        XCTAssertTrue(SupportMilestone.twoYears.isUnlocked(firstUse: start, now: afterTwoYears, calendar: calendar))
        XCTAssertFalse(SupportMilestone.threeYears.isUnlocked(firstUse: start, now: afterTwoYears, calendar: calendar))
    }

    func testFirstUseKeepsTheEarlierDate() {
        let local = UserDefaults(suiteName: "wakito.tenure.local.\(UUID().uuidString)")!
        let cloud = MemoryFirstUseStore()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_800_000_000)
        local.set(newer.timeIntervalSince1970, forKey: SupportTenureStore.key)
        cloud.set(older.timeIntervalSince1970, forKey: SupportTenureStore.key)
        let first = SupportTenureStore.ensureFirstUse(now: Date(), local: local, cloud: cloud)
        XCTAssertEqual(first.timeIntervalSince1970, older.timeIntervalSince1970, accuracy: 0.5)
        let stored = (local.object(forKey: SupportTenureStore.key) as? NSNumber)?.doubleValue ?? 0
        XCTAssertEqual(stored, older.timeIntervalSince1970, accuracy: 0.5)
    }
}

private final class MemoryFirstUseStore: FirstUseStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

final class LocalAchievementTests: XCTestCase {

    func testPlaceholderContentDecodesWithZeroRaised() throws {
        let json = """
        {"schemaVersion":1,"currency":"EUR","disclosure":{"en":"e","pl":"p"},"campaign":{"id":"placeholder","title":{"en":"t","pl":"t"},"who":{"en":"w","pl":"w"},"why":{"en":"y","pl":"y"},"photoURL":"","goalAmount":0,"raisedAmount":0,"date":"2026-11-19","linkURL":""},"history":[]}
        """
        let document = try AchievementsDocument.decode(Data(json.utf8))
        XCTAssertEqual(document.campaign?.raisedAmount, 0)
        XCTAssertEqual(document.totalDonated, 0)
        XCTAssertEqual(document.peopleHelped, 0)
        XCTAssertEqual(document.campaign?.progress, 0)
        XCTAssertNil(document.visibleUserCount)
        XCTAssertNil(document.campaign?.description)
        XCTAssertNil(document.campaign?.goalNote)
        XCTAssertNil(document.campaign?.photos)
        XCTAssertNil(document.campaign?.updates)
        XCTAssertNil(document.campaign?.thanks)
        XCTAssertEqual(document.campaign?.hasStory, false)
    }

    func testLegacyCampaignFileOmitsTheOptionalStory() throws {
        let document = try AchievementsDocument.decode(try Self.fixture("achievements-legacy"))
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.campaign?.id, "placeholder")
        XCTAssertEqual(document.campaign?.raisedAmount, 0)
        XCTAssertNil(document.campaign?.description)
        XCTAssertNil(document.campaign?.goalNote)
        XCTAssertNil(document.campaign?.photos)
        XCTAssertNil(document.campaign?.updates)
        XCTAssertNil(document.campaign?.thanks)
        XCTAssertEqual(document.campaign?.gallery.isEmpty, true)
        XCTAssertEqual(document.campaign?.hasStory, false)
    }

    func testRichCampaignFileDecodesStoryPhotosUpdatesAndThanks() throws {
        let campaign = try XCTUnwrap(AchievementsDocument.decode(try Self.fixture("achievements-rich")).campaign)
        XCTAssertEqual(campaign.story(languageCode: "pl"), [
            "Pierwsza część historii.",
            "Druga część, po pustej linii."
        ])
        XCTAssertEqual(campaign.story(languageCode: "en").count, 2)
        XCTAssertEqual(campaign.photos?.count, 3)
        XCTAssertEqual(campaign.gallery.map(\.url), [
            "https://example.com/before.jpg",
            "https://example.com/after.jpg"
        ])
        XCTAssertEqual(campaign.gallery[0].visibleCaption?.pl, "Przed")
        XCTAssertNil(campaign.gallery[1].caption)
        XCTAssertEqual(campaign.visibleUpdates.map(\.date), ["2026-11-20", "2026-11-02"])
        XCTAssertEqual(campaign.visibleUpdates[0].visibleTitle?.en, "Handed over")
        XCTAssertNil(campaign.visibleUpdates[1].title)
        XCTAssertEqual(campaign.visibleUpdates[0].gallery.count, 1)
        XCTAssertEqual(campaign.visibleUpdates[1].gallery.isEmpty, true)
        XCTAssertEqual(campaign.visibleThanks.count, 2)
        XCTAssertEqual(campaign.visibleThanks[0].author, "Anna")
        XCTAssertEqual(campaign.visibleThanks[0].video?.absoluteString, "https://example.com/anna.mp4")
        XCTAssertNil(campaign.visibleThanks[1].author)
        XCTAssertNil(campaign.visibleThanks[1].photo)
        XCTAssertEqual(campaign.progress, 0.4, accuracy: 0.001)
        XCTAssertTrue(campaign.hasStory)
    }

    func testGoalNoteDecodesWhenPresentAndStaysNilWhenAbsent() throws {
        let without = """
        {"schemaVersion":1,"currency":"EUR","disclosure":{"en":"e","pl":"p"},"campaign":{"id":"x","title":{"en":"t","pl":"t"},"who":{"en":"w","pl":"w"},"why":{"en":"y","pl":"y"},"photoURL":"","goalAmount":100000,"raisedAmount":0,"date":"2026-11-20","linkURL":""},"history":[]}
        """
        let absent = try XCTUnwrap(AchievementsDocument.decode(Data(without.utf8)).campaign)
        XCTAssertNil(absent.goalNote)
        XCTAssertNil(absent.visibleGoalNote)
        XCTAssertEqual(absent.goalAmount, 100_000)

        let withNote = """
        {"schemaVersion":1,"currency":"EUR","disclosure":{"en":"e","pl":"p"},"campaign":{"id":"x","title":{"en":"t","pl":"t"},"who":{"en":"w","pl":"w"},"why":{"en":"y","pl":"y"},"photoURL":"","goalAmount":100000,"raisedAmount":0,"date":"2026-11-20","linkURL":"","goalNote":{"pl":"Cel: 100 000 € – czyli 50 000 użytkowników Wakito.","en":"Goal: €100,000 – that's 50,000 Wakito users."}},"history":[]}
        """
        let note = try XCTUnwrap(AchievementsDocument.decode(Data(withNote.utf8)).campaign?.goalNote)
        XCTAssertEqual(note.pl, "Cel: 100 000 € – czyli 50 000 użytkowników Wakito.")
        XCTAssertEqual(note.en, "Goal: €100,000 – that's 50,000 Wakito users.")
    }

    func testEuroAmountsUseTheLocaleThousandsSeparator() {
        let polish = Locale(identifier: "pl_PL")
        let raised = AchievementMoney.format(0, currencyCode: "EUR", locale: polish)
        let goal = AchievementMoney.format(100_000, currencyCode: "EUR", locale: polish)
        let label = "\(raised) / \(goal)"
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(label, "0 € / 100 000 €")
    }

    func testBlankStoryAndEmptyListsStayHidden() throws {
        let json = """
        {"schemaVersion":1,"currency":"EUR","disclosure":{"en":"e","pl":"p"},"campaign":{"id":"x","title":{"en":"t","pl":"t"},"who":{"en":"w","pl":"w"},"why":{"en":"y","pl":"y"},"photoURL":"","goalAmount":1,"raisedAmount":0,"date":"2026-11-20","linkURL":"","description":{"en":"  ","pl":""},"photos":[],"updates":[{"date":"2026-11-20","text":{"en":"","pl":"  "}}],"thanks":[{"text":{"en":"","pl":""},"photoURL":"notaurl"}]},"history":[]}
        """
        let campaign = try XCTUnwrap(AchievementsDocument.decode(Data(json.utf8)).campaign)
        XCTAssertFalse(campaign.hasStory)
        XCTAssertTrue(campaign.gallery.isEmpty)
        XCTAssertTrue(campaign.visibleUpdates.isEmpty)
        XCTAssertTrue(campaign.visibleThanks.isEmpty)
    }

    private static func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: LocalAchievementTests.self)
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        let file = try XCTUnwrap(url, "Missing \(name).json in the test bundle")
        return try Data(contentsOf: file)
    }

    func testMissingOrZeroUserCountStaysHidden() throws {
        let zero = """
        {"schemaVersion":1,"currency":"EUR","disclosure":{"en":"e","pl":"p"},"userCount":0,"userCountDate":"2026-11-20","history":[]}
        """
        let document = try AchievementsDocument.decode(Data(zero.utf8))
        XCTAssertEqual(document.userCount, 0)
        XCTAssertNil(document.visibleUserCount)
    }

    func testPositiveUserCountIsShown() throws {
        let json = """
        {"schemaVersion":1,"currency":"EUR","disclosure":{"en":"e","pl":"p"},"userCount":1234,"userCountDate":"2026-11-20","history":[]}
        """
        let document = try AchievementsDocument.decode(Data(json.utf8))
        XCTAssertEqual(document.visibleUserCount, 1234)
        XCTAssertEqual(document.userCountDate, "2026-11-20")
    }

    func testCommunityFileOverridesTheAchievementsCount() throws {
        let json = """
        {"schemaVersion":1,"currency":"EUR","disclosure":{"en":"e","pl":"p"},"userCount":9,"userCountDate":"2026-11-01","history":[]}
        """
        let document = try AchievementsDocument.decode(Data(json.utf8))
        let hidden = document.applying(community: CommunityCountSnapshot(userCount: 0, userCountDate: "2026-11-20"))
        XCTAssertNil(hidden.visibleUserCount)
        let shown = document.applying(community: CommunityCountSnapshot(userCount: 1234, userCountDate: "2026-11-20"))
        XCTAssertEqual(shown.visibleUserCount, 1234)
        XCTAssertEqual(shown.userCountDate, "2026-11-20")
        let unchanged = document.applying(community: CommunityCountSnapshot(userCount: nil, userCountDate: nil))
        XCTAssertEqual(unchanged.visibleUserCount, 9)
    }
}

final class RemoteAlarmNoticeTests: XCTestCase {
    func testNoticeNamesTheSenderAndTheTime() {
        let text = RemoteAlarmNotice.text(
            sender: "Ola",
            schedule: .wallClock(hour: 6, minute: 30, repeatDays: [])
        )
        let parts = ClockFormat.parts(hour: 6, minute: 30, locale: .current, timeZone: .current)
        XCTAssertTrue(text.contains("Ola"))
        XCTAssertTrue(text.contains(parts.time))
    }
}

final class AppearanceTests: XCTestCase {
    func testDefaultsAreSystemOrangeAndPrimaryIcon() {
        let defaults = UserDefaults(suiteName: "wakito.appearance.\(UUID().uuidString)")!
        XCTAssertEqual(AppearanceRecord.load(from: defaults), .default)
        XCTAssertEqual(AppearanceRecord.default.accent, .orange)
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    func testAppearanceRoundTrip() {
        let defaults = UserDefaults(suiteName: "wakito.appearance.\(UUID().uuidString)")!
        let record = AppearanceRecord(theme: .dark, accent: .teal, icon: .minimal)
        record.save(to: defaults)
        XCTAssertEqual(AppearanceRecord.load(from: defaults), record)
    }

    func testUnknownStoredValuesFallBack() {
        let defaults = UserDefaults(suiteName: "wakito.appearance.\(UUID().uuidString)")!
        defaults.set("nope", forKey: AppearanceKeys.theme)
        defaults.set("nope", forKey: AppearanceKeys.accent)
        defaults.set("nope", forKey: AppearanceKeys.icon)
        XCTAssertEqual(AppearanceRecord.load(from: defaults), .default)
    }

    func testAlternateIconNamesMatchTheAssetCatalog() {
        XCTAssertNil(AppIconChoice.primary.alternateName)
        XCTAssertEqual(AppIconChoice.dark.alternateName, "Dark")
        XCTAssertEqual(AppIconChoice.minimal.alternateName, "Minimal")
        XCTAssertEqual(AppIconChoice.color.alternateName, "Color")
        XCTAssertEqual(AppIconChoice.matching(alternateName: "Color"), .color)
        XCTAssertEqual(AppIconChoice.matching(alternateName: nil), .primary)
        XCTAssertEqual(AppAccent.allCases.count, 8)
    }
}

final class AlarmDeliveryTests: XCTestCase {
    func testGrantedPermissionNeverFallsBackToANotification() {
        let scheduled = AlarmDeliveryPolicy.decide(
            permission: .authorized,
            alarmKitAvailable: true,
            namedSoundError: nil,
            defaultSoundError: nil
        )
        XCTAssertEqual(scheduled, .alarmKit)

        let missingFile = AlarmDeliveryPolicy.decide(
            permission: .authorized,
            alarmKitAvailable: true,
            namedSoundError: "sound not found",
            defaultSoundError: nil
        )
        XCTAssertEqual(missingFile, .alarmKitSystemSound)

        let bothFailed = AlarmDeliveryPolicy.decide(
            permission: .authorized,
            alarmKitAvailable: true,
            namedSoundError: "sound not found",
            defaultSoundError: "schedule rejected"
        )
        XCTAssertEqual(bothFailed, .blocked("schedule rejected"))
    }

    func testNotificationFallbackRequiresDeniedOrUnavailableAlarmKit() {
        XCTAssertEqual(
            AlarmDeliveryPolicy.decide(
                permission: .denied,
                alarmKitAvailable: true,
                namedSoundError: nil,
                defaultSoundError: nil
            ),
            .notificationFallback
        )
        XCTAssertEqual(
            AlarmDeliveryPolicy.decide(
                permission: .authorized,
                alarmKitAvailable: false,
                namedSoundError: nil,
                defaultSoundError: nil
            ),
            .notificationFallback
        )
        XCTAssertEqual(
            AlarmDeliveryPolicy.decide(
                permission: .notDetermined,
                alarmKitAvailable: true,
                namedSoundError: nil,
                defaultSoundError: nil
            ),
            .blocked("Alarm permission has not been granted.")
        )
    }

    func testNamedSoundIsUsedWhenTheFileIsPresent() {
        XCTAssertEqual(
            AlarmSoundResolver.choose(preferredFilename: "classic.wav", present: ["classic.wav"]),
            .named("classic.wav")
        )
        XCTAssertEqual(
            AlarmSoundResolver.choose(preferredFilename: "clip.caf", present: ["clip.caf"]),
            .named("clip.caf")
        )
    }

    func testMissingSoundUsesTheSystemAlarmSound() {
        XCTAssertEqual(
            AlarmSoundResolver.choose(preferredFilename: "classic.wav", present: []),
            .systemDefault
        )
        XCTAssertEqual(
            AlarmSoundResolver.choose(preferredFilename: "missing.caf", present: ["classic.wav"]),
            .systemDefault
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
        let processed = Date(timeIntervalSince1970: 1_700_000_000)
        let soon = WakeNowSchedule.applying(to: alarm, processedAt: processed)
        if case let .oneShot(fireAt) = soon.schedule {
            XCTAssertEqual(fireAt.timeIntervalSince(processed), WakeNowSchedule.leadTime, accuracy: 0.001)
        } else {
            XCTFail("Wake now has to be a one-shot alarm")
        }
        XCTAssertEqual(
            OutgoingVoice.payload(soundID: "voice-1", voiceName: "voice-1", uploaded: false),
            OutgoingVoice.Payload(soundID: SoundCatalog.defaultID, voiceRecordName: nil, warn: true)
        )
        XCTAssertEqual(
            OutgoingVoice.payload(soundID: "classic", voiceName: "voice-1", uploaded: true),
            OutgoingVoice.Payload(soundID: "voice-1", voiceRecordName: "voice-1", warn: false)
        )
        func assetFile() throws -> CKAsset {
            let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).m4a")
            try Data([0]).write(to: file)
            return CKAsset(fileURL: file)
        }
        let production = CKRecord(recordType: VoiceAssetField.recordType)
        VoiceAssetField.assign(try assetFile(), on: production)
        XCTAssertNotNil(production[VoiceAssetField.key])
        XCTAssertNil(production[VoiceAssetField.legacyKey])
        XCTAssertNotNil(VoiceAssetField.asset(from: production))
        let legacy = CKRecord(recordType: VoiceAssetField.recordType)
        legacy[VoiceAssetField.legacyKey] = try assetFile()
        XCTAssertNotNil(VoiceAssetField.asset(from: legacy))
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
        let before = try await AudioTrimmer.duration(of: source)
        XCTAssertEqual(before, 2, accuracy: 0.05)
        try await AudioTrimmer.trim(source: source, window: TrimWindow(start: 0.5, end: 1.5), destination: destination)
        let after = try await AudioTrimmer.duration(of: destination)
        XCTAssertEqual(after, 1, accuracy: 0.08)
        let peak = try Self.peak(of: destination)
        XCTAssertGreaterThan(peak, 0.45)
        XCTAssertLessThan(peak, 0.95)
    }

    func testM4ATrimWritesAPlayableCAF() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("tone.m4a")
        let destination = directory.appendingPathComponent("clip.caf")
        try M4AFixture.write(to: source, seconds: 1.2)
        let before = try await AudioTrimmer.duration(of: source)
        XCTAssertEqual(before, 1.2, accuracy: 0.2)
        try await AudioTrimmer.trim(source: source, window: TrimWindow(start: 0.2, end: 0.9), destination: destination)
        XCTAssertEqual(destination.pathExtension, "caf")
        let after = try await AudioTrimmer.duration(of: destination)
        XCTAssertEqual(after, 0.7, accuracy: 0.2)
        let file = try AVAudioFile(forReading: destination)
        XCTAssertGreaterThan(file.length, 0)
        XCTAssertEqual(file.fileFormat.commonFormat, .pcmFormatInt16)
    }

    func testUnreadableAudioHasNoDuration() async {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).m4a")
        try? Data("not audio".utf8).write(to: url)
        do {
            _ = try await AudioTrimmer.duration(of: url)
            XCTFail("A text file should not have a duration")
        } catch {
            XCTAssertEqual(error as? AudioTrimError, .unreadable)
        }
    }

    func testSpikyAudioStopsAtThePeakCeiling() {
        let gain = AlarmLoudness.gain(peak: 0.5, meanSquare: 0.001)
        XCTAssertEqual(gain * 0.5, AlarmLoudness.peakCeiling, accuracy: 0.001)
    }

    func testSoundFilenamesIncludeTheExtension() {
        let custom = CustomSound(id: "abc", displayName: "Clip", filename: "abc.caf")
        XCTAssertEqual(SoundFiles.alarmKitName(for: "classic", customSounds: []), "classic.wav")
        XCTAssertEqual(SoundFiles.notificationName(for: "classic", customSounds: []), "classic.wav")
        XCTAssertEqual(SoundFiles.alarmKitName(for: "abc", customSounds: [custom]), "abc.caf")
        XCTAssertEqual(SoundFiles.notificationName(for: "abc", customSounds: [custom]), "abc.caf")
        XCTAssertEqual(SoundFiles.alarmKitName(for: "dawn", customSounds: []), "dawn.caf")
        XCTAssertEqual(SoundFiles.notificationName(for: "sleepy", customSounds: []), "sleepy.caf")
    }

    func testNewSoundsSitBesideTheOriginalFive() {
        XCTAssertEqual(SoundCatalog.defaultID, "classic")
        XCTAssertEqual(
            Array(SoundCatalog.bundled.prefix(5).map(\.id)),
            ["classic", "chime", "rise", "pulse", "bell"]
        )
        XCTAssertEqual(
            SoundCatalog.bundled.dropFirst(5).map(\.id),
            ["dawn", "beep", "bells", "digital", "morning", "birds", "marimba", "sleepy"]
        )
        XCTAssertTrue(SoundCatalog.bundled.prefix(5).allSatisfy { $0.fileExtension == "wav" })
        XCTAssertTrue(SoundCatalog.bundled.dropFirst(5).allSatisfy { $0.fileExtension == "caf" })
    }

    private static func peak(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return 0
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return 0 }
        var peak: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(channels[0][frame]))
        }
        return peak
    }
}

enum M4AFixture {
    static func write(to url: URL, seconds: Double, sampleRate: Double = 44_100) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw AudioTrimError.exportFailed
        }
        buffer.frameLength = frames
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(frames) {
                samples[index] = sin(2 * Float.pi * 440 * Float(index) / Float(sampleRate)) * 0.4
            }
        } else if let samples = buffer.int16ChannelData?[0] {
            for index in 0..<Int(frames) {
                samples[index] = Int16(sin(2 * Float.pi * 440 * Float(index) / Float(sampleRate)) * 8_000)
            }
        }
        try file.write(from: buffer)
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

final class InviteLinkPolicyTests: XCTestCase {
    func testPendingInviteStaysOpenToTheLink() {
        XCTAssertTrue(InviteLinkPolicy.allowsAnyoneWithLink(grantState: .pending))
    }

    func testAcceptedOrRevokedInviteStopsNewPeople() {
        XCTAssertFalse(InviteLinkPolicy.allowsAnyoneWithLink(grantState: .active))
        XCTAssertFalse(InviteLinkPolicy.allowsAnyoneWithLink(grantState: .revoked))
    }

    func testOnlyHTTPSLinksCanBeCopied() {
        XCTAssertEqual(
            InviteLinkPolicy.url(from: " https://www.icloud.com/share/abc ")?.absoluteString,
            "https://www.icloud.com/share/abc"
        )
        XCTAssertNil(InviteLinkPolicy.url(from: "OLA-DEMO"))
        XCTAssertNil(InviteLinkPolicy.url(from: "http://example.com/share"))
    }

    func testCloudShareLinkIsRecognizedInsideTheInviteMessage() {
        let link = "https://www.icloud.com/share/abc123"
        XCTAssertTrue(InviteLinkPolicy.isCloudShare(URL(string: link)!))
        XCTAssertFalse(InviteLinkPolicy.isCloudShare(URL(string: "https://example.com/share/abc")!))
        XCTAssertEqual(
            InviteLinkPolicy.cloudShareURL(from: "Open this link in Wakito. \(link)")?.absoluteString,
            link
        )
        XCTAssertNil(InviteLinkPolicy.cloudShareURL(from: "no link here"))
    }

    func testAcceptedInviteeIsVisibleToTheOwnerAndCanSetThatPhone() {
        let owner = Participant(id: UUID(), displayName: "A")
        let friend = Participant(id: UUID(), displayName: "B")
        var grant = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/abc",
            secret: "s",
            owner: owner,
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: "grant",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "__defaultOwner__"
        )
        XCTAssertEqual(ShareRoster.canSetAlarmsHere(profileID: owner.id, grants: [grant]).count, 1)
        XCTAssertTrue(ShareRoster.phonesICanSet(profileID: owner.id, grants: [grant]).isEmpty)
        grant.grantee = friend
        grant.state = .active
        XCTAssertEqual(ShareRoster.canSetAlarmsHere(profileID: owner.id, grants: [grant]).first?.grantee?.displayName, "B")
        XCTAssertEqual(ShareRoster.phonesICanSet(profileID: friend.id, grants: [grant]).first?.owner.displayName, "A")
    }
}

final class AsyncDeadlineTests: XCTestCase {
    func testAHungCallBecomesATimeout() async {
        do {
            _ = try await AsyncDeadline.run(seconds: 0.05) {
                try await Task.sleep(for: .seconds(5))
                return "late"
            }
            XCTFail("The hung call should time out")
        } catch {
            XCTAssertEqual(error as? AsyncDeadlineError, .timedOut)
        }
    }

    func testAFastCallReturnsBeforeTheDeadline() async throws {
        let value = try await AsyncDeadline.run(seconds: 2) { "ready" }
        XCTAssertEqual(value, "ready")
    }
}

final class ReleaseNotesTests: XCTestCase {
    func testNewestEntryComesFirstAndBuildIsOptional() throws {
        let json = """
        {"entries":[
          {"version":"1.0.0","date":"2026-11-19","changes":{"en":["Older"],"pl":["Starsze"]}},
          {"version":"1.0.0","build":22,"date":"2026-11-20","changes":{"en":["Newer"],"pl":["Nowsze"]}}
        ]}
        """.data(using: .utf8)!
        let notes = try ReleaseNotesDocument.decode(json).newestFirst
        XCTAssertEqual(notes.map(\.heading), ["1.0.0 (22)", "1.0.0"])
        XCTAssertEqual(notes[0].bullets(for: "pl"), ["Nowsze"])
        XCTAssertEqual(notes[1].bullets(for: "fr"), ["Older"])
    }

    func testBundledHistoryStartsWithTheLatestChange() {
        let notes = ReleaseNotesDocument.bundled().newestFirst
        XCTAssertGreaterThanOrEqual(notes.count, 7)
        XCTAssertEqual(notes.first?.date, notes.map(\.date).max())
        let english = notes.flatMap { $0.bullets(for: "en") }.joined(separator: " ")
        XCTAssertTrue(english.contains("full screen"))
        XCTAssertTrue(english.contains("Achievements"))
        XCTAssertFalse(english.localizedCaseInsensitiveContains("Przypomnij"))
    }

    func testWhatsNewAppearsOnlyAfterTheBuildChanges() {
        let name = "wakito.tests.release-notes"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertFalse(ReleaseNotesPrompt.shouldShow(currentBuild: "22", defaults: defaults))
        ReleaseNotesPrompt.markSeen(currentBuild: "22", defaults: defaults)
        XCTAssertFalse(ReleaseNotesPrompt.shouldShow(currentBuild: "22", defaults: defaults))
        XCTAssertTrue(ReleaseNotesPrompt.shouldShow(currentBuild: "23", defaults: defaults))
    }
}

final class VoiceClipPolicyTests: XCTestCase {
    func testAVoiceClipStopsAtTwentySeconds() {
        XCTAssertEqual(VoiceClipPolicy.clamped(0), 0)
        XCTAssertEqual(VoiceClipPolicy.clamped(12), 12)
        XCTAssertEqual(VoiceClipPolicy.clamped(20), 20)
        XCTAssertEqual(VoiceClipPolicy.clamped(45), 20)
        XCTAssertEqual(VoiceClipPolicy.clamped(.nan), 0)
    }

    func testAMissingVoiceFileFallsBackToTheDefaultSound() {
        XCTAssertEqual(VoiceClipPolicy.soundID(installed: true, voiceID: "voice-1"), "voice-1")
        XCTAssertEqual(VoiceClipPolicy.soundID(installed: false, voiceID: "voice-1"), SoundCatalog.defaultID)
        XCTAssertEqual(VoiceClipPolicy.soundID(installed: true, voiceID: nil), SoundCatalog.defaultID)
        XCTAssertEqual(VoiceClipPolicy.soundID(installed: true, voiceID: ""), SoundCatalog.defaultID)
    }

    func testAVoicePathStaysARelativeFilenameInsideTheAppContainer() throws {
        XCTAssertEqual(VoiceFiles.relativeFilename(soundID: "voice-abc"), "voice-abc.m4a")
        XCTAssertFalse(VoiceFiles.relativeFilename(soundID: "/tmp/voice-abc.m4a").contains("/"))
        XCTAssertEqual(VoiceFiles.ringingFilename(stored: "voice-abc.m4a"), "voice-abc.caf")
        XCTAssertEqual(VoiceFiles.ringingFilename(stored: "clip.caf"), "clip.caf")
        let directory = URL(fileURLWithPath: "/tmp/WakeMeUpSounds", isDirectory: true)
        let resolved = VoiceFiles.url(
            relativeFilename: "/var/mobile/Containers/Data/Application/tmp/voice-x.m4a",
            in: directory
        )
        XCTAssertEqual(resolved.lastPathComponent, "voice-x.m4a")
        XCTAssertEqual(
            resolved.deletingLastPathComponent().standardizedFileURL.path,
            directory.standardizedFileURL.path
        )
        XCTAssertEqual(VoiceRecordingFormat.fileExtension, "m4a")
        XCTAssertEqual(VoiceRecordingFormat.settings()[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        let recording = VoiceAudioRoute.recording()
        XCTAssertEqual(recording.category, .playAndRecord)
        XCTAssertTrue(recording.options.contains(.defaultToSpeaker))
        let preview = VoiceAudioRoute.preview()
        XCTAssertEqual(preview.category, .playback)
        XCTAssertTrue(preview.options.contains(.defaultToSpeaker))
        XCTAssertEqual(VoiceClipPolicy.clock(0), "0:00")
        XCTAssertEqual(VoiceClipPolicy.clock(12.8), "0:12")
        XCTAssertEqual(VoiceClipPolicy.clock(20), "0:20")
        XCTAssertEqual(VoiceClipPolicy.clock(65), "0:20")
        XCTAssertEqual(MicrophoneAccess.map(.granted), .granted)
        XCTAssertEqual(MicrophoneAccess.map(.denied), .denied)
        XCTAssertEqual(MicrophoneAccess.map(.undetermined), .undetermined)
    }

    func testInstallingAVoiceKeepsAACAndWritesTheAlarmCAF() throws {
        let directory = try SoundFiles.librarySoundsDirectory()
        let source = directory.appendingPathComponent("src-\(UUID().uuidString).m4a")
        try M4AFixture.write(to: source, seconds: 0.3)
        defer { try? FileManager.default.removeItem(at: source) }
        let id = "voice-\(UUID().uuidString)"
        let sound = try VoiceFiles.install(from: source, soundID: id)
        defer { VoiceFiles.remove(relativeFilename: sound.filename) }
        XCTAssertEqual(sound.filename, "\(id).m4a")
        XCTAssertFalse(sound.filename.contains("/"))
        let stored = VoiceFiles.url(relativeFilename: sound.filename, in: directory)
        XCTAssertTrue(VoiceFileCheck.isStoredAAC(stored))
        XCTAssertGreaterThan(VoiceFileCheck.byteCount(at: stored), 0)
        let ringingName = VoiceFiles.ringingFilename(stored: sound.filename)
        let ringing = directory.appendingPathComponent(ringingName)
        XCTAssertGreaterThan(VoiceFileCheck.byteCount(at: ringing), 0)
        XCTAssertEqual(ringing.pathExtension, "caf")
        XCTAssertEqual(SoundFiles.alarmKitName(for: id, customSounds: [sound]), ringingName)
        XCTAssertEqual(SoundFiles.notificationName(for: id, customSounds: [sound]), ringingName)
        XCTAssertEqual(SoundFiles.previewURL(for: id, customSounds: [sound])?.lastPathComponent, sound.filename)
        let replayed = try AVAudioFile(forReading: stored)
        XCTAssertGreaterThan(replayed.length, 0)
    }
}

final class RemoteCommandGateTests: XCTestCase {
    func testCommandsAlreadyOnTheShareAreSealedWhenTheConnectionStarts() {
        let old = command(action: .triggerNow)
        let applied: Set<UUID> = []
        let sealed = RemoteCommandGate.partition(commands: [old], applied: applied, sealExisting: true)
        XCTAssertTrue(sealed.apply.isEmpty)
        XCTAssertEqual(sealed.seal, [old.id])
        let later = command(action: .upsert)
        let next = RemoteCommandGate.partition(commands: [old, later], applied: Set(sealed.seal), sealExisting: false)
        XCTAssertEqual(next.apply.map(\.id), [later.id])
        XCTAssertTrue(next.seal.isEmpty)
    }

    private func command(action: RemoteAction) -> RemoteAlarmCommand {
        RemoteAlarmCommand(
            id: UUID(),
            grantID: UUID(),
            senderID: UUID(),
            recipientID: UUID(),
            action: action,
            createdAt: .now,
            alarm: nil,
            alarmID: nil,
            enabled: nil
        )
    }
}

final class ContactRosterTests: XCTestCase {
    func testOneMutualConnectionIsASingleContact() {
        let me = UUID()
        let them = UUID()
        var hosted = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/out",
            secret: "s",
            owner: Participant(id: me, displayName: "Me"),
            grantee: Participant(id: them, displayName: "Aleksandra"),
            state: .active,
            createdAt: .now,
            cloudKitRootRecordName: "a",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_me"
        )
        hosted.inviteeName = "Ola"
        let wake = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/back",
            secret: "s2",
            owner: Participant(id: them, displayName: "Aleksandra"),
            grantee: Participant(id: me, displayName: "Me"),
            state: .active,
            createdAt: .now,
            cloudKitRootRecordName: "b",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_them"
        )
        let contacts = ContactRoster.contacts(profileID: me, grants: [hosted, wake])
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].name, "Ola")
        XCTAssertEqual(contacts[0].wakeGrantID, wake.id)
        XCTAssertEqual(contacts[0].hostedGrantID, hosted.id)
        XCTAssertFalse(contacts[0].isPending)
        XCTAssertEqual(contacts[0].memberID, them)
    }

    func testAPendingReturnShareDoesNotDuplicateAConnectedPerson() {
        let me = UUID()
        let them = UUID()
        let acceptedID = UUID()
        let accepted = ShareGrant(
            id: acceptedID,
            inviteCode: "https://www.icloud.com/share/theirs",
            secret: "s",
            owner: Participant(id: them, displayName: "Mateusz"),
            grantee: Participant(id: me, displayName: "Akhi"),
            state: .active,
            createdAt: .now,
            cloudKitRootRecordName: "grant-accepted",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_76b4ce4cbc5b09999462b2f690a9b48a"
        )
        var reciprocal = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/mine",
            secret: "s2",
            owner: Participant(id: me, displayName: "Akhi"),
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: "grant-8CFDCC36-07B5-4392-9CC6-2F21EFFC7B48",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_mine"
        )
        reciprocal.reciprocal = true
        reciprocal.reciprocalForGrantID = acceptedID
        let contacts = ContactRoster.contacts(profileID: me, grants: [accepted, reciprocal])
        XCTAssertEqual(contacts.count, 1)
        XCTAssertFalse(contacts[0].isPending)
        XCTAssertEqual(contacts[0].wakeGrantID, acceptedID)
        XCTAssertEqual(contacts[0].hostedGrantID, reciprocal.id)
        XCTAssertEqual(contacts[0].memberID, them)
        XCTAssertTrue(ContactActionPolicy.canWake(contacts[0]))
        XCTAssertTrue(ContactActionPolicy.canAddToGroup(contacts[0]))
        XCTAssertTrue(GroupButtonPolicy.canAddGroup(contactCount: contacts.count))
        XCTAssertFalse(GroupButtonPolicy.canAddGroup(contactCount: 0))
        XCTAssertFalse(
            MutualInvite.shouldCreateReturnShare(accepted: accepted, profileID: me, existing: [accepted, reciprocal])
        )
        XCTAssertTrue(
            MutualInvite.shouldCreateReturnShare(accepted: accepted, profileID: me, existing: [accepted])
        )
    }
}

final class AlarmNoteTests: XCTestCase {
    func testANoteIsTrimmedTo140CharactersAndBlankBecomesNil() {
        XCTAssertNil(AlarmNote.cleaned("   "))
        XCTAssertEqual(AlarmNote.cleaned("  Bring the keys  "), "Bring the keys")
        let long = String(repeating: "a", count: 1800)
        XCTAssertEqual(AlarmNote.cleaned(long)?.count, 1000)
    }
}

final class SoundPreviewPolicyTests: XCTestCase {
    func testPreviewStaysWithinTenSeconds() {
        XCTAssertEqual(SoundPreviewPolicy.length(fileDuration: 12, requested: nil), 10)
        XCTAssertEqual(SoundPreviewPolicy.length(fileDuration: 4, requested: nil), 4)
        XCTAssertEqual(SoundPreviewPolicy.length(fileDuration: 40, requested: 20), 10)
        XCTAssertEqual(SoundPreviewPolicy.length(fileDuration: 40, requested: 3), 3)
        XCTAssertEqual(SoundPreviewPolicy.length(fileDuration: 8, requested: 0), 0)
    }
}

private final class MemoryStringStore: StringKeyValueStore {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        values[key]
    }

    func setString(_ value: String, forKey key: String) {
        values[key] = value
    }
}

final class OwnNamePersistenceTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "wakito.tests.own-name.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testNameSurvivesANewStoreAndAnEmptyWrite() {
        let cloud = MemoryStringStore()
        let store = OwnNameStore(local: UserDefaultsStringStore(defaults: defaults), cloud: cloud)
        store.save("Mateusz")
        store.save("")
        store.save("   ")
        XCTAssertEqual(store.load(), "Mateusz")
        XCTAssertEqual(defaults.string(forKey: OwnNameStore.key), "Mateusz")

        let reopened = OwnNameStore(local: UserDefaultsStringStore(defaults: defaults), cloud: MemoryStringStore())
        XCTAssertEqual(reopened.load(), "Mateusz")
    }

    func testEmptyCloudValueDoesNotClearTheSavedName() {
        let defaultsStore = UserDefaultsStringStore(defaults: defaults)
        let cloud = MemoryStringStore()
        cloud.setString("Ola", forKey: OwnNameStore.key)
        let store = OwnNameStore(local: defaultsStore, cloud: cloud)
        XCTAssertEqual(store.load(), "Ola")
        XCTAssertEqual(defaults.string(forKey: OwnNameStore.key), "Ola")

        cloud.setString("", forKey: OwnNameStore.key)
        XCTAssertEqual(store.load(), "Ola")
        XCTAssertEqual(defaults.string(forKey: OwnNameStore.key), "Ola")
    }

    func testSavedNameWinsOverADifferentCloudName() {
        defaults.set("Mateusz", forKey: OwnNameStore.key)
        let cloud = MemoryStringStore()
        cloud.setString("Someone", forKey: OwnNameStore.key)
        let store = OwnNameStore(local: UserDefaultsStringStore(defaults: defaults), cloud: cloud)
        XCTAssertEqual(store.load(), "Mateusz")
        XCTAssertEqual(cloud.string(forKey: OwnNameStore.key), "Someone")
    }

    func testEmptyFetchedNameDoesNotClearTheStoredLabel() {
        let owner = Participant(id: UUID(), displayName: "Mateusz")
        var local = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/abc",
            secret: "s",
            owner: owner,
            grantee: Participant(id: UUID(), displayName: "Aleksandra"),
            state: .active,
            createdAt: .now,
            cloudKitRootRecordName: "grant",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "__defaultOwner__"
        )
        local.inviteeName = "Ola"
        var fetched = local
        fetched.inviteeName = " "
        fetched.owner.displayName = ""
        fetched.grantee?.displayName = ""
        let merged = GrantRefreshMerge.merging(fetched, with: local)
        XCTAssertEqual(merged.inviteeName, "Ola")
        let kept = GrantRefreshMerge.applyingOwnName("", to: merged, profileID: owner.id)
        XCTAssertEqual(kept.owner.displayName, "")
        let restored = GrantRefreshMerge.applyingOwnName("Mateusz", to: kept, profileID: owner.id)
        XCTAssertEqual(restored.owner.displayName, "Mateusz")
        XCTAssertEqual(restored.grantee?.displayName, "")
    }
}

final class MutualInviteTests: XCTestCase {
    func testInviterKeepsTheTypedNameWhilePendingAndAfterBothDirections() {
        let owner = Participant(id: UUID(), displayName: "Mateusz")
        let friend = Participant(id: UUID(), displayName: "Aleksandra")
        var outgoing = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/out",
            secret: "s",
            owner: owner,
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: "grant-a",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_owner"
        )
        outgoing.inviteeName = "Ola"
        XCTAssertEqual(
            PersonName.listLabel(for: outgoing, profileID: owner.id, grants: [outgoing], generic: "Someone"),
            "Ola"
        )

        outgoing.grantee = friend
        outgoing.state = .active
        var returning = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/back",
            secret: "s2",
            owner: friend,
            grantee: owner,
            state: .active,
            createdAt: .now,
            cloudKitRootRecordName: "grant-b",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_friend"
        )
        returning.reciprocal = true
        returning.reciprocalForGrantID = outgoing.id
        returning.inviteeName = "Old label"
        outgoing.returnInviteURL = returning.inviteCode
        let grants = [outgoing, returning]

        XCTAssertEqual(ShareRoster.canSetAlarmsHere(profileID: owner.id, grants: grants).count, 1)
        XCTAssertEqual(ShareRoster.phonesICanSet(profileID: owner.id, grants: grants).count, 1)
        XCTAssertEqual(ShareRoster.canSetAlarmsHere(profileID: friend.id, grants: grants).count, 1)
        XCTAssertEqual(ShareRoster.phonesICanSet(profileID: friend.id, grants: grants).count, 1)
        XCTAssertEqual(
            PersonName.listLabel(for: returning, profileID: owner.id, grants: grants, generic: "Someone"),
            "Ola"
        )
        XCTAssertEqual(
            PersonName.listLabel(for: outgoing, profileID: friend.id, grants: grants, generic: "Someone"),
            "Mateusz"
        )
        XCTAssertEqual(
            PersonName.listLabel(for: returning, profileID: friend.id, grants: grants, generic: "Someone"),
            "Mateusz"
        )
    }

    func testOwnNameBeatsICloudAndTheTypedInviteeNameStaysTheSenderFallback() {
        XCTAssertEqual(PersonName.ownName(entered: "Mateusz", cloud: "iCloud Mateusz"), "Mateusz")
        XCTAssertEqual(PersonName.ownName(entered: " ", cloud: "iCloud Mateusz"), "iCloud Mateusz")
        XCTAssertNil(PersonName.ownName(entered: "", cloud: nil))

        let grant = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/out",
            secret: "s",
            owner: Participant(id: UUID(), displayName: "Mateusz"),
            grantee: Participant(id: UUID(), displayName: "Aleksandra"),
            state: .active,
            createdAt: .now,
            cloudKitRootRecordName: "grant",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_owner",
            inviteeName: "Ola"
        )
        XCTAssertEqual(PersonName.senderName(grant: grant), "Aleksandra")
        var unnamed = grant
        unnamed.grantee?.displayName = " "
        XCTAssertEqual(PersonName.senderName(grant: unnamed), "Ola")
    }

    func testOneAcceptanceCreatesTheReturnShareAndTheInviterAcceptsItOnce() {
        let owner = Participant(id: UUID(), displayName: "A")
        let friend = Participant(id: UUID(), displayName: "B")
        var accepted = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/out",
            secret: "s",
            owner: owner,
            grantee: friend,
            state: .active,
            createdAt: .now,
            cloudKitRootRecordName: "grant-a",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_a"
        )
        XCTAssertTrue(MutualInvite.shouldCreateReturnShare(accepted: accepted, profileID: friend.id, existing: [accepted]))
        XCTAssertFalse(MutualInvite.shouldCreateReturnShare(accepted: accepted, profileID: owner.id, existing: [accepted]))

        var back = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/back",
            secret: "s2",
            owner: friend,
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: "grant-b",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_b"
        )
        back.reciprocal = true
        back.reciprocalForGrantID = accepted.id
        XCTAssertFalse(MutualInvite.shouldCreateReturnShare(accepted: accepted, profileID: friend.id, existing: [accepted, back]))

        accepted.returnInviteURL = back.inviteCode
        let url = MutualInvite.returnURLToAccept(in: [accepted], profileID: owner.id)
        XCTAssertEqual(url?.absoluteString, back.inviteCode)
        back.grantee = owner
        back.state = .active
        XCTAssertNil(MutualInvite.returnURLToAccept(in: [accepted, back], profileID: owner.id))
        XCTAssertFalse(MutualInvite.shouldCreateReturnShare(accepted: back, profileID: owner.id, existing: [accepted, back]))
    }

    func testJoiningDoesNotLookLikeAnAlarm() {
        let owner = Participant(id: UUID(), displayName: "A")
        var pending = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/out",
            secret: "s",
            owner: owner,
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: "grant",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_a",
            inviteeName: "Ola"
        )
        var active = pending
        active.state = .active
        active.grantee = Participant(id: UUID(), displayName: "Aleksandra")
        XCTAssertEqual(ShareChangeNotice.joinedName(previous: pending, updated: active), "Ola")
        XCTAssertNil(ShareChangeNotice.joinedName(previous: active, updated: active))
    }

    func testOldGrantJSONDecodesWithoutTheNewFields() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","inviteCode":"https://www.icloud.com/share/abc","secret":"s","owner":{"id":"22222222-2222-2222-2222-222222222222","displayName":"A"},"state":"pending","createdAt":"2026-11-20T12:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let grant = try decoder.decode(ShareGrant.self, from: json)
        XCTAssertEqual(grant.owner.displayName, "A")
        XCTAssertNil(grant.inviteeName)
        XCTAssertNil(grant.returnInviteURL)
        XCTAssertNil(grant.reciprocal)
        XCTAssertNil(grant.reciprocalForGrantID)
        XCTAssertNil(grant.wakeReports)
    }

    func testZoneNotFoundIsRecognizedAndAnExistingZoneIsNot() {
        XCTAssertTrue(CloudKitZoneFailure.isZoneNotFound(CKError(.zoneNotFound)))
        XCTAssertFalse(CloudKitZoneFailure.isZoneNotFound(CKError(.serverRecordChanged)))
        XCTAssertTrue(CloudKitZoneFailure.isZoneAlreadyExists(CKError(.serverRecordChanged)))
        let partial = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: ["grant": CKError(.zoneNotFound)]
        ])
        XCTAssertTrue(CloudKitZoneFailure.isZoneNotFound(partial))
    }

    func testOnlyAMissingZoneIsCreatedAndADeletedZoneIsLeftAlone() {
        XCTAssertTrue(CloudKitZoneFailure.shouldRecreateZone(CKError(.zoneNotFound)))
        XCTAssertTrue(CloudKitZoneFailure.shouldRecreateZone(CKError(.userDeletedZone)))
        XCTAssertFalse(CloudKitZoneFailure.shouldRecreateZone(CKError(.unknownItem)))
        XCTAssertTrue(CloudKitZoneFailure.isMissingRecord(CKError(.unknownItem)))
        XCTAssertTrue(GrantRecordRecovery.shouldCreateInstead(of: CKError(.zoneNotFound)))
        XCTAssertFalse(GrantRecordRecovery.shouldCreateInstead(of: CKError(.userDeletedZone)))
        XCTAssertFalse(PrivateZonePolicy.shouldCreate(after: CKError(.userDeletedZone)))
        XCTAssertTrue(PrivateZonePolicy.shouldCreate(after: CKError(.zoneNotFound)))
        XCTAssertTrue(GrantRecordRecovery.shouldCreateInstead(of: CKError(.unknownItem)))
        XCTAssertFalse(GrantRecordRecovery.shouldCreateInstead(of: CKError(.networkUnavailable)))
        let wrapped = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: ["zone": CKError(.userDeletedZone)]
        ])
        XCTAssertTrue(CloudKitZoneFailure.shouldRecreateZone(wrapped))
    }

    func testTheServerZoneOwnerReplacesTheDefaultOwnerPlaceholder() {
        let requested = CKRecordZone.ID(zoneName: "WakeMeUp", ownerName: CKCurrentUserDefaultName)
        let server = CKRecordZone.ID(zoneName: "WakeMeUp", ownerName: "_76b4ce4cbc5b09999462b2f690a9b48a")
        let resolved = PrivateCloudZone.canonical(requested: requested, server: server)
        XCTAssertEqual(resolved.zoneName, "WakeMeUp")
        XCTAssertEqual(resolved.ownerName, "_76b4ce4cbc5b09999462b2f690a9b48a")
        XCTAssertEqual(PrivateCloudZone.canonical(requested: requested, server: nil).ownerName, CKCurrentUserDefaultName)
        let placeholder = CKRecordZone.ID(zoneName: "WakeMeUp", ownerName: CKCurrentUserDefaultName)
        XCTAssertEqual(
            PrivateCloudZone.canonical(requested: requested, server: placeholder).ownerName,
            CKCurrentUserDefaultName
        )
    }

    func testPrivateRecordsUseTheCurrentUserAndSharedRecordsKeepTheShareOwner() {
        let foreign = "_76b4ce4cbc5b09999462b2f690a9b48a"
        let privateID = ShareRecordAddress.zoneID(
            zoneName: "WakeMeUp",
            storedOwnerName: foreign,
            database: .privateDatabase
        )
        XCTAssertEqual(privateID.zoneName, "WakeMeUp")
        XCTAssertEqual(privateID.ownerName, CKCurrentUserDefaultName)
        let sharedID = ShareRecordAddress.zoneID(
            zoneName: "WakeMeUp",
            storedOwnerName: foreign,
            database: .sharedDatabase
        )
        XCTAssertEqual(sharedID.ownerName, foreign)
        XCTAssertEqual(ShareRecordAddress.database(isOwner: true), .privateDatabase)
        XCTAssertEqual(ShareRecordAddress.database(isOwner: false), .sharedDatabase)
        XCTAssertNotEqual(privateID.ownerName, sharedID.ownerName)
    }

    func testAMissingSharedZoneIsAcceptedAgainAndABackgroundSyncDoesNotLookLikeAFailedInvite() {
        let owner = "_76b4ce4cbc5b09999462b2f690a9b48a"
        XCTAssertEqual(
            ShareAccessPlan.decide(preferredOwner: owner, sharedOwners: [owner], hasInviteURL: true),
            .use(ownerName: owner)
        )
        XCTAssertEqual(
            ShareAccessPlan.decide(preferredOwner: owner, sharedOwners: ["_other"], hasInviteURL: false),
            .use(ownerName: "_other")
        )
        XCTAssertEqual(
            ShareAccessPlan.decide(preferredOwner: owner, sharedOwners: ["_a", "_b"], hasInviteURL: true),
            .reaccept
        )
        XCTAssertEqual(
            ShareAccessPlan.decide(preferredOwner: owner, sharedOwners: ["_a", "_b"], hasInviteURL: false),
            .unavailable
        )
        XCTAssertEqual(
            ShareAccessPlan.decide(preferredOwner: CKCurrentUserDefaultName, sharedOwners: [owner], hasInviteURL: false),
            .use(ownerName: owner)
        )
        let error = CKError(.zoneNotFound)
        XCTAssertNil(CloudKitErrorText.alertMessage(for: error, context: .backgroundSync))
        XCTAssertNil(CloudKitErrorText.alertKind(for: .backgroundSync))
        let invite = CloudKitErrorText.alertMessage(for: error, context: .creatingInvite)
        let reach = CloudKitErrorText.alertMessage(for: error, context: .sendingAlarm)
        XCTAssertNotEqual(invite, reach)
        XCTAssertEqual(ContactConnectionNote.note(wakeGrantID: nil, isPending: false), .connecting)
        let wake = UUID()
        XCTAssertNil(ContactConnectionNote.note(wakeGrantID: wake, isPending: false))
        XCTAssertNil(ContactConnectionNote.note(wakeGrantID: nil, isPending: true))
        XCTAssertFalse(ShareLinkLifetime.mayClosePublicLink(revoking: false))
        XCTAssertTrue(ShareLinkLifetime.mayClosePublicLink(revoking: true))
        let gone = NSError(
            domain: CKError.errorDomain,
            code: CKError.unknownItem.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "when fetching short token metadata for https://www.icloud.com/share/abc#Wakito: share not found"]
        )
        XCTAssertEqual(ShareFailureKind.classify(gone), .shareLinkGone)
        XCTAssertNotEqual(ShareFailureKind.classify(CKError(.unknownItem)), .shareLinkGone)
        XCTAssertTrue(ContactActionPolicy.canWake(SharingContact(
            id: "a",
            name: "Mateusz",
            memberID: UUID(),
            wakeGrantID: wake,
            hostedGrantID: nil,
            isPending: false
        )))
    }
}

final class FriendGroupRosterTests: XCTestCase {
    func testAGroupShowsEachPersonAndAnUngroupedAlarmStaysSeparate() {
        let group = UUID()
        let first = sent(name: "Ola", group: group, status: .up, at: Date(timeIntervalSince1970: 300))
        let second = sent(name: "Jan", group: group, status: .asleep, at: Date(timeIntervalSince1970: 200))
        let alone = sent(name: "Ewa", group: nil, status: nil, at: Date(timeIntervalSince1970: 100))
        let sections = FriendGroupRoster.sections(from: [first, second, alone])
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Rodzina")
        XCTAssertEqual(sections[0].rows.map(\.name), ["Ola", "Jan"])
        XCTAssertEqual(sections[0].rows.map(\.status), [.up, .asleep])
        XCTAssertNil(sections[1].title)
        XCTAssertEqual(sections[1].rows.map(\.name), ["Ewa"])
    }

    private func sent(name: String, group: UUID?, status: WakeStatusKind?, at: Date) -> SentAlarm {
        SentAlarm(
            alarm: Alarm(
                id: UUID(),
                schedule: .wallClock(hour: 7, minute: 0, repeatDays: []),
                label: "",
                soundID: "classic",
                snoozeEnabled: true,
                snoozeMinutes: 9,
                isEnabled: true,
                groupID: nil,
                songLink: nil,
                origin: .local,
                resumeWhenGroupEnables: nil
            ),
            recipientID: UUID(),
            recipientName: name,
            sentAt: at,
            commandID: UUID(),
            wakeStatus: status,
            friendGroupID: group,
            friendGroupName: group == nil ? nil : "Rodzina"
        )
    }
}

final class WakeReportTests: XCTestCase {
    private let fired = Date(timeIntervalSince1970: 1_700_000_000)

    func testDismissalReportsUpImmediately() {
        let outcome = WakeReportPolicy.outcome(
            firedAt: fired,
            now: fired.addingTimeInterval(30),
            snoozeCount: 0,
            dismissedAt: fired.addingTimeInterval(30)
        )
        XCTAssertEqual(outcome, .up(fired.addingTimeInterval(30)))
    }

    func testTenMinutesWithoutDismissalReportsStillAsleep() {
        XCTAssertEqual(
            WakeReportPolicy.outcome(firedAt: fired, now: fired.addingTimeInterval(9 * 60), snoozeCount: 0, dismissedAt: nil),
            .pending
        )
        XCTAssertEqual(
            WakeReportPolicy.outcome(firedAt: fired, now: fired.addingTimeInterval(10 * 60), snoozeCount: 0, dismissedAt: nil),
            .asleep
        )
    }

    func testASecondSnoozeReportsStillAsleep() {
        XCTAssertEqual(
            WakeReportPolicy.outcome(firedAt: fired, now: fired.addingTimeInterval(60), snoozeCount: 1, dismissedAt: nil),
            .pending
        )
        XCTAssertEqual(
            WakeReportPolicy.outcome(firedAt: fired, now: fired.addingTimeInterval(120), snoozeCount: 2, dismissedAt: nil),
            .asleep
        )
    }

    func testUpReplacesAsleepAndAsleepDoesNotReplaceUp() {
        let command = UUID()
        let sent = [
            SentAlarm(
                alarm: Alarm(
                    id: UUID(),
                    schedule: .wallClock(hour: 6, minute: 30, repeatDays: []),
                    label: "",
                    soundID: "classic",
                    snoozeEnabled: true,
                    snoozeMinutes: 9,
                    isEnabled: true,
                    groupID: nil,
                    songLink: nil,
                    origin: .local,
                    resumeWhenGroupEnables: nil
                ),
                recipientID: UUID(),
                recipientName: "Ola",
                sentAt: fired,
                commandID: command
            )
        ]
        let asleep = WakeReport(
            id: UUID(),
            commandID: command,
            alarmID: sent[0].alarm.id,
            reporterID: UUID(),
            reporterName: "Aleksandra",
            status: .asleep,
            at: fired
        )
        let up = WakeReport(
            id: UUID(),
            commandID: command,
            alarmID: sent[0].alarm.id,
            reporterID: asleep.reporterID,
            reporterName: "Aleksandra",
            status: .up,
            at: fired.addingTimeInterval(60)
        )
        let first = WakeStatusApply.changes(reports: [asleep], sent: sent) { $0.reporterName }
        XCTAssertEqual(first.map(\.status), [.asleep])
        XCTAssertTrue(first[0].notice.contains("Aleksandra"))
        var updated = sent
        updated[0].wakeStatus = .asleep
        let second = WakeStatusApply.changes(reports: [up], sent: updated) { _ in "Ola" }
        XCTAssertEqual(second.map(\.status), [.up])
        XCTAssertTrue(second[0].notice.contains("Ola"))
        updated[0].wakeStatus = .up
        XCTAssertTrue(WakeStatusApply.changes(reports: [asleep], sent: updated) { $0.reporterName }.isEmpty)
    }

    func testAMissingWakeReportOnTheServerDoesNotClearTheLocalOne() {
        var local = ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/abc",
            secret: "s",
            owner: Participant(id: UUID(), displayName: "A"),
            grantee: nil,
            state: .active,
            createdAt: fired,
            cloudKitRootRecordName: "grant",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "_a"
        )
        local.wakeReports = [
            WakeReport(
                id: UUID(),
                commandID: UUID(),
                alarmID: UUID(),
                reporterID: UUID(),
                reporterName: "Ola",
                status: .up,
                at: fired
            )
        ]
        var fetched = local
        fetched.wakeReports = nil
        XCTAssertEqual(GrantRefreshMerge.merging(fetched, with: local).wakeReports?.count, 1)
    }
}

final class TabEdgeSwipeTests: XCTestCase {
    func testOnlyAnEdgeSwipeChangesTabs() {
        let width: CGFloat = 390
        XCTAssertEqual(
            TabEdgeSwipe.direction(startX: 8, translationX: 90, translationY: 4, width: width),
            .previous
        )
        XCTAssertEqual(
            TabEdgeSwipe.direction(startX: 370, translationX: -90, translationY: 6, width: width),
            .next
        )
        XCTAssertNil(TabEdgeSwipe.direction(startX: 180, translationX: -120, translationY: 0, width: width))
        XCTAssertNil(TabEdgeSwipe.direction(startX: 10, translationX: 20, translationY: 0, width: width))
        XCTAssertNil(TabEdgeSwipe.direction(startX: 10, translationX: 40, translationY: 80, width: width))
        XCTAssertEqual(AppTab.nap.shifted(.next), .alarms)
        XCTAssertEqual(AppTab.alarms.shifted(.next), .sharing)
        XCTAssertEqual(AppTab.sharing.shifted(.next), .calendar)
        XCTAssertEqual(AppTab.calendar.shifted(.next), .achievements)
        XCTAssertEqual(AppTab.sharing.shifted(.previous), .alarms)
        XCTAssertEqual(AppTab.alarms.shifted(.previous), .nap)
        XCTAssertEqual(AppTab.nap.shifted(.previous), .nap)
        XCTAssertEqual(AppTab.achievements.shifted(.next), .achievements)
        XCTAssertEqual(AppTab.displayOrder, [.nap, .alarms, .sharing, .calendar, .achievements])
    }
}

final class ListHygieneTests: XCTestCase {
    func testCommandsYouSentAreNotAlarmsForYou() {
        let me = UUID()
        let them = UUID()
        let outgoing = RemoteAlarmCommand(
            id: UUID(),
            grantID: UUID(),
            senderID: me,
            recipientID: them,
            action: .upsert,
            createdAt: .now,
            alarm: nil,
            alarmID: nil,
            enabled: nil
        )
        let incoming = RemoteAlarmCommand(
            id: UUID(),
            grantID: UUID(),
            senderID: them,
            recipientID: me,
            action: .upsert,
            createdAt: .now,
            alarm: nil,
            alarmID: nil,
            enabled: nil
        )
        XCTAssertFalse(IncomingCommandPolicy.shouldApply(command: outgoing, profileID: me))
        XCTAssertTrue(IncomingCommandPolicy.shouldApply(command: incoming, profileID: me))
        let echo = Alarm(
            id: UUID(),
            schedule: .oneShot(fireAt: .now),
            label: "Echo",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .remote(senderID: me, senderName: "Mateusz", commandID: UUID()),
            resumeWhenGroupEnables: nil
        )
        let kept = Alarm(
            id: UUID(),
            schedule: .wallClock(hour: 7, minute: 0, repeatDays: [.monday]),
            label: "Mine",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        XCTAssertEqual(SelfAlarmCleanup.removingSelfAuthored(from: [echo, kept], profileID: me).map(\.id), [kept.id])
    }

    func testOneTimeAlarmsLeaveAfterTheyRingOrTheirTimePasses() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = Alarm(
            id: UUID(),
            schedule: .oneShot(fireAt: now.addingTimeInterval(-30)),
            label: "Past",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let soon = Alarm(
            id: UUID(),
            schedule: .oneShot(fireAt: now.addingTimeInterval(120)),
            label: "Soon",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let daily = Alarm(
            id: UUID(),
            schedule: .wallClock(hour: 7, minute: 0, repeatDays: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            label: "Daily",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        var once = Alarm(
            id: UUID(),
            schedule: .wallClock(hour: 6, minute: 30, repeatDays: []),
            label: "Once",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        once.firesOnceAt = now.addingTimeInterval(-5)
        let sent = SentAlarm(
            alarm: past,
            recipientID: UUID(),
            recipientName: "Akhi",
            sentAt: now.addingTimeInterval(-60),
            commandID: UUID()
        )
        let result = OneTimeAlarmExpiry.partition(
            alarms: [past, soon, daily, once],
            sent: [sent],
            now: now,
            calendar: Calendar(identifier: .gregorian),
            rungIDs: []
        )
        XCTAssertEqual(Set(result.alarms.map(\.label)), Set(["Soon", "Daily"]))
        XCTAssertTrue(result.sent.isEmpty)
        XCTAssertTrue(OneTimeAlarmExpiry.shouldRemove(
            schedule: soon.schedule,
            firesOnceAt: nil,
            now: now,
            hasRung: true
        ))
    }

    func testFriendSectionsRememberWhenTheyAreCollapsed() {
        let name = "wakito.tests.sections.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertTrue(SectionExpansionStore.isExpanded(SectionExpansionStore.fromOthers, defaults: defaults))
        SectionExpansionStore.setExpanded(false, id: SectionExpansionStore.toOthers, defaults: defaults)
        XCTAssertFalse(SectionExpansionStore.isExpanded(SectionExpansionStore.toOthers, defaults: defaults))
        XCTAssertTrue(SectionExpansionStore.isExpanded(SectionExpansionStore.fromOthers, defaults: defaults))
    }
}

final class HandshakeTests: XCTestCase {
    func testOneLinkLetsBothPeopleWakeEachOtherAndTheLinkStays() throws {
        let mateusz = Participant(id: UUID(), displayName: "Mateusz")
        let akhi = Participant(id: UUID(), displayName: "Akhi")
        let original = URL(string: "https://www.icloud.com/share/original#Wakito")!
        var cloud = HandshakeCloud()
        var mateuszGrants = [cloud.create(owner: mateusz, url: original)]
        var akhiGrants = [try cloud.accept(url: original, grantee: akhi)]
        for _ in 0..<8 {
            try Self.step(&mateuszGrants, person: mateusz, cloud: &cloud)
            try Self.step(&akhiGrants, person: akhi, cloud: &cloud)
            mateuszGrants = cloud.ownedView(mateuszGrants, owner: mateusz.id)
            akhiGrants = cloud.sharedView(akhiGrants, grantee: akhi.id)
            let idle = HandshakePlanner.actions(profileID: mateusz.id, grants: mateuszGrants).isEmpty
                && HandshakePlanner.actions(profileID: akhi.id, grants: akhiGrants).isEmpty
            if idle { break }
        }
        XCTAssertEqual(cloud.url(for: mateuszGrants[0].id), original)
        XCTAssertTrue(cloud.isOpen(mateuszGrants[0].id))
        XCTAssertEqual(ShareRoster.phonesICanSet(profileID: mateusz.id, grants: mateuszGrants).map(\.owner.id), [akhi.id])
        XCTAssertEqual(ShareRoster.phonesICanSet(profileID: akhi.id, grants: akhiGrants).map(\.owner.id), [mateusz.id])
        XCTAssertTrue(HandshakePlanner.actions(profileID: mateusz.id, grants: mateuszGrants).isEmpty)
        XCTAssertTrue(HandshakePlanner.actions(profileID: akhi.id, grants: akhiGrants).isEmpty)
        let shares = cloud.shareCount
        try Self.step(&mateuszGrants, person: mateusz, cloud: &cloud)
        try Self.step(&akhiGrants, person: akhi, cloud: &cloud)
        XCTAssertEqual(cloud.shareCount, shares)
        XCTAssertEqual(cloud.url(for: mateuszGrants[0].id), original)
        XCTAssertFalse(HandshakePlanner.actions(profileID: mateusz.id, grants: mateuszGrants).contains { action in
            if case .createReturnShare = action { return true }
            return false
        })
    }

    private static func step(_ grants: inout [ShareGrant], person: Participant, cloud: inout HandshakeCloud) throws {
        for action in HandshakePlanner.actions(profileID: person.id, grants: grants) {
            switch action {
            case let .createReturnShare(acceptedID):
                let accepted = try XCTUnwrap(grants.first { $0.id == acceptedID })
                grants.append(cloud.createReturn(answering: accepted, owner: person))
            case let .publishReturnURL(url, acceptedID):
                cloud.publish(url, on: acceptedID)
                guard let index = grants.firstIndex(where: { $0.id == acceptedID }) else { continue }
                grants[index].returnInviteURL = url.absoluteString
            case let .acceptReturnURL(url):
                grants.append(try cloud.accept(url: url, grantee: person))
            }
        }
    }
}

private struct HandshakeCloud {
    struct Share {
        var grant: ShareGrant
        var url: URL
        var isOpen: Bool
    }

    private var shares: [UUID: Share] = [:]

    var shareCount: Int { shares.count }

    mutating func create(owner: Participant, url: URL) -> ShareGrant {
        let grant = ShareGrant(
            id: UUID(),
            inviteCode: url.absoluteString,
            secret: "s",
            owner: owner,
            grantee: nil,
            state: .pending,
            createdAt: .now,
            cloudKitRootRecordName: "grant-\(UUID().uuidString)",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: owner.id.uuidString
        )
        shares[grant.id] = Share(grant: grant, url: url, isOpen: true)
        return grant
    }

    mutating func accept(url: URL, grantee: Participant) throws -> ShareGrant {
        guard let id = shares.first(where: { $0.value.url == url })?.key, var share = shares[id] else {
            throw RemoteBackendError.shareLinkGone
        }
        share.grant.grantee = grantee
        share.grant.state = .active
        shares[id] = share
        return share.grant
    }

    mutating func createReturn(answering accepted: ShareGrant, owner: Participant) -> ShareGrant {
        let url = URL(string: "https://www.icloud.com/share/return-\(UUID().uuidString)#Wakito")!
        var grant = create(owner: owner, url: url)
        grant.reciprocal = true
        grant.reciprocalForGrantID = accepted.id
        grant.inviteeName = accepted.owner.displayName
        if var share = shares[grant.id] {
            share.grant = grant
            shares[grant.id] = share
        }
        return grant
    }

    mutating func publish(_ url: URL, on acceptedID: UUID) {
        guard var share = shares[acceptedID] else { return }
        share.grant.returnInviteURL = url.absoluteString
        shares[acceptedID] = share
    }

    func url(for grantID: UUID) -> URL? { shares[grantID]?.url }

    func isOpen(_ grantID: UUID) -> Bool { shares[grantID]?.isOpen == true }

    func ownedView(_ local: [ShareGrant], owner: UUID) -> [ShareGrant] {
        local.map { grant in
            guard grant.owner.id == owner, let stored = shares[grant.id]?.grant else { return grant }
            var merged = stored
            merged.reciprocal = grant.reciprocal ?? stored.reciprocal
            merged.reciprocalForGrantID = grant.reciprocalForGrantID ?? stored.reciprocalForGrantID
            return merged
        }
    }

    func sharedView(_ local: [ShareGrant], grantee: UUID) -> [ShareGrant] {
        local.map { grant in
            guard grant.grantee?.id == grantee, let stored = shares[grant.id]?.grant else { return grant }
            return stored
        }
    }
}

final class EditingUXTests: XCTestCase {
    func testAddToGroupHidesAlarmsThatAlreadyHaveAGroup() {
        let morning = UUID()
        let loose = alarm(hour: 6, group: nil, label: "Loose")
        let placed = alarm(hour: 7, group: morning, label: "Placed")
        let later = alarm(hour: 9, group: nil, label: "Later")
        let candidates = GroupAlarmCandidates.unassigned([placed, later, loose])
        XCTAssertEqual(candidates.map(\.label), ["Loose", "Later"])
    }

    func testBulkEditChangesTimeAndSettingsOnlyForTheSelection() {
        var library = AlarmLibrary()
        let chosen = alarm(hour: 6, group: nil, label: "Chosen")
        let other = alarm(hour: 8, group: nil, label: "Other")
        library.upsert(chosen)
        library.upsert(other)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        library.apply(
            BulkAlarmPatch(
                hour: 5,
                minute: 30,
                repeatDays: [.monday, .tuesday],
                soundID: "bell",
                snoozeEnabled: false,
                snoozeMinutes: 4,
                label: "Shared",
                applyLabel: true
            ),
            to: [chosen.id],
            now: now,
            calendar: calendar
        )
        let updated = library.alarm(chosen.id)
        XCTAssertEqual(updated?.schedule, .wallClock(hour: 5, minute: 30, repeatDays: [.monday, .tuesday]))
        XCTAssertEqual(updated?.soundID, "bell")
        XCTAssertEqual(updated?.snoozeEnabled, false)
        XCTAssertEqual(updated?.snoozeMinutes, 4)
        XCTAssertEqual(updated?.label, "Shared")
        XCTAssertNil(updated?.firesOnceAt)
        XCTAssertEqual(library.alarm(other.id)?.label, "Other")
        XCTAssertEqual(library.alarm(other.id)?.schedule.hour, 8)
    }

    func testBulkEditWithoutARepeatStampsOneFireAndLeavesTheLabel() {
        let original = alarm(hour: 6, group: nil, label: "Keep")
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = BulkAlarmEdit.applying(
            BulkAlarmPatch(
                hour: 22,
                minute: 15,
                repeatDays: [],
                soundID: "classic",
                snoozeEnabled: true,
                snoozeMinutes: 9,
                label: "Ignored",
                applyLabel: false
            ),
            to: original,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(updated.label, "Keep")
        XCTAssertEqual(updated.schedule.hour, 22)
        XCTAssertEqual(updated.schedule.minute, 15)
        XCTAssertNotNil(updated.firesOnceAt)
    }

    func testOwnAlarmsAndSoundsCanBeRenamedAndDeleted() {
        var library = AlarmLibrary()
        let mine = alarm(hour: 6, group: nil, label: "Old")
        let remote = alarm(
            hour: 7,
            group: nil,
            label: "Theirs",
            origin: .remote(senderID: UUID(), senderName: "Akhi", commandID: UUID())
        )
        library.upsert(mine)
        library.upsert(remote)
        XCTAssertTrue(library.rename(alarmID: mine.id, to: "  Morning  "))
        XCTAssertEqual(library.alarm(mine.id)?.label, "Morning")
        XCTAssertFalse(library.rename(alarmID: remote.id, to: "Nope"))
        XCTAssertEqual(library.alarm(remote.id)?.label, "Theirs")

        let voice = CustomSound(id: "voice-1", displayName: "Wiadomość głosowa", filename: "voice-1.m4a")
        let imported = CustomSound(id: "file-1", displayName: "Song", filename: "file-1.caf")
        XCTAssertTrue(SoundLibraryEdit.isVoiceRecording(voice.id))
        XCTAssertFalse(SoundLibraryEdit.isVoiceRecording(imported.id))
        XCTAssertEqual(SoundLibraryEdit.renamed([voice], id: voice.id, to: "  Wakacje ")?.first?.displayName, "Wakacje")
        XCTAssertNil(SoundLibraryEdit.renamed([voice], id: voice.id, to: "   "))
        var using = mine
        using.soundID = voice.id
        XCTAssertEqual(SoundLibraryEdit.clearing(voice.id, in: [using]).first?.soundID, SoundCatalog.defaultID)
        XCTAssertTrue(SoundLibraryEdit.removed([voice, imported], id: voice.id).allSatisfy { $0.id != voice.id })
    }

    func testPausedContactDoesNotRingOrAcceptTheirAlarms() {
        let me = Participant(id: UUID(), displayName: "Mateusz")
        let friend = Participant(id: UUID(), displayName: "Akhi")
        var grant = share(owner: friend, grantee: me)
        grant.collaborationPaused = true
        grant.collaborationPausedAt = Date(timeIntervalSince1970: 20)
        grant.collaborationPausedBy = me.id
        let incoming = alarm(
            hour: 6,
            group: nil,
            label: "From Akhi",
            origin: .remote(senderID: friend.id, senderName: "Akhi", commandID: UUID())
        )
        let own = alarm(hour: 7, group: nil, label: "Mine")
        XCTAssertTrue(CollaborationPause.isPaused(profileID: me.id, otherID: friend.id, grants: [grant]))
        XCTAssertTrue(CollaborationPause.suppressesRinging(incoming, profileID: me.id, grants: [grant]))
        XCTAssertFalse(CollaborationPause.suppressesRinging(own, profileID: me.id, grants: [grant]))
        let scheduled = CollaborationPause.alarmsForSync([incoming, own], profileID: me.id, grants: [grant])
        XCTAssertEqual(scheduled.first?.isEnabled, false)
        XCTAssertEqual(scheduled.last?.isEnabled, true)
        let contact = SharingContact(
            id: friend.id.uuidString,
            name: "Akhi",
            memberID: friend.id,
            wakeGrantID: grant.id,
            hostedGrantID: nil,
            isPending: false
        )
        XCTAssertTrue(CollaborationPause.isPaused(contact: contact, profileID: me.id, grants: [grant]))

        var older = grant
        older.collaborationPaused = false
        older.collaborationPausedAt = Date(timeIntervalSince1970: 10)
        let kept = GrantRefreshMerge.merging(older, with: grant)
        XCTAssertEqual(kept.collaborationPaused, true)
        var newer = grant
        newer.collaborationPaused = false
        newer.collaborationPausedAt = Date(timeIntervalSince1970: 30)
        newer.collaborationPausedBy = friend.id
        let resumed = GrantRefreshMerge.merging(newer, with: grant)
        XCTAssertEqual(resumed.collaborationPaused, false)
        XCTAssertEqual(resumed.collaborationPausedBy, friend.id)
    }

    func testGrantWithoutPauseFieldsStillDecodes() throws {
        let me = Participant(id: UUID(), displayName: "Mateusz")
        let grant = share(owner: me, grantee: nil)
        let data = try JSONEncoder().encode(grant)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "collaborationPaused")
        object.removeValue(forKey: "collaborationPausedAt")
        object.removeValue(forKey: "collaborationPausedBy")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ShareGrant.self, from: stripped)
        XCTAssertNil(decoded.collaborationPaused)
        XCTAssertEqual(decoded.owner.displayName, "Mateusz")
    }

    func testVideoMessageStaysUnderThirtySecondsAndDropsWhenUploadFails() throws {
        XCTAssertEqual(VideoMessagePolicy.clamped(45), 30)
        XCTAssertEqual(VideoMessagePolicy.clamped(12), 12)
        XCTAssertFalse(VideoMessagePolicy.fits(byteCount: 0))
        XCTAssertTrue(VideoMessagePolicy.fits(byteCount: 1024))
        XCTAssertFalse(VideoMessagePolicy.fits(byteCount: VideoMessagePolicy.maxBytes + 1))
        XCTAssertEqual(
            OutgoingVideo.payload(recordName: "video-1", uploaded: true),
            OutgoingVideo.Payload(recordName: "video-1", warn: false)
        )
        XCTAssertEqual(
            OutgoingVideo.payload(recordName: "video-1", uploaded: false),
            OutgoingVideo.Payload(recordName: nil, warn: true)
        )
        XCTAssertEqual(
            OutgoingVideo.payload(recordName: nil, uploaded: false),
            OutgoingVideo.Payload(recordName: nil, warn: false)
        )
        let alarm = Alarm(
            id: UUID(),
            schedule: .oneShot(fireAt: Date(timeIntervalSince1970: 1)),
            label: "Clip",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let data = try JSONEncoder().encode(alarm)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "videoFileID")
        let decoded = try JSONDecoder().decode(Alarm.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.videoFileID)
        let command = RemoteAlarmCommand(
            id: UUID(),
            grantID: UUID(),
            senderID: UUID(),
            recipientID: UUID(),
            action: .upsert,
            createdAt: Date(timeIntervalSince1970: 1),
            alarm: decoded,
            alarmID: nil,
            enabled: true
        )
        let commandData = try JSONEncoder().encode(command)
        var commandObject = try JSONSerialization.jsonObject(with: commandData) as! [String: Any]
        commandObject.removeValue(forKey: "videoRecordName")
        let decodedCommand = try JSONDecoder().decode(RemoteAlarmCommand.self, from: JSONSerialization.data(withJSONObject: commandObject))
        XCTAssertNil(decodedCommand.videoRecordName)
    }

    private func share(owner: Participant, grantee: Participant?) -> ShareGrant {
        ShareGrant(
            id: UUID(),
            inviteCode: "https://www.icloud.com/share/abc",
            secret: "s",
            owner: owner,
            grantee: grantee,
            state: grantee == nil ? .pending : .active,
            createdAt: Date(timeIntervalSince1970: 1),
            cloudKitRootRecordName: "root",
            cloudKitZoneName: "WakeMeUp",
            cloudKitOwnerName: "__defaultOwner__"
        )
    }

    private func alarm(hour: Int, group: UUID?, label: String, origin: AlarmOrigin = .local) -> Alarm {
        Alarm(
            id: UUID(),
            schedule: .wallClock(hour: hour, minute: 0, repeatDays: [.monday]),
            label: label,
            soundID: "classic",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: group,
            songLink: nil,
            origin: origin,
            resumeWhenGroupEnables: nil
        )
    }
}

final class NapCalendarTests: XCTestCase {
    func testSpokenAlarmUsesTheClockTimeAndAContactMatchPrefersSomeoneYouCanWake() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let spoken = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 6, minute: 30))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 5, minute: 0))!
        let alarm = SpokenAlarm.make(at: spoken, now: now, calendar: calendar)
        XCTAssertEqual(alarm.schedule.hour, 6)
        XCTAssertEqual(alarm.schedule.minute, 30)
        XCTAssertEqual(alarm.schedule.repeatDays, [])
        XCTAssertNotNil(alarm.firesOnceAt)
        let akhi = SharingContact(id: "akhi", name: "Akhi", memberID: UUID(), wakeGrantID: UUID(), hostedGrantID: nil, isPending: false)
        let other = SharingContact(id: "ola", name: "Ola", memberID: UUID(), wakeGrantID: nil, hostedGrantID: UUID(), isPending: false)
        XCTAssertEqual(SpokenContactMatch.match(name: "akhi", contacts: [other, akhi])?.id, "akhi")
        XCTAssertEqual(SpokenContactMatch.match(name: "  AKHI ", contacts: [akhi])?.wakeGrantID, akhi.wakeGrantID)
        XCTAssertNil(SpokenContactMatch.match(name: "   ", contacts: [akhi]))
    }

    func testNapIsAOneShotAtTheChosenLength() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let alarm = NapAlarm.make(minutes: 15, now: now, id: UUID())
        guard case let .oneShot(fireAt) = alarm.schedule else {
            return XCTFail("A nap is a one-time alarm")
        }
        XCTAssertEqual(fireAt.timeIntervalSince(now), 15 * 60, accuracy: 0.1)
        XCTAssertEqual(alarm.countdownLead, nil)
        XCTAssertFalse(alarm.snoozeEnabled)
        XCTAssertEqual(NapSettings.presets, [10, 15, 20, 30, 45, 60])
        XCTAssertEqual(NapSettings.clamped(7), 7)
        XCTAssertEqual(NapSettings.clamped(15), 15)
        XCTAssertEqual(NapSettings.clamped(200), 180)
        XCTAssertEqual(NapCountdown.clock(75), "01:15")
        XCTAssertEqual(NapCountdown.clock(15 * 60), "15:00")
        let defaults = UserDefaults(suiteName: "nap-\(UUID().uuidString)")!
        XCTAssertEqual(NapSettings.minutes(in: defaults), NapSettings.defaultMinutes)
        NapSettings.setMinutes(30, in: defaults)
        XCTAssertEqual(NapSettings.minutes(in: defaults), 30)
        XCTAssertEqual(NapFailure.message(authorization: .authorized, scheduleFailure: nil), nil)
        XCTAssertEqual(NapFailure.message(authorization: .authorized, scheduleFailure: "AlarmKit"), "AlarmKit")
        XCTAssertNotNil(NapFailure.message(authorization: .denied, scheduleFailure: nil))
        let snoozeDefaults = UserDefaults(suiteName: "snooze-\(UUID().uuidString)")!
        XCTAssertEqual(DefaultSnooze.minutes(in: snoozeDefaults), DefaultSnooze.fallback)
        DefaultSnooze.setMinutes(12, in: snoozeDefaults)
        XCTAssertEqual(DefaultSnooze.minutes(in: snoozeDefaults), 12)
        XCTAssertEqual(NapSettings.minutes(in: snoozeDefaults), NapSettings.defaultMinutes)
    }

    func testNapSessionStaysOutOfTheAlarmList() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = NapSession.make(minutes: 15, soundID: "classic", now: now)
        XCTAssertEqual(session.fireAt.timeIntervalSince(now), 15 * 60, accuracy: 0.1)
        XCTAssertTrue(session.isRunning(at: now.addingTimeInterval(10)))
        XCTAssertFalse(session.isRunning(at: session.fireAt))
        XCTAssertEqual(NapCountdown.remaining(until: session.fireAt, now: now), 15 * 60, accuracy: 0.1)

        let defaults = UserDefaults(suiteName: "nap-session-\(UUID().uuidString)")!
        NapSessionStore.save(session, to: defaults)
        XCTAssertEqual(NapSessionStore.load(from: defaults, now: now.addingTimeInterval(30))?.id, session.id)
        let finished = NapSessionStore.load(from: defaults, now: session.fireAt.addingTimeInterval(1))
        XCTAssertEqual(finished?.id, session.id)
        XCTAssertFalse(finished?.isRunning(at: session.fireAt.addingTimeInterval(1)) ?? true)

        let nap = session.alarm()
        let oldNap = Alarm(
            id: UUID(),
            schedule: .oneShot(fireAt: now.addingTimeInterval(600)),
            label: "Drzemka",
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            note: nil,
            countdownLead: 600,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let meeting = Alarm(
            id: UUID(),
            schedule: .oneShot(fireAt: now.addingTimeInterval(3600)),
            label: "Meeting",
            soundID: "classic",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            note: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let cleaned = NapListCleanup.removing(from: [nap, oldNap, meeting], sessionID: session.id)
        XCTAssertEqual(cleaned.map(\.id), [meeting.id])
        XCTAssertEqual(
            NapListCleanup.idsToCancel(in: [nap, oldNap], sessionID: session.id, legacyID: oldNap.id),
            [oldNap.id]
        )
    }

    func testNapEndNeverLeavesAnEmptyRingingCover() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = NapSession.make(minutes: 20, soundID: "classic", now: now)
        let idle = RingingOverlayState(ringingID: nil, held: nil, nap: session)

        let firing = RingingOverlay.apply(
            alerting: [session.id],
            state: idle,
            now: session.fireAt,
            libraryAlarm: { _ in nil },
            calendarAlarm: { _ in nil }
        )
        XCTAssertEqual(firing.ringingID, session.id)
        XCTAssertEqual(firing.held?.id, session.id)
        XCTAssertNil(firing.nap)
        XCTAssertNotNil(firing.presentedAlarm(libraryAlarm: { _ in nil }, calendarAlarm: { _ in nil }))

        let stopped = RingingOverlay.apply(
            alerting: [],
            state: firing,
            now: session.fireAt.addingTimeInterval(5),
            libraryAlarm: { _ in nil },
            calendarAlarm: { _ in nil }
        )
        XCTAssertNil(stopped.ringingID)
        XCTAssertNil(stopped.held)
        XCTAssertNil(stopped.presentedAlarm(libraryAlarm: { _ in nil }, calendarAlarm: { _ in nil }))

        let relaunched = RingingOverlayState(ringingID: nil, held: nil, nap: session)
        let unknown = UUID()
        let unresolved = RingingOverlay.apply(
            alerting: [unknown],
            state: relaunched,
            now: session.fireAt,
            libraryAlarm: { _ in nil },
            calendarAlarm: { _ in nil }
        )
        XCTAssertNil(unresolved.ringingID, "An alarm id with nothing to draw must not present a cover")
        XCTAssertNil(unresolved.presentedAlarm(libraryAlarm: { _ in nil }, calendarAlarm: { _ in nil }))
        XCTAssertNil(unresolved.nap)

        let duringNap = RingingOverlay.apply(
            alerting: [unknown],
            state: idle,
            now: now.addingTimeInterval(30),
            libraryAlarm: { _ in nil },
            calendarAlarm: { _ in nil }
        )
        XCTAssertEqual(duringNap.nap?.id, session.id)
        XCTAssertNil(duringNap.ringingID)

        let running = RingingOverlay.apply(
            alerting: [],
            state: idle,
            now: now.addingTimeInterval(30),
            libraryAlarm: { _ in nil },
            calendarAlarm: { _ in nil }
        )
        XCTAssertEqual(running.nap?.id, session.id)
        XCTAssertNil(running.ringingID)

        let meeting = Alarm(
            id: UUID(),
            schedule: .wallClock(hour: 7, minute: 0, repeatDays: [.monday]),
            label: "Meeting",
            soundID: "classic",
            snoozeEnabled: true,
            snoozeMinutes: 9,
            isEnabled: true,
            groupID: nil,
            songLink: nil,
            origin: .local,
            resumeWhenGroupEnables: nil
        )
        let listed = RingingOverlay.apply(
            alerting: [meeting.id],
            state: RingingOverlayState(),
            now: now,
            libraryAlarm: { $0 == meeting.id ? meeting : nil },
            calendarAlarm: { _ in nil }
        )
        XCTAssertEqual(listed.presentedAlarm(libraryAlarm: { $0 == meeting.id ? meeting : nil }, calendarAlarm: { _ in nil })?.id, meeting.id)

        let blank = RingingOverlayState(ringingID: unknown, held: nil, nap: nil)
        XCTAssertNil(blank.presentedAlarm(libraryAlarm: { _ in nil }, calendarAlarm: { _ in nil }))
    }

    func testOneTimeCalendarAlarmsLeaveAndStayOutOfTheAlarmList() {
        let calendar = gregorian()
        let now = moment(2026, 11, 25, 8, 0, calendar)
        let future = sample(year: 2026, month: 11, day: 25, hour: 9, minute: 30, rule: .once, label: "Dentist")
        let past = sample(year: 2026, month: 11, day: 24, hour: 9, minute: 0, rule: .once, label: "Gone")
        XCTAssertEqual(future.nextFire(from: now, calendar: calendar), moment(2026, 11, 25, 9, 30, calendar))
        XCTAssertNil(past.nextFire(from: now, calendar: calendar))
        XCTAssertTrue(CalendarFire.shouldRemove(past, now: now, calendar: calendar, hasRung: false))
        XCTAssertFalse(CalendarFire.shouldRemove(future, now: now, calendar: calendar, hasRung: false))
        XCTAssertTrue(CalendarFire.shouldRemove(future, now: now, calendar: calendar, hasRung: true))
        let kept = CalendarFire.keeping([future, past], now: now, calendar: calendar, rungIDs: [])
        XCTAssertEqual(kept.map(\.label), ["Dentist"])
        let scheduled = CalendarFire.scheduled(kept, now: now, calendar: calendar)
        XCTAssertEqual(scheduled.map(\.id), [future.id])
        XCTAssertTrue(AlarmLibrary().alarms.isEmpty)
    }

    func testRepeatingCalendarAlarmsStayAndFindTheNextDate() {
        let calendar = gregorian()
        let morning = moment(2026, 11, 25, 6, 0, calendar)
        let weekly = sample(year: 2026, month: 11, day: 25, hour: 7, minute: 0, rule: .weekly, label: "Weekly")
        XCTAssertEqual(weekly.nextFire(from: morning, calendar: calendar), moment(2026, 11, 25, 7, 0, calendar))
        XCTAssertEqual(
            weekly.nextFire(from: moment(2026, 11, 25, 8, 0, calendar), calendar: calendar),
            moment(2026, 12, 2, 7, 0, calendar)
        )
        XCTAssertFalse(CalendarFire.shouldRemove(weekly, now: morning, calendar: calendar, hasRung: true))
        XCTAssertTrue(weekly.occurs(on: moment(2026, 12, 2, 12, 0, calendar), calendar: calendar))
        XCTAssertFalse(weekly.occurs(on: moment(2026, 11, 24, 12, 0, calendar), calendar: calendar))

        let monthly = sample(year: 2026, month: 1, day: 31, hour: 9, minute: 0, rule: .monthly, label: "Month")
        XCTAssertEqual(
            monthly.nextFire(from: moment(2026, 2, 1, 0, 0, calendar), calendar: calendar),
            moment(2026, 2, 28, 9, 0, calendar)
        )
        XCTAssertFalse(CalendarFire.shouldRemove(monthly, now: morning, calendar: calendar, hasRung: true))

        let yearly = sample(year: 2024, month: 2, day: 29, hour: 8, minute: 15, rule: .yearly, label: "Year")
        XCTAssertEqual(
            yearly.nextFire(from: moment(2025, 3, 1, 0, 0, calendar), calendar: calendar),
            moment(2026, 2, 28, 8, 15, calendar)
        )
    }

    func testMonthGridFollowsTheFirstWeekday() {
        var calendar = gregorian()
        calendar.firstWeekday = 2
        let cells = CalendarGrid.cells(monthContaining: moment(2026, 11, 15, 0, 0, calendar), calendar: calendar)
        XCTAssertEqual(cells.count % 7, 0)
        XCTAssertFalse(cells[0].inMonth)
        XCTAssertTrue(cells[6].inMonth)
        XCTAssertEqual(calendar.component(.day, from: cells[6].date), 1)
    }

    func testSavedLibraryWithoutCalendarAlarmsDecodes() throws {
        let profile = Participant(id: UUID(), displayName: "Maja")
        let snapshot = LibrarySnapshot.empty(profile: profile)
        let encoder = JSONEncoder()
        var object = try JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as! [String: Any]
        object.removeValue(forKey: "calendarAlarms")
        let decoded = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.calendarAlarms.isEmpty)
    }

    private func gregorian() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func sample(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        rule: CalendarRepeat,
        label: String
    ) -> CalendarAlarm {
        CalendarAlarm(
            id: UUID(),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            repeatRule: rule,
            label: label,
            soundID: "classic",
            snoozeEnabled: false,
            snoozeMinutes: 9,
            isEnabled: true
        )
    }
}

final class DemoScreenshotTests: XCTestCase {
    func testDemoDataFillsEveryStoreScreenAndStaysOutOfTheRealLibrary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 9, minute: 41))!
        let snapshot = DemoData.storeSnapshot(now: now, calendar: calendar)
        let names = ContactRoster.contacts(profileID: snapshot.profile.id, grants: snapshot.permissions.grants).map(\.name)
        XCTAssertEqual(names, ["Akhi", "Mama", "Ola", "Tomek"])
        XCTAssertTrue(ContactRoster.contacts(profileID: snapshot.profile.id, grants: snapshot.permissions.grants).allSatisfy { $0.wakeGrantID != nil })
        XCTAssertEqual(snapshot.library.groups.first?.id, DemoData.weekdaysID)
        XCTAssertEqual(snapshot.library.groups.dropFirst().first?.id, DemoData.weekendID)
        let loved = snapshot.library.alarm(DemoData.lovedOneAlarmID)
        XCTAssertEqual(loved?.label, "Akhi")
        XCTAssertEqual(loved?.soundID, DemoData.voiceSoundID)
        XCTAssertEqual(loved?.videoFileID, DemoData.videoID)
        let ringing = snapshot.library.alarm(DemoData.ringingAlarmID)
        XCTAssertEqual(ringing?.origin.senderName, "Akhi")
        XCTAssertFalse(ringing?.note?.isEmpty ?? true)
        XCTAssertEqual(snapshot.sentAlarms.map(\.recipientName), ["Ola", "Tomek"])
        XCTAssertEqual(snapshot.calendarAlarms.count, 4)
        XCTAssertTrue(snapshot.calendarAlarms.contains { $0.occurs(on: now, calendar: calendar) })
        let session = DemoData.napSession(now: now)
        XCTAssertTrue(session.isRunning(at: now))
        XCTAssertEqual(session.minutes, 10)
        let firstUse = DemoTenure.firstUse(now: now, calendar: calendar)
        XCTAssertTrue(SupportMilestone.oneYear.isUnlocked(firstUse: firstUse, now: now, calendar: calendar))
        XCTAssertFalse(SupportMilestone.twoYears.isUnlocked(firstUse: firstUse, now: now, calendar: calendar))
        let wav = DemoMedia.wavData(seconds: 12)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertGreaterThan(wav.count, 12 * 8_000)
    }
}

final class EditorDraftSessionTests: XCTestCase {
    func testCameraDismissalDoesNotDropTheOpenDraft() {
        let draft = AlarmDraft.makeNew()
        XCTAssertEqual(
            EditorDraftSession.draft(current: draft, proposed: nil, capturingVideo: true)?.id,
            draft.id
        )
        XCTAssertNil(EditorDraftSession.draft(current: draft, proposed: nil, capturingVideo: false))
        let replacement = AlarmDraft.makeNew()
        XCTAssertEqual(
            EditorDraftSession.draft(current: draft, proposed: replacement, capturingVideo: true)?.id,
            replacement.id
        )
    }
}

final class OnboardingStoreTests: XCTestCase {
    func testWelcomeAndTipsAreShownOnceAndStayHiddenInDemo() {
        let defaults = UserDefaults(suiteName: "onboarding-\(UUID().uuidString)")!
        XCTAssertTrue(OnboardingStore.shouldShowWelcome(demo: false, defaults: defaults))
        XCTAssertFalse(OnboardingStore.shouldShowWelcome(demo: true, defaults: defaults))
        XCTAssertFalse(OnboardingStore.shouldOfferGroupTip(demo: false, defaults: defaults))

        OnboardingStore.markWelcomeSeen(defaults: defaults)
        XCTAssertFalse(OnboardingStore.shouldShowWelcome(demo: false, defaults: defaults))
        XCTAssertTrue(OnboardingStore.shouldShowGroupTip(demo: false, defaults: defaults))
        XCTAssertTrue(OnboardingStore.shouldShowVoiceTip(demo: false, defaults: defaults))
        XCTAssertFalse(OnboardingStore.shouldShowGroupTip(demo: true, defaults: defaults))
        XCTAssertFalse(OnboardingStore.shouldShowVoiceTip(demo: true, defaults: defaults))

        OnboardingStore.markGroupTipSeen(defaults: defaults)
        XCTAssertFalse(OnboardingStore.shouldShowGroupTip(demo: false, defaults: defaults))
        XCTAssertFalse(OnboardingStore.shouldOfferGroupTip(demo: false, defaults: defaults))
        XCTAssertTrue(OnboardingStore.shouldShowVoiceTip(demo: false, defaults: defaults))

        OnboardingStore.markVoiceTipSeen(defaults: defaults)
        XCTAssertFalse(OnboardingStore.shouldShowVoiceTip(demo: false, defaults: defaults))
        OnboardingStore.markWelcomeSeen(defaults: defaults)
        OnboardingStore.markGroupTipSeen(defaults: defaults)
        XCTAssertFalse(OnboardingStore.shouldShowWelcome(demo: false, defaults: defaults))
        XCTAssertFalse(OnboardingStore.shouldShowGroupTip(demo: false, defaults: defaults))
    }
}
