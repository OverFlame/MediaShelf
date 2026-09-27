import 'package:flutter_test/flutter_test.dart';

import 'package:mediashelf/services/subtitle_parser.dart';

void main() {
  group('SubtitleParser', () {
    test('VTT', () {
      const vtt = '''WEBVTT

00:00:01.000 --> 00:00:04.000
你好世界

00:00:04.000 --> 00:00:07.000
第二句
''';
      final lines = SubtitleParser.parse(vtt, '.vtt');
      expect(lines.length, 2);
      expect(lines[0].startMs, 1000);
      expect(lines[0].endMs, 4000);
      expect(lines[0].text, '你好世界');
      expect(lines[1].text, '第二句');
    });

    test('VTT 带 inline 标签', () {
      const vtt = '''WEBVTT

00:00:01.000 --> 00:00:03.000
<i>斜体</i> 普通

''';
      final lines = SubtitleParser.parse(vtt, '.vtt');
      expect(lines.single.text, '斜体 普通');
    });

    test('SRT', () {
      const srt = '''1
00:00:01,000 --> 00:00:04,000
第一行

2
00:00:04,000 --> 00:00:08,000
第二行
多行文本
''';
      final lines = SubtitleParser.parse(srt, '.srt');
      expect(lines.length, 2);
      expect(lines[0].startMs, 1000);
      expect(lines[1].text, '第二行 多行文本');
    });

    test('LRC', () {
      const lrc = '''[ti:测试]
[00:01.00]第一句
[00:03.50]第二句
''';
      final lines = SubtitleParser.parse(lrc, '.lrc');
      expect(lines.length, 2);
      expect(lines[0].startMs, 1000);
      expect(lines[1].startMs, 3500);
      // endMs 取下一句开始
      expect(lines[0].endMs, 3500);
    });

    test('LRC 多个时间戳', () {
      const lrc = '[00:01.00][00:10.00]重复句';
      final lines = SubtitleParser.parse(lrc, '.lrc');
      expect(lines.length, 2);
      expect(lines[0].startMs, 1000);
      expect(lines[1].startMs, 10000);
    });
  });
}
