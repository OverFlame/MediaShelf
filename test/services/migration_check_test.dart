import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mediashelf/services/migration_check.dart';
import 'package:mediashelf/services/migration_service.dart';

import 'migration_fixtures.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String srcA;
  late String srcB;
  late String dst;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mediashelf_check');
    srcA = '${dir.path}/audioshelf.db';
    srcB = '${dir.path}/pv2.db';
    dst = '${dir.path}/mediashelf.db';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> migrate() async {
    final a = await openOldDb(srcA, audioShelfTables);
    await seedAudioShelf(a);
    await a.close();
    final b = await openOldDb(srcB, pictureViewerTables);
    await seedPictureViewer(b);
    await b.close();
    await MigrationService(factory: databaseFactoryFfi, backupOldDbs: false)
        .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);
  }

  Future<CheckReport> check() => MigrationChecker(factory: databaseFactoryFfi)
      .run(srcAudioDb: srcA, srcImageDb: srcB, dstDb: dst);

  List<String> failedNames(CheckReport report) => <String>[
        for (final item in report.items)
          if (!item.passed) item.name,
      ];

  test('迁移后五项校验全过', () async {
    await migrate();

    final report = await check();

    expect(report.items.length, 5);
    expect(report.passed, isTrue, reason: report.summary);
    expect(failedNames(report), isEmpty);
  });

  test('目标库少一行 media 时 ①②③ 报失败，④⑤ 仍过', () async {
    await migrate();
    final db = await databaseFactoryFfi.openDatabase(dst);
    await db.delete('media',
        where: 'path = ?', whereArgs: <Object?>['/m/画集/第1话/001.jpg']);
    await db.close();

    final report = await check();

    expect(report.passed, isFalse);
    expect(failedNames(report).length, 3);
    expect(failedNames(report)[0], contains('①'));
    expect(failedNames(report)[1], contains('②'));
    expect(failedNames(report)[2], contains('③'));
    expect(report.summary, contains('目标缺'));
  });

  test('media_type 与扩展名不符时只有 ④ 报失败', () async {
    await migrate();
    final db = await databaseFactoryFfi.openDatabase(dst);
    await db.update('media', <String, Object?>{'media_type': 'video'},
        where: 'path = ?', whereArgs: <Object?>['/m/画集/第1话/001.jpg']);
    await db.close();

    final report = await check();

    expect(report.passed, isFalse);
    expect(failedNames(report).length, 1);
    expect(failedNames(report).single, contains('④'));
    expect(report.summary, contains('001.jpg'));
  });

  test('目标库不存在时直接报失败', () async {
    await migrate();
    await File(dst).delete();

    final report = await check();

    expect(report.passed, isFalse);
    expect(report.items.single.name, '目标库存在');
  });
}
