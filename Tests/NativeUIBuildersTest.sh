#!/bin/zsh
# Opt-in build regression; never launches an app or contacts a receiver.
set -euo pipefail
project_dir="${0:A:h:h}"
builder="$project_dir/Scripts/build_native_ui_check.sh"
if "$builder" invalid-mode >/dev/null 2>&1; then
  echo 'Unknown UI fixture unexpectedly accepted' >&2
  exit 1
else
  [[ $? == 2 ]]
fi
for mode in chapter-skip playback-information episode-presentation season-continuation subtitle-preferences library-recovery; do
  case "$mode" in
    chapter-skip) type=ChapterSkip; prefix=ChapterSkip; label='Chapter Check' ;;
    playback-information) type=PreparedPlaybackInformation; prefix=PlaybackInformation; label='Information Check' ;;
    episode-presentation) type=EpisodePresentation; prefix=EpisodePresentation; label='Episode Check' ;;
    season-continuation) type=SeasonContinuation; prefix=SeasonContinuation; label='Season Check' ;;
    subtitle-preferences) type=SubtitlePreferences; prefix=SubtitlePreferences; label='Subtitle Preferences Check' ;;
    library-recovery) type=RecoveryUI; prefix=RecoveryUI; label='Recovery Check' ;;
  esac
  # Exercise the retained entry points as well as the shared constructor.
  case "$mode" in
    season-continuation|subtitle-preferences|library-recovery)
      app="$(zsh "$project_dir/Scripts/build_${mode//-/_}_ui_check.sh")" ;;
    *) app="$("$builder" "$mode")" ;;
  esac
  [[ "$app" == "$project_dir/.build/tests/$prefix-"*.app ]]
  plist="$app/Contents/Info.plist"
  [[ "$(plutil -extract CFBundleName raw "$plist")" == "AirCiller $label" ]]
  [[ "$(plutil -extract CFBundleExecutable raw "$plist")" == "${type}Check" ]]
  [[ "$(plutil -extract CFBundleIdentifier raw "$plist")" == "local.airciller.${type}Check."* ]]
  [[ "$(plutil -extract CFBundlePackageType raw "$plist")" == APPL ]]
  [[ -x "$app/Contents/MacOS/${type}Check" ]]
  diff -r "$project_dir/Resources/en.lproj" "$app/Contents/Resources/en.lproj"
  diff -r "$project_dir/Resources/es.lproj" "$app/Contents/Resources/es.lproj"
  codesign --verify --strict "$app"
  echo "$mode: build, metadata, resources and signature OK"
done
