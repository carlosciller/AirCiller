# Apple Shortcuts: deferred from 0.14.1

On 23 September 2026, the maintainer chose to prepare 0.14.1 as a maintenance
release without Shortcuts. The working integration has been preserved; it has
not been deleted or included in the public patch.

- [Implementation snapshot](https://github.com/carlosciller/AirCiller/tree/f5a2780f863fbe20456df8ab34c0e3c7879a5d74)
- [Full validation and signing record](https://github.com/carlosciller/AirCiller/blob/f5a2780f863fbe20456df8ab34c0e3c7879a5d74/Docs/SHORTCUTS.md)

That snapshot contains six foreground actions: Open Movie, Send Movie to Apple
TV, Add Movie to Playlist, Pause, Resume and Stop. Native Spanish execution,
chained actions, cold launch and controls over HLS and direct HDR passed their
recorded development-candidate checks. Sampled digital Apple TV output has its
own evidence and limits in the linked record.

The tested candidate used Apple Development signing. A complete application
built with the existing public ad hoc policy passed compilation but failed native
registration on the tested macOS 27 system: `linkd` reported `Unable to get teamId`.
The public app's actions could not be selected, so public dispatch was not
accepted. Repeating playback tests does not resolve that signing boundary.

## Resume here

Choose and validate the public distribution/signing route before scheduling a
Shortcuts release. Keep the existing local signing identity and pinned credential
service intact; the tested development candidate has its own separate service.
Do not publish that candidate or loosen credential checks as a workaround.

Remaining feature checks include native English discovery, protected-folder
access across relaunch and large-file handoff. These belong to the deferred
integration, not the maintenance patch. Finder Quick Actions, Services entries
and permanent background processes remain outside its scope.

The [roadmap](../ROADMAP.md#deferred-apple-shortcuts) tracks the follow-up. The
[maintenance record](BUGFIXES_0.14.1.md) tracks 0.14.1 separately.
