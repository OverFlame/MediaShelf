import 'package:sqflite/sqflite.dart';
import '../utils/filter_expression.dart';
import '../utils/log_util.dart';

/// 标签数据类
class Tag {
  final int? id;
  final String namespace;
  final String name;
  final String color;

  const Tag({
    this.id,
    this.namespace = 'general',
    required this.name,
    this.color = '#cba6f7',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'namespace': namespace,
        'name': name,
        'color': color,
      };

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
        id: map['id'] as int?,
        namespace: map['namespace'] as String? ?? 'general',
        name: map['name'] as String,
        color: map['color'] as String? ?? '#cba6f7',
      );

  @override
  bool operator ==(Object other) =>
      other is Tag && other.namespace == namespace && other.name == name;

  @override
  int get hashCode => Object.hash(namespace, name);

  @override
  String toString() => namespace == 'general' ? name : '$namespace:$name';
}

class TagCount {
  final Tag tag;
  final int trackCount;
  const TagCount({required this.tag, required this.trackCount});
}

class TagDao {
  final Database _db;
  TagDao(this._db);

  // ═══ CRUD ═══

  Future<Tag> insert(Tag tag) async {
    final id = await _db.insert('tags', tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id > 0) {
      return Tag(id: id, namespace: tag.namespace, name: tag.name);
    }
    final rows = await _db.query('tags',
        where: 'namespace = ? AND name = ?',
        whereArgs: [tag.namespace, tag.name]);
    return Tag.fromMap(rows.first);
  }

  Future<Tag?> getById(int id) async {
    final rows = await _db.query('tags', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Tag.fromMap(rows.first);
  }

  Future<Tag?> getByFullName(String namespace, String name) async {
    final rows = await _db.query('tags',
        where: 'namespace = ? AND name = ?',
        whereArgs: [namespace, name]);
    if (rows.isEmpty) return null;
    return Tag.fromMap(rows.first);
  }

  Future<int> update(Tag tag) async {
    if (tag.id == null) return 0;
    return _db.update('tags', tag.toMap(),
        where: 'id = ?', whereArgs: [tag.id]);
  }

  Future<int> delete(int id) async {
    return _db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Tag>> getAll() async {
    final rows = await _db.query('tags', orderBy: 'namespace, name');
    return rows.map(Tag.fromMap).toList();
  }

  Future<List<TagCount>> listWithCount() async {
    final rows = await _db.rawQuery('''
      SELECT t.*, COUNT(tt.track_id) as track_count
      FROM tags t
      LEFT JOIN track_tags tt ON t.id = tt.tag_id
      GROUP BY t.id
      ORDER BY t.namespace, t.name
    ''');
    return rows
        .map((r) =>
            TagCount(tag: Tag.fromMap(r), trackCount: r['track_count'] as int))
        .toList();
  }

  Future<List<Tag>> listByNamespace(String namespace) async {
    final rows = await _db.query('tags',
        where: 'namespace = ?', whereArgs: [namespace], orderBy: 'name');
    return rows.map(Tag.fromMap).toList();
  }

  Future<List<String>> listNamespaces() async {
    final rows = await _db.rawQuery(
        'SELECT DISTINCT namespace FROM tags ORDER BY namespace');
    return rows.map((r) => r['namespace'] as String).toList();
  }

  // ═══ 曲目标签关联 ═══

  Future<void> addTagToTrack(int trackId, int tagId) async {
    await _db.insert('track_tags', {'track_id': trackId, 'tag_id': tagId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeTagFromTrack(int trackId, int tagId) async {
    await _db.delete('track_tags',
        where: 'track_id = ? AND tag_id = ?', whereArgs: [trackId, tagId]);
  }

  Future<void> setTrackTags(int trackId, List<int> tagIds) async {
    await _db.transaction((txn) async {
      await txn
          .delete('track_tags', where: 'track_id = ?', whereArgs: [trackId]);
      for (final tagId in tagIds) {
        await txn.insert('track_tags', {'track_id': trackId, 'tag_id': tagId});
      }
    });
  }

  /// 一次事务里给多条曲目打同一批标签。
  ///
  /// 逐条 await 的写法在 N×M 次提交之外还有更硬的问题：中途一条失败，
  /// 前面已经写进库的关联留下半截状态。放进事务后要么全成、要么全不成。
  Future<void> addTagsToTracks(
      Iterable<int> trackIds, Iterable<int> tagIds) async {
    final tids = trackIds.toList();
    final gids = tagIds.toList();
    if (tids.isEmpty || gids.isEmpty) return;
    await _db.transaction((txn) async {
      for (final trackId in tids) {
        for (final tagId in gids) {
          await txn.insert('track_tags',
              {'track_id': trackId, 'tag_id': tagId},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }

  /// 一次事务里摘掉多条曲目上的同一批标签，与 [addTagsToTracks] 对称。
  Future<void> removeTagsFromTracks(
      Iterable<int> trackIds, Iterable<int> tagIds) async {
    final tids = trackIds.toList();
    final gids = tagIds.toList();
    if (tids.isEmpty || gids.isEmpty) return;
    await _db.transaction((txn) async {
      for (final trackId in tids) {
        for (final tagId in gids) {
          await txn.delete('track_tags',
              where: 'track_id = ? AND tag_id = ?',
              whereArgs: [trackId, tagId]);
        }
      }
    });
  }

  Future<List<Tag>> getTagsForTrack(int trackId) async {
    final rows = await _db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN track_tags tt ON t.id = tt.tag_id
      WHERE tt.track_id = ?
      ORDER BY t.namespace, t.name
    ''', [trackId]);
    return rows.map(Tag.fromMap).toList();
  }

  Future<Map<int, List<Tag>>> getTagsForTracks(List<int> trackIds) async {
    if (trackIds.isEmpty) return {};
    final placeholders = trackIds.map((_) => '?').join(',');
    final rows = await _db.rawQuery('''
      SELECT tt.track_id, t.*
      FROM track_tags tt
      INNER JOIN tags t ON t.id = tt.tag_id
      WHERE tt.track_id IN ($placeholders)
      ORDER BY t.namespace, t.name
    ''', trackIds);
    final map = <int, List<Tag>>{};
    for (final row in rows) {
      final tid = row['track_id'] as int;
      map.putIfAbsent(tid, () => []).add(Tag.fromMap(row));
    }
    return map;
  }

  /// 按标签 AND/OR/NOT 筛选曲目，返回匹配的曲目 id 集合
  Future<Set<int>> getTrackIdsByTags({
    List<int> andTagIds = const [],
    List<int> orTagIds = const [],
    List<int> notTagIds = const [],
  }) async {
    final and = andTagIds.toSet();
    final or = orTagIds.toSet();
    final not = notTagIds.toSet();

    if (and.isEmpty && or.isEmpty && not.isEmpty) {
      final rows = await _db.query('tracks', columns: ['id']);
      return rows.map((r) => r['id'] as int).toSet();
    }

    final conds = <String>[];
    final args = <Object?>[];

    if (and.isNotEmpty) {
      final ph = and.map((_) => '?').join(',');
      conds.add('''
        id IN (
          SELECT track_id FROM track_tags
          WHERE tag_id IN ($ph)
          GROUP BY track_id
          HAVING COUNT(DISTINCT tag_id) = ${and.length}
        )
      ''');
      args.addAll(and);
    }

    if (or.isNotEmpty) {
      final ph = or.map((_) => '?').join(',');
      conds.add(
          'id IN (SELECT DISTINCT track_id FROM track_tags WHERE tag_id IN ($ph))');
      args.addAll(or);
    }

    if (not.isNotEmpty) {
      final ph = not.map((_) => '?').join(',');
      conds.add(
          'id NOT IN (SELECT DISTINCT track_id FROM track_tags WHERE tag_id IN ($ph))');
      args.addAll(not);
    }

    final rows = await _db.rawQuery(
      'SELECT id FROM tracks WHERE ${conds.join(' AND ')}',
      args,
    );
    return rows.map((r) => r['id'] as int).toSet();
  }

  /// 按布尔表达式筛选曲目
  Future<Set<int>> getTrackIdsByExpression(
      String expression, List<Tag> allTags) async {
    final ast = FilterExpressionParser.parse(expression);
    final sub = buildTrackIdSubquery(ast, (ref) => _resolveTagRef(ref, allTags));
    final rows = await _db.rawQuery('SELECT id FROM tracks WHERE id IN ($sub)');
    return rows.map((r) => r['id'] as int).toSet();
  }

  List<int> _resolveTagRef(TagRef ref, List<Tag> allTags) {
    final target = ref.text.toLowerCase();
    final Iterable<Tag> matches;
    if (ref.quoted) {
      matches = allTags.where((t) => t.name.toLowerCase() == target);
    } else {
      final ci = ref.text.indexOf(':');
      if (ci > 0) {
        final ns = ref.text.substring(0, ci).toLowerCase();
        final name = ref.text.substring(ci + 1).toLowerCase();
        matches = allTags.where((t) =>
            t.namespace.toLowerCase() == ns && t.name.toLowerCase() == name);
      } else {
        matches = allTags.where((t) => t.name.toLowerCase() == target);
      }
    }
    return matches.where((t) => t.id != null).map((t) => t.id!).toList();
  }

  // ═══ 文件夹标签关联 ═══

  Future<void> addTagToFolder(int folderId, int tagId) async {
    await _db.insert('folder_tags', {'folder_id': folderId, 'tag_id': tagId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeTagFromFolder(int folderId, int tagId) async {
    await _db.delete('folder_tags',
        where: 'folder_id = ? AND tag_id = ?', whereArgs: [folderId, tagId]);
  }

  Future<void> setFolderTags(int folderId, List<int> tagIds) async {
    await _db.transaction((txn) async {
      await txn.delete('folder_tags',
          where: 'folder_id = ?', whereArgs: [folderId]);
      for (final tagId in tagIds) {
        await txn
            .insert('folder_tags', {'folder_id': folderId, 'tag_id': tagId});
      }
    });
  }

  Future<List<Tag>> getTagsForFolder(int folderId) async {
    final rows = await _db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN folder_tags ft ON t.id = ft.tag_id
      WHERE ft.folder_id = ?
      ORDER BY t.namespace, t.name
    ''', [folderId]);
    return rows.map(Tag.fromMap).toList();
  }

  Future<Map<int, List<Tag>>> getTagsForFolders(List<int> folderIds) async {
    if (folderIds.isEmpty) return {};
    final placeholders = folderIds.map((_) => '?').join(',');
    final rows = await _db.rawQuery('''
      SELECT ft.folder_id, t.*
      FROM folder_tags ft
      INNER JOIN tags t ON t.id = ft.tag_id
      WHERE ft.folder_id IN ($placeholders)
      ORDER BY t.namespace, t.name
    ''', folderIds);
    final map = <int, List<Tag>>{};
    for (final row in rows) {
      final fid = row['folder_id'] as int;
      map.putIfAbsent(fid, () => []).add(Tag.fromMap(row));
    }
    return map;
  }

  /// 删除无引用的孤立标签
  Future<int> deleteOrphanTags() async {
    final count = await _db.delete('tags',
        where: '''
      id NOT IN (SELECT DISTINCT tag_id FROM track_tags)
      AND id NOT IN (SELECT DISTINCT tag_id FROM folder_tags)
    ''');
    logInfo('TagDao', 'deleteOrphanTags: removed $count orphan(s)');
    return count;
  }
}
