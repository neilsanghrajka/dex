# Dex Agent Notes

## Public Release Steps

Use this flow when preparing a public Dex DMG. Preserve any existing user changes; do not reset or revert unrelated work.

1. Verify the source tree:

```bash
swift test
bash script/build_and_run.sh --verify
```

2. Reinstall the local app build:

```bash
pkill -x Dex >/dev/null 2>&1 || true
rm -rf /Applications/Dex.app
/usr/bin/ditto --norsrc dist/Dex.app /Applications/Dex.app
/usr/bin/xattr -rc /Applications/Dex.app >/dev/null 2>&1 || true
/usr/bin/codesign --verify --deep --strict --verbose=2 /Applications/Dex.app
/usr/bin/open -n /Applications/Dex.app
```

3. Commit the release changes after tests and local reinstall are clean.

4. Build the distributable DMG from a staged copy of `dist/Dex.app`, not the `/Applications` install. Sign the staged app and final DMG with:

```text
Developer ID Application: Neil Sanghrajka (HB7DDUKF98)
```

Use hardened runtime and timestamps for the staged app:

```bash
codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: Neil Sanghrajka (HB7DDUKF98)" "$STAGE/Dex.app"
```

5. Notarize and staple the DMG:

```bash
xcrun notarytool submit dist/Dex.dmg --keychain-profile dex-notary --wait --output-format json
xcrun stapler staple dist/Dex.dmg
xcrun stapler validate dist/Dex.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 dist/Dex.dmg
```

6. Verify the final artifact:

```bash
codesign --verify --verbose=2 dist/Dex.dmg
hdiutil verify dist/Dex.dmg
shasum -a 256 dist/Dex.dmg
```

If `notarytool` reports that an agreement is missing or expired, check Apple Developer Account and App Store Connect Business agreements, accept any required Developer Program or Free Apps agreement, wait briefly for propagation, then retry.
