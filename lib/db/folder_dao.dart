import 'package:sqflite/sqflite.dart';
import '../utils/log_util.dart';

/// 虚拟文件夹
class VirtualFolder {
  final int? id;
  final String name;
  final int? parentId;
  final int? workId;

  const VirtualFolder({
    this.id,
    required this.name,
    this.parentId,
    this.workId,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'parent': parentId,
        'work_id': workId,
      };

  factory VirtualFolder.fromMap(Map<String, dynamic> map) => VirtualFolder(
        id: map['id'] as int?,
        name: map['name'] as String,
        parentId: map['parent'] as int?,
        workId: map['work_id'] as int?,
      );
}

/// 文件夹路径映射
class FolderPath {
  final int folderId;
  final String path;
  final bool recursive;

  const FolderPath({
    required this.folderId,
    required this.path,
    this.recursive = false,
  });

  Map<String, dynamic> toMap() => {
        'folder_id': folderId,
        'path': path,
        'recursive': recursive ? 1 : 0,
      };
}

class FolderDao {
  final Database _db;
  FolderDao(this._db);

  // ═══ 文件夹 CRUD ═══

  Future<VirtualFolder> create(String name,
      {int? parentId, int? workId}) async {
    final id = await _db.insert('folders', {
      'name': name,
      'parent': parentId,
      'work_id': workId,
    });
    logInfo('FolderDao',
        'Created folder: id=$id name="$name" parent=$parentId work=$workId');
    return VirtualFolder(id: id, name: name, parentId: parentId, workId: workId);
  }

  Future<List<VirtualFolder>> listRoot() async {
    final rows = await _db.query('folders',
        where: 'parent IS NULL', orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  Future<List<VirtualFolder>> listChildren(int parentId) async {
    final rows = await _db.query('folders',
        where: 'parent = ?', whereArgs: [parentId], orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  Future<List<VirtualFolder>> listAll() async {
    final rows = await _db.query('folders', orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  /// 某作品下的所有文件夹（用于作品详情）
  Future<List<VirtualFolder>> listByWork(int workId) async {
    final rows = await _db.query('folders',
        where: 'work_id = ?', whereArgs: [workId], orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  /// 某作品下的「入口文件夹」（parent 为空，即该作品的顶层文件夹）
  Future<List<VirtualFolder>> listRootsByWork(int workId) async {
    final rows = await _db.query('folders',
        where: 'work_id = ? AND parent IS NULL',
        whereArgs: [workId],
        orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  /// 未归类（work_id 为空）的顶层文件夹
  Future<List<VirtualFolder>> listUnassignedRoots() async {
    final rows = await _db.query('folders',
        where: 'work_id IS NULL AND parent IS NULL', orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  Future<VirtualFolder?> getById(int id) async {
    final rows = await _db.query('folders', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return VirtualFolder.fromMap(rows.first);
  }

  Future<int> rename(int id, String newName) async {
    return _db.update('folders', {'name': newName},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 移动文件夹到新父级（null=根级）
  Future<int> move(int id, int? newParentId) async {
    return _db.update('folders', {'parent': newParentId},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 设置文件夹所属作品（null=未归类）
  Future<int> setWork(int id, int? workId) async {
    return _db.update('folders', {'work_id': workId},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countChildren(int parentId) async {
    final count = Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT COUNT(*) FROM folders WHERE parent = ?', [parentId]));
    return count ?? 0;
  }

  /// 删除文件夹（CASCADE 清理 folder_paths；子文件夹上移为根级）
  ///
  /// 两条语句必须同一事务：中间失败会留下「子级已上移、本行还在」的树。
  Future<int> delete(int id) async {
    return _db.transaction((txn) async {
      await txn.update('folders', {'parent': null},
          where: 'parent = ?', whereArgs: [id]);
      final count = await txn.delete('folders', where: 'id = ?', whereArgs: [id]);
      logInfo('FolderDao', 'Deleted folder id=$id (affected $count row(s))');
      return count;
    });
  }

  /// 一次事务里给多个文件夹改归属，供「整棵子树换作品」使用。
  Future<void> setWorkMany(Iterable<int> ids, int? workId) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await _db.transaction((txn) async {
      for (final id in list) {
        await txn.update('folders', {'work_id': workId},
            where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// 收集某文件夹及其所有后代文件夹（BFS）
  Future<Set<int>> collectDescendants(int folderId) async {
    final result = <int>{folderId};
    final queue = <int>[folderId];
    while (queue.isNotEmpty) {
      final fid = queue.removeAt(0);
      for (final c in await listChildren(fid)) {
        if (c.id != null && result.add(c.id!)) {
          queue.add(c.id!);
        }
      }
    }
    return result;
  }

  // ═══ 路径管理 ═══

  Future<void> addPath(int folderId, String path,
      {bool recursive = false}) async {
    await _db.insert(
        'folder_paths',
        FolderPath(folderId: folderId, path: path, recursive: recursive)
            .toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removePath(int folderId, String path) async {
    await _db.delete('folder_paths',
        where: 'folder_id = ? AND path = ?', whereArgs: [folderId, path]);
  }

  Future<VirtualFolder?> getByPath(String path) async {
    // 同一个路径可能挂在多个文件夹上（migrations[4] 之前建的数据）。
    // 不给顺序时返回哪一行由 SQLite 扫描顺序决定，导入时命中的文件夹会来回跳，
    // 所以固定取 id 最小的那个。
    final rows = await _db.rawQuery('''
      SELECT f.* FROM folders f
      INNER JOIN folder_paths fp ON f.id = fp.folder_id
      WHERE fp.path = ?
      ORDER BY f.id
    ''', [path]);
    if (rows.isEmpty) return null;
    return VirtualFolder.fromMap(rows.first);
  }

  /// 按路径取文件夹；不存在就连同 path 映射一起建。整个过程在一个事务里。
  ///
  /// 原来的写法是「先 getByPath、再 create、再 addPath」三条独立语句：并发调用时
  /// 两边都查不到、都新建，同一个目录于是变成两个文件夹，各挂一条相同的 path。
  /// 已存在的记录会顺带把 parent / work 对齐到本次期望值。
  Future<VirtualFolder> ensureByPath(
    String path, {
    required String name,
    int? parentId,
    int? workId,
  }) async {
    return _db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT f.* FROM folders f
        INNER JOIN folder_paths fp ON f.id = fp.folder_id
        WHERE fp.path = ?
        ORDER BY f.id
      ''', [path]);

      if (rows.isNotEmpty) {
        final existing = VirtualFolder.fromMap(rows.first);
        final patch = <String, Object?>{};
        if (existing.parentId != parentId) patch['parent'] = parentId;
        if (existing.workId != workId) patch['work_id'] = workId;
        if (patch.isNotEmpty) {
          await txn.update('folders', patch,
              where: 'id = ?', whereArgs: [existing.id]);
        }
        return VirtualFolder(
          id: existing.id,
          name: existing.name,
          parentId: parentId,
          workId: workId,
        );
      }

      final id = await txn.insert('folders', {
        'name': name,
        'parent': parentId,
        'work_id': workId,
      });
      await txn.insert('folder_paths', {
        'folder_id': id,
        'path': path,
        'recursive': 0,
      });
      logInfo('FolderDao',
          'ensureByPath 新建文件夹 id=$id name="$name" path="$path"');
      return VirtualFolder(
          id: id, name: name, parentId: parentId, workId: workId);
    });
  }

  Future<VirtualFolder> insert({
    required String name,
    required String path,
    int? parentId,
    int? workId,
  }) async {
    final folder = await create(name, parentId: parentId, workId: workId);
    await addPath(folder.id!, path);
    return folder;
  }

  Future<List<FolderPath>> getPaths(int folderId) async {
    final rows = await _db.query('folder_paths',
        where: 'folder_id = ?', whereArgs: [folderId], orderBy: 'rowid');
    return rows
        .map((r) => FolderPath(
              folderId: r['folder_id'] as int,
              path: r['path'] as String,
              recursive: (r['recursive'] as int) == 1,
            ))
        .toList();
  }

  /// 某作品下所有文件夹的所有路径（用于查询作品内曲目）
  Future<List<String>> getPathsByWork(int workId) async {
    final rows = await _db.rawQuery('''
      SELECT fp.path FROM folder_paths fp
      INNER JOIN folders f ON f.id = fp.folder_id
      WHERE f.work_id = ?
    ''', [workId]);
    return rows.map((r) => r['path'] as String).toList();
  }

  Future<Map<int, List<FolderPath>>> getAllPaths() async {
    final rows = await _db.query('folder_paths');
    final map = <int, List<FolderPath>>{};
    for (final r in rows) {
      final fid = r['folder_id'] as int;
      map.putIfAbsent(fid, () => []).add(FolderPath(
            folderId: fid,
            path: r['path'] as String,
            recursive: (r['recursive'] as int) == 1,
          ));
    }
    return map;
  }
}
