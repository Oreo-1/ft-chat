import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../config.dart';
import '../models/message.dart';
import '../pb.dart';
import '../theme.dart';
import '../widgets/animated_dialog.dart';
import '../widgets/animated_entry.dart';
import '../widgets/composer.dart';
import '../widgets/message_bubble.dart';
import 'media_viewer.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  /// Newest first. The ListView is reversed, so index 0 sits at the bottom.
  final List<Message> _messages = [];
  final ScrollController _scroll = ScrollController();

  bool _initialLoading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  String? _error;

  Future<void>? _latestInFlight;
  bool _ownConnect = false;
  bool _realtimeConnected = false;
  Timer? _retryTimer;

  /// Ids that should animate in (just sent / arrived live) or out (deleted).
  final Set<String> _appearing = {};
  final Set<String> _removing = {};

  RecordService get _col => pb.collection(kMessagesCollection);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    pb.realtime.onDisconnect = (_) {
      if (mounted) setState(() => _realtimeConnected = false);
    };
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    pb.realtime.onDisconnect = null;
    pb.realtime.unsubscribe();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Back in the foreground: fresh realtime connection + refetch.
        _connect();
      case AppLifecycleState.paused:
        // Backgrounded: the OS will kill the socket anyway, so close it cleanly.
        _retryTimer?.cancel();
        _realtimeConnected = false;
        pb.realtime.unsubscribe();
      default:
        break;
    }
  }

  /// (Re)subscribe to realtime, then fetch the newest page.
  /// Subscribing first means nothing created during the fetch is missed.
  Future<void> _connect() async {
    _retryTimer?.cancel();
    try {
      await _subscribe();
    } catch (_) {
      _realtimeConnected = false;
      // Offline / server unreachable: retry in a bit while we're on screen.
      _retryTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) _connect();
      });
    }
    if (mounted) setState(() {});
    await _loadLatest();
  }

  Future<void> _subscribe() async {
    // Drop any existing (possibly dead) connection and start clean.
    await pb.realtime.unsubscribe();

    _ownConnect = true;
    await pb.realtime.subscribe('PB_CONNECT', (_) {
      if (mounted) setState(() => _realtimeConnected = true);
      if (_ownConnect) {
        _ownConnect = false; // the connect we just initiated; _connect() fetches
        return;
      }
      // The SDK reconnected on its own after a network drop while we were in
      // the foreground; events during the gap were lost, so refetch.
      _loadLatest();
    });
    await _col.subscribe('*', _onRealtime);
  }

  void _onRealtime(RecordSubscriptionEvent e) {
    final record = e.record;
    if (record == null || !mounted) return;
    final msg = Message(record);
    if (e.action == 'delete') {
      _removeAnimated(msg.id);
      return;
    }
    if (e.action == 'create') _markAppearing(msg.id);
    setState(() => _upsert(msg)); // create / update
  }

  void _markAppearing(String id) {
    _appearing.add(id);
    // Forget it after the animation, so it doesn't replay when the bubble is
    // scrolled off and rebuilt later.
    Future.delayed(kAnimMedium * 2, () => _appearing.remove(id));
  }

  /// Collapse the bubble, then drop it from the list.
  void _removeAnimated(String id) {
    if (_removing.contains(id) || !_messages.any((m) => m.id == id)) return;
    setState(() => _removing.add(id));
    Future.delayed(kAnimMedium, () {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == id);
        _removing.remove(id);
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  /// Insert or replace [msg], keeping newest-first order.
  void _upsert(Message msg) {
    _messages.removeWhere((m) => m.id == msg.id);
    // Older than the loaded window and there's more history: it'll come in
    // when the user scrolls up, don't insert it out of sequence.
    if (_hasMore && _messages.isNotEmpty && msg.compareTo(_messages.last) < 0) return;
    final i = _messages.indexWhere((m) => msg.compareTo(m) > 0);
    i < 0 ? _messages.add(msg) : _messages.insert(i, msg);
  }

  /// Fetch the newest page and merge it with what's already loaded.
  /// Concurrent calls share one request.
  Future<void> _loadLatest() {
    return _latestInFlight ??= _doLoadLatest().whenComplete(() => _latestInFlight = null);
  }

  Future<void> _doLoadLatest() async {
    // Refetch the whole window that's currently loaded (not just 40), so edits
    // and deletions made elsewhere while we were away are picked up too.
    // Capped to keep the request reasonable if you've scrolled very far back.
    final want = _messages.length.clamp(kPageSize, 500);
    try {
      final res = await _col.getList(
        page: 1,
        perPage: want,
        sort: '-created,-id',
        skipTotal: true,
      );
      final fresh = res.items.map(Message.new).toList();
      if (!mounted) return;

      setState(() {
        _error = null;
        _initialLoading = false;

        if (fresh.length < want) {
          // That's the entire history.
          _messages
            ..clear()
            ..addAll(fresh);
          _hasMore = false;
        } else if (_messages.isEmpty ||
            _messages.first.created.compareTo(fresh.last.created) <= 0) {
          // First load, or more arrived while we were away than this fetch
          // covers (there'd be a gap) -> start over from the fresh page.
          // Strict timestamp check: a new message created in the same ms as
          // our newest one could sort below it by id, so don't trust overlap.
          _messages
            ..clear()
            ..addAll(fresh);
          _hasMore = true;
        } else {
          // Overlap: replace everything in the fresh page's range (drops
          // messages deleted elsewhere) and keep the older ones we have.
          final boundary = fresh.last;
          final older = _messages.where((m) => m.compareTo(boundary) < 0).toList();
          _messages
            ..clear()
            ..addAll(fresh)
            ..addAll(older);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _error = _errorText(e);
      });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);

    final oldest = _messages.last;
    try {
      final res = await _col.getList(
        page: 1,
        perPage: kPageSize,
        sort: '-created,-id',
        skipTotal: true,
        // Cursor pagination: stable even while new messages keep arriving.
        filter: pb.filter(
          'created < {:c} || (created = {:c} && id < {:id})',
          {'c': oldest.created, 'id': oldest.id},
        ),
      );
      if (!mounted) return;
      setState(() {
        // List may have been reset meanwhile (e.g. resume); then drop this page.
        if (_messages.isEmpty || _messages.last.id != oldest.id) return;
        final known = _messages.map((m) => m.id).toSet();
        _messages.addAll(res.items.map(Message.new).where((m) => !known.contains(m.id)));
        _hasMore = res.items.length == kPageSize;
      });
    } catch (e) {
      _snack('Could not load older messages: ${_errorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _onScroll() {
    final pos = _scroll.position;
    // Reversed list: the visual top is maxScrollExtent.
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadOlder();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _send(String text, List<PlatformFile> files) async {
    final multipart = <http.MultipartFile>[];
    for (final f in files) {
      final len = await f.length();
      multipart.add(len != null
          ? http.MultipartFile('files', f.readAsByteStream(), len, filename: f.name)
          : http.MultipartFile.fromBytes('files', await f.readAsBytes(), filename: f.name));
    }

    final record = await _col.create(
      body: {
        'user': pb.authStore.record!.id,
        'text': text,
        'device': kDeviceName,
      },
      files: multipart,
    );

    if (!mounted) return;
    _markAppearing(record.id);
    setState(() => _upsert(Message(record)));
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  /// Long-press menu, shown as a popup at the press position.
  Future<void> _showMenu(Message msg, Offset globalPosition) async {
    HapticFeedback.selectionClick();
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;

    PopupMenuItem<String> item(String value, IconData icon, String label) => PopupMenuItem(
          value: value,
          height: 44,
          child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
        );

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        item('copy', Icons.copy, msg.text.isNotEmpty ? 'Copy text' : 'Copy file link(s)'),
        item('delete', Icons.delete_outline, 'Delete'),
      ],
    );

    switch (action) {
      case 'copy':
        final text = msg.text.isNotEmpty
            ? msg.text
            : msg.files.map((f) => msg.fileUrl(f).toString()).join('\n');
        await Clipboard.setData(ClipboardData(text: text));
        _snack('Copied');
      case 'delete':
        await _delete(msg);
    }
  }

  Future<void> _delete(Message msg) async {
    final ok = await showAnimatedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(msg.files.isEmpty
            ? 'This removes it from all devices.'
            : 'This removes it and its ${msg.files.length} file(s) from all devices.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _col.delete(msg.id);
      _removeAnimated(msg.id);
    } catch (e) {
      // 404 means it was already deleted from another device, so treat it as success.
      if (e is ClientException && e.statusCode == 404) {
        _removeAnimated(msg.id);
      } else {
        _snack('Delete failed: ${_errorText(e)}');
      }
    }
  }

  Future<void> _logout() async {
    _retryTimer?.cancel();
    await pb.realtime.unsubscribe();
    pb.authStore.clear(); // main.dart swaps back to the login screen
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text('ft-chat'),
        actions: [
          // Tiny realtime status dot; restyle later.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Tooltip(
              message: _realtimeConnected ? 'Live' : 'Offline',
              child: AnimatedContainer(
                duration: kAnimMedium,
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _realtimeConnected ? Colors.green : Colors.grey,
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: kAnimMedium,
              child: KeyedSubtree(
                // Fade between loading / empty / list states.
                key: ValueKey(_initialLoading ? 'loading' : (_messages.isEmpty ? 'empty' : 'list')),
                child: _buildList(),
              ),
            ),
          ),
          Composer(onSend: _send),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'No messages yet.'),
            if (_error != null)
              TextButton(onPressed: _connect, child: const Text('Retry')),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      // +1 for the "loading older" / "start of history" row at the top.
      itemCount: _messages.length + 1,
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: _loadingOlder
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_hasMore ? '' : 'Start of history',
                      style: Theme.of(context).textTheme.bodySmall),
            ),
          );
        }
        final msg = _messages[i];
        return AnimatedEntry(
          key: ValueKey(msg.id),
          appear: _appearing.contains(msg.id),
          removing: _removing.contains(msg.id),
          child: MessageBubble(
            message: msg,
            onLongPress: (pos) => _showMenu(msg, pos),
            onOpenMedia: (index) => MediaViewer.open(context, msg, index),
          ),
        );
      },
    );
  }
}

String _errorText(Object e) {
  if (e is ClientException) {
    final msg = e.response['message'];
    if (e.statusCode == 0) return 'Network error';
    return msg is String && msg.isNotEmpty ? '$msg (${e.statusCode})' : 'Error ${e.statusCode}';
  }
  return e.toString();
}
