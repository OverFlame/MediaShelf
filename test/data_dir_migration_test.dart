import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:mediashelf/services/data_dir_service.dart';

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
  late String supportRoot;
  late String defaultDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audioshelf_datadir');
    supportRoot = p.join(tmp.path, 'support');
    defaultDir = p.join(supportRoot, 'AudioShelf');
    PathProviderPlatform.instance = _FakePathProvider(supportRoot);
    DataDirService.instance.resetCache();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> seed(String dir) async {
    await Directory(p.join(dir, 'covers')).create(recursive: true);
    await File(p.join(dir, 'audioshelf.db')).writeAsString('DB-CONTENT');
    await File(p.join(dir, 'settings.json')).writeAsString('{"theme":"dark"}');
    await File(p.join(dir, 'covers', 'track_1.jpg')).writeAsString('IMG');
  }

  String pointerPath() => p.join(defaultDir, '.datadir');

  test('迁移成功：文件到位、指针指向新目录、缓存同步', () async {
    await seed(defaultDir);
    final newD = p.join(tmp.path, 'new');

    final result = await DataDirService.instance.migrateTo(newD);

    expect(result, p.normalize(newD));
    expect((await DataDirService.instance.dataDir), p.normalize(newD));
    expect(File(pointerPath()).readAsStringSync().trim(), p.normalize(newD));

    expect(File(p.join(newD, 'audioshelf.db')).readAsStringSync(), 'DB-CONTENT');
    expect(File(p.join(newD, 'settings.json')).readAsStringSync(),
        '{"theme":"dark"}');
    expect(File(p.join(newD, 'covers', 'track_1.jpg')).readAsStringSync(), 'IMG');
    expect(File('${pointerPath()}.tmp').existsSync(), isFalse,
        reason: '临时指针文件不该留下');
  });

  test('目标已有不同内容的库：抛异常，且不写指针、不改缓存', () async {
    await seed(defaultDir);
    final newD = p.join(tmp.path, 'occupied');
    await Directory(newD).create(recursive: true);
    await File(p.join(newD, 'audioshelf.db')).writeAsString('OTHER-DB');

    await expectLater(
      DataDirService.instance.migrateTo(newD),
      throwsA(isA<StateError>()),
    );

    expect(File(pointerPath()).existsSync(), isFalse,
        reason: '失败时不能留下指针文件');
    expect(await DataDirService.instance.dataDir, p.normalize(defaultDir),
        reason: '失败后仍应使用旧目录');
    expect(File(p.join(newD, 'audioshelf.db')).readAsStringSync(), 'OTHER-DB',
        reason: '已有数据不能被覆盖');
  });

  test('重复迁到同一目录：内容一致则幂等', () async {
    await seed(defaultDir);
    final newD = p.join(tmp.path, 'again');

    await DataDirService.instance.migrateTo(newD);
    // 清缓存后再迁一次，模拟重启后重跑
    DataDirService.instance.resetCache();
    final second = await DataDirService.instance.migrateTo(newD);

    expect(second, p.normalize(newD));
    expect(File(p.join(newD, 'audioshelf.db')).readAsStringSync(), 'DB-CONTENT');
  });

  test('目标即当前目录：直接返回，不做复制', () async {
    await seed(defaultDir);

    final result =
        await DataDirService.instance.migrateTo(defaultDir);

    expect(result, p.normalize(defaultDir));
    expect(File(pointerPath()).existsSync(), isFalse);
  });
}
