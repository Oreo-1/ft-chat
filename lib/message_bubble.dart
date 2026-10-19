import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:share_plus/share_plus.dart';

import 'backend.dart';

const _thumbSize = '400x0'; // must also be listed in the field's "Thumb sizes"

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

bool _isImage(String name) =>
    const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(_ext(name));

IconData _iconFor(String name) {
  switch (_ext(name)) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return Icons.folder_zip_outlined;
    case 'mp4':
    case 'mov':
    case 'mkv':
    case 'webm':
      return Icons.movie_outlined;
    case 'mp3':
    case 'm4a':
    case 'wav':
    case 'ogg':
    case 'flac':
      return Icons.audiotrack_outlined;
    case 'txt':
    case 'md':
      return Icons.description_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

String _time(String created) {
  final t = DateTime.tryParse(created)?.toLocal();
  if (t == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final now = DateTime.now();
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return today ? hm : '${t.year}-${two(t.month)}-${two(t.day)} $hm';
}

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.backend,
    required this.record,
    required this.fileToken,
    required this.onDelete,
  });

  final Backend backend;
  final RecordModel record;
  final String? fileToken;
  final VoidCallback onDelete;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  /// stored file name -> download progress (null = started, unknown yet)
  final Map<String, double?> _progress = {};

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<File?> _fetch(String name) async {
    setState(() => _progress[name] = null);
    try {
      return await widget.backend.downloadFile(
        widget.record,
        name,
        onProgress: (p) {
          if (mounted) setState(() => _progress[name] = p);
        },
      );
    } catch (e) {
      _toast('Download failed: ${describeError(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _progress.remove(name));
    }
  }

  Future<void> _open(String name) async {
    final file = await _fetch(name);
    if (file == null) return;
    final res = await OpenFilex.open(file.path);
    if (res.type != ResultType.done) {
      _toast('No app found to open this file. Use the share button instead.');
    }
  }

  Future<void> _share(String name) async {
    final file = await _fetch(name);
    if (file == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  void _showMenu() {
    final text = widget.record.getStringValue('text');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy text'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(ctx);
                  _toast('Copied');
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.record;
    final text = r.getStringValue('text');
    final files = r.getListValue<String>('files');
    final mine = r.getStringValue('device') == Backend.deviceName;
    final images = files.where(_isImage).toList();
    final others = files.where((f) => !_isImage(f)).toList();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Material(
            color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onLongPress: _showMenu,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in images)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _imageTile(f),
                      ),
                    for (final f in others) _fileTile(f),
                    if (text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(text),
                      ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _time(r.getStringValue('created')),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageTile(String name) {
    final token = widget.fileToken;
    const placeholder = ColoredBox(color: Color(0x14000000));
    return GestureDetector(
      onTap: () => _open(name),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 240,
          height: 180,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (token == null)
                placeholder
              else
                CachedNetworkImage(
                  imageUrl: widget.backend
                      .fileUrl(widget.record, name, token: token, thumb: _thumbSize)
                      .toString(),
                  // Stable key: the token in the URL changes every few minutes,
                  // the cached image must not.
                  cacheKey: '${widget.record.id}/$name/$_thumbSize',
                  fit: BoxFit.cover,
                  placeholder: (_, _) => placeholder,
                  errorWidget: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              if (_progress.containsKey(name))
                Center(child: CircularProgressIndicator(value: _progress[name])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileTile(String name) {
    final busy = _progress.containsKey(name);
    return InkWell(
      onTap: busy ? null : () => _open(name),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(name)),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Backend.displayName(name),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(value: _progress[name]),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Save / share',
              icon: const Icon(Icons.ios_share),
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : () => _share(name),
            ),
          ],
        ),
      ),
    );
  }
}
