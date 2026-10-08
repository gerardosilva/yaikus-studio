import Foundation

/// Local validators: they run on whatever ANY agent returns, so quality does not depend on the AI.
public enum Rules {
    public static func wordCount(_ s: String) -> Int { s.split(whereSeparator: { $0.isWhitespace }).count }

    public static func validate(title: String = "", hook: String, script: String, playbook: Playbook) -> [Problem] {
        var out: [Problem] = []
        let script = script.trimmingCharacters(in: .whitespacesAndNewlines)
        let hook = hook.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = wordCount(script)
        if script.isEmpty { out.append(Problem(.empty)) }
        else if n < playbook.minWords { out.append(Problem(.tooShort, n: n, min: playbook.minWords)) }
        else if n > playbook.maxWords { out.append(Problem(.tooLong, n: n, max: playbook.maxWords)) }
        if !hook.isEmpty, wordCount(hook) > playbook.hookMaxWords { out.append(Problem(.hookLong, n: wordCount(hook), max: playbook.hookMaxWords)) }
        let low = (script + " " + hook).lowercased()
        for b in playbook.banned where !b.isEmpty && low.contains(b.lowercased()) { out.append(Problem(.banned, phrase: b)) }
        if script.range(of: #"https?://|#\w+|\[\d+(,\s*\d+)*\]"#, options: .regularExpression) != nil { out.append(Problem(.junk)) }
        return out
    }

    /// English text used to send the problems back to the agent.
    public static func describe(_ problems: [Problem]) -> String {
        problems.map { p -> String in
            switch p.code {
            case .empty: return "- The script is empty."
            case .tooShort: return "- The script has \(p.n ?? 0) words; the minimum is \(p.min ?? 0)."
            case .tooLong: return "- The script has \(p.n ?? 0) words; the maximum is \(p.max ?? 0)."
            case .hookLong: return "- The hook has \(p.n ?? 0) words; the maximum is \(p.max ?? 0)."
            case .banned: return "- It contains the banned phrase \"\(p.phrase ?? "")\"."
            case .junk: return "- The script contains links, hashtags or [1]-style citations; remove them."
            }
        }.joined(separator: "\n")
    }
}
