import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../config.dart';

/// Text input + attachments + send. Calls [onSend] and clears itself only if
/// it succeeds, so nothing is lost on a failed upload.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.onSend});

  final Future<void> Function(String text, List<PlatformFile> files) onSend;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final List<PlatformFile> _files = [];
  final Map<PlatformFile, int> _sizes = {};
  bool _sending = false;

  int get _totalBytes => _sizes.values.fold(0, (a, b) => a + b);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(FileType type) async {
    final picked = await FilePicker.pickFiles(type: type);
    if (picked.isEmpty) return;

    var skipped = 0;
    for (final f in picked) {
      final size = await f.length() ?? 0;
      if (_totalBytes + size + _text.text.length > kMaxUploadBytes) {
        skipped++;
        continue;
      }
      _files.add(f);
      _sizes[f] = size;
    }
    setState(() {});
    if (skipped > 0) {
      _snack('$skipped file(s) skipped: one message is limited to ${formatBytes(kMaxUploadBytes)} '
          '(Cloudflare tunnel limit).');
    }
  }

  void _remove(PlatformFile f) => setState(() {
        _files.remove(f);
        _sizes.remove(f);
      });

  Future<void> _send() async {
    final text = _text.text.trim();
    if (_sending || (text.isEmpty && _files.isEmpty)) return;

    setState(() => _sending = true);
    try {
      await widget.onSend(text, List.of(_files));
      _text.clear();
      _files.clear();
      _sizes.clear();
    } on ClientException catch (e) {
      final msg = e.response['message'];
      _snack('Send failed: ${e.statusCode == 413 ? 'too large' : msg ?? 'network error'}'
          ' (${e.statusCode})');
    } catch (e) {
      _snack('Send failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_files.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final f in _files)
                      InputChip(
                        label: Text('${f.name} (${formatBytes(_sizes[f] ?? 0)})',
                            overflow: TextOverflow.ellipsis),
                        onDeleted: _sending ? null : () => _remove(f),
                      ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PopupMenuButton<FileType>(
                  enabled: !_sending,
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Attach',
                  onSelected: _pick,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: FileType.media, child: Text('Photos & videos')),
                    PopupMenuItem(value: FileType.any, child: Text('Files')),
                  ],
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    enabled: !_sending,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Message'),
                  ),
                ),
                _sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
