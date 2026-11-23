import Foundation

private extension GuardDecision {
    var isDisable: Bool {
        if case .disable = self { return true }
        return false
    }

    var isRetire: Bool {
        if case .retire = self { return true }
        return false
    }
}

func guardTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // The deadline is the next 08:00 strictly after the moment KeepGoing is switched on.
    check(KeepGoingGuard.nextDeadline(hour: 8, minute: 0, after: at(24, 23, 0), calendar: calendar) == at(25, 8, 0), "23:00 → tomorrow 08:00")
    check(KeepGoingGuard.nextDeadline(hour: 8, minute: 0, after: at(24, 7, 0), calendar: calendar) == at(24, 8, 0), "07:00 → today 08:00")
    check(KeepGoingGuard.nextDeadline(hour: 8, minute: 0, after: at(24, 8, 0), calendar: calendar) == at(25, 8, 0), "08:00 exactly → tomorrow")

    let both = KeepGoingAutoOffSettings()
    let state = KeepGoingGuard.makeState(from: both, now: at(24, 23, 0), calendar: calendar)
    check(state?.deadline == at(25, 8, 0) && state?.batteryFloorPercent == 20, "default rules: 08:00 and 20%")
    var none = KeepGoingAutoOffSettings()
    none.deadlineEnabled = false
    none.batteryFloorEnabled = false
    check(KeepGoingGuard.makeState(from: none, now: at(24, 23, 0), calendar: calendar) == nil, "no rules → no guard")

    let armed = KeepGoingGuardState(deadline: at(25, 8, 0), batteryFloorPercent: 20, armedAt: at(24, 23, 0))
    let battery40 = BatteryReading(percent: 40, onBattery: true)
    check(KeepGoingGuard.evaluate(state: armed, sleepDisabled: true, battery: battery40, now: at(25, 3, 0)) == .idle, "03:00 at 40%: keep going")
    check(KeepGoingGuard.evaluate(state: armed, sleepDisabled: true, battery: battery40, now: at(25, 8, 0)).isDisable, "08:00 reached: switch off")
    check(KeepGoingGuard.evaluate(state: armed, sleepDisabled: true, battery: BatteryReading(percent: 18, onBattery: true), now: at(25, 3, 0)).isDisable, "18% on battery: switch off")
    check(KeepGoingGuard.evaluate(state: armed, sleepDisabled: true, battery: BatteryReading(percent: 5, onBattery: false), now: at(25, 3, 0)) == .idle, "5% but charging: keep going")
    check(KeepGoingGuard.evaluate(state: armed, sleepDisabled: true, battery: nil, now: at(25, 3, 0)) == .idle, "no battery (desktop Mac): only the deadline applies")
    check(KeepGoingGuard.evaluate(state: armed, sleepDisabled: false, battery: battery40, now: at(25, 3, 0)).isRetire, "KeepGoing already off: the guard retires")
    check(KeepGoingGuard.evaluate(state: nil, sleepDisabled: true, battery: battery40, now: at(25, 3, 0)).isRetire, "no saved rules: the guard retires")

    // Settings round-trip through the store.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KeepGoingGuardTests-\(UUID().uuidString)")
    let store = KeepGoingStore(directory: directory)
    check(store.loadAutoOff() == KeepGoingAutoOffSettings(), "missing file → defaults")
    var custom = KeepGoingAutoOffSettings()
    custom.deadlineHour = 7
    custom.deadlineMinute = 30
    custom.batteryFloorPercent = 30
    try? store.saveAutoOff(custom)
    check(store.loadAutoOff() == custom, "auto-off settings round-trip")
    try? store.saveGuardState(armed)
    check(store.loadGuardState() == armed, "guard state round-trips")
    store.clearGuardState()
    check(store.loadGuardState() == nil, "guard state clears")
    try? FileManager.default.removeItem(at: directory)
}
