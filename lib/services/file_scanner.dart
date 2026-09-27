import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/log_util.dart';

/// 支持的音频格式
const audioExtensions = {'.mp3', '.wav'};

/// 支持的字幕格式
const subtitleExtensions = {'.vtt', '.srt', '.lrc'};

bool isAudioFile(String path) {
  final lower = path.toLowerCase();
  return audioExtensions.any((e) => lower.endsWith(e));
}

bool isSubtitleFile(String path) {
  final lower = path.toLowerCase();
  return subtitleExtensions.any((e) => lower.endsWith(e));
}

/// 扫描结果
class ScanResult {
  final List<String> audioPaths;
  final Map<String, String> subtitleByAudio;
  final List<String> coverFiles;

  ScanResult({
    required this.audioPaths,
    required this.subtitleByAudio,
    required this.coverFiles,
  });
}

/// 文件系统扫描器 — 递归遍历目录，返回音频 + 匹配的字幕 + 封面图
class FileScanner {
  /// 在调用方 isolate 上递归遍历，扫描结果直接返回。
  static Future<ScanResult> scanDirectory(String dirPath) => _scan(dirPath);

  /// 在单独 isolate 里递归遍历（报告第 25 项）。
  ///
  /// 目录树大时遍历与排序要几十毫秒到几百毫秒，留在界面 isolate 上会掉帧；
  /// [ScanResult] 只含字符串，可以跨 isolate 传回来。
  static Future<ScanResult> scanDirectoryOffThread(String dirPath) =>
      compute(_scan, dirPath, debugLabel: 'mediashelf.scan');

  /// 测试用：判断 [_scan] 是否跑在调用方 isolate 上。
  ///
  /// 每个 isolate 有自己的静态变量，扫描跑到别的 isolate 时这里的值不变。
  @visibleForTesting
  static bool debugScannedOnCallerIsolate = false;

  static Future<ScanResult> _scan(String dirPath) async {
    debugScannedOnCallerIsolate = true;
    final audio = <String>[];
    final subtitles = <String>[];
    final covers = <String>[];
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      logWarn('Scanner', 'Directory not found: $dirPath');
      return ScanResult(audioPaths: [], subtitleByAudio: {}, coverFiles: []);
    }

    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (isAudioFile(path)) {
          audio.add(path);
        } else if (isSubtitleFile(path)) {
          subtitles.add(path);
        } else if (_isCoverImage(path)) {
          covers.add(path);
        }
      }
    } catch (e) {
      // 子目录读不了（权限、被占用、遍历中消失）时，退回已经扫到的部分。
      logWarn('Scanner', '遍历中断 "$dirPath": $e');
    }

    audio.sort();
    subtitles.sort();
    covers.sort();
    final map = _matchSubtitles(audio, subtitles);
    logInfo('Scanner',
        'scanDirectory "$dirPath" → ${audio.length} audio, ${map.length} subtitles, ${covers.length} covers');
    return ScanResult(
        audioPaths: audio, subtitleByAudio: map, coverFiles: covers);
  }

  /// 为每首音频匹配同目录字幕：
  /// 1) `a.mp3` → `a.mp3.vtt` / `a.mp3.srt` / `a.mp3.lrc`（完整文件名优先）
  /// 2) `a.mp3` → `a.vtt` / `a.srt` / `a.lrc`（去扩展名）
  static Map<String, String> _matchSubtitles(
      List<String> audio, List<String> subs) {
    final result = <String, String>{};
    final subSet = subs.toSet();
    for (final a in audio) {
      final dir = p.dirname(a);
      final base = p.basenameWithoutExtension(a);
      final full = p.basename(a);
      String? found;
      for (final ext in subtitleExtensions) {
        final cand = p.join(dir, '$full$ext');
        if (subSet.contains(cand)) {
          found = cand;
          break;
        }
      }
      if (found == null) {
        for (final ext in subtitleExtensions) {
          final cand = p.join(dir, '$base$ext');
          if (subSet.contains(cand)) {
            found = cand;
            break;
          }
        }
      }
      if (found != null) result[a] = found;
    }
    return result;
  }

  static bool _isCoverImage(String path) {
    final lower = path.toLowerCase();
    const exts = {'.jpg', '.jpeg', '.png', '.webp', '.bmp'};
    if (!exts.any((e) => lower.endsWith(e))) return false;
    final base = p.basenameWithoutExtension(path).toLowerCase();
    const names = {
      'cover', 'folder', 'front', 'album', 'albumart', 'artwork', 'jacket'
    };
    return names.contains(base);
  }
}
