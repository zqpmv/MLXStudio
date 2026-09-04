import Foundation
import MarkdownUI
import SwiftUI

struct StudioCodeHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        let lang = language?.lowercased() ?? ""
        let keywords = Self.keywords(for: lang)
        guard !keywords.isEmpty else {
            return Text(code).font(.system(.body, design: .monospaced))
        }

        var result = Text("")
        let pattern = #"(\/\/[^\n]*|#[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b[A-Za-z_][A-Za-z0-9_]*\b|\d+(?:\.\d+)?|\s+|.)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsCode = code as NSString
        let full = NSRange(location: 0, length: nsCode.length)
        let matches = regex?.matches(in: code, range: full) ?? []

        if matches.isEmpty {
            return Text(code).font(.system(.body, design: .monospaced))
        }

        for match in matches {
            let token = nsCode.substring(with: match.range)
            result = result + styled(token, keywords: keywords)
        }
        return result.font(.system(.body, design: .monospaced))
    }

    private func styled(_ token: String, keywords: Set<String>) -> Text {
        if token.hasPrefix("//") || token.hasPrefix("#") && !token.hasPrefix("#!") {
            return Text(token).foregroundStyle(.secondary)
        }
        if token.hasPrefix("\"") || token.hasPrefix("'") {
            return Text(token).foregroundStyle(.green)
        }
        if token.first?.isNumber == true {
            return Text(token).foregroundStyle(.orange)
        }
        if keywords.contains(token) {
            return Text(token).foregroundStyle(.purple)
        }
        return Text(token)
    }

    private static func keywords(for language: String) -> Set<String> {
        switch language {
        case "swift":
            ["let", "var", "func", "struct", "class", "enum", "import", "return", "if", "else", "guard", "switch", "case", "for", "while", "in", "true", "false", "nil", "self", "async", "await", "try", "throws", "private", "public", "static"]
        case "python", "py":
            ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "in", "True", "False", "None", "and", "or", "not", "with", "as", "try", "except", "async", "await", "lambda", "yield"]
        case "javascript", "js", "typescript", "ts":
            ["const", "let", "var", "function", "return", "if", "else", "for", "while", "class", "import", "from", "export", "async", "await", "true", "false", "null", "undefined", "new"]
        case "json":
            ["true", "false", "null"]
        case "rust":
            ["fn", "let", "mut", "struct", "enum", "impl", "pub", "use", "return", "if", "else", "match", "true", "false", "async", "await"]
        case "go":
            ["func", "var", "const", "package", "import", "return", "if", "else", "for", "range", "struct", "type", "true", "false", "nil"]
        case "bash", "sh", "shell", "zsh":
            ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case", "esac", "function", "return", "export"]
        default:
            []
        }
    }
}
