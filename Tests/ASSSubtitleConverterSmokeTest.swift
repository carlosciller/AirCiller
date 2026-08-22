import Foundation

@main
struct ASSSubtitleConverterSmokeTest {
    static func main() throws {
        let source = #"""
            [Script Info]
            PlayResX: 1920
            PlayResY: 1080

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
            Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,1,2,60,60,42,1
            Style: Sign,Arial,54,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,2,1,8,40,40,36,1

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\i1}Hello from below{\i0}\NSecond line
            Dialogue: 1,0:00:04.00,0:00:06.00,Sign,,0,0,0,,{\an8\pos(960,120)\b1}UPPER SIGN{\b0}
            Dialogue: 2,0:00:07.00,0:00:09.00,Default,,0,0,0,,{\an4\k20}LEFT KARAOKE
            """#

        let conversion = ASSSubtitleConverter.convert(source)
        guard conversion.webVTT.hasPrefix("WEBVTT\n"),
            conversion.webVTT.contains(
                "00:00:01.000 --> 00:00:03.500 line:96.111%,end position:50%,center align:center size:90%"),
            conversion.webVTT.contains("<i>Hello from below</i>\nSecond line"),
            conversion.webVTT.contains(
                "00:00:04.000 --> 00:00:06.000 line:11.111%,start position:50%,center align:center size:90%"),
            conversion.webVTT.contains("<b>UPPER SIGN</b>"),
            conversion.webVTT.contains(
                "00:00:07.000 --> 00:00:09.000 line:50%,center position:3.125%,line-left align:start size:90%"),
            conversion.webVTT.contains("LEFT KARAOKE"),
            conversion.simplifiedEffects
        else {
            throw NSError(
                domain: "ASSSubtitleConverterSmokeTest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: conversion.webVTT]
            )
        }
        print("ASS/SSA · posición, formato básico y simplificación explícita · OK")
    }
}
