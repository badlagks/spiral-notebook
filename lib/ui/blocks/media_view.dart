import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../data/media/media_store.dart';
import '../../models/notebook.dart';
import '../store_scope.dart';
import '../theme.dart';
import 'checklist_view.dart';

/// A photo or video taped to the page like a print, with room underneath
/// for a note, where it was, and things to do about it.
class MediaView extends StatefulWidget {
  const MediaView({super.key, required this.block});

  final MediaBlock block;

  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  late final _note = TextEditingController(text: widget.block.note);
  late final _place = TextEditingController(text: widget.block.place);

  @override
  void dispose() {
    _note.dispose();
    _place.dispose();
    super.dispose();
  }

  void _addTodo() {
    setState(() => widget.block.todos.items.add(ChecklistItem()));
    StoreScope.read(context).changed();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final faint = Pen.pencil.withValues(alpha: 0.5);
    final small = handwriting.copyWith(fontSize: 16, height: 1.3);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: const BoxDecoration(
        color: Color(0xFFFEFDF9),
        boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 5, offset: Offset(1, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: b.aspect,
            child: ClipRect(
              child: switch (b.kind) {
                _ when b.isSample => _SamplePicture(video: b.kind == MediaKind.video),
                MediaKind.photo => StoredPicture(mediaId: b.mediaId),
                MediaKind.video => _Video(block: b),
              },
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _note,
            maxLines: null,
            style: small,
            decoration: InputDecoration.collapsed(
              hintText: b.kind == MediaKind.photo ? 'What is this photo about?' : 'What is this video about?',
              hintStyle: small.copyWith(color: faint),
            ),
            onChanged: (t) {
              b.note = t;
              StoreScope.read(context).changedQuietly();
            },
          ),
          Row(
            children: [
              Icon(Icons.place_outlined, size: 15, color: faint),
              const SizedBox(width: 3),
              Expanded(
                child: TextField(
                  controller: _place,
                  style: small.copyWith(fontSize: 15, color: Pen.pencil),
                  decoration: InputDecoration.collapsed(
                    hintText: 'Where was this?',
                    hintStyle: small.copyWith(fontSize: 15, color: faint),
                  ),
                  onChanged: (t) {
                    b.place = t;
                    StoreScope.read(context).changedQuietly();
                  },
                ),
              ),
            ],
          ),
          if (b.todos.items.isNotEmpty)
            ChecklistView(block: b.todos, fontSize: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Pen.pencil,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: const Size(0, 28),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _addTodo,
              icon: const Icon(Icons.add_task, size: 15),
              label: Text('Add a to-do', style: small.copyWith(fontSize: 15, color: Pen.pencil)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Photos already read from storage, so turning pages doesn't reload them.
final _photoCache = <String, Future<Uint8List?>>{};

/// A photo kept on the device, shown once it has been read.
class StoredPicture extends StatelessWidget {
  const StoredPicture({super.key, required this.mediaId, this.fit = BoxFit.cover, this.alignment = Alignment.center});
  final String mediaId;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _photoCache.putIfAbsent(mediaId, () => mediaStore.get(mediaId)),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return _Missing(loading: snap.connectionState != ConnectionState.done, icon: Icons.photo_outlined);
        }
        return Image.memory(
          bytes,
          fit: fit,
          alignment: alignment,
          cacheWidth: 1600,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const _Missing(loading: false, icon: Icons.broken_image_outlined),
        );
      },
    );
  }
}

class _Video extends StatefulWidget {
  const _Video({required this.block});
  final MediaBlock block;

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  VideoPlayerController? _player;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final player = await mediaStore.videoPlayer(widget.block.mediaId);
      if (player == null) throw StateError('missing');
      if (!mounted) {
        await player.dispose();
        return;
      }
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return;
      }
      player.addListener(_onTick);
      final aspect = player.value.aspectRatio;
      if ((aspect - widget.block.aspect).abs() > 0.01) {
        widget.block.aspect = aspect;
        StoreScope.read(context).changedQuietly();
      }
      setState(() => _player = player);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    final v = _player!.value;
    // Back to the start when it ends, ready to play again.
    if (v.isCompleted && !v.isPlaying) _player!.seekTo(Duration.zero);
    setState(() {});
  }

  @override
  void dispose() {
    _player?.removeListener(_onTick);
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (player == null) return _Missing(loading: !_failed, icon: Icons.videocam_off_outlined);
    final playing = player.value.isPlaying;
    return GestureDetector(
      onTap: () => playing ? player.pause() : player.play(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(player),
          if (!playing) const _PlayBadge(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              player,
              allowScrubbing: true,
              padding: const EdgeInsets.only(top: 8),
              colors: const VideoProgressColors(playedColor: Colors.white, bufferedColor: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
        ),
      );
}

class _Missing extends StatelessWidget {
  const _Missing({required this.loading, required this.icon});
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFFE8E2D4),
        child: Center(
          child: loading
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, color: Pen.pencil),
        ),
      );
}

/// A little painted landscape that stands in for a photo in previews.
class _SamplePicture extends StatelessWidget {
  const _SamplePicture({required this.video});
  final bool video;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _LandscapePainter()),
          if (video) const _PlayBadge(),
        ],
      );
}

class _LandscapePainter extends CustomPainter {
  const _LandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8EC5E8), Color(0xFFF6E3C2)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawCircle(Offset(w * 0.74, h * 0.3), h * 0.11, Paint()..color = const Color(0xFFFFD36B));
    final far = Path()
      ..moveTo(0, h * 0.7)
      ..quadraticBezierTo(w * 0.25, h * 0.38, w * 0.5, h * 0.62)
      ..quadraticBezierTo(w * 0.72, h * 0.44, w, h * 0.66)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFF7FA27A));
    final near = Path()
      ..moveTo(0, h * 0.86)
      ..quadraticBezierTo(w * 0.45, h * 0.64, w, h * 0.88)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = const Color(0xFF557F55));
  }

  @override
  bool shouldRepaint(_LandscapePainter old) => false;
}
