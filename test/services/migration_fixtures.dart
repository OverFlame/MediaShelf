import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 两个老库的建表语句（照 AudioShelf/lib/db/tables.dart 与
/// PictureViewer2/lib/db/tables.dart 的 v4 版本抄写），迁移测试用。
const Map<String, String> audioShelfTables = <String, String>{
  'works': '''
    CREATE TABLE works (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL,
      cover_path TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )
  ''',
  'folders': '''
    CREATE TABLE folders (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      name    TEXT    NOT NULL,
      parent  INTEGER REFERENCES folders(id),
      work_id INTEGER REFERENCES works(id) ON DELETE SET NULL,
      UNIQUE(name, parent)
    )
  ''',
  'folder_paths': '''
    CREATE TABLE folder_paths (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      path      TEXT    NOT NULL,
      recursive INTEGER NOT NULL DEFAULT 0
    )
  ''',
  'tracks': '''
    CREATE TABLE tracks (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      path          TEXT    NOT NULL UNIQUE,
      filename      TEXT    NOT NULL,
      title         TEXT,
      artist        TEXT,
      album         TEXT,
      duration_ms   INTEGER,
      format        TEXT,
      file_size     INTEGER,
      file_mtime    INTEGER,
      subtitle_path TEXT,
      cover_path    TEXT,
      added_at      INTEGER NOT NULL
    )
  ''',
  'tags': '''
    CREATE TABLE tags (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      namespace TEXT    NOT NULL DEFAULT 'general',
      name      TEXT    NOT NULL,
      color     TEXT    NOT NULL DEFAULT '#cba6f7',
      UNIQUE(namespace, name)
    )
  ''',
  'track_tags': '''
    CREATE TABLE track_tags (
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id)   ON DELETE CASCADE,
      PRIMARY KEY (track_id, tag_id)
    )
  ''',
  'folder_tags': '''
    CREATE TABLE folder_tags (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (folder_id, tag_id)
    )
  ''',
  'play_history': '''
    CREATE TABLE play_history (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      track_id  INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      played_at INTEGER NOT NULL
    )
  ''',
};

const Map<String, String> pictureViewerTables = <String, String>{
  'images': '''
    CREATE TABLE images (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      path       TEXT    NOT NULL UNIQUE,
      filename   TEXT    NOT NULL,
      width      INTEGER,
      height     INTEGER,
      format     TEXT,
      file_size  INTEGER,
      file_mtime INTEGER,
      hash       TEXT,
      added_at   INTEGER NOT NULL,
      note       TEXT,
      alias      TEXT
    )
  ''',
  'folders': '''
    CREATE TABLE folders (
      id     INTEGER PRIMARY KEY AUTOINCREMENT,
      name   TEXT    NOT NULL,
      parent INTEGER REFERENCES folders(id),
      UNIQUE(name, parent)
    )
  ''',
  'folder_paths': '''
    CREATE TABLE folder_paths (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      path      TEXT    NOT NULL,
      recursive INTEGER NOT NULL DEFAULT 1
    )
  ''',
  'tags': '''
    CREATE TABLE tags (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      namespace TEXT    NOT NULL DEFAULT 'general',
      name      TEXT    NOT NULL,
      color     TEXT    NOT NULL DEFAULT '#cba6f7',
      UNIQUE(namespace, name)
    )
  ''',
  'image_tags': '''
    CREATE TABLE image_tags (
      image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id)   ON DELETE CASCADE,
      PRIMARY KEY (image_id, tag_id)
    )
  ''',
  'folder_tags': '''
    CREATE TABLE folder_tags (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (folder_id, tag_id)
    )
  ''',
};

/// 打开一个老库，[only] 用来只建部分表（模拟老库缺表）。
Future<Database> openOldDb(
  String path,
  Map<String, String> tables, {
  List<String>? only,
}) {
  return databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (db, version) async {
        for (final entry in tables.entries) {
          if (only != null && !only.contains(entry.key)) continue;
          await db.execute(entry.value);
        }
      },
    ),
  );
}

/// AudioShelf 样例：一个系列两个卷、两首曲目、两个标签、一条播放记录。
Future<void> seedAudioShelf(Database db, {String? extraTrackPath}) async {
  await db.insert('works', <String, Object?>{
    'id': 1,
    'name': '某系列',
    'cover_path': '/m/某系列/cover.jpg',
    'sort_order': 0,
    'created_at': 1000,
  });
  await db.insert('folders',
      <String, Object?>{'id': 1, 'name': '某系列', 'parent': null, 'work_id': 1});
  await db.insert('folders',
      <String, Object?>{'id': 2, 'name': '第1卷', 'parent': 1, 'work_id': 1});
  await db.insert('folders',
      <String, Object?>{'id': 3, 'name': '第2卷', 'parent': 1, 'work_id': 1});
  await db.insert('folder_paths',
      <String, Object?>{'folder_id': 1, 'path': '/m/某系列', 'recursive': 1});
  await db.insert('folder_paths', <String, Object?>{
    'folder_id': 2,
    'path': '/m/某系列/第1卷',
    'recursive': 0
  });
  await db.insert('folder_paths', <String, Object?>{
    'folder_id': 3,
    'path': '/m/某系列/第2卷',
    'recursive': 0
  });
  await db.insert('tracks', <String, Object?>{
    'id': 1,
    'path': '/m/某系列/第1卷/a.mp3',
    'filename': 'a.mp3',
    'title': 'A 曲',
    'artist': '歌手',
    'album': '第1卷',
    'duration_ms': 123456,
    'format': 'MP3',
    'file_size': 1024,
    'file_mtime': 111,
    'subtitle_path': '/m/某系列/第1卷/a.mp3.vtt',
    'cover_path': null,
    'added_at': 2000,
  });
  await db.insert('tracks', <String, Object?>{
    'id': 2,
    'path': extraTrackPath ?? '/m/某系列/第2卷/b.WAV',
    'filename': 'b.WAV',
    'title': null,
    'artist': null,
    'album': null,
    'duration_ms': null,
    'format': 'WAV',
    'file_size': 2048,
    'file_mtime': 222,
    'subtitle_path': null,
    'cover_path': '/m/某系列/第2卷/b.jpg',
    'added_at': 2001,
  });
  await db.insert('tags', <String, Object?>{
    'id': 1,
    'namespace': 'general',
    'name': '收藏',
    'color': '#ff0000'
  });
  await db.insert('tags',
      <String, Object?>{'id': 2, 'namespace': 'kind', 'name': 'audio'});
  await db.insert('track_tags', <String, Object?>{'track_id': 1, 'tag_id': 1});
  await db.insert('track_tags', <String, Object?>{'track_id': 2, 'tag_id': 1});
  await db.insert('track_tags', <String, Object?>{'track_id': 2, 'tag_id': 2});
  await db.insert('folder_tags', <String, Object?>{'folder_id': 2, 'tag_id': 1});
  await db.insert(
      'play_history', <String, Object?>{'id': 1, 'track_id': 2, 'played_at': 3000});
}

/// PictureViewer2 样例：一个画集两话、三张图、一个与音频侧同名的标签。
Future<void> seedPictureViewer(Database db) async {
  await db.insert('images', <String, Object?>{
    'id': 1,
    'path': '/m/画集/第1话/001.jpg',
    'filename': '001.jpg',
    'width': 800,
    'height': 1200,
    'format': 'JPEG',
    'file_size': 4096,
    'file_mtime': 333,
    'hash': 'hash-1',
    'added_at': 4000,
    'note': '首刷',
    'alias': '封面',
  });
  await db.insert('images', <String, Object?>{
    'id': 2,
    'path': '/m/画集/第1话/002.PNG',
    'filename': '002.PNG',
    'width': 800,
    'height': 1200,
    'format': 'PNG',
    'file_size': 4097,
    'file_mtime': 334,
    'hash': 'hash-2',
    'added_at': 4001,
    'note': null,
    'alias': null,
  });
  await db.insert('images', <String, Object?>{
    'id': 3,
    'path': '/m/画集/第2话/003.jpg',
    'filename': '003.jpg',
    'width': 800,
    'height': 1200,
    'format': 'JPEG',
    'file_size': 4098,
    'file_mtime': 335,
    'hash': 'hash-3',
    'added_at': 4002,
    'note': null,
    'alias': null,
  });
  await db.insert('folders', <String, Object?>{'id': 1, 'name': '画集', 'parent': null});
  await db.insert('folders', <String, Object?>{'id': 2, 'name': '第1话', 'parent': 1});
  await db.insert('folders', <String, Object?>{'id': 3, 'name': '第2话', 'parent': 1});
  await db.insert('folder_paths',
      <String, Object?>{'folder_id': 1, 'path': '/m/画集', 'recursive': 1});
  await db.insert('folder_paths', <String, Object?>{
    'folder_id': 2,
    'path': '/m/画集/第1话',
    'recursive': 1
  });
  await db.insert('folder_paths', <String, Object?>{
    'folder_id': 3,
    'path': '/m/画集/第2话',
    'recursive': 1
  });
  await db.insert('tags', <String, Object?>{
    'id': 1,
    'namespace': 'general',
    'name': '收藏',
    'color': '#00ff00'
  });
  await db.insert('image_tags', <String, Object?>{'image_id': 1, 'tag_id': 1});
  await db.insert('folder_tags', <String, Object?>{'folder_id': 2, 'tag_id': 1});
}
