import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mediashelf/services/video_launcher.dart';

/// 只用来占位，测试不读它的任何成员
class _FakeProcess implements Process {
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('平台分派表：Windows 用 start，Linux 用 xdg-open，其他不执行', () {
    final win = VideoLauncher.commandFor('/m/列表.m3u8', 'windows');
    expect(win, isNotNull);
    expect(win!.$1, 'cmd');
    expect(win.$2, ['/c', 'start', '', '/m/列表.m3u8']);

    final linux = VideoLauncher.commandFor('/m/列表.m3u8', 'linux');
    expect(linux, isNotNull);
    expect(linux!.$1, 'xdg-open');
    expect(linux.$2, ['/m/列表.m3u8']);

    expect(VideoLauncher.commandFor('/m/列表.m3u8', 'other'), isNull);
  });

  test('Linux 下把路径交给 xdg-open 并返回 ok', () async {
    final calls = <List<String>>[];
    final launcher = VideoLauncher(
      os: 'linux',
      start: (exe, args) async {
        calls.add([exe, ...args]);
        return _FakeProcess();
      },
    );

    expect(await launcher.open('/m/播放 列表.m3u8'), LaunchResult.ok);
    expect(calls, [
      ['xdg-open', '/m/播放 列表.m3u8']
    ]);
  });

  test('不支持的平台不执行进程', () async {
    var called = false;
    final launcher = VideoLauncher(
      os: 'other',
      start: (exe, args) async {
        called = true;
        return _FakeProcess();
      },
    );

    expect(await launcher.open('/m/a.m3u8'), LaunchResult.unsupportedPlatform);
    expect(called, isFalse);
  });

  test('进程起不来时返回 failed', () async {
    final launcher = VideoLauncher(
      os: 'linux',
      start: (exe, args) async => throw ProcessException('xdg-open', const []),
    );

    expect(await launcher.open('/m/a.m3u8'), LaunchResult.failed);
  });

  test('detectOs 只认 Windows 与 Linux', () {
    expect(VideoLauncher.detectOs(), anyOf('windows', 'linux', 'other'));
  });
}
