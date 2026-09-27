import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:mediashelf/db/tables.dart';
import 'package:mediashelf/db/work_dao.dart';

/// v2 时期线上跑的 DDL：folders.work_id 没有 ON DELETE 动作。
/// 迁移用例必须从真实旧结构出发，不能用新 DDL 假装旧库。
const _v2Statements = <String>[
  '''
  CREATE TABLE works (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    NOT NULL,
    cover_path  TEXT,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE folders (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    name    TEXT    NOT NULL,
    parent  INTEGER REFERENCES folders(id),
    work_id INTEGER REFERENCES works(id),
    UNIQUE(name, parent)
  )
  ''',
  '''
  CREATE TABLE folder_paths (
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    path      TEXT    NOT NULL,
    recursive INTEGER NOT NULL DEFAULT 0
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_folder_paths_path ON folder_paths(path)',
  '''
  CREATE TABLE tags (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    namespace  TEXT    NOT NULL DEFAULT 'general',
    name       TEXT    NOT NULL,
    color      TEXT    NOT NULL DEFAULT '#cba6f7',
    UNIQUE(namespace, name)
  )
  ''',
  '''
  CREATE TABLE folder_tags (
    folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
    PRIMARY KEY (folder_id, tag_id)
  )
  ''',
  'CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id)',
];

Future<void> _fkOn(Database db) async {
  await db.execute('PRAGMA foreign_keys=ON');
}

OpenDatabaseOptions _options({int? version, Future<void> Function(Database)? onCreate}) {
  return OpenDatabaseOptions(
    version: version,
    onConfigure: _fkOn,
    onCreate: (db, v) async => onCreate?.call(db),
    onUpgrade: (db, oldV, newV) async {
      for (int v = oldV + 1; v <= newV; v++) {
        for (final sql in Tables.migrations[v] ?? const <String>[]) {
          await db.execute(sql);
        }
      }
    },
  );
}

void main() {
  sqfliteFfiInit();

  test('v2 -> v4 迁移重建 folders 并给 folder_paths 加唯一约束，不丢数据', () async {
    final dir = await Directory.systemTemp.createTemp('audioshelf_migrate');
    final path = '${dir.path}/migrate.db';

    // ── 1. 造 v2 库并塞入真实数据 ──
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: _options(version: 2, onCreate: (db) async {
        for (final s in _v2Statements) {
          await db.execute(s);
        }
      }),
    );
    final workId = await v2.insert(
        'works', {'name': '专辑', 'sort_order': 0, 'created_at': 1});
    final rootId = await v2
        .insert('folders', {'name': '专辑', 'parent': null, 'work_id': workId});
    final subId = await v2
        .insert('folders', {'name': 'mp3', 'parent': rootId, 'work_id': workId});
    await v2.insert(
        'folder_paths', {'folder_id': rootId, 'path': '/m/x', 'recursive': 0});
    // v2 的 folder_paths 没有唯一约束，线上确实可能存在同一个 (folder_id, path) 重复多行
    await v2.insert(
        'folder_paths', {'folder_id': rootId, 'path': '/m/x', 'recursive': 1});
    await v2.insert(
        'folder_paths', {'folder_id': subId, 'path': '/m/x/mp3', 'recursive': 1});
    final tagId =
        await v2.insert('tags', {'namespace': 'general', 'name': '纯音乐'});
    await v2.insert('folder_tags', {'folder_id': subId, 'tag_id': tagId});
    await v2.close();

    // ── 2. 按生产路径升到 v3 ──
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: _options(version: Tables.version, onCreate: (db) async {
        for (final s in Tables.createStatements) {
          await db.execute(s);
        }
      }),
    );

    // ── 3. 结构：外键动作改成 SET NULL，且自引用已改写 ──
    final ddl = (await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type='table' AND name='folders'",
    )).first['sql'] as String;
    expect(ddl, contains('ON DELETE SET NULL'));
    expect(ddl, isNot(contains('folders_new')),
        reason: 'ALTER TABLE RENAME 后自引用必须指回 folders，否则外键悬空');

    // ── 4. 数据一条没丢，重复的 folder_paths 被去重（v2 里是 3 行）──
    expect((await db.query('folders')).length, 2);
    expect((await db.query('folder_paths')).length, 2,
        reason: 'v4 应把同一个 (folder_id, path) 的重复行去重');
    expect((await db.query('folder_tags')).length, 1);
    final sub =
        (await db.query('folders', where: 'id = ?', whereArgs: [subId])).single;
    expect(sub['parent'], rootId);
    expect(sub['work_id'], workId);

    // ── 5. 索引与临时表 ──
    final idx = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='folder_paths'",
    );
    expect(idx.map((r) => r['name']), contains('idx_folder_paths_path'));
    expect(idx.map((r) => r['name']), contains('idx_folder_paths_unique'),
        reason: 'v4 的唯一索引必须建上，否则 addPath 的 INSERT OR IGNORE 不生效');
    final rootPaths = await db
        .query('folder_paths', where: 'folder_id = ?', whereArgs: [rootId]);
    expect(rootPaths.length, 1, reason: '同文件夹同路径只应留一行');

    // 再挂一次同样的路径：被唯一索引挡掉，不新增行
    final dup = await db.insert(
        'folder_paths', {'folder_id': rootId, 'path': '/m/x', 'recursive': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    expect(dup, 0, reason: 'INSERT OR IGNORE 应返回 0，而不是再插一行');
    expect(
        (await db
                .query('folder_paths', where: 'folder_id = ?', whereArgs: [rootId]))
            .length,
        1);

    // 另一个文件夹挂同一路径仍然允许
    final other = await db.insert(
        'folder_paths', {'folder_id': subId, 'path': '/m/x', 'recursive': 0},
        conflictAlgorithm: ConflictAlgorithm.ignore);
    expect(other, greaterThan(0), reason: '唯一约束只约束 (folder_id, path) 组合');
    expect(
        await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE name IN "
          "('_folder_paths_backup','_folder_tags_backup')",
        ),
        isEmpty);

    // ── 6. 自引用外键仍可用：能挂新子文件夹 ──
    final newSub = await db
        .insert('folders', {'name': 'flac', 'parent': rootId, 'work_id': workId});
    expect(newSub, greaterThan(0));

    // ── 7. 外键动作生效：删作品后文件夹保留、归属置空 ──
    await db.delete('works', where: 'id = ?', whereArgs: [workId]);
    final after = await db.query('folders');
    expect(after.length, 3);
    for (final row in after) {
      expect(row['work_id'], isNull);
    }

    await db.close();
    await dir.delete(recursive: true);
  });

  test('WorkDao.delete 在一个事务里摘归属并删作品', () async {
    final dir = await Directory.systemTemp.createTemp('audioshelf_delete');
    final db = await databaseFactoryFfi.openDatabase(
      '${dir.path}/delete.db',
      options: _options(version: Tables.version, onCreate: (db) async {
        for (final s in Tables.createStatements) {
          await db.execute(s);
        }
      }),
    );

    final dao = WorkDao(db);
    final work = await dao.create('待删专辑');
    await db.insert('folders',
        {'name': '根', 'parent': null, 'work_id': work.id});
    await db.insert('folders', {'name': '子', 'parent': 1, 'work_id': work.id});

    await dao.delete(work.id!);

    expect(await dao.getById(work.id!), isNull, reason: '作品应已删除');
    final folders = await db.query('folders');
    expect(folders.length, 2, reason: '文件夹不该被删，只该摘归属');
    for (final f in folders) {
      expect(f['work_id'], isNull);
    }

    await db.close();
    await dir.delete(recursive: true);
  });
}
