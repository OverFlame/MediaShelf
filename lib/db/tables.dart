/// 数据库 DDL 建表语句 & 迁移
class Tables {
  Tables._();

  static const int version = 4;

  static const List<String> createStatements = [
    // 作品集（专辑）
    '''
    CREATE TABLE works (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT    NOT NULL,
      cover_path  TEXT,
      sort_order  INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL
    )
    ''',

    // 虚拟文件夹（镜像磁盘目录树）
    '''
    CREATE TABLE folders (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      name    TEXT    NOT NULL,
      parent  INTEGER REFERENCES folders(id),
      -- 作品被删时自动摘掉归属，避免留下指向已删作品的悬空引用
      work_id INTEGER REFERENCES works(id) ON DELETE SET NULL,
      UNIQUE(name, parent)
    )
    ''',

    // 文件夹路径映射
    '''
    CREATE TABLE folder_paths (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      path      TEXT    NOT NULL,
      recursive INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_folder_paths_path ON folder_paths(path)',
    // 同一文件夹不能重复挂同一条路径。addPath 用 INSERT OR IGNORE 去重，靠这条唯一索引生效。
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_folder_paths_unique ON folder_paths(folder_id, path)',

    // 音频曲目
    '''
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
    'CREATE INDEX IF NOT EXISTS idx_tracks_path ON tracks(path)',

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

    // 曲目↔标签 多对多
    '''
    CREATE TABLE track_tags (
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (track_id, tag_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_track_tags_tag ON track_tags(tag_id)',

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
      track_id  INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      played_at INTEGER NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id)',
    'CREATE INDEX IF NOT EXISTS idx_play_history_time ON play_history(played_at)',
  ];

  /// 迁移脚本（按 version 递增）
  static const Map<int, List<String>> migrations = {
    2: [
      '''
      CREATE TABLE play_history (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id  INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
        played_at INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_play_history_track ON play_history(track_id)',
      'CREATE INDEX IF NOT EXISTS idx_play_history_time ON play_history(played_at)',
    ],
    // v3：folders.work_id 加 ON DELETE SET NULL。SQLite 改不了外键动作，只能重建表。
    //
    // 重建期间有三处坑：
    // 1. DROP TABLE folders 会做一次隐式 DELETE，外键开启时级联清空 folder_paths 与
    //    folder_tags。所以先备份这两张表，再拆掉，最后重建回填。
    // 2. 新表若不指向自己，DROP 旧表时新表里已回填的行会触发 NO ACTION 违规。
    //    所以新表的 parent 指向 folders_new，改名后 SQLite 会自动改写为 folders。
    // 3. 整段跑在 sqflite 的 onUpgrade 事务里，事务内改不了 PRAGMA foreign_keys。
    3: [
      'CREATE TABLE _folder_paths_backup AS SELECT folder_id, path, recursive FROM folder_paths',
      'CREATE TABLE _folder_tags_backup AS SELECT folder_id, tag_id FROM folder_tags',
      'DROP TABLE folder_paths',
      'DROP TABLE folder_tags',
      '''
      CREATE TABLE folders_new (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        name    TEXT    NOT NULL,
        parent  INTEGER REFERENCES folders_new(id),
        work_id INTEGER REFERENCES works(id) ON DELETE SET NULL,
        UNIQUE(name, parent)
      )
      ''',
      '''
      INSERT INTO folders_new (id, name, parent, work_id)
      SELECT id, name, parent, work_id FROM folders
      ''',
      'DROP TABLE folders',
      'ALTER TABLE folders_new RENAME TO folders',
      '''
      CREATE TABLE folder_paths (
        folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
        path      TEXT    NOT NULL,
        recursive INTEGER NOT NULL DEFAULT 0
      )
      ''',
      '''
      INSERT INTO folder_paths (folder_id, path, recursive)
      SELECT folder_id, path, recursive FROM _folder_paths_backup
      ''',
      'CREATE INDEX IF NOT EXISTS idx_folder_paths_path ON folder_paths(path)',
      '''
      CREATE TABLE folder_tags (
        folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
        tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
        PRIMARY KEY (folder_id, tag_id)
      )
      ''',
      '''
      INSERT INTO folder_tags (folder_id, tag_id)
      SELECT folder_id, tag_id FROM _folder_tags_backup
      ''',
      'CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id)',
      'DROP TABLE _folder_paths_backup',
      'DROP TABLE _folder_tags_backup',
    ],
    // v4：folder_paths 加 (folder_id, path) 唯一约束。
    //
    // 用唯一索引而不是表级 UNIQUE：老库只需先去重再补索引，不必再重建一次表。
    // 去重保留每个 (folder_id, path) 组合里 rowid 最小的那行。
    4: [
      '''
      DELETE FROM folder_paths
       WHERE rowid NOT IN (
         SELECT MIN(rowid) FROM folder_paths GROUP BY folder_id, path
       )
      ''',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_folder_paths_unique ON folder_paths(folder_id, path)',
    ],
  };
}
