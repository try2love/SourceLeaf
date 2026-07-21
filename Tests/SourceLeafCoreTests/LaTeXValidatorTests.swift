import Testing
@testable import SourceLeafCore

@Test func validatesBalancedLatex() {
    let result = LaTeXValidator.validate(
        original: #"Text \cite{paper}."#,
        replacement: #"Clearer text \cite{paper}."#
    )
    #expect(result.hasErrors == false)
    #expect(result.sensitiveChanges.isEmpty)
}

@Test func flagsSensitiveAndStructuralChanges() {
    let result = LaTeXValidator.validate(
        original: #"Text \cite{paper}."#,
        replacement: #"Text \cite{other} with {broken."#
    )
    #expect(result.hasErrors)
    #expect(result.sensitiveChanges.count == 2)
}

@Test func validatesEnvironmentStack() {
    let issues = LaTeXValidator.validateStructure("\\begin{itemize}\n\\item A")
    #expect(issues.contains { $0.message.contains("end{itemize}") })
}
