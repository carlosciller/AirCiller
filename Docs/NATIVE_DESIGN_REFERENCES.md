# Native design reference dossier

Researched on 13 September 2026 for a future AirCiller version. These references inform proposals; they do not establish that a redesign has shipped or passed native acceptance. Keep the [product brief and acceptance criteria](NATIVE_DESIGN.md) and [baseline audit](NATIVE_DESIGN_AUDIT.md) as the operational sources of truth.

## How to use the references

Start with Apple's platform resources, then inspect the particular interaction in a reference app. Borrow a decision that serves AirCiller's local-movie-to-Apple-TV task, not another product's complete layout or feature set. For each proposal, identify its source, what changes, why it helps, and the native test that could disprove the benefit.

The observations below come from official documentation, presentations and product pages. Promotional screenshots establish the depicted composition only: they do not prove keyboard behavior, accessibility, performance, current installed appearance or receiver playback. No reference app was installed or exercised for this dossier. Public images remain linked at their publishers; none were downloaded or incorporated into the app.

## Platform references

### Apple Design Resources: OS 27 kits

- **Source/version:** [Apple Design Resources](https://developer.apple.com/design/resources/) currently lists macOS 27 and iOS/iPadOS 27 UI kits for Figma and Sketch. The [macOS 27 Figma destination](https://www.figma.com/community/file/1651309434229735362/macos-27) is linked by Apple; the file itself was not inspected.
- **Supported observation:** Apple provides separate desktop and mobile templates.
- **AirCiller application:** Use the Mac kit to compare window structure, toolbar grouping, selection and control proportions. Consult the iOS kit for shared material direction while preserving Mac menus, pointer precision, keyboard access and resizable windows.
- **Limit:** The listing is a mutable resource index; record the actual kit revision when importing it. A kit does not establish runtime API availability. This work retains macOS 14 support.

### WWDC26: SwiftUI appearance and tooling

- **Source/version:** [What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/), appearance chapter at 2:12 and agent-skills discussion near the end.
- **Supported observation:** Apple demonstrates refined Liquid Glass responding to the system tint adjustment, pointer interaction on Mac, inactive-window appearance and toolbar prioritization when space shrinks.
- **AirCiller application:** Let native controls reflect the user's appearance settings. Review active/inactive states, custom sidebar elements and which commands remain visible in narrow windows.
- **Limit:** A demonstration is not proof that every new modifier supports macOS or macOS 14. Confirm each API's platform/SDK availability before implementation; do not replace system materials with a fixed golden or colored wash.

### WWDC25: material hierarchy

- **Source/version:** [Meet Liquid Glass, WWDC25](https://developer.apple.com/videos/play/wwdc2025/219/).
- **Supported observation:** The material adapts to content and context. Apple reserves tint for important elements/actions and distinguishes navigation/control surfaces from the content layer.
- **AirCiller application:** Keep the movie and file information visually stable. Concentrate material effects in appropriate native chrome; reserve accent emphasis for the meaningful selection or primary action. Avoid tinting every panel and button.
- **Limit:** A blurred CSS panel is a visual approximation. Contrast, transparency preferences and material behavior require observation in a native build on each supported appearance path.

### Landmarks: implementation reference

- **Source/version:** [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass), documented for OS 26/Xcode 26. Apple's public documentation data was read; the sample was not built.
- **Supported observation:** The sample uses a split view, sidebar/inspector, related toolbar groups, system glass and content extension behind auxiliary panes. It also demonstrates adaptation to window sizes.
- **AirCiller application:** Study grouping and inspector scope, then apply only the pieces justified by our task. A movie control surface should not require a decorative catalog or downloaded artwork to feel finished.
- **Limit:** This is a travel sample using newer APIs, not a drop-in AirCiller architecture or a macOS 14 compatibility example. Background extension is optional and must not obscure important content.

### Apple Design Awards: quality beyond appearance

- **Source/version:** [Apple Design Awards, 2026 selection](https://developer.apple.com/design/awards/).
- **Supported observation:** Apple's categories include interaction and inclusivity as well as visuals. Its Guitar Wiz description specifically discusses VoiceOver, contrast and conveying meaning without color.
- **AirCiller application:** Review whether each screen communicates state, destination and next action through more than tint or animation; use the existing native acceptance matrix to verify this.
- **Limit:** An award is editorial recognition, not a transferable implementation guarantee or a ranking of the best Mac media players. Cross-platform accessibility descriptions do not prove identical features on every platform.

## App references with a specific job

| Reference and source version | Publisher evidence | Proposed AirCiller use | Boundary |
| --- | --- | --- | --- |
| [IINA](https://iina.io/), current home page; screenshots are not tied to a release | The project describes Mac-specific design, dark appearance, media controls, gestures and subtitle features, with an image illustrating dark mode. | Study the relationship between content, timeline, transport and optional track controls. Keep selected file and receiver-playing item distinguishable. | IINA is a local player with different transport behavior. Its page still references older macOS features; use it for task anatomy, not as proof of OS 27 styling or AirPlay semantics. |
| [Things for OS 26](https://culturedcode.com/things/blog/2025/09/things-for-os-26/), September 2025 | Cultured Code describes adjusted geometry, more relaxed spacing and restrained sidebar glass, with Mac/iPad/iPhone screenshots. | Compare list rhythm, quiet surfaces and selective emphasis. Make filenames readable before decorating containers. | The article is an OS 26 design snapshot. Task-management density and touch interactions do not directly specify a Mac media controller. |
| [Transmit 5](https://panic.com/transmit/), current product page; image build unspecified | Panic shows a two-pane file browser and Activity Viewer, and describes inspection while browsing. | Keep destination and ongoing work explicit; separate status/recovery from file inspection. Borrow clarity of progress, not network-service features. | Transfers and playback have different success conditions. A completed local preparation must not imply observed Apple TV picture or sound. |
| [Pixelmator Pro](https://www.apple.com/pixelmator-pro/), current Apple product page; image build unspecified | The page depicts content surrounded by contextual editing tools and describes customizable sidebars/workspaces. | Give the selected movie clear priority and keep track/file details contextual and optional. | AirCiller does not need an editor's density, canvas machinery or workspace customization. Promotional visuals do not establish interaction quality in our app. |

These four products are chosen for relevant patterns, not because native frameworks automatically produce exemplary design. AirCiller's outcome still depends on decisions and runtime verification.

## Visual reference sheet

These are exact public image URLs linked by the official source pages/documentation. Captions identify publisher-described content; they do not claim new runtime observations. Open alongside the source page for context. Keep publisher imagery out of AirCiller assets and public app screenshots.

| Image | Factual caption and comparison target |
| --- | --- |
| [Apple macOS 27 UI-kit preview](https://developer.apple.com/design/resources/images/thumbnails/Thumbnail-UIKit-macOS27_2x.png) | Thumbnail for the macOS 27 UI kit in Apple Design Resources. Use to locate the official kit; it is not a specification at thumbnail scale. |
| [Transmit file browser](https://panic.com/transmit/images/screenshot1%402x.png) | Panic's screenshot identified as the Transmit 5 two-pane file viewer. Compare the visual distinction between source and destination. |
| [Things on macOS 26](https://culturedcode.com/frozen/2025/09/things-os26-screenshot-macos-io75.jpg) | Cultured Code's Mac screenshot accompanying its OS 26 redesign article. Compare list spacing, surface contrast and restrained color. |
| [IINA dark appearance](https://iina.io/images/feature-1.png) | Image accompanying IINA's Dark Mode section. Compare transport placement and optional playback settings. |
| [Transmit Activity Viewer](https://panic.com/transmit/images/screenshot2%402x.png) | Panic's screenshot identified as the Transmit 5 Activity Viewer. Compare operation status and destination context. |
| [Pixelmator Pro workspace](https://www.apple.com/v/pixelmator-pro/a/images/overview/design/workspace__cjje1b94zmxe_large.jpg) | Apple depicts a MacBook Pro with a rock-binding image and color-adjustment/white-balance tools. Compare content priority and contextual tools. |

## Optional Apple agent skills

WWDC26 officially describes two Xcode 27 resources: SwiftUI Specialist and What's New In SwiftUI. It states that `xcrun agent skills export` produces Markdown for other tools. This supports considering Apple's exported guidance alongside AirCiller's existing skill; it does not prove that the installed toolchain contains it or that a particular Codex import has succeeded. [Official presentation](https://developer.apple.com/videos/play/wwdc2026/269/).

If needed during a future implementation, inspect the installed toolchain first, read its export help and review only the relevant exported guidance against AirCiller's invariants and deployment target. No Xcode/SDK upgrade, skill installation, export or build-system migration was performed for this dossier.

## Applying this material to the three proposals

See the [comparison and decision record](NATIVE_DESIGN_PROPOSALS.md) for the shared fixtures, compositions and future integration boundary.

Hold fictional media, commands, states and information constant so that the comparison isolates the design decisions:

- **Mac essential:** Reference the Mac kit, Landmarks grouping and Things restraint. Test whether familiar chrome and a quiet list make the next action obvious.
- **Quiet cinema:** Reference IINA's content/transport relationship. Test whether cinematic emphasis still communicates selection, receiver state and recovery when no artwork is available.
- **Refined utility:** Reference Things lists, Transmit activity and Pixelmator contextual tools. Test whether useful detail stays optional and the window remains workable at compact sizes.

Keep macOS 14 native fallback and modern native enhancement as two implementations of the same task, not two separate products. A web concept can compare hierarchy and simulated states; choose a direction before using a small native SwiftUI prototype to assess actual materials, focus, keyboard access, resizing and movement.

Acceptance, playback evidence and release readiness remain in the [design guide](NATIVE_DESIGN.md#acceptance-and-implementation-order). Record the tested OS/SDK, commit and exact scenarios. Design research alone neither clears a release gate nor authorizes changes to the active playback work.
