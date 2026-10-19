import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import 'backend.dart';
import 'message_bubble.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.backend});
  final Backend backend;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const _perPage = 40;

  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Newest first (the ListView is reversed, so index 0 sits at the bottom).
  final List<RecordModel> _messages = [];

  Future<UnsubscribeFunc>? _subscription;
  Timer? _tokenTimer;
  String? _fileToken;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _uploading = false;
  String? _error;

  PocketBase get _pb => widget.backend.pb;
  RecordService get _col => _pb.collection(Backend.collection);

  // ------------------------------------------------------------ lifecycle

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _start();
  }

  Future<void> _start() async {
    // Subscribe first so nothing is missed between the fetch and the stream.
    try {
      _subscription = _col.subscribe('*', _onEvent);
      await _subscription;
    } catch (_) {
      // Offline at launch: the SDK retries; _refresh() below shows the error.
    }
    unawaited(_refreshToken());
    // File tokens are short-lived (~3 min by default), so renew regularly.
    _tokenTimer =
        Timer.periodic(const Duration(seconds: 100), (_) => _refreshToken());
    await _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _refreshToken();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenTimer?.cancel();
    _subscription?.then((unsub) => unsub()).catchError((_) {});
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- data

  Future<void> _refreshToken() async {
    try {
      final t = await _pb.files.getToken();
      if (mounted) setState(() => _fileToken = t);
    } catch (_) {/* keep the old one */}
  }

  void _sort() => _messages.sort(
      (a, b) => b.getStringValue('created').compareTo(a.getStringValue('created')));

  void _upsert(RecordModel r) {
    final i = _messages.indexWhere((m) => m.id == r.id);
    if (i >= 0) {
      _messages[i] = r;
    } else {
      _messages.add(r);
      _sort();
    }
  }

  /// Reloads the newest page and merges it with what's already loaded.
  /// Also used when the app returns to the foreground.
  Future<void> _refresh() async {
    try {
      final res = await _col.getList(page: 1, perPage: _perPage, sort: '-created');
      if (!mounted) return;
      setState(() {
        final fresh = res.items;
        if (fresh.length < _perPage) {
          _messages
            ..clear()
            ..addAll(fresh);
          _hasMore = false;
        } else {
          final oldest = fresh.last.getStringValue('created');
          final older = _messages
              .where((m) => m.getStringValue('created').compareTo(oldest) < 0)
              .toList();
          _messages
            ..clear()
            ..addAll(fresh)
            ..addAll(older);
          if (older.isEmpty) _hasMore = true;
        }
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeError(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    _loadingMore = true;
    try {
      final oldest = _messages.last.getStringValue('created');
      final res = await _col.getList(
        page: 1,
        perPage: _perPage,
        sort: '-created',
        filter: _pb.filter('created < {:oldest}', {'oldest': oldest}),
      );
      if (!mounted) return;
      setState(() {
        for (final r in res.items) {
          _upsert(r);
        }
        _hasMore = res.items.length == _perPage;
      });
    } catch (_) {
      // Will retry on the next scroll.
    } finally {
      _loadingMore = false;
    }
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  void _onEvent(RecordSubscriptionEvent e) {
    final r = e.record;
    if (r == null || !mounted) return;
    setState(() {
      if (e.action == 'delete') {
        _messages.removeWhere((m) => m.id == r.id);
      } else {
        _upsert(r);
      }
    });
  }

  // -------------------------------------------------------------- actions

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      final rec = await _col.create(
        body: {'text': text, 'device': Backend.deviceName},
      );
      if (mounted) setState(() => _upsert(rec));
    } catch (e) {
      _input.text = text; // give the note back
      _toast('Couldn’t send: ${describeError(e)}');
    }
  }

  Future<void> _attach() async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (picked == null || picked.files.isEmpty) return;

    final caption = _input.text.trim();
    setState(() => _uploading = true);
    try {
      final files = <http.MultipartFile>[];
      for (final f in picked.files) {
        final path = f.path;
        if (path == null) continue;
        files.add(await http.MultipartFile.fromPath('files', path, filename: f.name));
      }
      final rec = await _col.create(
        body: {'text': caption, 'device': Backend.deviceName},
        files: files,
      );
      _input.clear();
      if (mounted) setState(() => _upsert(rec));
    } catch (e) {
      _toast('Upload failed: ${describeError(e)}');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(RecordModel r) async {
    try {
      await _col.delete(r.id);
      if (mounted) setState(() => _messages.removeWhere((m) => m.id == r.id));
    } catch (e) {
      _toast('Couldn’t delete: ${describeError(e)}');
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ft-chat'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') widget.backend.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(widget.backend.serverUrl,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildList()),
          if (_uploading) const LinearProgressIndicator(),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error != null
                    ? 'Couldn’t load messages:\n$_error'
                    : 'Nothing here yet.\nSend yourself a note or a file.',
                textAlign: TextAlign.center,
              ),
              if (_error != null)
                TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _messages.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final r = _messages[i];
        return MessageBubble(
          key: ValueKey(r.id),
          backend: widget.backend,
          record: r,
          fileToken: _fileToken,
          onDelete: () => _delete(r),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Material(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Attach files',
                icon: const Icon(Icons.attach_file),
                onPressed: _uploading ? null : _attach,
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Note or message…',
                    filled: true,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: 'Send',
                icon: const Icon(Icons.send),
                onPressed: _sendText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
