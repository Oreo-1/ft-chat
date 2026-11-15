import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/message.dart';

/// One chat bubble: images, other files, then text. Right-aligned when it was
/// sent from this device (see kDeviceName), left-aligned otherwise.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, required this.onLongPress});

  final Message message;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final images = message.files.where(isImageFile).toList();
    final others = message.files.where((f) => !isImageFile(f)).toList();
    final t = message.createdAt;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: mine
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in images)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: GestureDetector(
                    onTap: () => _open(message.fileUrl(f)),
                    child: Image.network(
                      // "480x0" thumb is declared on the files field in pb_schema.json.
                      message.fileUrl(f, thumb: '480x0').toString(),
                      width: 240,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _FileRow(name: f, onTap: () => _open(message.fileUrl(f))),
                    ),
                  ),
                ),
              for (final f in others)
                _FileRow(name: f, onTap: () => _open(message.fileUrl(f, download: !isVideoFile(f)))),
              if (message.text.isNotEmpty) Text(message.text),
              const SizedBox(height: 2),
              Text(
                mine ? time : '${message.device} · $time',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isVideoFile(name) ? Icons.movie_outlined : Icons.insert_drive_file_outlined, size: 20),
            const SizedBox(width: 6),
            Flexible(child: Text(displayFileName(name), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}
