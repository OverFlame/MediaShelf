import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 单行歌词/字幕
class LyricLine {
  final int startMs;
  final int endMs;
  final String text;

  const LyricLine({
    required this.startMs,
    required this.endMs,
    required this.text,
  });

  bool contains(int ms) => ms >= startMs && ms < endMs;
}

/// 字幕解析器：VTT / SRT / LRC → List<LyricLine>
class SubtitleParser {
  SubtitleParser._();

  /// 根据路径读取并解析字幕文件
  static List<LyricLine> parseFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return [];
      String content;
      try {
        content = file.readAsStringSync(encoding: const Utf8Codec());
      } catch (_) {
        content = file.readAsStringSync(encoding: latin1);
      }
      return parse(content, p.extension(path).toLowerCase());
    } catch (_) {
      return [];
    }
  }

  static List<LyricLine> parse(String content, String ext) {
    switch (ext) {
      case '.vtt':
        return _parseVtt(content);
      case '.srt':
        return _parseSrt(content);
      case '.lrc':
        return _parseLrc(content);
      default:
        return [];
    }
  }

  // ── VTT ──
  static List<LyricLine> _parseVtt(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final result = <LyricLine>[];
    int? startMs;
    int? endMs;
    final buf = <String>[];
    bool inNote = false;

    void flush() {
      if (startMs != null && endMs != null && buf.isNotEmpty) {
        result.add(LyricLine(
            startMs: startMs!, endMs: endMs!, text: _clean(buf.join(' '))));
      }
      startMs = null;
      endMs = null;
      buf.clear();
    }

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) {
        inNote = false;
        flush();
        continue;
      }
      if (line.startsWith('WEBVTT') ||
          line.startsWith('STYLE') ||
          line.startsWith('REGION')) {
        continue;
      }
      if (line.startsWith('NOTE')) {
        inNote = true;
        continue;
      }
      if (inNote) continue;

      final arrow = line.indexOf('-->');
      if (arrow > 0) {
        flush();
        final before = line.substring(0, arrow).trim();
        final afterRaw = line.substring(arrow + 3).trim();
        // 时间戳后可能跟随 cue settings（position / align 等）
        final after = afterRaw.split(RegExp(r'\s+')).first;
        startMs = _parseTimestamp(before);
        endMs = _parseTimestamp(after);
      } else {
        buf.add(raw);
      }
    }
    flush();
    return result;
  }

  // ── SRT ──
  static List<LyricLine> _parseSrt(String content) {
    final blocks = content.split(RegExp(r'\r?\n\s*\r?\n'));
    final result = <LyricLine>[];
    for (final block in blocks) {
      final lines = block.split(RegExp(r'\r?\n'));
      int? timingIndex;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timingIndex = i;
          break;
        }
      }
      if (timingIndex == null) continue;
      final arrow = lines[timingIndex].indexOf('-->');
      final startMs = _parseTimestamp(lines[timingIndex].substring(0, arrow).trim());
      final endMs = _parseTimestamp(lines[timingIndex].substring(arrow + 3).trim());
      final text = lines.sublist(timingIndex + 1).join(' ').trim();
      if (startMs != null && endMs != null && text.isNotEmpty) {
        result.add(
            LyricLine(startMs: startMs, endMs: endMs, text: _clean(text)));
      }
    }
    return result;
  }

  // ── LRC ──
  static List<LyricLine> _parseLrc(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final tagRe = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
    final raw = <LyricLine>[];

    for (final line in lines) {
      final matches = tagRe.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.replaceAll(tagRe, '').trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final fracRaw = m.group(3);
        int ms;
        if (fracRaw == null) {
          ms = (min * 60 + sec) * 1000;
        } else {
          // 2 位为厘秒，3 位为毫秒
          final frac = int.parse(fracRaw);
          final fracMs = fracRaw.length <= 2 ? frac * 10 : frac;
          ms = (min * 60 + sec) * 1000 + fracMs;
        }
        raw.add(LyricLine(startMs: ms, endMs: 0, text: _clean(text)));
      }
    }

    raw.sort((a, b) => a.startMs.compareTo(b.startMs));
    final result = <LyricLine>[];
    for (int i = 0; i < raw.length; i++) {
      final end =
          (i + 1 < raw.length) ? raw[i + 1].startMs : raw[i].startMs + 5000;
      result.add(LyricLine(
          startMs: raw[i].startMs, endMs: end, text: raw[i].text));
    }
    return result;
  }

  /// 解析时间戳：HH:MM:SS.mmm / MM:SS.mmm / SS.mmm（. 或 , 作小数分隔）
  static int? _parseTimestamp(String s) {
    final t = s.trim().replaceAll(',', '.');
    final parts = t.split(':');
    if (parts.isEmpty || parts.length > 3) return null;
    double seconds;
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final sec = double.tryParse(parts[2]);
      if (h == null || m == null || sec == null) return null;
      seconds = h * 3600 + m * 60 + sec;
    } else if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final sec = double.tryParse(parts[1]);
      if (m == null || sec == null) return null;
      seconds = m * 60 + sec;
    } else {
      final sec = double.tryParse(parts[0]);
      if (sec == null) return null;
      seconds = sec;
    }
    return (seconds * 1000).round();
  }

  /// 清理字幕文本：去除 HTML / ASS 内联标签与常见实体
  static String _clean(String s) {
    var t = s;
    t = t.replaceAll(RegExp(r'<[^>]*>'), '');
    t = t.replaceAll(RegExp(r'\{[^}]*\}'), '');
    t = t
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"');
    return t.trim();
  }
}
