# MathBeat Studio — Native iOS

SwiftUI iPhone sequencer using AVAudioEngine. Requires iOS 17+ and Xcode 16+ on a supported Mac. No third-party dependencies.

## Run

1. Open `MathBeatStudio.xcodeproj` in Xcode.
2. Select the MathBeatStudio scheme and an iPhone simulator, then Run.
3. For a physical iPhone, select your development team in Signing & Capabilities and replace `com.example.MathBeatStudio` with your own unique bundle identifier. Select your connected iPhone and Run.

For an IPA, select a generic iOS device destination, use Product → Archive, then Distribute App in Organizer. Export and installation depend on your Apple account, provisioning, and chosen distribution method. This workspace does not contain signing credentials or an IPA.

## Use

The studio uses a dark mint interface with waveform previews, large step pads, haptic selection feedback, and a persistent play/stop bar. Tap a pad to open its pitch and rest editor. Tempo supports a slider and one-BPM adjustment buttons. The grid uses four columns on narrow screens, eight when space permits, and two at accessibility text sizes. Controls respect Dynamic Type and reduced-motion preferences. Saved sessions appear in the project library with tempo and oscillator details.

Playback shows a cancellable preparation state. Rapid edits are debounced for 80 ms before rendering to keep controls responsive, and edits made during startup are applied after playback begins. PCM scheduling still determines note timing.

Choose pitches or rests for 16 sixteenth-note steps, set 40–240 BPM, choose sine/square/triangle/sawtooth, and tap Play Loop. Save writes a project to the app's Documents/Projects folder as atomic, readable JSON. Saving a loaded project updates that project. Projects opens saved beats, supports swipe-to-delete, and creates new projects.

Each loop is one 4/4 bar, rendered at 44.1 kHz into a mono PCM buffer. Notes use MIDI pitches 48–84 (C3–C6), with short attack/release envelopes. Non-sine waveforms use additive synthesis with up to 64 harmonics below Nyquist. The player queues complete loop buffers ahead of playback; callbacks replenish the queue and never trigger individual notes. Buffer length is rounded once per loop to the nearest sample. Edits render off the main actor and enter the queue at a future loop boundary, normally within two bars. Playback stops when the app leaves the active state or receives an audio interruption.

## Verification on a Mac

```sh
xcodebuild -project MathBeatStudio.xcodeproj -scheme MathBeatStudio \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Check all waveforms, rests, full-range tempo changes while playing, repeated start/stop, backgrounding, interruption behavior, and save/load/delete across relaunch. At 120 BPM a loop should last 2 seconds; at 60 BPM, 4 seconds. Listen across several boundaries for gaps or clicks. Test on a physical device before distribution.

The project was authored on Windows, where Xcode and the iOS SDK are unavailable. Compilation, simulator execution, device audio, signing, and IPA export have not been verified here.

The `iOS Build Check` GitHub Actions workflow compiles for iPhone Simulator on pushes to main and pull requests. Physical-device audio and visual layout still require review on a supported Mac or iPhone.

## ReleaseDaBot

`VERSION` at the repository root is the source for issue-driven releases. It currently contains `0.0.3`. Commit a new value before requesting a new version. Issue titles and legacy `version = ...` lines do not override it.

Use the **Version release** issue template: it applies the `releasedabot` label automatically. Keep either `stable;` or `nightly;` in its body, optionally in a JavaScript code block. Opening, editing, reopening, or labeling a request runs ReleaseDaBot. The repository label must exist for template labels to apply; it is configured in glitchFling/Soundless.

To trigger an existing open issue, post one of these exact comments:

```text
releaseabot
releasedabot
/releasedabot nightly
/releasedabot stable
```

Both spellings are supported, with optional `/` or `@` prefixes. A command without a channel uses the issue body's `stable;` or `nightly;` setting. An explicit channel overrides the body. Commands target only their issue, including previously unlabeled issues, and apply the label. PR comments, unrelated comments, and closed issues do not publish. The command author must have repository write, maintain, or admin access. Automatic issue requests also require the issue author to have write access.

Run **Actions → ReleaseDaBot → Run workflow** to scan all open labeled requests. The workflow summary explains what it selected or why nothing will build. Invalid targeted requests fail with an explanation instead of silently skipping publication.

- `stable;` publishes `v0.0.3` as a stable release.
- `nightly;` publishes `v0.0.3-nightly` as a GitHub prerelease.

Both use the number from `VERSION` for the app version and Actions run number for its build number. Nightly releases are command-driven; no scheduled release has been configured. Each version/channel tag is immutable: bump `VERSION` to publish another build. Published assets are not overwritten. An already complete release is verified before its requesting issue is closed without rebuilding.

Successful publication uploads an unsigned IPA and SHA-256 checksum, then keeps the `releasedabot` label and closes the requesting issue as completed. A failed build leaves the issue open. Rescanning retries issue cleanup after a successful publication. Incomplete existing releases remain open for investigation. The label identifies release requests as well as completed releases; closed issue state indicates completion.

ReleaseDaBot builds a captured commit from the default branch using the reusable `iOS IPA Release` workflow. No Apple signing secrets are required. The IPA needs signing with a compatible sideloading tool before installation; it is not an App Store or TestFlight distribution build.

The IPA workflow also supports manual execution (blank version reads `VERSION`, with an optional override and channel selection), or pushing a version tag such as `v0.0.3` or `v0.0.3-nightly`. Direct manual/tag releases do not close an issue unless invoked by ReleaseDaBot with an issue number.

ReleaseDaBot is the workflow display name. GitHub activity uses `github-actions[bot]`; a separate `ReleaseDaBot[bot]` identity requires a GitHub App.

Run parser and scanner tests with:

```sh
node --test .github/scripts/release-issue.test.cjs
```
