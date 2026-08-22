import Foundation

struct ASSSubtitleConversion: Equatable, Sendable {
    let webVTT: String
    let simplifiedEffects: Bool
}

enum ASSSubtitleConverter {
    static func convert(_ source: String) -> ASSSubtitleConversion {
        let normalized =
            source
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
        var section = ""
        var playResX = 384.0
        var playResY = 288.0
        var styleFormat: [String] = []
        var eventFormat: [String] = []
        var styles: [String: ASSStyle] = [:]
        var cues: [ASSCue] = []
        var simplifiedEffects = false

        for rawLine in normalized.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = line.lowercased()
                continue
            }

            if section == "[script info]" {
                if let value = value(after: "PlayResX:", in: line), let parsed = Double(value), parsed > 0 {
                    playResX = parsed
                } else if let value = value(after: "PlayResY:", in: line), let parsed = Double(value), parsed > 0 {
                    playResY = parsed
                }
                continue
            }

            if section == "[v4+ styles]" || section == "[v4 styles]" {
                if let value = value(after: "Format:", in: line) {
                    styleFormat = commaSeparated(value).map(normalizedFieldName)
                } else if let value = value(after: "Style:", in: line), !styleFormat.isEmpty {
                    let fields = split(value, expectedCount: styleFormat.count)
                    let values = mappedValues(format: styleFormat, fields: fields)
                    let style = ASSStyle(values: values, usesLegacyAlignment: section == "[v4 styles]")
                    styles[style.name.lowercased()] = style
                }
                continue
            }

            if section == "[events]" {
                if let value = value(after: "Format:", in: line) {
                    eventFormat = commaSeparated(value).map(normalizedFieldName)
                    continue
                }
                guard let value = value(after: "Dialogue:", in: line) else { continue }
                if eventFormat.isEmpty {
                    eventFormat = [
                        "layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text",
                    ]
                }
                let fields = split(value, expectedCount: eventFormat.count)
                let values = mappedValues(format: eventFormat, fields: fields)
                guard let start = timestamp(values["start"] ?? ""),
                    let end = timestamp(values["end"] ?? ""),
                    end > start
                else { continue }

                let styleName = (values["style"] ?? "Default").trimmingCharacters(in: .whitespaces)
                let style = styles[styleName.lowercased()] ?? .default
                let sourceText = values["text"] ?? ""
                let override = layoutOverride(in: sourceText)
                let rendered = render(sourceText, style: style)
                simplifiedEffects = simplifiedEffects || rendered.simplified || override.simplified
                if !(values["effect"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    simplifiedEffects = true
                }
                guard !rendered.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let margins = ASSMargins(
                    left: positiveInt(values["marginl"]) ?? style.marginLeft,
                    right: positiveInt(values["marginr"]) ?? style.marginRight,
                    vertical: positiveInt(values["marginv"]) ?? style.marginVertical
                )
                let settings = cueSettings(
                    alignment: override.alignment ?? style.alignment,
                    position: override.position,
                    margins: margins,
                    playResX: playResX,
                    playResY: playResY
                )
                cues.append(ASSCue(start: start, end: end, settings: settings, text: rendered.text))
            }
        }

        cues.sort {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        let blocks = cues.map { cue in
            "\(vttTimestamp(cue.start)) --> \(vttTimestamp(cue.end)) \(cue.settings)\n\(cue.text)"
        }
        let body = blocks.isEmpty ? "" : "\n\n" + blocks.joined(separator: "\n\n") + "\n"
        return ASSSubtitleConversion(webVTT: "WEBVTT\n" + body, simplifiedEffects: simplifiedEffects)
    }

    private struct ASSStyle {
        let name: String
        let alignment: Int
        let marginLeft: Int
        let marginRight: Int
        let marginVertical: Int
        let bold: Bool
        let italic: Bool
        let underline: Bool

        static let `default` = ASSStyle(
            name: "Default",
            alignment: 2,
            marginLeft: 20,
            marginRight: 20,
            marginVertical: 20,
            bold: false,
            italic: false,
            underline: false
        )

        init(values: [String: String], usesLegacyAlignment: Bool) {
            name = values["name"]?.trimmingCharacters(in: .whitespaces) ?? "Default"
            let rawAlignment = Int(values["alignment"] ?? "") ?? 2
            alignment = usesLegacyAlignment ? modernAlignment(fromLegacy: rawAlignment) : rawAlignment
            marginLeft = Int(values["marginl"] ?? "") ?? 20
            marginRight = Int(values["marginr"] ?? "") ?? 20
            marginVertical = Int(values["marginv"] ?? "") ?? 20
            bold = flag(values["bold"])
            italic = flag(values["italic"])
            underline = flag(values["underline"])
        }

        private init(
            name: String,
            alignment: Int,
            marginLeft: Int,
            marginRight: Int,
            marginVertical: Int,
            bold: Bool,
            italic: Bool,
            underline: Bool
        ) {
            self.name = name
            self.alignment = alignment
            self.marginLeft = marginLeft
            self.marginRight = marginRight
            self.marginVertical = marginVertical
            self.bold = bold
            self.italic = italic
            self.underline = underline
        }
    }

    private struct ASSMargins {
        let left: Int
        let right: Int
        let vertical: Int
    }

    private struct ASSCue {
        let start: Double
        let end: Double
        let settings: String
        let text: String
    }

    private struct LayoutOverride {
        let alignment: Int?
        let position: (x: Double, y: Double)?
        let simplified: Bool
    }

    private struct RenderedText {
        let text: String
        let simplified: Bool
    }

    private struct InlineStyle {
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var drawing = false
    }

    private static func layoutOverride(in text: String) -> LayoutOverride {
        let modernOverride = captures(
            pattern: #"\\an([1-9])"#,
            in: text,
            caseInsensitive: true
        ).first?.first.flatMap(Int.init)
        let legacyOverride = captures(
            pattern: #"\\a(1|2|3|5|6|7|9|10|11)(?:\\|})"#,
            in: text,
            caseInsensitive: true
        ).first?.first.flatMap(Int.init).map(modernAlignment(fromLegacy:))
        let alignment = modernOverride ?? legacyOverride
        let positionCaptures = captures(
            pattern: #"\\pos\(\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)\s*\)"#,
            in: text,
            caseInsensitive: true
        ).first
        var position: (x: Double, y: Double)?
        if let positionCaptures,
            positionCaptures.count == 2,
            let x = Double(positionCaptures[0]),
            let y = Double(positionCaptures[1])
        {
            position = (x, y)
        }

        var simplified = regex(
            #"\\(?:k|kf|ko|t|frx|fry|frz|fax|fay|clip|iclip|org|fad|fade|p)\b"#,
            matches: text,
            caseInsensitive: true
        )
        if position == nil,
            let move = captures(
                pattern: #"\\move\(\s*(-?[0-9.]+)\s*,\s*(-?[0-9.]+)"#,
                in: text,
                caseInsensitive: true
            ).first,
            move.count == 2,
            let x = Double(move[0]),
            let y = Double(move[1])
        {
            position = (x, y)
            simplified = true
        }
        return LayoutOverride(alignment: alignment, position: position, simplified: simplified)
    }

    private static func render(_ source: String, style: ASSStyle) -> RenderedText {
        var state = InlineStyle(bold: style.bold, italic: style.italic, underline: style.underline)
        var output = ""
        var cursor = source.startIndex
        var simplified = false

        while let open = source[cursor...].firstIndex(of: "{"),
            let close = source[open...].firstIndex(of: "}")
        {
            output += renderedPlainText(String(source[cursor..<open]), state: state)
            let blockStart = source.index(after: open)
            let block = String(source[blockStart..<close])
            updateInlineStyle(&state, from: block, base: style)
            let tagNames = captures(pattern: #"\\([A-Za-z]+)"#, in: block).flatMap { $0 }
            if tagNames.contains(where: { !["an", "pos", "i", "b", "u", "r"].contains($0.lowercased()) }) {
                simplified = true
            }
            cursor = source.index(after: close)
        }
        output += renderedPlainText(String(source[cursor...]), state: state)
        return RenderedText(text: output, simplified: simplified)
    }

    private static func updateInlineStyle(_ state: inout InlineStyle, from block: String, base: ASSStyle) {
        if regex(#"\\r(?:[^\\}]*)"#, matches: block, caseInsensitive: true) {
            state.bold = base.bold
            state.italic = base.italic
            state.underline = base.underline
            state.drawing = false
        }
        for values in captures(
            pattern: #"\\([ibu])(-?[0-9]+)"#,
            in: block,
            caseInsensitive: true
        ) where values.count == 2 {
            let enabled = (Int(values[1]) ?? 0) != 0
            switch values[0].lowercased() {
            case "i": state.italic = enabled
            case "b": state.bold = enabled
            case "u": state.underline = enabled
            default: break
            }
        }
        if let drawing = captures(
            pattern: #"\\p([0-9]+)"#,
            in: block,
            caseInsensitive: true
        ).last?.first.flatMap(Int.init) {
            state.drawing = drawing > 0
        }
    }

    private static func renderedPlainText(_ source: String, state: InlineStyle) -> String {
        guard !state.drawing, !source.isEmpty else { return "" }
        var text =
            source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: "\u{00a0}")
        if state.underline { text = "<u>\(text)</u>" }
        if state.italic { text = "<i>\(text)</i>" }
        if state.bold { text = "<b>\(text)</b>" }
        return text
    }

    private static func cueSettings(
        alignment rawAlignment: Int,
        position explicitPosition: (x: Double, y: Double)?,
        margins: ASSMargins,
        playResX: Double,
        playResY: Double
    ) -> String {
        let alignment = (1...9).contains(rawAlignment) ? rawAlignment : 2
        let column = (alignment - 1) % 3
        let row = (alignment - 1) / 3
        let horizontalAlignment = ["start", "center", "end"][column]
        let positionAnchor = ["line-left", "center", "line-right"][column]
        let lineAnchor = ["end", "center", "start"][row]

        let defaultPosition: Double
        switch column {
        case 0: defaultPosition = Double(margins.left) / playResX * 100
        case 2: defaultPosition = 100 - Double(margins.right) / playResX * 100
        default: defaultPosition = 50
        }
        let defaultLine: Double
        switch row {
        case 0: defaultLine = 100 - Double(margins.vertical) / playResY * 100
        case 2: defaultLine = Double(margins.vertical) / playResY * 100
        default: defaultLine = 50
        }
        let position = clamp(explicitPosition.map { $0.x / playResX * 100 } ?? defaultPosition)
        let line = clamp(explicitPosition.map { $0.y / playResY * 100 } ?? defaultLine)
        return
            "line:\(percentage(line))%,\(lineAnchor) position:\(percentage(position))%,\(positionAnchor) align:\(horizontalAlignment) size:90%"
    }

    private static func timestamp(_ value: String) -> Double? {
        let fields = value.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard fields.count == 3,
            let hours = Double(fields[0]),
            let minutes = Double(fields[1]),
            let seconds = Double(fields[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func vttTimestamp(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        return String(
            format: "%02d:%02d:%02d.%03d",
            milliseconds / 3_600_000,
            (milliseconds % 3_600_000) / 60_000,
            (milliseconds % 60_000) / 1000,
            milliseconds % 1000
        )
    }

    private static func percentage(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }

    private static func clamp(_ value: Double) -> Double {
        min(98, max(2, value))
    }

    private static func flag(_ value: String?) -> Bool {
        guard let value, let integer = Int(value.trimmingCharacters(in: .whitespaces)) else { return false }
        return integer != 0
    }

    private static func modernAlignment(fromLegacy alignment: Int) -> Int {
        switch alignment {
        case 1, 2, 3: return alignment
        case 5: return 7
        case 6: return 8
        case 7: return 9
        case 9: return 4
        case 10: return 5
        case 11: return 6
        default: return 2
        }
    }

    private static func positiveInt(_ value: String?) -> Int? {
        guard let value, let parsed = Int(value.trimmingCharacters(in: .whitespaces)), parsed > 0 else { return nil }
        return parsed
    }

    private static func normalizedFieldName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func commaSeparated(_ value: String) -> [String] {
        value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    private static func split(_ value: String, expectedCount: Int) -> [String] {
        guard expectedCount > 1 else { return [value] }
        var fields = value.split(
            separator: ",",
            maxSplits: expectedCount - 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        while fields.count < expectedCount { fields.append("") }
        return fields
    }

    private static func mappedValues(format: [String], fields: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for (index, name) in format.enumerated() where index < fields.count {
            values[name] = fields[index]
        }
        return values
    }

    private static func value(after prefix: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func regex(_ pattern: String, matches text: String, caseInsensitive: Bool = false) -> Bool {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func captures(
        pattern: String,
        in text: String,
        caseInsensitive: Bool = false
    ) -> [[String]] {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}
