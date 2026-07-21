import Foundation

public struct PromptTemplate: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var nameZH: String
    public var body: String
    public var bodyZH: String
    public var variables: [String]
    public var builtIn: Bool
    public var enabled: Bool

    public init(
        id: String,
        name: String,
        nameZH: String,
        body: String,
        bodyZH: String,
        variables: [String] = ["selected_text", "section_context", "user_goal"],
        builtIn: Bool = true,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.nameZH = nameZH
        self.body = body
        self.bodyZH = bodyZH
        self.variables = variables
        self.builtIn = builtIn
        self.enabled = enabled
    }
}

public enum BuiltInPrompts {
    public static let all: [PromptTemplate] = [
        PromptTemplate(
            id: "academic-polish.v1",
            name: "Academic Polish",
            nameZH: "学术润色",
            body: "Polish the selected text for precise academic English. Preserve meaning, evidence, citations, labels, equations, and LaTeX commands.",
            bodyZH: "将选中文本润色为准确、克制的学术表达。保持原意、证据、引用、标签、公式和 LaTeX 命令不变。"
        ),
        PromptTemplate(
            id: "clarity.v1",
            name: "Improve Clarity",
            nameZH: "提升清晰度",
            body: "Rewrite the selected text to improve logical flow and readability without adding claims or changing technical meaning.",
            bodyZH: "改写选中文本以提升逻辑衔接和可读性，不增加新结论，也不改变技术含义。"
        ),
        PromptTemplate(
            id: "shorten.v1",
            name: "Shorten",
            nameZH: "压缩篇幅",
            body: "Shorten the selected text while retaining every essential claim, condition, result, citation, and LaTeX command.",
            bodyZH: "压缩选中文本，同时保留所有必要结论、条件、结果、引用和 LaTeX 命令。"
        ),
        PromptTemplate(
            id: "expand.v1",
            name: "Expand Explanation",
            nameZH: "扩展说明",
            body: "Expand the selected explanation using only facts supported by the provided context. Do not invent evidence or citations.",
            bodyZH: "仅依据所附上下文扩展选中说明，不得虚构证据或引用。"
        ),
        PromptTemplate(
            id: "translate-en.v1",
            name: "Translate to Academic English",
            nameZH: "翻译为学术英文",
            body: "Translate the selected text into natural academic English. Preserve LaTeX syntax, symbols, citations, labels, and equations exactly.",
            bodyZH: "将选中文本翻译为自然的学术英文，严格保留 LaTeX 语法、符号、引用、标签和公式。"
        ),
        PromptTemplate(
            id: "logic-review.v1",
            name: "Check Logic",
            nameZH: "检查逻辑",
            body: "Identify logical gaps, unsupported transitions, ambiguity, or conflicts with the supplied context. Propose the smallest correction.",
            bodyZH: "识别逻辑缺口、无依据的跳跃、歧义或与上下文的冲突，并提出最小修改。"
        ),
        PromptTemplate(
            id: "reviewer-action.v1",
            name: "Apply Reviewer Request",
            nameZH: "落实审稿意见",
            body: "Revise only the explicit targets to address the reviewer request in {{user_goal}}. Do not write reviewer-response prose unless asked.",
            bodyZH: "仅修改明确目标以落实 {{user_goal}} 中的审稿要求。除非明确要求，不要撰写回复审稿人的文字。"
        ),
        PromptTemplate(
            id: "citation-audit.v1",
            name: "Citation Audit",
            nameZH: "引用检查",
            body: "Check whether citation placement and nearby claims are internally consistent. Do not invent or replace citation keys.",
            bodyZH: "检查引用位置与附近论断是否一致，不得虚构或替换引用键。"
        )
    ]

    public static func render(_ template: PromptTemplate, language: String, variables: [String: String]) -> String {
        var result = language.hasPrefix("zh") ? template.bodyZH : template.body
        for (name, value) in variables {
            result = result.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return result
    }
}
