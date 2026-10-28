# DashLink 0.2.0 · Test release

Wireless CarPlay on an Apple silicon Mac. No cable, dongle, or companion iPhone app.

This is an experimental test release, not an Apple-certified CarPlay receiver.
It is locally signed and has not been notarized by Apple. Compatibility has been
observed on two iPhones; it is not established for every device or iOS release.

## Install

Requires an Apple silicon Mac (M1 or later), macOS 15 or later, and an iPhone with
CarPlay enabled. Intel Macs are not supported by this build. The app includes
its runtime; testers do not need Xcode, Java, Node.js, or command-line tools.

1. Unzip the release and drag **DashLink.app** into **Applications**.
2. Open DashLink. Since this test build is not notarized, macOS may block first
   launch. Review [Apple’s guidance for opening trusted apps](https://support.apple.com/102445).
   Only allow this app if you trust the person who provided it. Do not disable
   Gatekeeper or remove quarantine attributes.
3. Choose **Set up DashLink** and review the experimental connection notice.
   Internet access is needed for this first step. Setup downloads and verifies
   a pinned upstream preview; it does not execute the downloaded Android app.
4. Unlock your iPhone and open **Settings → Bluetooth**. Choose **Find iPhones**
   in DashLink and select your phone.
5. Connect both devices to the same Wi-Fi. Enter its name and password in
   DashLink and choose **Connect iPhone**.
6. Confirm matching pairing codes on both devices if asked. Accept the CarPlay
   prompt on the iPhone. If it asks for a PIN, enter **3939**.

DashLink combines pairing, Bluetooth verification, and receiver startup into one
connection action. A saved Bluetooth pairing is reused. Your Wi-Fi password is
held only for this session, so you must enter it again after quitting the app.

Click the live CarPlay screen to navigate. Home, Back, Siri, music, and volume
controls sit below it. **More** contains display, sound, night mode, and keyboard
help. Use **Disconnect** before changing phones or networks.

## What changed

- One connection card and one Connect action.
- A compact CarPlay viewer with no duplicate headers or persistent technical stats.
- Secondary controls and diagnostics move to menus.
- Music buffering accommodates the roughly 400 ms bursts observed during testing.
- Sound resumes automatically when the native viewer permits it; a click remains
  available as a fallback. Browser sound restrictions are respected.
- The shared app contains no local installation paths, accessory identity,
  Wi-Fi credentials, phone pairings, or diagnostic logs.

## Compatibility and known limits

The receiver uses PlayPort and a shared experimental accessory identity that is
prepared separately on each Mac. The setup notice describes its provenance and
limitations. Apple may stop accepting that identity after an iOS update or
revocation. It is not bundled in the app or source archive.

Live wireless video, 4K display, and Apple Music through Mac speakers were tested.
After increasing the music buffer, playback counters recorded no underruns or
drops across 7,002 scheduled buffers; the user subsequently confirmed working
playback. This is evidence from a limited test, not a guarantee of uninterrupted
playback. The user also confirmed that the 0.2.0 compact interface connected and played
music successfully. Broader real-device testing is still required. Siri, complete call behavior, sleep/wake, network roaming,
and long-running reconnection still need qualification. The minimum macOS target
is 15; live tests were performed on macOS 27.2. Fresh installations default to
1280 × 720; existing display preferences, including 4K, are retained.

Microphone access is optional and separately requested for Siri or calls.
Some Wi-Fi networks isolate devices and prevent connection.

## Privacy and local data

The app sends Wi-Fi credentials through private process input to its local
receiver and selected iPhone. It never saves the Wi-Fi password. There is no
analytics upload. Setup contacts GitHub to download the verified preview.

State is stored in `~/Library/Application Support/DashLink` with owner-only
access. It includes locally prepared connection identity, receiver pairing
records, display/network preferences, and local diagnostic logs. Logs can contain
device names and network identifiers; review them before sharing. Do not share
this folder. The shareable release is built separately from user state.

The viewer and authenticated control API listen on loopback, port 18741.
The CarPlay transport listens on the local network, port 17000, so the selected
iPhone can connect. A native Bluetooth relay uses a session-authenticated random
loopback port. Quitting DashLink stops its receiver.

## Troubleshooting

- **No phone found:** unlock the iPhone, keep Bluetooth settings open, then search
  again. Allow Bluetooth access for DashLink if macOS asks.
- **Connection fails:** check both devices use the same Wi-Fi and verify the
  password. Disconnect and try once more. Do not repeatedly forget/re-pair a
  working device without evidence of a pairing problem.
- **No sound:** start music in CarPlay and check its volume. Click inside the
  viewer if it asks to enable sound. Check the Mac’s output volume too.
- **Stuttering:** keep both devices close to the Wi-Fi access point. Display
  settings allow a lower resolution if needed; applying a setting reconnects.
- **Details:** use the top-right **More → Connection details**. Review any details
  before sending them to someone else; never share your state folder or password.

## Build and validation

Source is included under GPL-3.0. Prerequisites: Xcode command-line tools with
Swift 6.2+, Node.js 20.19+/22.12+, and JDK 21. Build on an Apple silicon Mac:

```sh
export JAVA_HOME="/path/to/jdk-21/Contents/Home"
bash build-app.sh
```

The script builds the receiver and viewer, compiles the native app, includes a
trimmed Java runtime, and creates a fresh locally signed app. It does not include
user state. To create a test-release archive with source and notices:

```sh
python3 scripts/package-test-release.py ../DashLink.app ../DashLink-0.2.0-test.zip
```

See `RELEASING.md` for validation and the remaining requirements for a public
production release. This test release must not be described as notarized,
Apple-certified, or broadly qualified.

PlayPort revision: `9a0882dd0ffe48e467b59d58b12d81391df55ade`.
See `NOTICE.txt` and `Receiver/LICENSE` for upstream attribution and licensing.
