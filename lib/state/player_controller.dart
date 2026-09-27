import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../db/track_dao.dart';
import '../utils/log_util.dart';

enum RepeatMode { off, all, one }

/// 播放器控制器（封装 flutter_soloud / SoLoud）
///
/// 提供播放队列、上一首/下一首、循环/随机、seek、位置流。
class PlayerController extends ChangeNotifier {
  SoLoud? _soloud;
  SoLoud get _engine => _soloud ??= SoLoud.instance;
  bool _initialized = false;

  List<TrackItem> _queue = [];
  int _index = -1;

  AudioSource? _source;
  SoundHandle? _handle;
  StreamSubscription<StreamSoundEvent>? _sub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  RepeatMode _repeat = RepeatMode.all;
  bool _shuffle = false;
  double _volume = 1.0;

  bool get initialized => _initialized;
  bool get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration;
  RepeatMode get repeatMode => _repeat;
  bool get shuffle => _shuffle;
  double get volume => _volume;
  bool get hasTrack => _index >= 0 && _index < _queue.length;
  TrackItem? get currentTrack =>
      hasTrack ? _queue[_index] : null;
  int get queueLength => _queue.length;

  /// 每首曲目开始播放时回调（用于记录播放历史）
  void Function(TrackItem track)? onTrackStarted;

  Timer? _ticker;

  /// 初始化共享 Future：并发调用只初始化一次
  Future<void>? _initFuture;

  /// 加载代际：快速连续切歌时，过期请求作废，避免多轨同时播放
  int _loadGen = 0;

  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    await _engine.init();
    _initialized = true;
    logInfo('Player', 'SoLoud initialized');
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _updatePosition();
    });
  }

  void _updatePosition() {
    final h = _handle;
    if (h == null) return;
    try {
      _position = _engine.getPosition(h);
      notifyListeners();
    } catch (_) {
      // handle 已失效（例如刚播完），忽略
    }
  }

  /// 设置播放队列并开始播放第 [startIndex] 首
  Future<void> playQueue(List<TrackItem> tracks, {int startIndex = 0}) async {
    if (!_initialized) await init();
    _queue = List.from(tracks);
    _index = _queue.isEmpty ? -1 : startIndex.clamp(0, _queue.length - 1);
    await _loadAndPlay();
  }

  Future<void> _loadAndPlay() async {
    final gen = ++_loadGen; // 本次加载代际
    await _disposeCurrent();
    // 释放期间可能已有更新的请求，放弃本次
    if (gen != _loadGen) return;

    if (!hasTrack) {
      _playing = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners();
      return;
    }
    final track = _queue[_index];

    AudioSource? newSource;
    try {
      newSource = await _engine.loadFile(track.path);
    } catch (e) {
      logError('Player', '加载失败 ${track.path}: $e');
      if (gen == _loadGen) {
        _playing = false;
        notifyListeners();
      }
      return;
    }

    // 加载耗时期间若已有新的点击，丢弃这次已加载的资源，避免多轨同时播放
    if (gen != _loadGen) {
      try {
        await _engine.disposeSource(newSource);
      } catch (_) {}
      return;
    }

    _source = newSource;
    _duration = _engine.getLength(newSource);
    _handle = _engine.play(newSource, volume: _volume);
    _listenEnd();
    _playing = true;
    _position = Duration.zero;
    logInfo('Player', '播放: ${track.path}');
    onTrackStarted?.call(track);
    notifyListeners();
  }

  void _listenEnd() {
    _sub?.cancel();
    final src = _source;
    if (src == null) return;
    _sub = src.soundEvents.listen((e) {
      if (e.event == SoundEventType.handleIsNoMoreValid) {
        _onEnded();
      }
    });
  }

  Future<void> _onEnded() async {
    if (_repeat == RepeatMode.one && _source != null) {
      // 单曲循环：重新播放同一 source
      _handle = _engine.play(_source!, volume: _volume);
      _position = Duration.zero;
      _playing = true;
      notifyListeners();
      return;
    }
    await next(auto: true);
  }

  Future<void> togglePlay() async {
    if (!_initialized) await init();
    if (_handle == null) {
      if (_queue.isNotEmpty) await _loadAndPlay();
      return;
    }
    if (_playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> play() async {
    if (_handle == null) {
      await _loadAndPlay();
      return;
    }
    _engine.setPause(_handle!, false);
    _playing = true;
    notifyListeners();
  }

  Future<void> pause() async {
    if (_handle == null) return;
    _engine.setPause(_handle!, true);
    _playing = false;
    notifyListeners();
  }

  Future<void> resume() async {
    if (_handle == null) return;
    _engine.setPause(_handle!, false);
    _playing = true;
    notifyListeners();
  }

  Future<void> seek(Duration d) async {
    final h = _handle;
    if (h == null) return;
    try {
      _engine.seek(h, d);
      _position = d;
      notifyListeners();
    } catch (e) {
      logWarn('Player', 'seek 失败: $e');
    }
  }

  Future<void> next({bool auto = false}) async {
    if (_queue.isEmpty) return;
    if (_shuffle) {
      _index = _randomIndex();
    } else if (_index < _queue.length - 1) {
      _index++;
    } else if (_repeat == RepeatMode.all) {
      _index = 0;
    } else {
      // 列表播完且非循环：停在末尾
      await stop();
      return;
    }
    await _loadAndPlay();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_shuffle) {
      _index = _randomIndex();
    } else if (_index > 0) {
      _index--;
    } else if (_repeat == RepeatMode.all) {
      _index = _queue.length - 1;
    } else {
      await seek(Duration.zero);
      return;
    }
    await _loadAndPlay();
  }

  int _randomIndex() {
    if (_queue.length <= 1) return 0;
    final rnd = Random();
    int n = _index;
    while (n == _index) {
      n = rnd.nextInt(_queue.length);
    }
    return n;
  }

  void setRepeatMode(RepeatMode m) {
    _repeat = m;
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    final h = _handle;
    if (h != null) {
      try {
        _engine.setVolume(h, _volume);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _loadGen++; // 使进行中的加载失效，避免停止后又冒出声音
    await _disposeCurrent();
    _playing = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _index = -1;
    _queue = [];
    notifyListeners();
  }

  Future<void> _disposeCurrent() async {
    // 先摘除字段再异步释放，避免并发调用重复释放同一资源
    final h = _handle;
    final s = _source;
    final sub = _sub;
    _handle = null;
    _source = null;
    _sub = null;
    sub?.cancel();
    if (h != null) {
      try {
        await _engine.stop(h);
      } catch (_) {}
    }
    if (s != null) {
      try {
        await _engine.disposeSource(s);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _engine.deinit();
    super.dispose();
  }
}
