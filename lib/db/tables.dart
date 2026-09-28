/// 数据库 DDL 建表语句 & 迁移
///
/// v5 起音频、图片、视频与字幕共用一张 media 表，见 BUILD_GUIDE 第 7.3 节。
/// 老库不做就地升级，走第 8 节的迁移流程，所以这里只保留 v5 之后的增量。
class Tables {
  Tables._();

  static const int version = 7;

  static const List<String> createStatements = [
    // 作品集：音频侧是系列，视频侧是剧集，图片侧是漫画系列
    '''
    CREATE TABLE works (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT    NOT NULL,
      library     TEXT    NOT NULL CHECK (library IN ('audio', 'image', 'video')),
      cover_path  TEXT,
      cover_crop  TEXT,
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
      width         INTEGER,
      height        INTEGER,
      hash          TEXT,
      note          TEXT,
      alias         TEXT,
      subtitle_path TEXT,
      cover_path    TEXT,
      -- 自然排序键：文件名里的连续数字补零，见 BUILD_GUIDE 第 20.2 节
      sort_key      TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_media_type ON media(media_type)',
    'CREATE INDEX IF NOT EXISTS idx_media_ext ON media(ext)',
    'CREATE INDEX IF NOT EXISTS idx_media_name_lower ON media(name_lower)',
    'CREATE INDEX IF NOT EXISTS idx_media_hash ON media(hash)',
    'CREATE INDEX IF NOT EXISTS idx_media_added_at ON media(added_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_media_title ON media(title)',
    'CREATE INDEX IF NOT EXISTS idx_media_sort_key ON media(sort_key)',

    // 虚拟文件夹（镜像磁盘目录树）。卷封面、裁剪与阅读方向都记在这一行。
    '''
    CREATE TABLE folders (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      name              TEXT    NOT NULL,
      parent            INTEGER REFERENCES folders(id),
      -- 库归属：音频、图片、视频各一棵树，见 BUILD_GUIDE 第 18.2 节
      library           TEXT    NOT NULL CHECK (library IN ('audio', 'image', 'video')),
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

    // 并排页对：v1 只建表，不写入，见 BUILD_GUIDE 第 22.5 节
    '''
    CREATE TABLE reading_spreads (
      volume_id     INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      left_media_id INTEGER NOT NULL REFERENCES media(id)   ON DELETE CASCADE,
      right_media_id INTEGER NOT NULL REFERENCES media(id)  ON DELETE CASCADE,
      PRIMARY KEY (volume_id, left_media_id)
    )
    ''',

    // 过渡视图：只读，阶段 6 结束前删掉（BUILD_GUIDE 第 7.4 节）。
    // 老查询按 tracks / images 读，写入一律走 MediaDao。
    'CREATE VIEW IF NOT EXISTS tracks AS '
        "SELECT * FROM media WHERE media_type = 'audio'",
    'CREATE VIEW IF NOT EXISTS images AS '
        "SELECT * FROM media WHERE media_type = 'image'",
  ];

  /// 迁移脚本（按 version 递增）。
  ///
  /// v5 是合并后的第一版结构，没有可复用的老增量：老库（v2 到 v4）
  /// 只走 lib/services/migration_service.dart 的跨库导入。
  static const Map<int, List<String>> migrations = {
    // v6：收藏选段（BUILD_GUIDE 第 24.3 节）
    6: [
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
      'CREATE INDEX IF NOT EXISTS idx_media_segments_media '
          'ON media_segments(media_id)',
    ],

    // v7：图片栈与阅读模式的结构（BUILD_GUIDE 第 19.2、20.1、20.2、21.2、22 节）
    7: [
      // works 要把 library 的枚举值扩到 image。SQLite 改不了 CHECK，只能重建表；
      // 而 DROP TABLE 会先做一次隐式 DELETE，folders.work_id 上的
      // ON DELETE SET NULL 会顺手把归属清成 NULL。所以先备份归属，重建完写回去。
      'CREATE TABLE folders_work_backup AS SELECT id, work_id FROM folders',
      '''
      CREATE TABLE works_new (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        library     TEXT    NOT NULL CHECK (library IN ('audio', 'image', 'video')),
        cover_path  TEXT,
        cover_crop  TEXT,
        sort_order  INTEGER NOT NULL DEFAULT 0,
        created_at  INTEGER NOT NULL
      )
      ''',
      'INSERT INTO works_new '
          '(id, name, library, cover_path, sort_order, created_at) '
          'SELECT id, name, library, cover_path, sort_order, created_at FROM works',
      'DROP TABLE works',
      'ALTER TABLE works_new RENAME TO works',
      'UPDATE folders SET work_id = '
          '(SELECT b.work_id FROM folders_work_backup b WHERE b.id = folders.id)',
      'DROP TABLE folders_work_backup',

      // media 加自然排序键
      'ALTER TABLE media ADD COLUMN sort_key TEXT',
      'CREATE INDEX IF NOT EXISTS idx_media_sort_key ON media(sort_key)',

      // folders 加卷封面、裁剪与阅读模式四列
      'ALTER TABLE folders ADD COLUMN cover_path TEXT',
      'ALTER TABLE folders ADD COLUMN cover_crop TEXT',
      "ALTER TABLE folders ADD COLUMN reading_direction TEXT NOT NULL "
          "DEFAULT 'rtl' CHECK (reading_direction IN ('rtl', 'ltr'))",
      "ALTER TABLE folders ADD COLUMN reading_fit TEXT NOT NULL "
          "DEFAULT 'page' CHECK (reading_fit IN ('page', 'height', 'width'))",

      // 并排页对
      '''
      CREATE TABLE reading_spreads (
        volume_id      INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
        left_media_id  INTEGER NOT NULL REFERENCES media(id)   ON DELETE CASCADE,
        right_media_id INTEGER NOT NULL REFERENCES media(id)   ON DELETE CASCADE,
        PRIMARY KEY (volume_id, left_media_id)
      )
      ''',
    ],
  };
}
