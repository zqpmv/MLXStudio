import Foundation

/// Routes decoded generation into reasoning vs response segments.
/// Algorithm matches mlx-swift-lm `ReasoningEventEmitter` (main, not in 3.31.4):
/// primed Qwen3/DeepSeek-R1 streams never emit an opening `<think>`, only `</think>`;
/// partial delimiters that straddle chunks are held back in `pendingPrefix`.
struct ReasoningEventEmitter: Sendable {
    enum Segment: Sendable, Equatable {
        case reasoning(String)
        case response(String)
    }

    private let startDelimiter: String
    private let endDelimiter: String
    private let endDelimiters: [String]
    private var inside: Bool
    private var pendingPrefix = ""
    private var pendingLeadingTrim = false

    private(set) var hasClosedReasoning = false

    var isInsideReasoning: Bool { inside }

    init(config: ReasoningConfig, primedInside: Bool) {
        startDelimiter = config.startDelimiter
        endDelimiter = config.endDelimiter
        endDelimiters = [config.endDelimiter] + config.implicitEndDelimiters.filter { $0 != config.endDelimiter }
        inside = primedInside
    }

    /// True when the rendered prompt already opened a think block (typical Qwen3 template).
    static func promptEndsInsideReasoning(renderedPromptTail tail: String, config: ReasoningConfig) -> Bool {
        guard !config.startDelimiter.isEmpty else { return false }
        var trimmed = Substring(tail)
        while let last = trimmed.last, last.isWhitespace {
            trimmed = trimmed.dropLast()
        }
        guard let lastStart = trimmed.range(of: config.startDelimiter, options: .backwards) else {
            return false
        }
        let afterStart = trimmed[lastStart.upperBound...]
        return ([config.endDelimiter] + config.implicitEndDelimiters)
            .filter { !$0.isEmpty }
            .allSatisfy { afterStart.range(of: $0) == nil }
    }

    mutating func process(_ chunk: String) -> [Segment] {
        var output: [Segment] = []
        var working = Substring(pendingPrefix + chunk)
        pendingPrefix = ""

        while true {
            let delimiters = inside ? endDelimiters : [startDelimiter]
            if let match = firstMatch(in: working, delimiters: delimiters) {
                appendSegment(
                    String(working[working.startIndex..<match.range.lowerBound]),
                    trimmingTrailing: true,
                    into: &output
                )

                if inside {
                    hasClosedReasoning = true
                    inside = false
                    if match.delimiter == endDelimiter {
                        working = working[match.range.upperBound...]
                        pendingLeadingTrim = true
                    } else {
                        working = working[match.range.lowerBound...]
                    }
                } else {
                    working = working[match.range.upperBound...]
                    pendingLeadingTrim = true
                    inside = true
                }
            } else {
                let tail = heldBackTailLength(working, delimiters: delimiters)
                let splitIndex = working.index(working.endIndex, offsetBy: -tail)
                appendSegment(
                    String(working[working.startIndex..<splitIndex]),
                    trimmingTrailing: false,
                    into: &output
                )
                pendingPrefix = String(working[splitIndex...])
                break
            }
        }
        return output
    }

    mutating func finalize() -> [Segment] {
        var output: [Segment] = []
        if !pendingPrefix.isEmpty {
            let leftover = pendingPrefix
            pendingPrefix = ""
            appendSegment(leftover, trimmingTrailing: true, into: &output)
        }
        return output
    }

    private mutating func appendSegment(_ text: String, trimmingTrailing: Bool, into output: inout [Segment]) {
        guard !text.isEmpty else { return }
        var t = Substring(text)
        if pendingLeadingTrim {
            t = t.drop(while: \.isWhitespace)
        }
        if trimmingTrailing {
            while let last = t.last, last.isWhitespace { t.removeLast() }
        }
        if t.isEmpty { return }
        pendingLeadingTrim = false
        if inside {
            output.append(.reasoning(String(t)))
        } else {
            output.append(.response(String(t)))
        }
    }

    private func firstMatch(
        in text: Substring,
        delimiters: [String]
    ) -> (delimiter: String, range: Range<String.Index>)? {
        var first: (delimiter: String, range: Range<String.Index>)?
        for delimiter in delimiters where !delimiter.isEmpty {
            guard let range = text.range(of: delimiter) else { continue }
            if let first, range.lowerBound >= first.range.lowerBound { continue }
            first = (delimiter, range)
        }
        return first
    }

    private func heldBackTailLength(_ text: Substring, delimiters: [String]) -> Int {
        delimiters.reduce(0) { longest, delimiter in
            max(longest, heldBackTailLength(text, delimiter: delimiter))
        }
    }

    private func heldBackTailLength(_ text: Substring, delimiter: String) -> Int {
        guard !delimiter.isEmpty else { return 0 }
        let textChars = Array(text)
        let delimiterChars = Array(delimiter)
        var k = min(textChars.count, delimiterChars.count - 1)
        while k >= 1 {
            if textChars.suffix(k).elementsEqual(delimiterChars.prefix(k)) {
                return k
            }
            k -= 1
        }
        return 0
    }
}

extension ReasoningEventEmitter {
    static func splitStoredAssistant(_ raw: String) -> (thinking: String, answer: String) {
        var emitter = ReasoningEventEmitter(config: .thinkTagsWithEnableThinking, primedInside: false)
        var thinking = ""
        var answer = ""
        for segment in emitter.process(raw) + emitter.finalize() {
            switch segment {
            case .reasoning(let text): thinking += text
            case .response(let text): answer += text
            }
        }
        return (thinking, answer)
    }
}
