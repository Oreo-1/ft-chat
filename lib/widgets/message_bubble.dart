import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/file_meta.dart';
import '../models/message.dart';
import '../theme.dart';

/// One chat bubble: media, other files, text, then "device · time".
/// Right-aligned when sent from this device (see kDeviceName), left otherwise.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.onLongPress,
    required this.onOpenMedia,
  });

  final Message message;

  /// Called with the global press position so the menu can open there.
  final void Function(Offset globalPosition) onLongPress;

  /// Called with the index into [Message.media] that was tapped.
  final void Function(int mediaIndex) onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.isMine;
    final media = message.media;
    final others = message.otherFiles;
    final t = message.createdAt;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPressStart: (d) => onLongPress(d.globalPosition),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            borderRadius: kBorderRadius,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: fg),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (media.isNotEmpty) _MediaGrid(message: message, onOpen: onOpenMedia),
                for (final f in others)
                  _FileTile(
                    name: f,
                    url: message.fileUrl(f),
                    onTap: () => launchUrl(message.fileUrl(f, download: true),
                        mode: LaunchMode.externalApplication),
                  ),
                if (message.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Text(message.text),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                  child: Text(
                    '${message.device} · $time',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: fg.withValues(alpha: 0.65)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One media item: full width (240). Several: a 2-column grid of squares.
class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.message, required this.onOpen});

  final Message message;
  final void Function(int) onOpen;

  @override
  Widget build(BuildContext context) {
    final media = message.media;
    if (media.length == 1) {
      return _MediaTile(
        message: message,
        filename: media.first,
        width: 240,
        maxHeight: 320,
        onTap: () => onOpen(0),
      );
    }
    return SizedBox(
      width: 240,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < media.length; i++)
            _MediaTile(
              message: message,
              filename: media[i],
              width: 118,
              height: 118,
              onTap: () => onOpen(i),
            ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.message,
    required this.filename,
    required this.width,
    required this.onTap,
    this.height,
    this.maxHeight,
  });

  final Message message;
  final String filename;
  final double width;
  final double? height;
  final double? maxHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = isVideoFile(filename)
        ? VideoPlaceholder(width: width, height: height ?? width * 9 / 16)
        : Image.network(
            // "480x0" thumb is declared on the files field in pb_schema.json.
            message.fileUrl(filename, thumb: '480x0').toString(),
            width: width,
            height: height,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: kAnimFast,
                    child: child,
                  ),
            errorBuilder: (_, _, _) => SizedBox(
              width: width,
              height: height ?? 120,
              child: const Icon(Icons.broken_image_outlined),
            ),
          );

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(kRadius - 2)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
          child: Hero(tag: message.heroTag(filename), child: content),
        ),
      ),
    );
  }
}

/// Stand-in for a video in the chat (PocketBase doesn't make video thumbnails).
class VideoPlaceholder extends StatelessWidget {
  const VideoPlaceholder({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      color: Colors.black,
      alignment: Alignment.center,
      child: const Icon(Icons.play_circle_outline, size: 44, color: Colors.white70),
    );
  }
}

/// Non-media attachment: icon + name + "TYPE · size".
class _FileTile extends StatelessWidget {
  const _FileTile({required this.name, required this.url, required this.onTap});

  final String name;
  final Uri url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ext = fileExt(name);
    final small = Theme.of(context).textTheme.labelSmall;

    return InkWell(
      onTap: onTap,
      borderRadius: kBorderRadius,
      child: Container(
        width: 240,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: kBorderRadius,
        ),
        child: Row(
          children: [
            const Icon(Icons.attach_file, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayFileName(name), maxLines: 2, overflow: TextOverflow.ellipsis),
                  FutureBuilder<FileMeta>(
                    future: fetchFileMeta(url),
                    builder: (context, snap) {
                      final meta = snap.data;
                      final type = ext.isNotEmpty
                          ? ext.toUpperCase()
                          : (meta?.contentType ?? 'File');
                      final size = meta?.size != null ? formatBytes(meta!.size!) : '…';
                      return Text(
                        snap.connectionState == ConnectionState.done && meta?.size == null
                            ? type
                            : '$type · $size',
                        style: small,
                      );
                    },
                  ),
                ],
              ),
            ),
            const Icon(Icons.download_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}
