import Foundation

struct AlarmSyncPlan: Equatable {
    var schedule: [UUID]
    var cancel: [UUID]

    /// Enabled alarms that are new or changed need a schedule call.
    /// Enabled alarms that disappeared or were switched off need a cancel.
    static func make(previous: [Alarm], current: [Alarm]) -> AlarmSyncPlan {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var schedule: [UUID] = []
        var cancel: [UUID] = []
        for (id, alarm) in currentByID {
            if alarm.isEnabled {
                if previousByID[id] != alarm {
                    schedule.append(id)
                }
            } else if previousByID[id]?.isEnabled == true {
                cancel.append(id)
            }
        }
        for (id, alarm) in previousByID where currentByID[id] == nil && alarm.isEnabled {
            cancel.append(id)
        }
        return AlarmSyncPlan(
            schedule: schedule.sorted { $0.uuidString < $1.uuidString },
            cancel: cancel.sorted { $0.uuidString < $1.uuidString }
        )
    }
}
