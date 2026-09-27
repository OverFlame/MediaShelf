import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mediashelf/services/file_scanner.dart';

void main() {
  test('扫描目录：识别音频并匹配字幕 + 封面', () async {
    final dir = await Directory.systemTemp.createTemp('audioshelf_scan');

    File('${dir.path}/a.mp3').writeAsStringSync('fake');
    File('${dir.path}/b.wav').writeAsStringSync('fake');
    File('${dir.path}/a.mp3.vtt').writeAsStringSync('WEBVTT\n');
    File('${dir.path}/b.vtt').writeAsStringSync('...\n');
    File('${dir.path}/c.srt').writeAsStringSync('...\n'); // 无对应音频
    File('${dir.path}/cover.jpg').writeAsStringSync('fake-image');
    File('${dir.path}/readme.txt').writeAsStringSync('not audio');

    final scan = await FileScanner.scanDirectory(dir.path);

    expect(scan.audioPaths.length, 2);
    // 完整文件名优先
    expect(scan.subtitleByAudio['${dir.path}/a.mp3'], '${dir.path}/a.mp3.vtt');
    // 去扩展名匹配
    expect(scan.subtitleByAudio['${dir.path}/b.wav'], '${dir.path}/b.vtt');
    // c.srt 无对应音频，不应出现在映射里
    expect(scan.subtitleByAudio.values.contains('${dir.path}/c.srt'), isFalse);
    expect(scan.coverFiles.length, 1);

    await dir.delete(recursive: true);
  });

  test('优先完整文件名而非去扩展名', () async {
    final dir = await Directory.systemTemp.createTemp('audioshelf_scan2');
    File('${dir.path}/a.mp3').writeAsStringSync('fake');
    File('${dir.path}/a.mp3.vtt').writeAsStringSync('full');
    File('${dir.path}/a.vtt').writeAsStringSync('base');

    final scan = await FileScanner.scanDirectory(dir.path);
    expect(scan.subtitleByAudio['${dir.path}/a.mp3'], '${dir.path}/a.mp3.vtt');

    await dir.delete(recursive: true);
  });
}
