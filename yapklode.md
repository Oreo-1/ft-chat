# Stash: personal chat-to-yourself (Flutter client)

A WhatsApp/Discord-style "chat with myself" for notes and file transfer, backed by your own PocketBase.
This is the mobile client (Android/iOS). The desktop client (Tauri/Electron) can use the same collection.

> The code was written against the current PocketBase Dart SDK docs but has **not been compiled yet**.
> Run `flutter analyze` first and expect to fix a small thing or two.

---

## 1. PocketBase setup (v0.23+)

### Lock down the `users` collection (important)
The default `users` collection lets **anyone** sign up. Open Admin UI → Collections → `users` → API Rules
and set **Create rule** to "Set superusers only" (the lock icon). Then create your own user manually
(Admin UI → `users` → New record). Nobody else can register.

### Create the `messages` collection
Type **Base**, name `messages`, with these fields:

| Field    | Type       | Options |
|----------|------------|---------|
| `text`   | Plain text | not required |
| `files`  | File       | **Max select: 99**, **Max size: e.g. 524288000** (500 MB, in bytes; the default is only ~5 MB), **Protected: on**, **Thumb sizes: `400x0`** |
| `device` | Plain text | not required (`mobile` / `desktop`) |
| `created`| Autodate   | on create (usually added by default) |
| `updated`| Autodate   | on create + update (usually added by default) |

**API rules**, all five (List, View, Create, Update, Delete):

```
@request.auth.id != ""
```

Without the `created` autodate field, sorting and pagination won't work.

### Reverse proxy
- **Caddy** (simplest, automatic HTTPS): `pb.example.com { reverse_proxy 127.0.0.1:8090 }`
- **nginx**: set `client_max_body_size 0;`, `proxy_request_buffering off;`, `proxy_buffering off;`
  (the last one matters for realtime/SSE) and a long `proxy_read_timeout`.
- Cloudflare Tunnel/proxy caps uploads at 100 MB on free plans. Tailscale avoids this entirely.

---

## 2. Flutter project

```bash
flutter create --org com.yourname --project-name stash .   # inside this folder
```

Replace the `dependencies:` section of `pubspec.yaml` with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  pocketbase: ^0.25.1
  shared_preferences: ^2.3.0
  file_picker: ^10.0.0
  http: ^1.2.0
  path_provider: ^2.1.0
  open_filex: ^4.5.0
  share_plus: ^11.0.0
  cached_network_image: ^3.4.0
```

Then:

```bash
flutter pub get
flutter analyze
flutter run
```

`lib/` is already in place (`main.dart`, `backend.dart`, `login_page.dart`, `chat_page.dart`, `message_bubble.dart`).

> Versions are pinned on purpose: `file_picker` (v12 changed its API) and `share_plus` (v11 changed its API)
> have moved fast. If you bump them, adjust `FilePicker.platform.pickFiles` and `SharePlus.instance.share`.

### Android
`android/app/src/main/AndroidManifest.xml`, inside `<manifest>` (before `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Flutter only adds this for debug builds, so release builds fail silently without it.
If you test against plain `http://` (e.g. LAN IP), also add `android:usesCleartextTraffic="true"` to `<application>`.
Prefer HTTPS for anything real.

### iOS
Plain `http://` needs an ATS exception in `ios/Runner/Info.plist` (`NSAppTransportSecurity` →
`NSAllowsLocalNetworking` or `NSAllowsArbitraryLoads`). HTTPS needs nothing.

---

## 3. How it works

- **Auth**: email/password against the `users` collection; the session is stored in `shared_preferences` and refreshed on launch.
- **History**: newest 40 messages, older ones load as you scroll up (cursor on `created`).
- **Realtime**: subscribes to `messages/*`; messages from your other devices appear instantly. Refetches when the app returns to the foreground.
- **Send**: text goes as a message; the 📎 button picks any number of files and sends them as one message (the text box becomes the caption).
- **Files**: protected, so access uses short-lived file tokens (renewed every ~100 s). Tap to download and open, share icon to save elsewhere, long-press a bubble to copy/delete.
- **Names**: PocketBase appends `_xxxxxxxxxx` to stored filenames; the app strips it for display and downloads.
- `Backend.deviceName` is stored in `device` so bubbles align left/right. Use `'desktop'` in your desktop client.

## 4. Known limits / next steps

1. **Receive shares from other apps** (the killer feature: "Share → Stash" from the gallery/browser). Look at `receive_sharing_intent` or `share_handler`.
2. **Upload progress**: the SDK doesn't expose it; use a plain `http.MultipartRequest` with a progress-reporting stream.
3. **Offline queue**: failed sends currently restore the text and show an error.
4. **Background/large uploads**: Android may kill long uploads when the app is backgrounded (needs a foreground service, e.g. `flutter_background_service`/`workmanager`).
5. **Search, pinned notes, tags, markdown rendering**.
6. **Cleanup**: downloaded files live in the OS cache dir; add a "clear cache" action if it grows.
