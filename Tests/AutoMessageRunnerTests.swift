import Foundation

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func target(_ name: String, message: String = "继续昨天的任务", enabled: Bool = true) -> AutoMessageTarget {
    AutoMessageTarget(enabled: enabled, appName: name, processName: name, message: message, filePaths: nil, launchWaitSeconds: 0)
}

private func settings(hour: Int = 2, minute: Int = 0, dryRun: Bool = false, startDate: Date? = nil, targets: [AutoMessageTarget]) -> AutoMessageSettings {
    AutoMessageSettings(startDate: startDate, hour: hour, minute: minute, dryRun: dryRun, submitAfterPaste: true, targets: targets, updatedAt: Date())
}

/// A runner whose clock, session and delivery are all fake.
private func makeRunner(now: Date, session: ScreenSessionState = ScreenSessionState(hasGUISession: true, isLocked: false, isOnConsole: true),
                        deliver: @escaping (AutoMessageTarget) -> AutoMessageRunResult) -> AutoMessageRunner {
    let store = AutoMessageSettingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("runner-tests.json"))
    var environment = AutoMessageEnvironment()
    environment.now = { now }
    environment.calendar = calendar
    environment.screenSession = { session }
    environment.accessibilityTrusted = { _ in true }
    let runner = AutoMessageRunner(store: store, environment: environment)
    runner.deliverOverride = { target, _ in deliver(target) }
    return runner
}

func runnerTests() {
    // Lateness is measured from the most recent planned time, across midnight too.
    let plan = settings(targets: [target("Codex")])
    check(AutoMessageRunner.lateness(of: plan, now: date(2026, 11, 24, 2, 0, 20), calendar: calendar) == 20, "on time: 20 s late")
    check(AutoMessageRunner.staleRunResult(plan, now: date(2026, 11, 24, 2, 17), calendar: calendar) == nil, "17 min late is still sent")
    check(AutoMessageRunner.staleRunResult(plan, now: date(2026, 11, 24, 9, 10), calendar: calendar)?.status == .skipped, "a run at 09:10 for 02:00 is skipped")
    let lateNight = settings(hour: 23, minute: 50, targets: [target("Codex")])
    check(AutoMessageRunner.lateness(of: lateNight, now: date(2026, 11, 25, 0, 10), calendar: calendar) == 20 * 60, "23:50 → 00:10 is 20 min late")
    check(AutoMessageRunner.staleRunResult(lateNight, now: date(2026, 11, 25, 7, 0), calendar: calendar)?.status == .skipped, "23:50 → 07:00 next day is skipped")

    // One failing target does not stop the others.
    var attempted: [String] = []
    let independent = makeRunner(now: date(2026, 11, 24, 2, 0)) { target in
        attempted.append(target.appName)
        return target.appName == "Codex" ? .failed("打开 Codex 失败") : .sent("已发送到 Claude 并回车提交")
    }
    let mixed = independent.run(settings: settings(targets: [target("Codex"), target("Claude")]), trigger: .scheduled)
    check(attempted == ["Codex", "Claude"], "both targets are attempted, in order (got \(attempted))")
    check(mixed.status == .failed && mixed.message.hasPrefix("部分失败"), "a partial failure is reported as such (got \(mixed.message))")
    check(mixed.message.contains("Claude"), "the result names the target that worked")

    // An invalid target is reported, and the valid one is still sent.
    attempted = []
    let validation = makeRunner(now: date(2026, 11, 24, 2, 0)) { target in
        attempted.append(target.appName)
        return .sent("已发送到 \(target.appName)")
    }
    let invalid = validation.run(settings: settings(targets: [target("Codex", message: "  "), target("Claude")]), trigger: .scheduled)
    check(attempted == ["Claude"], "the empty target is not delivered, the other one is")
    check(invalid.message.contains("Codex：消息和附件都是空的"), "the empty target is named in the result")

    // A locked screen stops the run before anything is typed.
    var delivered = false
    let locked = makeRunner(now: date(2026, 11, 24, 2, 0), session: ScreenSessionState(hasGUISession: true, isLocked: true, isOnConsole: true)) { _ in
        delivered = true
        return .sent("x")
    }
    let lockedResult = locked.run(settings: settings(targets: [target("Codex")]), trigger: .scheduled)
    check(lockedResult.status == .failed && lockedResult.message.contains("屏幕已锁定"), "a locked screen fails the run")
    check(!delivered, "nothing is delivered while the screen is locked")

    // A stale scheduled run is skipped; a manual send at the same moment still goes out.
    delivered = false
    let stale = makeRunner(now: date(2026, 11, 24, 8, 0)) { _ in
        delivered = true
        return .sent("x")
    }
    check(stale.run(settings: plan, trigger: .scheduled).status == .skipped, "a scheduled run 6 h late is skipped")
    check(!delivered, "the stale scheduled run delivers nothing")
    check(stale.run(settings: plan, trigger: .manual).status == .sent, "a manual send ignores the schedule")

    // Dry run, start date and an empty target list all skip without delivering.
    delivered = false
    let quiet = makeRunner(now: date(2026, 11, 24, 2, 0)) { _ in
        delivered = true
        return .sent("x")
    }
    check(quiet.run(settings: settings(dryRun: true, targets: [target("Codex")]), trigger: .manual).status == .skipped, "dry run skips")
    check(quiet.run(settings: settings(startDate: date(2026, 12, 1, 0, 0), targets: [target("Codex")]), trigger: .scheduled).status == .skipped, "before the start date skips")
    check(quiet.run(settings: settings(targets: [target("Codex", enabled: false)]), trigger: .manual).status == .skipped, "no enabled target skips")
    check(!delivered, "skipped runs deliver nothing")

    // Summaries.
    check(AutoMessageRunner.summarize([.sent("a"), .sent("b")]).status == .sent, "all sent → sent")
    check(AutoMessageRunner.summarize([.failed("a"), .failed("b")]).message == "a；b", "all failed → plain list")
}
