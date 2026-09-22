#if !AIRCILLER_PLAYBACK_CHECKS && !AIRCILLER_NO_SHORTCUTS
    import AppIntents
    import Foundation

    struct OpenMovieIntent: AppIntent {
        static let title = LocalizedStringResource("Open Movie", table: "Shortcuts")
        static var description: IntentDescription {
            IntentDescription(
                LocalizedStringResource(
                    "Open a saved local movie in AirCiller without starting playback. Stop the current session first.",
                    table: "Shortcuts"))
        }
        static let openAppWhenRun = true
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
        @available(macOS 26.0, *)
        static var supportedModes: IntentModes { .foreground }

        @Parameter(title: LocalizedStringResource("Movie", table: "Shortcuts"))
        var movie: IntentFile

        static var parameterSummary: some ParameterSummary {
            Summary("Open \(\.$movie)", table: "Shortcuts")
        }

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog {
            try Task.checkCancellation()
            try ShortcutsController.shared.openMovie(
                url: movie.fileURL, removedOnCompletion: movie.removedOnCompletion)
            return .result(
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Opening the movie in AirCiller. Playback has not started.", table: "Shortcuts")))
        }
    }

    struct SendMovieToAppleTVIntent: AppIntent {
        static let title = LocalizedStringResource("Send Movie to Apple TV", table: "Shortcuts")
        static var description: IntentDescription {
            IntentDescription(
                LocalizedStringResource(
                    "Start preparing a saved local movie for Apple TV. AirCiller handles playback and asks before converting audio. Stop the current session first.",
                    table: "Shortcuts"))
        }
        static let openAppWhenRun = true
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
        @available(macOS 26.0, *)
        static var supportedModes: IntentModes { .foreground }

        @Parameter(title: LocalizedStringResource("Movie", table: "Shortcuts"))
        var movie: IntentFile

        @Parameter(
            title: LocalizedStringResource("Apple TV Name", table: "Shortcuts"),
            description: LocalizedStringResource(
                "Enter the exact name shown in AirCiller. Required when more than one Apple TV is available.",
                table: "Shortcuts"))
        var destinationName: String?

        @Parameter(title: LocalizedStringResource("Play from Beginning", table: "Shortcuts"), default: false)
        var fromBeginning: Bool

        static var parameterSummary: some ParameterSummary {
            Summary("Send \(\.$movie) to Apple TV", table: "Shortcuts") {
                \.$destinationName
                \.$fromBeginning
            }
        }

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog {
            try Task.checkCancellation()
            try await ShortcutsController.shared.sendMovie(
                url: movie.fileURL, removedOnCompletion: movie.removedOnCompletion,
                destinationName: destinationName, fromBeginning: fromBeginning)
            return .result(
                dialog: IntentDialog(
                    LocalizedStringResource(
                        "Preparation has started in AirCiller. Playback will start when the movie is ready and any required approval is complete.",
                        table: "Shortcuts")))
        }
    }

    struct AddMovieToPlaylistIntent: AppIntent {
        static let title = LocalizedStringResource("Add Movie to Playlist", table: "Shortcuts")
        static var description: IntentDescription {
            IntentDescription(
                LocalizedStringResource(
                    "Add a saved local movie to AirCiller's playlist without changing the current playback. Existing entries are kept in place.",
                    table: "Shortcuts"))
        }
        static let openAppWhenRun = true
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
        @available(macOS 26.0, *)
        static var supportedModes: IntentModes { .foreground }

        @Parameter(title: LocalizedStringResource("Movie", table: "Shortcuts"))
        var movie: IntentFile

        static var parameterSummary: some ParameterSummary {
            Summary("Add \(\.$movie) to playlist", table: "Shortcuts")
        }

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog {
            try Task.checkCancellation()
            try ShortcutsController.shared.addMovie(
                url: movie.fileURL, removedOnCompletion: movie.removedOnCompletion)
            return .result(
                dialog: IntentDialog(
                    LocalizedStringResource("The movie is in AirCiller's playlist.", table: "Shortcuts")))
        }
    }

    struct PauseAirCillerIntent: AppIntent {
        static let title = LocalizedStringResource("Pause AirCiller", table: "Shortcuts")
        static var description: IntentDescription {
            IntentDescription(
                LocalizedStringResource("Request a pause for AirCiller's active Apple TV session.", table: "Shortcuts"))
        }
        static let openAppWhenRun = true
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
        @available(macOS 26.0, *)
        static var supportedModes: IntentModes { .foreground }

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog {
            try Task.checkCancellation()
            try ShortcutsController.shared.pause()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Pause requested in AirCiller.", table: "Shortcuts")))
        }
    }

    struct ResumeAirCillerIntent: AppIntent {
        static let title = LocalizedStringResource("Resume AirCiller", table: "Shortcuts")
        static var description: IntentDescription {
            IntentDescription(
                LocalizedStringResource(
                    "Request playback to resume in AirCiller's active Apple TV session. Does not start a stopped movie.",
                    table: "Shortcuts"))
        }
        static let openAppWhenRun = true
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
        @available(macOS 26.0, *)
        static var supportedModes: IntentModes { .foreground }

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog {
            try Task.checkCancellation()
            try ShortcutsController.shared.resume()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Resume requested in AirCiller.", table: "Shortcuts")))
        }
    }

    struct StopAirCillerIntent: AppIntent {
        static let title = LocalizedStringResource("Stop AirCiller", table: "Shortcuts")
        static var description: IntentDescription {
            IntentDescription(
                LocalizedStringResource(
                    "Stop AirCiller's current playback or preparation and keep its saved playback position.",
                    table: "Shortcuts"))
        }
        static let openAppWhenRun = true
        static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
        @available(macOS 26.0, *)
        static var supportedModes: IntentModes { .foreground }

        @MainActor
        func perform() async throws -> some IntentResult & ProvidesDialog {
            try Task.checkCancellation()
            try ShortcutsController.shared.stop()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Stop requested in AirCiller.", table: "Shortcuts")))
        }
    }
#endif
