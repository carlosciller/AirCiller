import Foundation

@main
struct TrackMetadataSmokeTest {
    static func main() throws {
        let audio = AudioTrack(
            streamIndex: 1,
            codec: "eac3",
            profile: nil,
            channels: 6,
            channelLayout: "5.1",
            language: "eng",
            title: "English 5.1",
            isDefault: true
        )
        guard audio.displayName == "English 5.1" else {
            throw NSError(domain: "TrackMetadataSmokeTest.AudioName", code: 1)
        }

        let spanishDefaultAudio = AudioTrack(
            streamIndex: 2,
            codec: "aac",
            profile: nil,
            channels: 2,
            channelLayout: "stereo",
            language: "spa",
            title: "Español",
            isDefault: true
        )
        let englishAlternateAudio = AudioTrack(
            streamIndex: 3,
            codec: "eac3",
            profile: nil,
            channels: 6,
            channelLayout: "5.1",
            language: "eng",
            title: "English Atmos",
            isDefault: false
        )
        guard
            AudioTrackSelection.preferredTrack(
                in: [spanishDefaultAudio, englishAlternateAudio],
                language: "eng"
            )?.id == englishAlternateAudio.id
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.AudioPreference", code: 10)
        }

        let englishSDH = SubtitleTrack(
            streamIndex: 2,
            codec: "subrip",
            language: "eng",
            title: "SDH",
            isDefault: true,
            isForced: false,
            isHearingImpaired: true,
            externalPath: nil
        )
        guard englishSDH.displayName == "English SDH" else {
            throw NSError(domain: "TrackMetadataSmokeTest.SubtitleName", code: 2)
        }

        let englishRegular = SubtitleTrack(
            streamIndex: 500,
            codec: "subrip",
            language: "eng",
            title: "English",
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
            externalPath: nil
        )
        guard
            SubtitleTrackSelection.preferredTrack(
                in: [englishSDH, englishRegular],
                language: "eng"
            )?.id == englishRegular.id
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.PreferRegular", code: 3)
        }
        guard
            SubtitleTrackSelection.preferredTrack(
                in: [englishRegular, englishSDH],
                language: "eng",
                preference: .sdh
            )?.id == englishSDH.id
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.PreferSDH", code: 12)
        }

        let englishForced = SubtitleTrack(
            streamIndex: 501,
            codec: "subrip",
            language: "eng",
            title: "English Forced",
            isDefault: false,
            isForced: true,
            isHearingImpaired: false,
            externalPath: nil
        )
        guard
            SubtitleTrackSelection.preferredTrack(
                in: [englishRegular, englishSDH, englishForced],
                language: "eng",
                preference: .forced
            )?.id == englishForced.id,
            SubtitleTrackSelection.preferredTrack(
                in: [englishRegular, englishSDH],
                language: "eng",
                preference: .forced
            ) == nil
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.ForcedOnly", code: 13)
        }

        let spanishByTitle = SubtitleTrack(
            streamIndex: 6,
            codec: "subrip",
            language: "und",
            title: "Spanish",
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
            externalPath: nil
        )
        let spanishPGS = SubtitleTrack(
            streamIndex: 7,
            codec: "hdmv_pgs_subtitle",
            language: "spa",
            title: "Español PGS",
            isDefault: true,
            isForced: false,
            isHearingImpaired: false,
            externalPath: nil
        )
        guard
            SubtitleTrackSelection.preferredTrack(
                in: [spanishPGS, spanishByTitle],
                language: "spa"
            )?.id == spanishByTitle.id
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.CompatibleOnly", code: 4)
        }
        guard spanishPGS.isSelectable,
            spanishPGS.unsupportedReason == nil,
            SubtitleTrackSelection.preferredTrack(
                in: [spanishPGS],
                language: "spa"
            )?.id == spanishPGS.id
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.PGSFallback", code: 7)
        }
        let vobSub = SubtitleTrack(
            streamIndex: 8,
            codec: "dvd_subtitle",
            language: "eng",
            title: "VobSub",
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
            externalPath: nil
        )
        guard vobSub.isSelectable, vobSub.usesBitmapOCR, vobSub.unsupportedReason == nil else {
            throw NSError(domain: "TrackMetadataSmokeTest.VobSub", code: 8)
        }

        guard MediaPresentation.resolutionLabel(width: 3840, height: 1608) == "4K",
            MediaPresentation.resolutionLabel(width: 4096, height: 1716) == "4K",
            MediaPresentation.resolutionLabel(width: 1920, height: 1080) == "Full HD",
            MediaPresentation.dolbyVisionProfile(8, compatibilityID: 1) == "Perfil 8.1"
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.MediaPresentation", code: 5)
        }

        let coverArt = VideoStreamCandidate(
            index: 0,
            width: 1_000,
            height: 1_000,
            isDefault: true,
            isAttachedPicture: true
        )
        let feature = VideoStreamCandidate(
            index: 3,
            width: 3_840,
            height: 2_160,
            isDefault: false,
            isAttachedPicture: false
        )
        guard VideoStreamSelection.primaryStreamIndex(in: [coverArt, feature]) == feature.index,
            VideoStreamSelection.primaryStreamIndex(in: [coverArt]) == nil
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.VideoSelection", code: 11)
        }

        let queue = [
            QueueMediaItem(path: "/A.mkv", title: "A"),
            QueueMediaItem(path: "/B.mkv", title: "B"),
            QueueMediaItem(path: "/C.mkv", title: "C"),
        ]
        guard QueueOrdering.moving(queue, fromOffsets: [0], toOffset: queue.endIndex).map(\.title) == ["B", "C", "A"],
            QueueOrdering.moving(queue, fromOffsets: [2], toOffset: 0).map(\.title) == ["C", "A", "B"],
            QueueOrdering.moving(queue, fromOffsets: [1], toOffset: queue.endIndex).map(\.title) == ["A", "C", "B"]
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.QueueOrdering", code: 6)
        }

        let longerQueue = [
            QueueMediaItem(path: "/A.mkv", title: "A"),
            QueueMediaItem(path: "/B.mkv", title: "B"),
            QueueMediaItem(path: "/C.mkv", title: "C"),
            QueueMediaItem(path: "/D.mkv", title: "D"),
            QueueMediaItem(path: "/E.mkv", title: "E"),
        ]
        guard
            QueueOrdering.moving(longerQueue, fromOffsets: [4], toOffset: 1).map(\.title) == ["A", "E", "B", "C", "D"],
            QueueOrdering.moving(longerQueue, fromOffsets: [3], toOffset: 1).map(\.title) == ["A", "D", "B", "C", "E"],
            QueueOrdering.moving(longerQueue, fromOffsets: [1], toOffset: 3).map(\.title) == ["A", "C", "B", "D", "E"],
            QueueOrdering.moving(longerQueue, fromOffsets: [3], toOffset: 3).map(\.title) == ["A", "B", "C", "D", "E"]
        else {
            throw NSError(domain: "TrackMetadataSmokeTest.QueueOrderingUpward", code: 9)
        }

        print("Track preferences, scope 4K, Dolby Vision profile, and reordering: OK")
    }
}
