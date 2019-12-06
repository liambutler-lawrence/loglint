import Foundation
import RxSwift

/// TODOS:
/// - Figure out how 3rd party libs are posting logs before we turn on linting at the top of didFinishLaunching
/// - Figure out variable-length wildcards or use alterntative like regexes
/// - Figure out multi-line logs
public class LogLinter {

    // MARK: - Constants

    private let logPublishSubject = PublishSubject<String>()
    private let disposeBag = DisposeBag()

    // MARK: - Constant Properties

    private let logWhitelist: [String]

    // MARK: - Variable Properties

    private lazy var fileChangeQueue = SKQueue(delegate: self)!

    private var logFileContents = "" {
        didSet {
            let oldLogLines = oldValue.components(separatedBy: "\n").filter { !$0.isEmpty }
            let newLogLines = logFileContents.components(separatedBy: "\n").filter { !$0.isEmpty }
            let newLogLineCount = newLogLines.count - oldLogLines.count

            guard newLogLineCount >= 0 else {
                print("Somehow log file lost lines")
                return
            }

            guard oldLogLines == Array(newLogLines.dropLast(newLogLineCount)) else {
                print("Existing lines changed in log file")
                return
            }

            guard newLogLineCount > 0 else {
                print("No change in log file")
                return
            }

            let newLogs = newLogLines.suffix(newLogLineCount)
            newLogs.forEach {
                logPublishSubject.onNext($0)
            }
        }
    }

    // MARK: - Initializers

    public init(logWhitelist: [String]) {
        self.logWhitelist = logWhitelist
    }

    // MARK: - Functions

    public func startLinting() {
        let documentsDirPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!

        let logFilePath = documentsDirPath + "/hijacked_output_\(UUID()).log"
        print(
            """
            ********** LOG LINTER ENABLED **********
            Redirecting logs to observed file at \(logFilePath)
            """
        )

        // swiftlint:disable:next force_try
        try! "".write(to: URL(fileURLWithPath: logFilePath), atomically: true, encoding: .utf8)

        // swiftlint:disable:next force_try
        try! fileChangeQueue.addPath(logFilePath)

//        print("[TEST BEFORE] print")
//        os_log("[TEST BEFORE] os_log")
        //        NSLog("[TEST BEFORE] NSLog")

        freopen(logFilePath, "a+", stderr)

        func isWhitelisted(logLine: String) -> Bool {
            return logWhitelist.map { whitelistString in

                guard whitelistString.count == logLine.count else {
                    return false
                }

                var pos = 0
                for char in logLine {

                    let whitelistPos = whitelistString.index(whitelistString.startIndex, offsetBy: pos)

                    if char == whitelistString[whitelistPos] || whitelistString[whitelistPos] == "*" {
                        pos += 1
                    } else {
                        return false
                    }
                }

                return true
            }.contains(true)
        }

        logPublishSubject.subscribe(onNext: { logLine in

            guard !isWhitelisted(logLine: logLine) else {
                print("Log whitelisted: \(logLine)")
                return
            }
            print(
                """
                ********** LOG LINTER CAUGHT AN UNEXPECTED LOG **********
                Please address the issue that caused this log, then re-run your application.
                \(logLine)
                """
            )
             fatalError()
        }).disposed(by: disposeBag)

//        print("[TEST AFTER] print")
//        os_log("[TEST AFTER] os_log")
//        NSLog("[TEST AFTER] NSLog")

        //            freopen(logFilePath, "a+", stdout)
        //
        //            print("[TEST AFTEROUT] print")
        //            os_log("[TEST AFTEROUT] os_log")
        //            NSLog("[TEST AFTEROUT] NSLog")
    }
}

extension LogLinter: SKQueueDelegate {

    // MARK: - Functions

    public func receivedNotification(_ notification: SKQueueNotification, path: String, queue: SKQueue) {
        guard notification.contains(.Write) else {
            return
        }

        DispatchQueue.main.async {
            do {
                self.logFileContents = try String(contentsOfFile: path)
            } catch {
                print("********** LOG LINTER COULD NOT READ INTERCEPTED LOG **********")
                fatalError()
            }
        }
    }
}
