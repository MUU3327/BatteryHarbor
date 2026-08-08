# Unnotarized Community DMG

The Battery Harbor community DMG is a self-signed early-testing build that is not notarized by Apple. It is not a Mac App Store release, and it must never require users to disable Gatekeeper or SIP.

## Install

1. Download the DMG containing `unnotarized` and its `.sha256` file from the official GitHub Releases page.
2. Run `shasum -a 256 <path-to-DMG>` and compare the result with the release page.
3. Open the DMG and drag `Battery Harbor.app` to `Applications`.
4. Try to open Battery Harbor once. macOS will block the build because it is not notarized by Apple.
5. Open System Settings, select Privacy & Security, and click Open Anyway in the Security section.
6. Confirm that you want to open Battery Harbor.

Do not disable Gatekeeper globally, disable SIP, or run untrusted `sudo` installation commands.

## Enable charging control

1. Open Battery Harbor Settings and select Charging.
2. Register or update the control helper.
3. Follow the app prompt to System Settings > General > Login Items & Extensions and approve the Battery Harbor background control module.
4. Return to Battery Harbor and test the connection.
5. Read the safety notice and personally start the safety self-test.
6. Do not test pause, resume, or charge limits until write, read-back, and restore verification has passed.

The self-test briefly switches a whitelisted charging-control value, reads it back, and restores the original value. Hardware writes lock again whenever the Helper or Mac restarts.

## Upgrade

1. Select Remove Helper in Settings > Charging.
2. Quit the old Battery Harbor build.
3. Replace the old app in Applications with the new build.
4. Launch the new build, then register, approve, and run the safety self-test again.

The first community preview does not guarantee in-place Helper upgrades across every macOS release and Mac model.

## Uninstall

1. Select Remove Helper in Settings > Charging and confirm that it is no longer enabled.
2. Disable Launch Battery Harbor at Login.
3. Quit Battery Harbor.
4. Move `Battery Harbor.app` from Applications to the Trash.
5. If System Settings still lists the old background item, log out or restart the Mac and check again.

## Known limitations

- The build is not signed with Apple Developer ID or notarized, so first launch requires manual approval.
- Only Apple Silicon Macs are currently targeted; the compatibility matrix is incomplete.
- The self-signed root Helper passed testing in a clean temporary administrator account with no Apple ID or maintainer certificate. Other Mac models and macOS releases still need community validation.
- Automatically Discharge Above Limit is experimental and should remain disabled in the first preview.
- After the Helper allows charging again, macOS may take tens of seconds or about a minute to restore actual battery input. This is expected while the adapter remains connected and the battery is not being actively discharged.

## Maintainer signing certificate

Every community DMG must sign both the App and Helper with the same `Battery Harbor Open Source Release` certificate. The maintainer must keep an encrypted `.p12` backup containing the private key outside the repository. Never commit the private key, backup password, or an unencrypted key to GitHub. Losing the private key prevents future releases from proving continuity with earlier community builds.
