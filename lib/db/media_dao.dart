import 'package:sqflite/sqflite.dart';

import '../services/media_rules.dart';
import '../utils/log_util.dart';

/// 媒体类型。音频、图片、视频、字幕共用一张 media 表。
enum MediaType {
  audio('audio'),
  image('image'),
  video('video'),
  subtitle('subtitle');

  const MediaType(this.value);

  /// 落库值
  final String value;

  /// 由落库值反解，未知值返回 null
  static MediaType? fromValue(Object? value) {
    for (final t in values) {
      if (t.value == value) return t;
    }
    return null;
  }

  /// 全部落库值，供 CHECK 断言与 IN 查询拼接
  static List<String> get allValues => values.map((t) => t.value).toList();
}

/// media 表的一行
class MediaItem {
  final int? id;
  final String path;
  final MediaType mediaType;
  final String ext;
  final String nameLower;
  final String filename;
  final String? format;
  final int? fileSize;
  final int? fileMtime;
  final int addedAt;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final int? width;
  final int? height;
  final String? hash;
  final String? note;
  final String? alias;
  final String? subtitlePath;
  final String? coverPath;

  const MediaItem({
    this.id,
    required this.path,
    required this.mediaType,
    this.ext = '',
    this.nameLower = '',
    required this.filename,
    this.format,
    this.fileSize,
    this.fileMtime,
    required this.addedAt,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.width,
    this.height,
    this.hash,
    this.note,
    this.alias,
    this.subtitlePath,
    this.coverPath,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'path': path,
        'media_type': mediaType.value,
        'ext': ext,
        'name_lower': nameLower,
        'filename': filename,
        'format': format,
        'file_size': fileSize,
        'file_mtime': fileMtime,
        'added_at': addedAt,
        'title': title,
        'artist': artist,
        'album': album,
        'duration_ms': durationMs,
        'width': width,
        'height': height,
        'hash': hash,
        'note': note,
        'alias': alias,
        'subtitle_path': subtitlePath,
        'cover_path': coverPath,
      };

  factory MediaItem.fromMap(Map<String, dynamic> map) => MediaItem(
        id: map['id'] as int?,
        path: map['path'] as String,
        mediaType:
            MediaType.fromValue(map['media_type']) ?? MediaType.image,
        ext: (map['ext'] as String?) ?? '',
        nameLower: (map['name_lower'] as String?) ?? '',
        filename: (map['filename'] as String?) ?? '',
        format: map['format'] as String?,
        fileSize: map['file_size'] as int?,
        fileMtime: map['file_mtime'] as int?,
        addedAt: (map['added_at'] as int?) ?? 0,
        title: map['title'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        durationMs: map['duration_ms'] as int?,
        width: map['width'] as int?,
        height: map['height'] as int?,
        hash: map['hash'] as String?,
        note: map['note'] as String?,
        alias: map['alias'] as String?,
        subtitlePath: map['subtitle_path'] as String?,
        coverPath: map['cover_path'] as String?,
      );
}

/// media 表的读写入口。视图 tracks / images 只读，写入一律走这里。
class MediaDao {
  final Database _db;
  MediaDao(this._db);

  static const int _batchSize = 500;

  // ═══ 归一化工具 ═══

  /// 取小写扩展名（含点）。规则在 media_rules.dart，这里只是转发。
  ///
  /// 只认最后一个点；点在路径开头（隐藏文件）或结尾时算没有扩展名，
  /// 所以 `.gitignore` 与 `a` 都返回空串，`a.tar.gz` 返回 `.gz`。
  static String extOf(String path) => extOfPath(path);

  /// 供大小写不敏感查找的列值，统一小写。查询侧也要先 toLowerCase 再回填。
  static String nameLowerOf(String path) => nameLowerOfPath(path);

  /// 补全 ext 与 name_lower 再落库，避免调用点漏填。
  static Map<String, Object?> rowWithDerived(Map<String, Object?> row) {
    final path = (row['path'] as String?) ?? '';
    return {
      ...row,
      'ext': row['ext'] ?? extOf(path),
      'name_lower': row['name_lower'] ?? nameLowerOf(path),
    };
  }

  // ═══ 写 ═══

  Future<int> insertRow(
    Map<String, Object?> row, {
    ConflictAlgorithm conflict = ConflictAlgorithm.ignore,
  }) {
    return _db.insert('media', rowWithDerived(row), conflictAlgorithm: conflict);
  }

  /// 按 id 更新。给了 type 就顺带校验这一行的类型，避免跨类型误改。
  Future<int> updateRow(int id, Map<String, Object?> fields,
      {MediaType? type}) async {
    final where = StringBuffer('id = ?');
    final args = <Object?>[id];
    if (type != null) {
      where.write(' AND media_type = ?');
      args.add(type.value);
    }
    return _db.update('media', fields, where: where.toString(), whereArgs: args);
  }

  Future<void> setSubtitlePath(int id, String? path) async {
    await updateRow(id, {'subtitle_path': path}, type: MediaType.audio);
  }

  Future<void> setCoverPath(int id, String? path) async {
    await updateRow(id, {'cover_path': path});
  }

  Future<int> deleteByPaths(Iterable<String> paths, {MediaType? type}) async {
    final list = paths.toList();
    if (list.isEmpty) return 0;
    final typeSql = type == null ? '' : ' AND media_type = ?';
    final typeArg = type == null ? const <Object?>[] : <Object?>[type.value];
    var deleted = 0;
    for (var i = 0; i < list.length; i += _batchSize) {
      final batch = list.sublist(
          i, i + _batchSize > list.length ? list.length : i + _batchSize);
      final ph = List.filled(batch.length, '?').join(',');
      deleted += await _db.delete('media',
          where: 'path IN ($ph)$typeSql', whereArgs: [...batch, ...typeArg]);
    }
    logInfo('MediaDao', 'deleteByPaths 删除 $deleted 行（type=${type?.value}）');
    return deleted;
  }

  // ═══ 读 ═══

  String _typeWhere(MediaType? type, List<Object?> args, {String? extra}) {
    final parts = <String>[];
    if (type != null) {
      parts.add('media_type = ?');
      args.add(type.value);
    }
    if (extra != null) parts.add(extra);
    return parts.join(' AND ');
  }

  Future<MediaItem?> getById(int id) async {
    final rows = await _db.query('media', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MediaItem.fromMap(rows.first);
  }

  Future<MediaItem?> getByPath(String path) async {
    final rows =
        await _db.query('media', where: 'path = ?', whereArgs: [path]);
    if (rows.isEmpty) return null;
    return MediaItem.fromMap(rows.first);
  }

  Future<List<MediaItem>> queryAll(
      {MediaType? type, String orderBy = 'filename'}) async {
    final args = <Object?>[];
    final where = _typeWhere(type, args);
    final rows = await _db.query('media',
        where: where.isEmpty ? null : where,
        whereArgs: where.isEmpty ? null : args,
        orderBy: orderBy);
    return rows.map(MediaItem.fromMap).toList();
  }

  Future<int> count({MediaType? type}) async {
    final args = <Object?>[];
    final where = _typeWhere(type, args);
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS n FROM media'
        '${where.isEmpty ? '' : ' WHERE $where'}',
        args.isEmpty ? null : args);
    return (rows.first['n'] as int?) ?? 0;
  }

  /// 已入库的路径集合。导入前用它跳过重复文件。
  Future<Set<String>> existingPaths(Iterable<String> paths,
      {MediaType? type}) async {
    final list = paths.toList();
    if (list.isEmpty) return <String>{};
    final typeSql = type == null ? '' : ' AND media_type = ?';
    final typeArg = type == null ? const <Object?>[] : <Object?>[type.value];
    final found = <String>{};
    for (var i = 0; i < list.length; i += _batchSize) {
      final batch = list.sublist(
          i, i + _batchSize > list.length ? list.length : i + _batchSize);
      final ph = List.filled(batch.length, '?').join(',');
      final rows = await _db.rawQuery(
          'SELECT path FROM media WHERE path IN ($ph)$typeSql',
          [...batch, ...typeArg]);
      for (final r in rows) {
        found.add(r['path'] as String);
      }
    }
    return found;
  }
}
