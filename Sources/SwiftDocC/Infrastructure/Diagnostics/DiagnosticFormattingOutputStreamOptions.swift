/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

public protocol DiagnosticFormattingOutputStreamOptions {
    func makeFormatter(_ outputStream: TextOutputStream) -> DiagnosticConsumer
}

public struct ToolsFormattingOptions: DiagnosticFormattingOutputStreamOptions {
    public init() {}

    public func makeFormatter(
        _ outputStream: TextOutputStream
    ) -> DiagnosticConsumer {
        StreamingDiagnosticOutputStreamWriter(
            formatter: IDEDiagnosticConsoleFormatter(),
            outputStream: outputStream
        )
    }
}

public struct HumanReadableFormattingOptions: DiagnosticFormattingOutputStreamOptions {
    private let baseUrl: URL?
    private let dataProvider: DocumentationWorkspaceDataProvider?
    private let highlight: Bool

    public init(
        baseUrl: URL?,
        dataProvider: DocumentationWorkspaceDataProvider?,
        highlight: Bool? = nil
    ) {
        self.baseUrl = baseUrl
        self.dataProvider = dataProvider
        self.highlight = highlight ?? TerminalHelper.isConnectedToTerminal
    }

    public func makeFormatter(
        _ outputStream: TextOutputStream
    ) -> DiagnosticConsumer {
        BufferedDiagnosticOutputStreamWriter(
            formatter: DefaultDiagnosticConsoleFormatter(
                baseUrl: baseUrl,
                dataProvider: dataProvider,
                highlight: highlight
            ),
            outputStream: outputStream
        )
    }
}
