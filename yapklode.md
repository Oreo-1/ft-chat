# ft-chat

A personal chat with yourself across your devices: notes and file transfer, stored in PocketBase.

## 1. PocketBase

1. Admin UI → **Settings → Import collections** → paste or load `pb_schema.json`.
   Leave **"Delete missing collections"** unchecked so your existing collections stay as they are.
   This creates:
   - `ft_users` (auth): `username` + `password`, log in by username, email optional, no self-registration (`createRule` is null).
   - `ft_messages`: `user` (relation), `text`, `files` (up to 20, 100 MiB each, `480x0` thumbnails), `device`, `created`, `updated`.
     Every rule is "owner only", so realtime events only go to your own sessions.
2. Create your user in the admin UI: `ft_users` → New record → username + password.

## 2. Flutter app

```sh
# from this folder: generates android/ and ios/ next to the existing lib/ and pubspec.yaml
flutter create --project-name ft_chat --org com.yourname --platforms=android,ios .
flutter pub get
flutter run --dart-define=PB_URL=https://pb.yourdomain.tld
```

Or change the default URL in `lib/config.dart`.

Platform bits after `flutter create`:
- **Android** `android/app/src/main/AndroidManifest.xml`:
  - add `<uses-permission android:name="android.permission.INTERNET"/>` above `<application>` (debug builds have it, release builds don't).
  - set `android:label="ft-chat"`.
  - inside `<manifest>`, add this so url_launcher can open links:
    ```xml
    <queries>
      <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
    </queries>
    ```
- **iOS** `ios/Runner/Info.plist`: add `NSPhotoLibraryUsageDescription` (needed for the photo/video picker) and set `CFBundleDisplayName` to `ft-chat`.

## How it works

| Feature | Where |
|---|---|
| Login (username/password, saved across restarts) | `lib/pb.dart`, `lib/screens/login_screen.dart` |
| Realtime: subscribes to `ft_messages`. On resume it reconnects and refetches; it also refetches when the SDK reconnects by itself | `ChatScreen._connect`, `_subscribe` |
| History: newest 40, cursor-paginated (`created`/`id`) while scrolling up | `_loadLatest`, `_loadOlder` |
| Long-press → copy (text, or file links) / delete | `_showMenu` |
| `device` field → `mobile` on the right, everything else on the left | `kDeviceName`, `MessageBubble` |
| Upload limit (95 MiB per message, under Cloudflare's 100 MB request cap) | `kMaxUploadBytes` |

### Desktop client contract
- Auth: `POST /api/collections/ft_users/auth-with-password` with `{identity: username, password}`.
- Create a message: multipart `POST /api/collections/ft_messages/records` with `user=<auth id>`, `device=desktop`, optional `text`, and zero or more `files`.
- List: `sort=-created,-id`, `perPage=40`, and for older pages
  `filter=created < "<oldest.created>" || (created = "<oldest.created>" && id < "<oldest.id>")`.
- Realtime: subscribe to `ft_messages/*`.

## Known limitations / next steps
- **File URLs are unprotected.** Anyone who has the exact URL can download the file. URLs include a random record id and a random filename suffix, but if you want token-gated files, set `protected: true` on the `files` field and append `pb.files.getToken()` to the URLs.
- No upload progress bar. The SDK's multipart request doesn't report progress, so use `http.StreamedRequest` if you want one.
- Tapping a file opens it in the browser (images full size, videos inline, other files as a download).
- Not done yet: sharing into the app from other apps (`receive_sharing_intent`), message editing, local cache for offline viewing.
