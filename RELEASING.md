# Releasing MIDITrainer to the App Store

This guide covers the complete process for releasing MIDITrainer to the App Store.

## Prerequisites

1. **Apple Developer Account**: Enrolled in the Apple Developer Program ($99/year)
2. **App Store Connect**: App created at [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
3. **Fastlane**: Already installed via rbenv
4. **Xcode**: With valid signing certificates

## Initial Setup (One-Time)

### 1. Create App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click "My Apps" → "+" → "New App"
3. Fill in:
   - Platform: iOS
   - Name: MIDI Trainer
   - Primary Language: English (U.S.)
   - Bundle ID: com.sambender.MIDITrainer
   - SKU: MIDITrainer (or any unique identifier)

### 2. Configure Fastlane Authentication

Set your Apple ID for fastlane:

```bash
export APPLE_ID="your-apple-id@example.com"
```

Or edit `fastlane/Appfile` directly.

For CI/CD or to avoid 2FA prompts, create an App Store Connect API key:

1. Go to App Store Connect → Users and Access → Keys
2. Generate a new key with "App Manager" access
3. Download the .p8 file
4. Set environment variables:
   ```bash
   export APP_STORE_CONNECT_API_KEY_ID="YOUR_KEY_ID"
   export APP_STORE_CONNECT_API_KEY_ISSUER_ID="YOUR_ISSUER_ID"
   export APP_STORE_CONNECT_API_KEY_PATH="/path/to/AuthKey.p8"
   ```

### 3. Set Up Privacy Policy & Support URLs

Before submitting, you need:
- A privacy policy URL (required for all apps)
- A support URL

Update these in `fastlane/metadata/en-US/privacy_url.txt` and `support_url.txt`.

## Release Process

### 1. Update Version Number

Edit the version in Xcode:
- Select the project in the navigator
- Select the "MIDITrainer" target
- Under "General", update "Version" (e.g., 1.0, 1.1, 2.0)

The build number is auto-incremented by Fastlane.

### 2. Update Release Notes

Edit `fastlane/metadata/en-US/release_notes.txt` with what's new in this version.

### 3. Build and Upload to TestFlight

```bash
cd /Users/sam/code/ios/MIDITrainer
fastlane beta
```

This will:
- Increment the build number if needed
- Build the app for App Store
- Upload to TestFlight

### 4. Test on TestFlight

1. Wait for Apple to process the build (~15-30 minutes)
2. Open TestFlight on your iPad
3. Install and test the new build
4. Invite beta testers if desired

### 5. Submit for App Store Review

Once testing is complete:

```bash
fastlane release
```

Or manually in App Store Connect:
1. Go to your app → App Store tab
2. Click "+ Version or Platform" if creating a new version
3. Select your build from TestFlight
4. Fill in App Information:
   - Screenshots (required for each device size)
   - App Preview videos (optional)
   - Description, keywords, etc. (auto-filled by fastlane metadata)
5. Answer the App Review questions
6. Submit for Review

## App Store Requirements Checklist

### Screenshots Required
- 6.7" iPhone (iPhone 15 Pro Max) - 1290 x 2796 pixels
- 6.5" iPhone (iPhone 11 Pro Max) - 1242 x 2688 pixels
- 12.9" iPad Pro - 2048 x 2732 pixels

Generate screenshots with:
```bash
fastlane screenshots
```

### App Review Information
- Contact info for the reviewer
- Notes about MIDI requirements (they may not have a MIDI keyboard)

### Content Rating
Answer the questionnaire in App Store Connect about:
- Violence, sexual content, etc. (all "None" for this app)

### Privacy
Since this app:
- Does NOT collect any user data
- Does NOT use analytics
- All data stays on device

You can declare "Data Not Collected" in App Store Connect privacy section.

## Attribution Requirements

The app uses melody data from these sources that require attribution:

### Weimar Jazz Database (ODbL License)
Required citation in the app (see Settings → Acknowledgements):
> Pfleiderer, M., Frieler, K., Abeßer, J., Zaddach, W.-G., & Burkhart, B. (Eds.). (2017). Inside the Jazzomat: New Perspectives for Jazz Research. Schott Campus.

### McGill Billboard Dataset (CC0 License)
Attribution requested (scholarly norm):
> Burgoyne, J. A., Wild, J., & Fujinaga, I. (2011). An Expert Ground Truth Set for Audio Chord Recognition and Music Analysis. ISMIR.

### POP909 Dataset (MIT License)
Standard MIT license attribution included in Acknowledgements view.

### Piano Samples
**TODO**: Verify the source and licensing of the piano samples (Piano.ff.*.mp3). These were copied from an older project and the original source is unknown.

## Troubleshooting

### "No signing certificate" error
Ensure automatic signing is enabled in Xcode and you're signed in with your Apple ID.

### Build number already exists
Fastlane automatically handles this, but if needed:
```bash
fastlane run increment_build_number
```

### Upload fails with auth error
Re-authenticate:
```bash
fastlane spaceauth -u your@email.com
```

## Fastlane Commands Reference

| Command | Description |
|---------|-------------|
| `fastlane beta` | Build and upload to TestFlight |
| `fastlane release` | Build and upload to App Store |
| `fastlane build` | Build only (no upload) |
| `fastlane test` | Run tests |
| `fastlane screenshots` | Capture App Store screenshots |

## Post-Release

After your app is approved:
1. Monitor crash reports in App Store Connect
2. Respond to user reviews
3. Check download analytics
