import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/log_util.dart';
import 'media_rules.dart';

// 扩展名白名单与类型判定都定义在 media_rules.dart，这里转出去，
// 老调用方（`import '../services/file_scanner.dart'`）不用改。
export 'media_rules.dart';

/// 扫描结果
class ScanResult {
  final List<String> audioPaths;

  /// 每首音频对应的字幕列表，按匹配优先级排好（BUILD_GUIDE 第 23.5 节）
  final Map<String, List<String>> subtitleByAudio;
  final List<String> coverFiles;

  ScanResult({
    required this.audioPaths,
    required this.subtitleByAudio,
    required this.coverFiles,
  });
}

/// 语言后缀词表，参与字幕匹配（BUILD_GUIDE 第 23.5 节）
///
/// 组合写法一并认：`zh-CN`、`简日`、`CHS&JPN`。比较前统一转小写。
const subtitleLanguageTokens = {
  'zh', 'chs', 'cht', 'chi',
  'eng', 'jpn', 'jp', 'kor',
  'sc', 'tc',
  '简', '繁', '日', '英',
};

/// 地区标记：只允许接在中文系语言标记后面（`zh-CN`、`zh-TW`）
const subtitleRegionTokens = {
  'cn', 'tw', 'hk', 'sg', 'mo', 'hans', 'hant',
};

/// 中文系语言标记，地区标记只能跟在这几个后面
const _chineseLanguageTokens = {
  'zh', 'chs', 'cht', 'chi', 'sc', 'tc', '简', '繁',
};

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

  /// 为每首音频匹配同目录字幕，一个音频可以挂多条（BUILD_GUIDE 第 23.5 节）。
  ///
  /// 优先级从高到低：
  /// 1. `a.mp3.vtt`（完整文件名）
  /// 2. `a.mp3.zh.srt`（完整文件名 + 语言后缀）
  /// 3. `a.vtt`（去扩展名）
  /// 4. `a.zh-CN.srt`（去扩展名 + 语言后缀）
  ///
  /// 同档内按路径字典序，保证结果稳定。只认能解析的格式，
  /// 占位格式（.ass 等）只入库，不参与匹配。
  static Map<String, List<String>> _matchSubtitles(
      List<String> audio, List<String> subs) {
    final result = <String, List<String>>{};
    for (final a in audio) {
      final dir = p.dirname(a);
      final base = p.basenameWithoutExtension(a);
      final full = p.basename(a);
      final ranked = <(int, String)>[];
      for (final s in subs) {
        if (p.dirname(s) != dir) continue;
        final name = p.basename(s);
        final ext = p.extension(name).toLowerCase();
        if (!subtitleExtensions.contains(ext)) continue;
        final stem = name.substring(0, name.length - ext.length);
        final rank = _matchRank(stem, full, base);
        if (rank == null) continue;
        ranked.add((rank, s));
      }
      if (ranked.isEmpty) continue;
      ranked.sort((x, y) {
        final byRank = x.$1.compareTo(y.$1);
        return byRank != 0 ? byRank : x.$2.compareTo(y.$2);
      });
      result[a] = [for (final r in ranked) r.$2];
    }
    return result;
  }

  /// 判断字幕主干与音频名的匹配档位，认不出返回 null。
  ///
  /// [stem] 是去掉扩展名后的字幕文件名，比如 `a.mp3.zh`。
  static int? _matchRank(String stem, String full, String base) {
    if (stem == full) return 0;
    if (stem == base) return 2;
    if (stem.startsWith('$full.')) {
      final tag = _languageTag(stem.substring(full.length + 1));
      if (tag != null) return 1;
    }
    if (stem.startsWith('$base.')) {
      final tag = _languageTag(stem.substring(base.length + 1));
      if (tag != null) return 3;
    }
    return null;
  }

  /// 语言后缀判定：`zh`、`zh-cn`、`简日`、`chs&jpn` 都算，其余不算。
  ///
  /// 规则（BUILD_GUIDE 第 23.5 节）：
  /// - 用 `-` 或 `&` 切段，每段必须是语言词或地区词；
  /// - 地区词（cn/tw/hk 等）只接在中文系语言词后面，`zh-CN` 才成立；
  /// - 连写的汉字标记逐个字符看，`简日` 成立，`英美` 不成立；
  /// - 至少要认出一个语言词，纯地区词后缀不算。
  static String? _languageTag(String suffix) {
    if (suffix.isEmpty) return null;
    final lower = suffix.toLowerCase();
    var seenLanguage = false;
    String? previous;
    for (final token in lower.split(RegExp(r'[-&]'))) {
      if (token.isEmpty) return null;
      if (subtitleLanguageTokens.contains(token)) {
        seenLanguage = true;
        previous = token;
        continue;
      }
      if (subtitleRegionTokens.contains(token) &&
          previous != null &&
          _chineseLanguageTokens.contains(previous)) {
        continue;
      }
      // 连写汉字标记：「简日」拆成「简」「日」两个词
      final chars = token.runes.map(String.fromCharCode).toList();
      if (chars.isNotEmpty &&
          chars.every(subtitleLanguageTokens.contains)) {
        seenLanguage = true;
        previous = token;
        continue;
      }
      return null;
    }
    return seenLanguage ? lower : null;
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
