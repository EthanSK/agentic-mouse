# YouTube and Chrome bridge setup

Agentic Mouse's YouTube controls use **AgentFlow YouTube Bridge**, a separate Chrome extension and macOS helper. AgentFlow supplies the recording events for automatic pause and resume.

The [bridge source is public](https://github.com/EthanSK/AgentFlow/tree/main/companions/youtube-bridge) in the AgentFlow repository. It is not bundled with Agentic Mouse and needs its own installation; installing Agentic Mouse alone will not enable these controls.

## What each part does

| Part | Role |
|---|---|
| [Agentic Mouse](../README.md) | Sends the mouse's YouTube seek, volume and speed commands, plus Chrome history and website commands. |
| [AgentFlow](https://ethansk.github.io/AgentFlow/) | Reports when dictation starts and stops. Ordinary VoiceInk is not a verified substitute. |
| YouTube Spotify Media Key | The macOS menu-bar helper relays commands through Chrome's native messaging host. Despite its name, hardware media-key interception is disabled for this workflow. |
| AgentFlow YouTube Bridge | The Chrome extension selects the YouTube player and applies commands without bringing Chrome forward. |

YouTube pauses when dictation starts and resumes only if this setup paused it. A video that was already paused stays paused; manually playing or pausing during dictation gives control back to you. AgentFlow handles other media apps separately.

## Install the bridge

1. Set up AgentFlow and its recording controls using its [build and configuration guide](https://github.com/EthanSK/AgentFlow/blob/main/SETUP.md).
2. Clone AgentFlow and keep its `companions/youtube-bridge` folder in a permanent location: the native host registration points into its `dist` folder.
3. Review the bridge's `scripts/install.sh` and build instructions. Configure your own signing identity using `YOUTUBE_SPOTIFY_MEDIA_KEY_CODESIGN_IDENTITY`; Ethan's certificate is not available on another person's Mac.
4. Run `./scripts/install.sh` from the bridge checkout. It builds the helper, registers Chrome native messaging, installs and launches `~/Applications/YouTube Spotify Media Key.app`, and adds its login LaunchAgent. It replaces any existing copy of that helper.
5. In Chrome, go to `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select the checkout's **`dist/extension`** folder.
6. Check that Chrome lists **AgentFlow YouTube Bridge**, then reload YouTube pages that were already open.

The helper's dictation auto-pause path does not require Accessibility or Input Monitoring. Agentic Mouse and AgentFlow have their own separate permissions.

## Check it works

- Open the extension's popup and check **Chrome bridge** is connected and **YouTube** reports your player.
- Play a YouTube video, start dictation, and confirm it pauses; finish dictation and confirm the same video resumes.
- Repeat with an already-paused video and confirm it stays paused.
- Test the mouse's seek, volume and temporary 2× speed controls against the [current mouse map](https://ethansk.github.io/agentic-mouse/mouse-map.html). Test normal watch pages and Shorts separately.

After a bridge update, rebuild using `./scripts/build.sh`, reload the extension in `chrome://extensions`, and reload existing YouTube pages. If the bridge is disconnected, check the menu-bar helper is running and the checkout has not moved. Reinstalling updates the native host path; reloading only the extension does not.

The website's mouse demo runs entirely in the browser and does not test or install this integration on your Mac.
