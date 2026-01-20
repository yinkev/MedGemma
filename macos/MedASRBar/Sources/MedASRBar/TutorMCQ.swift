import Foundation

struct TutorMCQ: Equatable {
    struct Option: Equatable, Identifiable {
        let label: String
        let text: String

        var id: String { "\(label):\(text)" }
        var displayText: String { "\(label). \(text)" }
    }

    let prompt: String
    let options: [Option]
}

enum TutorMCQParser {
    static func parse(from question: String) -> TutorMCQ? {
        let normalized = question.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var promptLines: [String] = []
        var options: [TutorMCQ.Option] = []
        var currentLabel: String?
        var currentText: String = ""

        func flushCurrent() {
            guard let label = currentLabel else { return }
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                options.append(.init(label: label, text: text))
            }
            currentLabel = nil
            currentText = ""
        }

        let regex = try? NSRegularExpression(pattern: "^\\s*\\(?([A-Da-d])\\)?[\\).:]\\s*(.+)$")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let regex {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 3,
                   let labelRange = Range(match.range(at: 1), in: line),
                   let textRange = Range(match.range(at: 2), in: line) {
                    flushCurrent()
                    currentLabel = String(line[labelRange]).uppercased()
                    currentText = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    continue
                }
            }

            if currentLabel == nil {
                promptLines.append(line)
            } else if !trimmed.isEmpty {
                if currentText.isEmpty {
                    currentText = trimmed
                } else {
                    currentText += " " + trimmed
                }
            }
        }

        flushCurrent()

        guard options.count >= 2 else { return nil }

        let prompt = promptLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return TutorMCQ(prompt: prompt, options: options)
    }
}
