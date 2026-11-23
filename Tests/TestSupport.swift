import Foundation

private var failureCount = 0
private var checkCount = 0

/// Records one expectation. A failure prints where it happened and keeps going.
func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #fileID, line: UInt = #line) {
    checkCount += 1
    if !condition() {
        failureCount += 1
        fputs("FAIL \(file):\(line) \(message)\n", stderr)
    }
}

@main
struct TestMain {
    static func main() throws {
        try composerTests()
        runnerTests()
        guardTests()
        if failureCount > 0 {
            fputs("\(failureCount) of \(checkCount) checks failed\n", stderr)
            exit(1)
        }
        print("\(checkCount) checks passed")
    }
}
