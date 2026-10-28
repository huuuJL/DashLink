# Release notes and validation

## 0.2.0 test release

This release is for direct testing on Apple silicon Macs. The owner chose a test
release because no Apple Developer Program membership or Developer ID certificate
is configured. Local signing is not Apple notarization.

Before distributing:

1. Build a fresh app, outside a cloud-synced folder when possible.
2. Run the native connection-state, pairing-confirmation, process-lifecycle, and
   relay tests; run the viewer tests and receiver tests.
3. Run `python3 Tests/receiver-smoke.py /path/to/DashLink.app /tmp/dashlink-smoke`.
   It uses a synthetic identity, checks packaged HTML/assets, verifies loopback
   binding and rejected control tokens, and checks shutdown when its parent exits.
4. Run `scripts/package-test-release.py` to verify the app signature and package
   the app, user instructions, licensing notices, and corresponding source.
   The packager rejects local state and installation overrides.
5. Test fresh setup and a saved pairing on a separate Mac. Test normal and 4K
   playback, microphone permission denial, disconnect/reconnect, app quit,
   network failure, and sleep/wake. Do not claim an untested scenario passes.

## Before a production release

- Obtain a Developer ID Application certificate via Apple Developer Program.
  Sign all executable components, including the bundled Java runtime, with the
  appropriate hardened-runtime settings, then submit for notarization and staple
  the accepted ticket. Validate the resulting archive on a separate Mac under
  normal Gatekeeper settings. Do not clear quarantine or disable Gatekeeper.
- Resolve the CarPlay accessory authentication/certification requirements. The
  shared experimental identity used by this prototype is not production approval.
  Developer ID signing and notarization do not certify a CarPlay receiver.
- Qualify supported macOS/iOS versions and supported hardware. The current build
  is ARM64 only and does not claim Intel support.
- Complete call/Siri, long-session, reconnect, network-change, and sleep/wake
  testing; perform a dedicated security review of the receiver protocol surface.
- Publish a support/update policy and a source distribution matching each binary.
  No update service or telemetry backend is included in this test release.

Official references:

- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://developer.apple.com/carplay/
- https://mfi.apple.com/en/how-it-works
- https://support.apple.com/102445
