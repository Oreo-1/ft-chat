import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cache/downloads.dart';
import '../cache/media_cache.dart';
import '../models/file_meta.dart';
import '../models/message.dart';
import '../theme.dart';

/// Popup card with a non-media file's details. It zooms out of the tapped
/// attachment tile (the type icon flies across as a Hero), like the media
/// viewer does for images/videos. It shows metadata only, never the content.
class FileViewer extends StatelessWidget {
  const FileViewer({super.key, required this.message, required this.filename});

  final Message message;
  final String filename;

  /// [origin] is the tapped tile's rect in global coordinates; the card
  /// scales out from there.
  static Future<void> open(BuildContext context, Message message, String filename, Rect origin) {
    final screen = MediaQuery.sizeOf(context);
    final alignment = Alignment(
      (origin.center.dx / screen.width) * 2 - 1,
      (origin.center.dy / screen.height) * 2 - 1,
    );

    return Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: kAnimMedium,
      reverseTransitionDuration: kAnimFast,
      pageBuilder: (_, _, _) => FileViewer(message: message, filename: filename),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.5, end: 1.0).animate(curved),
            alignment: alignment,
            child: child,
          ),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = message.fileUrl(filename);
    final ext = fileExt(filename);
    final t = message.createdAt;
    final sent = '${t.year}-${us2(t.month)}-${us2(t.day)} ${us2(t.hour)}:${us2(t.minute)}';
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 380.0);

    // Own (transparent) Scaffold so snackbars show above the dimmed backdrop.
    // Tapping outside the card closes it; taps on the card are swallowed.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: SizedBox(
              width: width,
              child: Material(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: kShape,
                clipBehavior: Clip.antiAlias,
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: FileTypeIcon(
                              filename: filename,
                              heroTag: fileHeroTag(message, filename),
                              size: 56,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                displayFileName(filename),
                                style: theme.textTheme.titleMedium,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<FileMeta>(
                        future: fetchFileMeta(mediaCacheKey(message.id, filename), url),
                        builder: (context, snap) {
                          final meta = snap.data;
                          final loading = snap.connectionState != ConnectionState.done;
                          final size = meta?.size;
                          return Column(
                            children: [
                              _Row('Type', ext.isEmpty ? 'File' : '${ext.toUpperCase()} file'),
                              _Row('MIME type', meta?.contentType ?? (loading ? '…' : 'Unknown')),
                              _Row(
                                'Size',
                                size != null
                                    ? '${formatBytes(size)}  (${_groupDigits(size)} bytes)'
                                    : (loading ? '…' : 'Unknown'),
                              ),
                              _Row('Sent from', message.device),
                              _Row('Sent', sent),
                              _Row('Stored as', filename),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _DownloadActions(message: message, filename: filename, url: url),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String us2(int n) => n.toString().padLeft(2, '0');

  static String _groupDigits(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

/// Copy link + download / progress / open, driven by [Downloads].
class _DownloadActions extends StatelessWidget {
  const _DownloadActions({required this.message, required this.filename, required this.url});

  final Message message;
  final String filename;
  final Uri url;

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final downloads = Downloads.instance;
    final theme = Theme.of(context);
    const compact = Size(0, 40); // the theme's FilledButton default is full width

    return ValueListenableBuilder<DownloadState>(
      valueListenable: downloads.state(message, filename),
      builder: (context, state, _) {
        final Widget status;
        final List<Widget> buttons;

        switch (state) {
          case DownloadRunning(:final received, :final total, :final progress):
            status = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 6),
                Text(
                  total != null
                      ? '${formatBytes(received)} / ${formatBytes(total)}'
                      : formatBytes(received),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
            buttons = [
              TextButton(
                onPressed: () => downloads.cancel(message, filename),
                child: const Text('Cancel'),
              ),
            ];
          case DownloadDone(:final path):
            status = Text('Saved on this device', style: theme.textTheme.bodySmall);
            buttons = [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove downloaded copy',
                onPressed: () => downloads.remove(message, filename),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: compact),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
                onPressed: () async {
                  final err = await downloads.open(path);
                  if (err != null && context.mounted) _snack(context, err);
                },
              ),
            ];
          case DownloadFailed(:final error):
            status = Text('Download failed: $error',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis);
            buttons = [
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: compact),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                onPressed: () => downloads.start(message, filename),
              ),
            ];
          case DownloadIdle():
            status = const SizedBox.shrink();
            buttons = [
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: compact),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Download'),
                onPressed: () => downloads.start(message, filename),
              ),
            ];
        }

        return AnimatedSize(
          duration: kAnimFast,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.only(right: 8, bottom: 8), child: status),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copy link'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url.toString()));
                      if (context.mounted) _snack(context, 'Link copied');
                    },
                  ),
                  const Spacer(),
                  ...buttons,
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

String fileHeroTag(Message message, String filename) => 'file/${message.id}/$filename';

/// Icon for a file based on its extension. Wrapped in FittedBox + Hero so it
/// can fly between the small tile icon and the big card icon smoothly.
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({
    super.key,
    required this.filename,
    required this.size,
    this.heroTag,
    this.color,
  });

  final String filename;
  final double size;
  final String? heroTag;
  final Color? color;

  static IconData iconFor(String filename) {
    switch (fileExt(filename)) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'xz':
        return Icons.folder_zip_outlined;
      case 'mp3' || 'wav' || 'flac' || 'ogg' || 'm4a' || 'aac' || 'opus':
        return Icons.audio_file_outlined;
      case 'apk':
        return Icons.android;
      case 'txt' || 'md' || 'csv' || 'json' || 'log' || 'xml' || 'yaml' || 'yml':
        return Icons.description_outlined;
      case 'doc' || 'docx' || 'odt' || 'rtf':
        return Icons.article_outlined;
      case 'xls' || 'xlsx' || 'ods':
        return Icons.table_chart_outlined;
      case 'ppt' || 'pptx' || 'odp':
        return Icons.slideshow_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = FittedBox(child: Icon(iconFor(filename), size: 64, color: color));
    return SizedBox(
      width: size,
      height: size,
      child: heroTag == null ? icon : Hero(tag: heroTag!, child: icon),
    );
  }
}
