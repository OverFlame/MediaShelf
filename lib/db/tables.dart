import 'package:sqflite_common/sqlite_api.dart';

/// 数据库 DDL 建表语句
///
/// v5 起音频、图片、视频与字幕共用一张 media 表，见 BUILD_GUIDE 第 7.3 节。
/// v10 起栏目合并为「音频栏 + 多媒体栏」，库归属只剩 `audio` 与 `media`
/// 两个值，同一个文件两个栏目共用一行。
///
/// 结构不兼容时不做增量迁移：版本号对不上就删表重建，见 [applyMigrations]。
class Tables {
  Tables._();

  static const int version = 10;

  /// 全部表名，按子表在前的顺序排。删表重建与测试夹具都照这个顺序清库。
  static const List<String> tableNames = <String>[
    'media_tags',
    'folder_tags',
    'media_segments',
    'play_history',
    'reading_progress',
    'media',
    'folder_paths',
    'folders',
    'works',
    'tags',
  ];

  /// 视图名。`images` 是 v10 之前遗留的，列在这里只为删掉它。
  static const List<String> viewNames = <String>['tracks', 'images'];

  static const List<String> createStatements = [
    // 作品集：音频侧是系列，多媒体侧是剧集或漫画系列
    '''
    CREATE TABLE works (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT    NOT NULL,
      library     TEXT    NOT NULL CHECK (library IN ('audio', 'media')),
      cover_path  TEXT,
      sort_order  INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL
    )
    ''',

    // 媒体：音频、图片、视频、字幕共用
    '''
    CREATE TABLE media (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      path          TEXT    NOT NULL UNIQUE,
      media_type    TEXT    NOT NULL CHECK (media_type IN ('audio', 'image', 'video', 'subtitle')),
      ext           TEXT    NOT NULL DEFAULT '',
      name_lower    TEXT    NOT NULL DEFAULT '',
      filename      TEXT    NOT NULL,
      format        TEXT,
      file_size     INTEGER,
      file_mtime    INTEGER,
      added_at      INTEGER NOT NULL,
      title         TEXT,
      artist        TEXT,
      album         TEXT,
      duration_ms   INTEGER,
      -- 上一次播到的位置（毫秒）：磁贴右侧的已播时间与下次续播都用它，
      -- 取舍规则见 lib/services/play_position.dart
      play_position_ms INTEGER NOT NULL DEFAULT 0,
      width         INTEGER,
      height        INTEGER,
      alias         TEXT,
      subtitle_path TEXT,
      cover_path    TEXT,
      -- 自然排序键：文件名里的连续数字补零，见 BUILD_GUIDE 第 20.2 节
      sort_key      TEXT,
      -- 多字幕归属：字幕行指回它所属的音频行，见 BUILD_GUIDE 第 23.6 节
      subtitle_of         INTEGER REFERENCES media(id) ON DELETE SET NULL,
      is_default_subtitle INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_media_type ON media(media_type)',
    'CREATE INDEX IF NOT EXISTS idx_media_ext ON media(ext)',
    'CREATE INDEX IF NOT EXISTS idx_media_name_lower ON media(name_lower)',
    'CREATE INDEX IF NOT EXISTS idx_media_added_at ON media(added_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_media_title ON media(title)',
    'CREATE INDEX IF NOT EXISTS idx_media_sort_key ON media(sort_key)',
    'CREATE INDEX IF NOT EXISTS idx_media_subtitle_of ON media(subtitle_of)',

    // 虚拟文件夹（镜像磁盘目录树）。卷封面、裁剪与阅读方向都记在这一行。
    '''
    CREATE TABLE folders (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      name              TEXT    NOT NULL,
      parent            INTEGER REFERENCES folders(id),
      -- 库归属：音频与多媒体各一棵树，见 BUILD_GUIDE 第 18.2 节
      library           TEXT    NOT NULL CHECK (library IN ('audio', 'media')),
      -- 作品被删时自动摘掉归属，避免留下指向已删作品的悬空引用
      work_id           INTEGER REFERENCES works(id) ON DELETE SET NULL,
      -- 卷封面与裁剪，见 BUILD_GUIDE 第 19.2 与 21 节
      cover_path        TEXT,
      cover_crop        TEXT,
      -- 阅读模式，见 BUILD_GUIDE 第 22.2 与 22.3 节
      reading_direction TEXT    NOT NULL DEFAULT 'rtl'
                                CHECK (reading_direction IN ('rtl', 'ltr')),
      reading_fit       TEXT    NOT NULL DEFAULT 'page'
                                CHECK (reading_fit IN ('page', 'height', 'width')),
      UNIQUE(name, parent)
    )
    ''',

    // 文件夹路径映射
    '''
    CREATE TABLE folder_paths (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      path      TEXT    NOT NULL,
      recursive INTEGER NOT NULL DEFAULT 1
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_folder_paths_path ON folder_paths(path)',
    // 同一文件夹不能重复挂同一条路径。addPath 用 INSERT OR IGNORE 去重，靠这条唯一索引生效。
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_folder_paths_unique ON folder_paths(folder_id, path)',

    // 标签
    '''
    CREATE TABLE tags (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      namespace  TEXT    NOT NULL DEFAULT 'general',
      name       TEXT    NOT NULL,
      color      TEXT    NOT NULL DEFAULT '#cba6f7',
      UNIQUE(namespace, name)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_tags_namespace ON tags(namespace)',
    'CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name)',

    // 媒体↔标签 多对多
    '''
    CREATE TABLE media_tags (
      media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
      PRIMARY KEY (media_id, tag_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_media_tags_tag ON media_tags(tag_id)',

    // 文件夹↔标签 多对多
    '''
    CREATE TABLE folder_tags (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (folder_id, tag_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id)',

    // 播放历史
    '''
    CREATE TABLE play_history (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      media_id  INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      played_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_play_history_media ON play_history(media_id)',
    'CREATE INDEX IF NOT EXISTS idx_play_history_time ON play_history(played_at)',

    // 收藏选段：一轨可存多段，见 BUILD_GUIDE 第 24.3 节
    '''
    CREATE TABLE media_segments (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      media_id   INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      start_ms   INTEGER NOT NULL,
      end_ms     INTEGER NOT NULL,
      name       TEXT,
      created_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_media_segments_media ON media_segments(media_id)',

    // 阅读进度：一卷一条，见 BUILD_GUIDE 第 22.6 节
    '''
    CREATE TABLE reading_progress (
      volume_id  INTEGER PRIMARY KEY REFERENCES folders(id) ON DELETE CASCADE,
      media_id   INTEGER REFERENCES media(id) ON DELETE SET NULL,
      page_index INTEGER NOT NULL DEFAULT 0,
      finished   INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )
    ''',

    // 过渡视图：只读，老查询按 tracks 读，写入一律走 MediaDao。
    'CREATE VIEW IF NOT EXISTS tracks AS '
        "SELECT * FROM media WHERE media_type = 'audio'",
  ];

  /// 建全表：开库时 onCreate 用。
  static Future<void> createAll(DatabaseExecutor db) async {
    for (final sql in createStatements) {
      await db.execute(sql);
    }
  }

  /// 清掉全部视图与表：删表重建之前、以及测试造空库时用。
  static Future<void> dropAll(DatabaseExecutor db) async {
    for (final name in viewNames) {
      await db.execute('DROP VIEW IF EXISTS $name');
    }
    for (final name in tableNames) {
      await db.execute('DROP TABLE IF EXISTS $name');
    }
  }

  /// 版本号对不上就删表重建：开库时 onUpgrade 用。
  ///
  /// v10 起不再维护增量迁移链。软件未发布，旧库直接清空重建，代价可以接受；
  /// 这样改 CHECK 约束、删列都不必再靠重建单表绕开。
  static Future<void> applyMigrations(
      DatabaseExecutor db, int oldVersion, int newVersion) async {
    if (oldVersion == newVersion) return;
    await dropAll(db);
    await createAll(db);
  }
}
