import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/log_util.dart';

/// 外链播放的结果
enum LaunchResult { ok, unsupportedPlatform, failed }

/// Android 侧「交给系统播放器」的入口签名。
///
/// 参数是文件路径与 MIME，返回系统是否接下了这次分派。
typedef SystemOpen = Future<bool> Function(String path, String mimeType);

/// 把文件或播放列表交给系统默认播放器（BUILD_GUIDE 第 9.4、9.5 与 24.2 节）
///
/// 桌面端起进程，Android 走 Intent，都不链接任何播放器库，
/// 因此不引入许可证风险。
class VideoLauncher {
  VideoLauncher({
    Future<Process> Function(String, List<String>)? start,
    SystemOpen? openWithSystem,
    String? os,
  })  : _start = start ?? Process.start,
        _openWithSystem = openWithSystem ?? _invokeNativeOpen,
        _os = os ?? detectOs();

  final Future<Process> Function(String executable, List<String> arguments)
      _start;
  final SystemOpen _openWithSystem;
  final String _os;

  /// 平台通道，名字与 `MediaBridge.channel` 一致：同一个通道由 MainActivity 处理。
  @visibleForTesting
  static const MethodChannel channel = MethodChannel('mediashelf/playback');

  static Future<bool> _invokeNativeOpen(String path, String mimeType) async {
    final ok = await channel.invokeMethod<bool>('openVideo', <String, Object>{
      'path': path,
      'mimeType': mimeType,
    });
    return ok ?? false;
  }

  static String detectOs() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    return 'other';
  }

  /// 桌面平台分派表。Android 走 Intent，认不出平台时返回 null。
  static (String, List<String>)? commandFor(String path, String os) =>
      switch (os) {
        'windows' => ('cmd', <String>['/c', 'start', '', path]),
        'linux' => ('xdg-open', <String>[path]),
        _ => null,
      };

  /// 扩展名到 MIME 的对照表（BUILD_GUIDE 第 9.5 节：MIME 由扩展名给出）
  static const Map<String, String> mimeByExtension = <String, String>{
    '.mp4': 'video/mp4',
    '.m4v': 'video/x-m4v',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.flv': 'video/x-flv',
    '.wmv': 'video/x-ms-wmv',
    '.mpg': 'video/mpeg',
    '.mpeg': 'video/mpeg',
    '.ts': 'video/mp2t',
    '.3gp': 'video/3gpp',
    // 外链播放的产物是 m3u8 播放列表
    '.m3u8': 'application/x-mpegurl',
    '.m3u': 'audio/x-mpegurl',
  };

  /// 取 MIME。认不出扩展名时给 `video/*`，让系统自己挑应用。
  static String mimeTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return 'video/*';
    return mimeByExtension[path.substring(dot).toLowerCase()] ?? 'video/*';
  }

  Future<LaunchResult> open(String path) async {
    if (_os == 'android') return _openOnAndroid(path);
    final cmd = commandFor(path, _os);
    if (cmd == null) {
      logWarn('Launch', '平台 $_os 不支持外链播放：$path');
      return LaunchResult.unsupportedPlatform;
    }
    try {
      await _start(cmd.$1, cmd.$2);
      logInfo('Launch', '已交给外部播放器：${cmd.$1} ${cmd.$2.join(' ')}');
      return LaunchResult.ok;
    } catch (e) {
      logWarn('Launch', '外链播放失败：$e');
      return LaunchResult.failed;
    }
  }

  /// Android 起不了进程：交给 MainActivity，用 Intent.ACTION_VIEW + FileProvider 分派。
  Future<LaunchResult> _openOnAndroid(String path) async {
    final mime = mimeTypeFor(path);
    try {
      final ok = await _openWithSystem(path, mime);
      if (!ok) {
        logWarn('Launch', '没有应用能打开 $mime：$path');
        return LaunchResult.failed;
      }
      logInfo('Launch', '已交给系统播放器（$mime）：$path');
      return LaunchResult.ok;
    } catch (e) {
      logWarn('Launch', '外链播放失败：$e');
      return LaunchResult.failed;
    }
  }
}
