import 'dart:io';

import '../utils/log_util.dart';

/// 外链播放的结果
enum LaunchResult { ok, unsupportedPlatform, failed }

/// 把文件或播放列表交给系统默认播放器（BUILD_GUIDE 第 9.4 与 24.2 节）
///
/// 只起进程，不链接任何播放器库，因此不引入许可证风险。
class VideoLauncher {
  VideoLauncher({
    Future<Process> Function(String, List<String>)? start,
    String? os,
  })  : _start = start ?? Process.start,
        _os = os ?? detectOs();

  final Future<Process> Function(String executable, List<String> arguments)
      _start;
  final String _os;

  static String detectOs() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  /// 平台分派表。认不出平台时返回 null。
  static (String, List<String>)? commandFor(String path, String os) =>
      switch (os) {
        'windows' => ('cmd', <String>['/c', 'start', '', path]),
        'linux' => ('xdg-open', <String>[path]),
        _ => null,
      };

  Future<LaunchResult> open(String path) async {
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
}
