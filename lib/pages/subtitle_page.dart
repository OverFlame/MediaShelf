import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/track_dao.dart';
import '../services/subtitle_parser.dart';
import '../state/app_state.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// 字幕模式（全屏）：模糊封面背景 + 可滑动/点击跳转的字幕
class SubtitlePage extends StatefulWidget {
  const SubtitlePage({super.key});

  @override
  State<SubtitlePage> createState() => _SubtitlePageState();
}

class _SubtitlePageState extends State<SubtitlePage> {
  static const double _itemExtent = 56.0;

  final ScrollController _scroll = ScrollController();
  bool _userScrolling = false;
  int _lastIndex = -1;
  Timer? _resumeTimer;
  double _viewportHeight = 400;

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final appState = context.watch<AppState>();
    final track = player.currentTrack;

    final lines = track == null ? const <LyricLine>[] : appState.getSubtitleLines(track);
    final cover = track == null ? null : appState.coverForTrack(track);

    final currentIndex = _currentIndex(lines, player.position);

    // 自动滚动到当前行
    if (currentIndex != _lastIndex && currentIndex >= 0 && !_userScrolling) {
      _lastIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollTo(currentIndex);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: Stack(
        children: [
          _background(cover),
          SafeArea(
            child: Column(
              children: [
                _topBar(context, track),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _viewportHeight = constraints.maxHeight;
                      return _lyricsView(lines, currentIndex, player);
                    },
                  ),
                ),
                _bottomBar(player),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _background(String? cover) {
    Widget? image;
    if (cover != null && File(cover).existsSync()) {
      image = Image.file(File(cover), fit: BoxFit.cover);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
              child: image,
            ),
          ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _topBar(BuildContext context, TrackItem? track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down,
                size: 28, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track?.displayTitle ?? '未在播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                if (track != null)
                  Text(
                    track.artist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lyricsView(
      List<LyricLine> lines, int currentIndex, PlayerController player) {
    if (lines.isEmpty) {
      return const Center(
        child: Text('无字幕',
            style: TextStyle(color: Colors.white54, fontSize: 14)),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _userScrolling = true;
        } else if (n is ScrollEndNotification && n.dragDetails != null) {
          _resumeTimer?.cancel();
          _resumeTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _userScrolling = false);
          });
        }
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _itemExtent,
        padding: EdgeInsets.symmetric(vertical: _viewportHeight / 2 - _itemExtent / 2),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          final active = i == currentIndex;
          return GestureDetector(
            onTap: () => player.seek(Duration(milliseconds: line.startMs)),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontSize: active ? 22 : 16,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  height: 1.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bottomBar(PlayerController player) {
    final maxMs = player.duration.inMilliseconds;
    final posMs = player.position.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : 0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(formatDuration(player.position),
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: Colors.white24,
                  ),
                  child: Slider(
                    value: maxMs > 0 ? posMs.toDouble() : 0,
                    max: maxMs > 0 ? maxMs.toDouble() : 1,
                    onChanged: (v) =>
                        player.seek(Duration(milliseconds: v.round())),
                  ),
                ),
              ),
              Text(formatDuration(player.duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white, size: 30),
                onPressed: () => player.previous(),
              ),
              IconButton(
                icon: Icon(
                  player.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.white,
                  size: 52,
                ),
                onPressed: () => player.togglePlay(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                onPressed: () => player.next(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _currentIndex(List<LyricLine> lines, Duration pos) {
    final ms = pos.inMilliseconds;
    int idx = -1;
    for (int i = 0; i < lines.length; i++) {
      if (ms >= lines[i].startMs) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  void _scrollTo(int index) {
    if (!_scroll.hasClients) return;
    final target =
        index * _itemExtent - _viewportHeight / 2 + _itemExtent / 2;
    final maxExtent = _scroll.position.maxScrollExtent;
    final clamped = target.clamp(0.0, maxExtent < 0 ? 0.0 : maxExtent);
    _scroll.animateTo(clamped,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }
}
