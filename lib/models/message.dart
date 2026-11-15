import 'package:pocketbase/pocketbase.dart';

import '../config.dart';
import '../pb.dart';

/// Thin wrapper around a `ft_messages` record.
class Message {
  Message(this.record);

  final RecordModel record;

  String get id => record.id;
  String get text => record.getStringValue('text');
  String get device => record.getStringValue('device');
  List<String> get files => record.getListValue<String>('files');

  /// PocketBase datetime string, e.g. "2026-11-15 10:00:00.123Z".
  /// This format sorts correctly as a plain string.
  String get created => record.getStringValue('created');
  DateTime get createdAt => DateTime.tryParse(created)?.toLocal() ?? DateTime.now();

  bool get isMine => device == kDeviceName;

  Uri fileUrl(String filename, {String? thumb, bool download = false}) =>
      pb.files.getURL(record, filename, thumb: thumb, download: download ? true : null);

  /// Newest-first ordering key, matching the server sort "-created,-id".
  /// Returns > 0 if this message is newer than [other].
  int compareTo(Message other) {
    final c = created.compareTo(other.created);
    return c != 0 ? c : id.compareTo(other.id);
  }
}

const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
const _videoExts = {'mp4', 'mov', 'webm', 'mkv', 'avi', '3gp', 'm4v'};

String fileExt(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
}

bool isImageFile(String filename) => _imageExts.contains(fileExt(filename));
bool isVideoFile(String filename) => _videoExts.contains(fileExt(filename));

/// PocketBase stores uploads as "name_<10 random chars>.ext".
/// Strip that suffix for display.
String displayFileName(String filename) =>
    filename.replaceFirst(RegExp(r'_[a-zA-Z0-9]{10}(?=\.[^.]+$|$)'), '');
