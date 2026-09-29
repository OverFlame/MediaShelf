import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mediashelf/services/playlist_writer.dart';

void main() {
  test('m3u8 行序正确，时长取整，缺时长写 -1', () {
    final text = PlaylistWriter.buildM3u8([
      PlaylistEntry(
          path: '/m/剧集/第1话.mp4', title: '第1话', durationMs: 1454999),
      PlaylistEntry(path: '/m/剧集/第2话.mp4', title: '第2话'),
    ]);
    final lines = text.trimRight().split('\n');

    expect(lines.length, 5);
    expect(lines[0], '#EXTM3U');
    expect(lines[1], '#EXTINF:1455,第1话');
    expect(lines[2], '/m/剧集/第1话.mp4');
    expect(lines[3], '#EXTINF:-1,第2话');
    expect(lines[4], '/m/剧集/第2话.mp4');
  });

  test('标题为空或只有空白时回落到文件名', () {
    final text = PlaylistWriter.buildM3u8([
      PlaylistEntry(path: '/m/第3话.mp4', title: '   '),
      PlaylistEntry(path: '/m/第4话.mp4'),
    ]);
    final lines = text.trimRight().split('\n');

    expect(lines[1], '#EXTINF:-1,第3话.mp4');
    expect(lines[3], '#EXTINF:-1,第4话.mp4');
  });

  test('写文件时建目录，名字里的非法字符换掉', () async {
    final tmp = await Directory.systemTemp.createTemp('mediashelf_playlist');
    addTearDown(() => tmp.delete(recursive: true));
    final writer = PlaylistWriter(outputDir: p.join(tmp.path, 'playlist'));

    final file = await writer.write(
      name: '剧集:第1季?',
      entries: [PlaylistEntry(path: '/m/a.mp4', title: 'a')],
    );

    expect(file, endsWith(p.join('playlist', '剧集_第1季_.m3u8')));
    final written = File(file);
    expect(written.existsSync(), isTrue);
    expect(await written.readAsString(), contains('/m/a.mp4'));
  });

  test('名字为空时用 playlist 兜底', () async {
    final tmp = await Directory.systemTemp.createTemp('mediashelf_playlist');
    addTearDown(() => tmp.delete(recursive: true));
    final writer = PlaylistWriter(outputDir: tmp.path);

    final file = await writer.write(name: '  ', entries: []);

    expect(file, endsWith('playlist.m3u8'));
    expect(await File(file).readAsString(), '#EXTM3U\n');
  });
}
