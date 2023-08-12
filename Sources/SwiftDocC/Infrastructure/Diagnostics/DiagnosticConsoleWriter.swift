/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown

/// Writes diagnostic messages to a text output stream.
///
/// By default, this type writes to `stderr`.
@available(*, deprecated, message: "Use an instance of `DiagnosticFormattingOutputStreamOptions` instead.")
public final class DiagnosticConsoleWriter: DiagnosticFormattingConsumer {

    var outputStream: TextOutputStream
    public var formattingOptions: DiagnosticFormattingOptions
    private var diagnosticFormatter: DiagnosticConsoleFormatter
    private var problems: [Problem] = []

    /// Creates a new instance of this class with the provided output stream and filter level.
    /// - Parameter stream: The output stream to which this instance will write.
    /// - Parameter filterLevel: Determines what diagnostics should be printed. This filter level is inclusive, i.e. if a level of ``DiagnosticSeverity/information`` is specified, diagnostics with a severity up to and including `.information` will be printed.
    @available(*, deprecated, message: "Use init(_:formattingOptions:) instead")
    public convenience init(_ stream: TextOutputStream = LogHandle.standardError, filterLevel: DiagnosticSeverity = .warning) {
        self.init(stream, formattingOptions: [], baseURL: nil, highlight: nil)
    }

    /// Creates a new instance of this class with the provided output stream.
    /// - Parameters:
    ///   - stream: The output stream to which this instance will write.
    ///   - formattingOptions: The formatting options for the diagnostics.
    ///   - baseUrl: A url to be used as a base url when formatting diagnostic source path.
    ///   - highlight: Whether or not to highlight the default diagnostic formatting output.
    public init(
        _ stream: TextOutputStream = LogHandle.standardError,
        formattingOptions options: DiagnosticFormattingOptions = [],
        baseURL: URL? = nil,
        highlight: Bool? = nil
    ) {
        outputStream = stream
        formattingOptions = options
        diagnosticFormatter = Self.makeDiagnosticFormatter(
            options,
            baseURL: baseURL,
            highlight: highlight ?? TerminalHelper.isConnectedToTerminal
        )
    }

    public func receive(_ problems: [Problem]) {
        if formattingOptions.contains(.formatConsoleOutputForTools) {
            // Add a newline after each formatter description, including the last one.
            let text = problems.map { diagnosticFormatter.formattedDescription(for: $0).appending("\n") }.joined()
            outputStream.write(text)
        } else {
            self.problems.append(contentsOf: problems)
        }
    }
    
    public func finalize() throws {
        if formattingOptions.contains(.formatConsoleOutputForTools) {
            // For tools, the console writer writes each diagnostic as they are received.
        } else {
            let text = self.diagnosticFormatter.formattedDescription(for: problems)
            outputStream.write(text)
        }
        self.diagnosticFormatter.finalize()
    }
    
    private static func makeDiagnosticFormatter(
        _ options: DiagnosticFormattingOptions,
        baseURL: URL?,
        highlight: Bool
    ) -> DiagnosticConsoleFormatter {
        if options.contains(.formatConsoleOutputForTools) {
            return IDEDiagnosticConsoleFormatter()
        } else {
            return DefaultDiagnosticConsoleFormatter(baseUrl: baseURL, dataProvider: nil, highlight: highlight)
        }
    }
}

// MARK: Formatted descriptions

@available(*, deprecated)
extension DiagnosticConsoleWriter { // FIXME: deprecate and replace this APIs with new architecture.

    public static func formattedDescription<Problems>(for problems: Problems, options: DiagnosticFormattingOptions = []) -> String where Problems: Sequence, Problems.Element == Problem {
        return problems.map { formattedDescription(for: $0, options: options) }.joined(separator: "\n")
    }
    
    public static func formattedDescription(for problem: Problem, options: DiagnosticFormattingOptions = []) -> String {
        let diagnosticFormatter = makeDiagnosticFormatter(options, baseURL: nil, highlight: TerminalHelper.isConnectedToTerminal)
        return diagnosticFormatter.formattedDescription(for: problem)
    }
    
    public static func formattedDescription(for diagnostic: Diagnostic, options: DiagnosticFormattingOptions = []) -> String {
        let diagnosticFormatter = makeDiagnosticFormatter(options, baseURL: nil, highlight: TerminalHelper.isConnectedToTerminal)
        return diagnosticFormatter.formattedDescription(for: diagnostic)
    }
}
