/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

final class BufferedDiagnosticOutputStreamWriter: DiagnosticConsumer {
    private let formatter: DiagnosticConsoleFormatter
    private var outputStream: TextOutputStream
    private var problems: [Problem] = []

    init(
        formatter: DiagnosticConsoleFormatter,
        outputStream: TextOutputStream
    ) {
        self.formatter = formatter
        self.outputStream = outputStream
    }

    public func receive(_ problems: [Problem]) {
        self.problems.append(contentsOf: problems)
    }

    public func finalize() throws {
        let text = self.formatter.formattedDescription(for: problems)
        outputStream.write(text)
        self.formatter.finalize()
    }
}

final class StreamingDiagnosticOutputStreamWriter: DiagnosticConsumer {
    private let formatter: DiagnosticConsoleFormatter
    private var outputStream: TextOutputStream

    init(
        formatter: DiagnosticConsoleFormatter,
        outputStream: TextOutputStream
    ) {
        self.formatter = formatter
        self.outputStream = outputStream
    }

    public func receive(_ problems: [Problem]) {
        // Add a newline after each formatter description, including the last one.
        let text = problems
            .map { formatter.formattedDescription(for: $0).appending("\n") }
            .joined()
        outputStream.write(text)
    }

    public func finalize() throws {
        self.formatter.finalize()
    }
}
