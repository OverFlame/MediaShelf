import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mediashelf/utils/file_io.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pv2_file_io');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('safeCopyFile', () {
    test('源与目标是同一路径时不动文件（迁移截断数据的回归）', () async {
      final f = File(p.join(tmp.path, 'pv2.db'));
      final payload = 'x' * 300;
      await f.writeAsString(payload);

      await safeCopyFile(f.path, f.path);

      expect(await f.length(), 300);
      expect(await f.readAsString(), payload);
    });

    test('源与目标写法不同但指向同一位置时也不动文件', () async {
      final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
      final f = File(p.join(sub.path, 'pv2.db'));
      await f.writeAsString('y' * 128);

      await safeCopyFile(f.path, p.join(sub.path, '.', 'pv2.db'));

      expect(await f.length(), 128);
    });

    test('正常复制并覆盖已有目标', () async {
      final src = File(p.join(tmp.path, 'a.txt'))
        ..writeAsStringSync('hello');
      final dst = File(p.join(tmp.path, 'b.txt'))..writeAsStringSync('old');

      await safeCopyFile(src.path, dst.path);

      expect(dst.readAsStringSync(), 'hello');
      expect(src.readAsStringSync(), 'hello');
    });

    test('目标父目录不存在时自动创建', () async {
      final src = File(p.join(tmp.path, 'a.txt'))
        ..writeAsStringSync('hello');
      final dstPath = p.join(tmp.path, 'deep', 'nested', 'b.txt');

      await safeCopyFile(src.path, dstPath);

      expect(File(dstPath).readAsStringSync(), 'hello');
    });

    test('源不存在时静默返回且不创建目标', () async {
      final dstPath = p.join(tmp.path, 'nope.txt');

      await safeCopyFile(p.join(tmp.path, 'missing.txt'), dstPath);

      expect(File(dstPath).existsSync(), isFalse);
    });

    test('复制结束后不残留 .migrating 临时文件', () async {
      final src = File(p.join(tmp.path, 'a.txt'))
        ..writeAsStringSync('hello');

      await safeCopyFile(src.path, p.join(tmp.path, 'b.txt'));

      expect(File(p.join(tmp.path, 'b.txt.migrating')).existsSync(), isFalse);
    });
  });

  group('AtomicFileWriter', () {
    test('并发 40 次写入后内容是完整的最后一次', () async {
      final path = p.join(tmp.path, 'settings.json');
      final writer = AtomicFileWriter(path);

      final futures = <Future<void>>[
        for (var i = 0; i < 40; i++) writer.write(jsonEncode({'i': i})),
      ];
      await Future.wait(futures);

      expect(jsonDecode(await File(path).readAsString()), {'i': 39});
    });

    test('留下 .bak 备份且不残留 .tmp', () async {
      final path = p.join(tmp.path, 'settings.json');
      final writer = AtomicFileWriter(path);

      await writer.write('{"a":1}');
      await writer.write('{"a":2}');

      expect(jsonDecode(await File(path).readAsString()), {'a': 2});
      expect(jsonDecode(await File('$path.bak').readAsString()), {'a': 1});
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('单次写入失败抛给调用方，之后的写入仍然可用', () async {
      final path = p.join(tmp.path, 'settings.json');
      // 用目录占住 .tmp 的名字，制造一次必然失败
      Directory('$path.tmp').createSync();
      final writer = AtomicFileWriter(path);

      await expectLater(
        writer.write('{"a":1}'),
        throwsA(isA<FileSystemException>()),
      );

      await Directory('$path.tmp').delete();
      await writer.write('{"a":2}');
      expect(jsonDecode(await File(path).readAsString()), {'a': 2});
    });
  });
}
