import Foundation

protocol JumpLogging: Sendable {
    func log(_ message: String)
}

struct JumpLogger: JumpLogging {
    private let sink: @Sendable (String) -> Void

    init(sink: @escaping @Sendable (String) -> Void = { message in
        NSLog("%@", message)
    }) {
        self.sink = sink
    }

    func log(_ message: String) {
        sink(message)
    }
}
