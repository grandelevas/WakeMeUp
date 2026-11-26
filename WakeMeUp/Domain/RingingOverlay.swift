import Foundation

struct RingingOverlayState: Equatable {
    var ringingID: UUID? = nil
    var held: Alarm? = nil
    var nap: NapSession? = nil

    /// The alarm the full-screen cover is allowed to draw.
    /// A ringing id with no alarm must not present a cover: that cover is an empty black screen.
    func presentedAlarm(
        libraryAlarm: (UUID) -> Alarm?,
        calendarAlarm: (UUID) -> Alarm?
    ) -> Alarm? {
        guard let ringingID else { return nil }
        if let held, held.id == ringingID { return held }
        if let alarm = libraryAlarm(ringingID) { return alarm }
        if let alarm = calendarAlarm(ringingID) { return alarm }
        return nil
    }
}

enum RingingOverlay {
    /// Applies the alarms AlarmKit currently says are alerting.
    /// An empty set means the person stopped or snoozed the alarm, including from the Lock Screen.
    static func apply(
        alerting: Set<UUID>,
        state: RingingOverlayState,
        now: Date,
        libraryAlarm: (UUID) -> Alarm?,
        calendarAlarm: (UUID) -> Alarm?
    ) -> RingingOverlayState {
        var state = state
        let candidates = ordered(alerting, preferring: state.ringingID)
        if let chosen = candidates.first(where: { resolve($0, state: state, libraryAlarm: libraryAlarm, calendarAlarm: calendarAlarm) != nil }) {
            let alarm = resolve(chosen, state: state, libraryAlarm: libraryAlarm, calendarAlarm: calendarAlarm)
            state.ringingID = chosen
            state.held = alarm
            if state.nap?.id == chosen {
                state.nap = nil
            }
        } else {
            state.ringingID = nil
            state.held = nil
        }
        if let nap = state.nap, !nap.isRunning(at: now), !alerting.contains(nap.id) {
            state.nap = nil
        }
        return state
    }

    private static func ordered(_ alerting: Set<UUID>, preferring current: UUID?) -> [UUID] {
        var ids = alerting.sorted { $0.uuidString < $1.uuidString }
        if let current, let index = ids.firstIndex(of: current) {
            ids.remove(at: index)
            ids.insert(current, at: 0)
        }
        return ids
    }

    private static func resolve(
        _ id: UUID,
        state: RingingOverlayState,
        libraryAlarm: (UUID) -> Alarm?,
        calendarAlarm: (UUID) -> Alarm?
    ) -> Alarm? {
        if let nap = state.nap, nap.id == id { return nap.alarm() }
        if let alarm = libraryAlarm(id) { return alarm }
        if let alarm = calendarAlarm(id) { return alarm }
        if let held = state.held, held.id == id { return held }
        return nil
    }
}
