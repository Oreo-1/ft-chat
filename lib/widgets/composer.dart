import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';

import '../config.dart';
import '../models/file_meta.dart';
import '../theme.dart';

/// Chat-app style input bar: [attach | text field] [send].
/// Calls [onSend] and clears itself only if it succeeds, so nothing is lost
/// on a failed upload.
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
    final scheme = Theme.of(context).colorScheme;
    const noBorder = InputBorder.none;

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pending attachments; grows/shrinks smoothly.
              AnimatedSize(
                duration: kAnimFast,
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: _files.isEmpty
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final f in _files)
                                InputChip(
                                  avatar: const Icon(Icons.attach_file, size: 16),
                                  label: Text('${f.name} (${formatBytes(_sizes[f] ?? 0)})',
                                      overflow: TextOverflow.ellipsis),
                                  onDeleted: _sending ? null : () => _remove(f),
                                ),
                            ],
                          ),
                        ),
                      ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Input "pill": attach button + multiline text field.
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: kBorderRadius,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          PopupMenuButton<FileType>(
                            enabled: !_sending,
                            icon: const Icon(Icons.add),
                            tooltip: 'Attach',
                            onSelected: _pick,
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: FileType.media,
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.photo_library_outlined),
                                  title: Text('Photos & videos'),
                                ),
                              ),
                              PopupMenuItem(
                                value: FileType.any,
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(Icons.insert_drive_file_outlined),
                                  title: Text('Files'),
                                ),
                              ),
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
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                isDense: true,
                                contentPadding: EdgeInsets.fromLTRB(0, 14, 12, 14),
                                border: noBorder,
                                enabledBorder: noBorder,
                                focusedBorder: noBorder,
                                disabledBorder: noBorder,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Send button: enabled when there's something to send,
                  // swaps to a spinner while uploading.
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _text,
                    builder: (context, value, _) {
                      final canSend = value.text.trim().isNotEmpty || _files.isNotEmpty;
                      return SizedBox(
                        width: 48,
                        height: 48,
                        child: AnimatedSwitcher(
                          duration: kAnimFast,
                          transitionBuilder: (child, a) =>
                              ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
                          child: _sending
                              ? const Padding(
                                  key: ValueKey('sending'),
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton.filled(
                                  key: const ValueKey('send'),
                                  icon: const Icon(Icons.send),
                                  onPressed: canSend ? _send : null,
                                ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
