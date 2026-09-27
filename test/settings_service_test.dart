import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mediashelf/services/data_dir_service.dart';
import 'package:mediashelf/services/settings_service.dart';

/// 把 getApplicationSupportDirectory() 指到临时目录。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File settingsFile;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audioshelf_settings');
    PathProviderPlatform.instance =
        _FakePathProvider(p.join(tmp.path, 'support'));
    DataDirService.instance.resetCache();
    SettingsService.instance.resetForTest();
    // DataDirService.defaultDir() = <applicationSupport>/AudioShelf
    settingsFile =
        File(p.join(tmp.path, 'support', 'AudioShelf', 'settings.json'));
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('并发保存：文件始终是完整 JSON，值是最新的，不留临时文件', () async {
    final s = SettingsService.instance;

    // 一次性发起多次保存，模拟「同时改主题与排序」。
    await Future.wait(<Future<void>>[
      s.setSortKey('title'),
      s.setSortDescending(true),
      s.setThemeMode(ThemeMode.light),
      s.setCoverCacheLimitMB(128),
      s.addExpression('artist:周杰伦'),
      s.setSortKey('added_at'),
    ]);

    final json = jsonDecode(await settingsFile.readAsString())
        as Map<String, dynamic>;
    expect(json['sort_key'], 'added_at');
    expect(json['sort_desc'], isTrue);
    expect(json['theme_mode'], 'light');
    expect(json['cover_cache_mb'], 128);
    expect(json['expr_history'], ['artist:周杰伦']);

    final leftovers = settingsFile.parent
        .listSync()
        .map((e) => p.basename(e.path))
        .where((n) => n.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty, reason: '临时文件必须被改名消费掉');
  });

  test('保存不就地截断旧文件：先写临时文件再改名', () async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      return; // 硬链接校验只在 POSIX 上有意义
    }
    final s = SettingsService.instance;
    await s.setSortKey('first');
    expect(settingsFile.existsSync(), isTrue);

    // 硬链接指向保存前的那个 inode。改名换的是目录项，
    // 就地截断换的是 inode 内容，两者靠这个区分。
    final link = p.join(tmp.path, 'before.link');
    final ln = await Process.run('ln', [settingsFile.path, link]);
    expect(ln.exitCode, 0, reason: 'ln 失败: ${ln.stderr}');

    await s.setSortKey('second');

    expect(await File(link).readAsString(), contains('first'),
        reason: '旧 inode 被就地覆盖了，说明保存不是「写临时文件再改名」');
    expect(await settingsFile.readAsString(), contains('second'));
  });

  test('重新 init 能读回保存的值', () async {
    final s = SettingsService.instance;
    await s.setSortKey('duration');
    await s.setSortDescending(true);
    await s.addExpression('tag:live');

    s.resetForTest(); // 丢掉内存状态，模拟重启
    await s.init();

    expect(s.sortKey, 'duration');
    expect(s.sortDescending, isTrue);
    expect(s.expressionHistory, ['tag:live']);
  });
}
