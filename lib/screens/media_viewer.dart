import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../cache/media_cache.dart';
import '../config.dart';
import '../models/message.dart';
import '../theme.dart';

/// Fullscreen viewer for a message's images/videos. Opened with a Hero
/// animation so the media grows out of the tapped bubble. Swipe sideways
/// between items; the message text (if any) shows as a caption.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.message, required this.initialIndex});

  final Message message;
  final int initialIndex;

  static Future<void> open(BuildContext context, Message message, int index) {
    return Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      barrierDismissible: false,
      transitionDuration: kAnimMedium,
      reverseTransitionDuration: kAnimFast,
      pageBuilder: (_, _, _) => MediaViewer(message: message, initialIndex: index),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _chrome = true; // top bar + caption visible

  List<String> get _media => widget.message.media;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final current = _media[_index];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: _media.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final f = _media[i];
              return isVideoFile(f)
                  ? _VideoPage(
                      url: msg.fileUrl(f),
                      cacheKey: mediaCacheKey(msg.id, f),
                      heroTag: msg.heroTag(f),
                      onTap: () => setState(() => _chrome = !_chrome),
                    )
                  : _ImagePage(
                      url: msg.fileUrl(f),
                      thumbUrl: msg.fileUrl(f, thumb: '480x0'),
                      cacheKey: mediaCacheKey(msg.id, f),
                      thumbCacheKey: mediaCacheKey(msg.id, f, thumb: '480x0'),
                      heroTag: msg.heroTag(f),
                      onTap: () => setState(() => _chrome = !_chrome),
                    );
            },
          ),

          // Top bar
          AnimatedOpacity(
            opacity: _chrome ? 1 : 0,
            duration: kAnimFast,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: Container(
                color: Colors.black54,
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          _media.length > 1
                              ? '${_index + 1} / ${_media.length}  ·  ${displayFileName(current)}'
                              : displayFileName(current),
                          style: const TextStyle(color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.download_outlined, color: Colors.white),
                        tooltip: 'Download',
                        onPressed: () => launchUrl(msg.fileUrl(current, download: true),
                            mode: LaunchMode.externalApplication),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Caption
          if (msg.text.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedOpacity(
                opacity: _chrome ? 1 : 0,
                duration: kAnimFast,
                child: IgnorePointer(
                  ignoring: !_chrome,
                  child: Container(
                    color: Colors.black54,
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Text(msg.text, style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImagePage extends StatelessWidget {
  const _ImagePage({
    required this.url,
    required this.thumbUrl,
    required this.cacheKey,
    required this.thumbCacheKey,
    required this.heroTag,
    required this.onTap,
  });

  final Uri url;
  final Uri thumbUrl;
  final String cacheKey;
  final String thumbCacheKey;
  final String heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Hero(
            tag: heroTag,
            child: CachedNetworkImage(
              imageUrl: url.toString(),
              cacheKey: cacheKey,
              cacheManager: mediaCache,
              fit: BoxFit.contain,
              fadeInDuration: kAnimFast,
              fadeOutDuration: Duration.zero,
              // While the full image loads, show the (already cached)
              // thumbnail so the hero flight and first frame aren't empty.
              placeholder: (_, _) => Stack(
                alignment: Alignment.center,
                children: [
                  CachedNetworkImage(
                    imageUrl: thumbUrl.toString(),
                    cacheKey: thumbCacheKey,
                    cacheManager: mediaCache,
                    fit: BoxFit.contain,
                    fadeInDuration: Duration.zero,
                  ),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ),
              errorWidget: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  const _VideoPage({
    required this.url,
    required this.cacheKey,
    required this.heroTag,
    required this.onTap,
  });

  final Uri url;
  final String cacheKey;
  final String heroTag;
  final VoidCallback onTap;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _c;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Play from the media cache if this video was saved before (works
  /// offline); otherwise stream it and, if enabled, save it in the background.
  Future<void> _init() async {
    final cached = await mediaCache.getFileFromCache(widget.cacheKey);
    if (!mounted) return;

    final c = cached != null
        ? VideoPlayerController.file(cached.file)
        : VideoPlayerController.networkUrl(widget.url);
    if (cached == null && kCacheVideos) {
      mediaCache
          .downloadFile(widget.url.toString(), key: widget.cacheKey)
          .then((_) {}, onError: (_) {});
    }

    _c = c..addListener(_onTick);
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() {});
      c.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {}); // play/pause icon
  }

  @override
  void dispose() {
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        color: Colors.transparent, // make the whole page tappable
        alignment: Alignment.center,
        child: Hero(
          tag: widget.heroTag,
          child: ready
              ? AspectRatio(
                  aspectRatio: c!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(c!),
                      AnimatedOpacity(
                        opacity: c!.value.isPlaying ? 0 : 1,
                        duration: kAnimFast,
                        child: IconButton(
                          iconSize: 64,
                          icon: const Icon(Icons.play_circle_fill, color: Colors.white70),
                          onPressed: _togglePlay,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(
                          c!,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      // Tap anywhere on the video (above the bar) to pause.
                      if (c!.value.isPlaying)
                        Positioned.fill(
                          bottom: 36,
                          child: GestureDetector(onTap: _togglePlay),
                        ),
                    ],
                  ),
                )
              : AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const ColoredBox(color: Colors.black, child: SizedBox.expand()),
                      if (_failed)
                        const Text('Could not play this video.\nUse download instead.',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70))
                      else
                        const CircularProgressIndicator(strokeWidth: 2),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
