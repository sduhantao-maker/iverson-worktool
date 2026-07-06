import Foundation

@main
struct AutoMessageHelper {
    static func main() {
        let result = AutoMessageRunner().runOnce()
        FileHandle.standardOutput.write(Data((result.message + "\n").utf8))
        exit(result.ok ? 0 : 1)
    }
}
