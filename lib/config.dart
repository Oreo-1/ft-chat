/// App-wide configuration. Everything you're likely to tweak lives here.
library;

/// PocketBase base URL (your Cloudflare tunnel hostname).
/// Override at build time: flutter run --dart-define=PB_URL=https://pb.example.com
const String kPocketBaseUrl = String.fromEnvironment(
  'PB_URL',
  defaultValue: 'https://pb.aryo.fyi',
);

const String kUsersCollection = 'ft_users';
const String kMessagesCollection = 'ft_messages';

/// Written into each message's `device` field. Messages whose device equals
/// this value are drawn on the right; everything else on the left.
/// The desktop client should use 'desktop'.
const String kDeviceName = 'mobile';

/// Messages fetched per page (initial load and each "load older" step).
const int kPageSize = 40;

/// Cloudflare (Free/Pro plan) rejects request bodies over 100 MB, and the
/// tunnel sits in front of PocketBase, so this is the real ceiling for one
/// message (all attachments + text + multipart overhead). We keep some
/// headroom below 100 MB. Raise this if you change plans/tunnel setup, and
/// raise the `files` field maxSize in PocketBase to match.
const int kMaxUploadBytes = 95 * 1024 * 1024; // ~99.6 MB

// -----------------------------------------------------------------------------
// Local cache (Android/iOS)
// Set any of these to a value to add a limit; null means unlimited.
// -----------------------------------------------------------------------------

/// Max messages kept in the local chat cache (newest kept). Applied at app
/// start. Example: `const int? kMessageCacheLimit = 5000;`
const int? kMessageCacheLimit = null;

/// Max number of media files (images, thumbnails, videos) kept on disk.
/// Least recently used are evicted first. Example: `= 2000;`
const int? kMediaCacheMaxFiles = null;

/// Evict media not viewed for this long. Example: `= Duration(days: 90);`
const Duration? kMediaCacheMaxAge = null;

/// Save a video to the media cache the first time it's played, so it plays
/// offline afterwards. That first play downloads it twice (stream + save).
const bool kCacheVideos = true;
