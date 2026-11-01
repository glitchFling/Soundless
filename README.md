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

## GitHub Actions releases

The `iOS IPA Release` workflow runs on a hosted macOS runner, builds an iPhone archive, packages an **unsigned IPA**, and uploads it plus a SHA-256 checksum to GitHub Releases. It uses the repository's built-in `GITHUB_TOKEN`; no Apple signing secrets are needed. Unsigned IPAs require signing with a compatible sideloading tool before installation. This workflow does not produce an App Store/TestFlight distribution build.

After pushing this project (including `.github`) to a GitHub repository with Actions enabled, create the first release in either of these ways:

- Open **Actions → iOS IPA Release → Run workflow**, select the desired branch, and leave the version at **0.0.1**. The workflow creates tag `v0.0.1` on the selected commit after the build succeeds.
- Push an existing version tag:

  ```sh
  git tag v0.0.1
  git push origin v0.0.1
  ```

For later releases use `0.0.2`, `0.0.3`, etc., manually or through matching `v` tags. The workflow sets the app's marketing version from that release version and its build number from the Actions run number. A manual run cannot reuse a tag pointing to another commit, and published assets are never overwritten. Download `MathBeatStudio-0.0.1-unsigned.ipa` from the release. The IPA and checksum are also retained as workflow artifacts if release publication fails.

The workflow has been statically checked here but has not run on GitHub; this workspace currently has no Git repository or remote configured.

## ReleaseDaBot version issues

Once these workflows are on the repository's default branch, choose the **Version release** issue template. For the first release, use title `v0.0.1` and body:

```javascript
version = 0.0.1
stable;
```

For example, title `v2.3.3` requires `version = 2.3.3` in the body. These lines are a small declarative format, not executable JavaScript. Only stable releases are currently supported. The version line can optionally end with a semicolon. Both plain text and a single JavaScript code block are accepted; extra commands, duplicate lines, mismatched versions, and `0.0.0` are rejected.

**ReleaseDaBot** scans all open issues when a version issue is opened, edited, or reopened, or when its workflow is run manually. The initiating user and the issue author must currently have repository write, maintain, or admin permission. Invalid requests generate workflow warnings. Pull requests are excluded. Duplicate versions and versions that already have a GitHub Release are skipped. Closed issues are excluded; reopen one to reconsider it.

Pending versions use the existing IPA release workflow in sequence, building one captured commit from the default branch. A stable GitHub Release contains the unsigned IPA and checksum. After verifying both uploaded assets, ReleaseDaBot adds the `releasedabot` label (creating it if necessary) and closes the version issue as completed. Failed builds leave issues open and unlabeled. If issue cleanup fails after publication, a later scan retries cleanup without rebuilding the release. Edited requests are checked again before closing. Inspect the ReleaseDaBot workflow summary and release build logs for status. Failed builds can be retried by running ReleaseDaBot manually. Existing releases with incomplete assets leave their issues open for investigation; the scanner only finishes issue cleanup when both assets are present and uploaded.

ReleaseDaBot is the workflow's display name. Its GitHub activity uses `github-actions[bot]` with the built-in token. A distinct `ReleaseDaBot[bot]` account requires registering and installing a GitHub App and wiring its credentials; that account has not been created or configured here.

Run parser and scanner tests locally with:

```sh
node --test .github/scripts/release-issue.test.cjs
```
