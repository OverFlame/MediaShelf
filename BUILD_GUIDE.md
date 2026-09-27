# MediaShelf 构建指南

本文件写给接手实现的 AI 代理。
路径以 /home/hoshi/code 为根。
先读第 1 节到第 3 节。
再按第 11 节的阶段顺序动手。

## 1 目标与范围

MediaShelf 合并两个现有应用。
两边都是本地媒体库。
合并后统一管理音频、图片、视频。
工作目录固定为 /home/hoshi/code/MediaShelf。

已确认的范围：

| 项 | 决定 |
|---|---|
| 骨架 | AudioShelf |
| 项目名 | MediaShelf |
| pubspec 名 | mediashelf |
| 数据库 | 单一新库 mediashelf.db，另写迁移脚本 |
| 平台 | Windows 与 Linux 优先 |
| 视频 v1 | 识别、列表、卡片、拉起外部播放器 |
| 视频缩略图 | 统一图标，不引入解码依赖 |
| Android | 保留代码，首版不验收 |
| 许可证 | 暂定 MIT，见第 15 节 |

首版不做这些事：

- 在应用内解码与播放视频。
- 提取视频首帧。
- 读视频时长与分辨率。
- iOS 与 macOS 平台目录。
- web 平台。

原因：内嵌视频播放器要引入原生解码栈。
外链播放器把这件事交给系统。
音频链路沿用现有实现，改动面最小。

## 2 现状事实

两个仓库同源分叉。
下面的数字与行号都已核对。

### 2.1 同一祖先

lib 下的目录同名：db/、pages/、services/、state/、theme/、utils/、widgets/。
文件也大量同名。

| 文件 | AudioShelf 行数 | PictureViewer2 行数 |
|---|---|---|
| lib/main.dart | 90 | 85 |
| lib/db/database.dart | 92 | 80 |
| lib/db/tables.dart | 190 | 119 |
| lib/db/folder_dao.dart | 308 | 274 |
| lib/db/tag_dao.dart | 351 | 386 |
| lib/services/data_dir_service.dart | 163 | 113 |
| lib/services/file_scanner.dart | 137 | 77 |
| lib/services/import_service.dart | 239 | 343 |
| lib/services/settings_service.dart | 142 | 179 |
| lib/state/app_state.dart | 1172 | 1085 |
| lib/utils/filter_expression.dart | 263 | 317 |
| lib/utils/log_util.dart | 76 | 83 |
| lib/widgets/tag_panel.dart | 816 | 821 |

lib 目录总量：AudioShelf 7566 行。
PictureViewer2 10805 行。

两边 lib 内部用相对导入。
只有测试用 package: 前缀。
AudioShelf 有 16 个测试文件用 package:audioshelf/。
PictureViewer2 有 18 个测试文件用 package:pictureviewer/。

### 2.2 数据库冲突

这是第一难点。

| 冲突 | 证据 |
|---|---|
| 库文件名不同 | AudioShelf/lib/db/database.dart:48 写 audioshelf.db；PictureViewer2/lib/db/database.dart:32 写 pv2.db |
| 版本号相同 | 两份 lib/db/tables.dart:5 都写 version = 4 |
| 四张表重名 | tags、folders、folder_paths、folder_tags |
| folders 的列不同 | AudioShelf/lib/db/tables.dart:26 有 work_id；PictureViewer2/lib/db/tables.dart:57 没有 |
| folder_paths.recursive 默认值不同 | AudioShelf/lib/db/tables.dart:36 默认 0；PictureViewer2/lib/db/tables.dart:70 默认 1 |
| 唯一索引名不同 | AudioShelf/lib/db/tables.dart:41 用 idx_folder_paths_unique；PictureViewer2/lib/db/tables.dart:74 用 idx_folder_paths_uniq |
| 媒体表不同名 | AudioShelf 用 tracks；PictureViewer2 用 images |
| 播放历史指向曲目 | AudioShelf/lib/db/tables.dart:100 的 play_history.track_id 引用 tracks |

结论：直接叠加两边的 DDL 会失败。
统一表结构见第 7 节。
迁移方案见第 8 节。

### 2.3 数据目录

两个应用的数据根不同。

| 应用 | 默认根 | 库文件名 | 指针文件 |
|---|---|---|---|
| AudioShelf | getApplicationSupportDirectory()/AudioShelf | audioshelf.db | .datadir |
| PictureViewer2 | getApplicationDocumentsDirectory()/PictureViewer | pv2.db | .datadir |

证据：AudioShelf/lib/services/data_dir_service.dart:29 与 :30。PictureViewer2/lib/services/data_dir_service.dart:30 与 :31。
Linux 上两个根的差异是 ~/.local/share 与 ~/Documents。
指针文件路径由 AudioShelf/lib/services/data_dir_service.dart:33 给出。
指针文件始终位于默认根下，内容是实际数据目录。

### 2.4 独有能力

AudioShelf 独有：

| 能力 | 位置 |
|---|---|
| 音频播放控制器 | lib/state/player_controller.dart:15 |
| Android 前台服务与媒体会话 | lib/services/media_bridge.dart:31 |
| 字幕解析 | lib/services/subtitle_parser.dart:22 |
| 音频元数据 | lib/services/metadata_service.dart:30 |
| 封面写入与限制 | lib/services/cover_service.dart:10 |
| 作品集 | lib/db/work_dao.dart:5 |
| 播放条 | lib/widgets/player_bar.dart |
| 文件夹浏览 | lib/widgets/folder_browser.dart |
| 字幕页 | lib/pages/subtitle_page.dart |

PictureViewer2 独有：

| 能力 | 位置 |
|---|---|
| 三层缩略图缓存 | lib/services/thumbnail_cache.dart:52 |
| EXIF 数据 | lib/services/exif_service.dart:90 |
| 图片查看器 | lib/widgets/image_viewer.dart |
| 图片详情 | lib/widgets/image_detail.dart |
| 桌面拖放 | lib/pages/home_page.dart:73 |
| 颜色工具 | lib/utils/color_util.dart |
| 图像缓存工具 | lib/utils/image_cache_util.dart |
| 原子写文件 | lib/utils/file_io.dart |
| 路径比较与重名 | lib/utils/path_util.dart |
| LIKE 转义 | lib/db/sql_like.dart |
| CI | .github/workflows/ci.yml |
| 表达式深度护栏 | lib/utils/filter_expression.dart:167 |

最后一行的差别要注意。
PictureViewer2 的解析器带 maxDepth = 256。
AudioShelf 的版本没有这道护栏。
迁入时取 PictureViewer2 的版本。

### 2.5 测试

| 仓库 | 测试文件 | 用例数 |
|---|---|---|
| AudioShelf/test | 17，另有 test/support 1 个辅助文件 | 72 |
| PictureViewer2/test | 18 | 127 |

PictureViewer2 有两个大用例：
test/widget/narrow_window_test.dart，312 行。
test/perf/library_scale_test.dart，291 行。

## 3 命名与仓库

| 项 | 值 |
|---|---|
| 目录 | /home/hoshi/code/MediaShelf |
| pubspec 名 | mediashelf |
| MaterialApp title | MediaShelf |
| Android namespace | com.mediashelf.mediashelf |
| Android applicationId | com.mediashelf.mediashelf |
| 远端建议 | git@github.com:<用户名>/MediaShelf.git |
| 默认分支 | master |

改名步骤见下表。

| 步 | 动作 |
|---|---|
| 1 | 改 pubspec 的 name 字段 |
| 2 | 改 android/app/build.gradle.kts:8 的 namespace |
| 3 | 改 android/app/build.gradle.kts:19 的 applicationId |
| 4 | 移 Kotlin 目录到 com/mediashelf/mediashelf/ |
| 5 | 改 Kotlin 文件首行的 package 声明 |
| 6 | 替换测试文件的 package:audioshelf/ 前缀 |
| 7 | 改 AndroidManifest.xml 里 .MainActivity 与 .PlaybackService 的引用 |

lib 内部用相对导入，改名不动 lib。

## 4 目标目录结构

```
MediaShelf/
├── BUILD_GUIDE.md
├── PROJECTLOG.md
├── README.md
├── pubspec.yaml
├── analysis_options.yaml
├── .gitignore
├── android/                     # 迁自 AudioShelf，改包名
├── linux/                       # 迁自 AudioShelf
├── windows/                     # 迁自 AudioShelf
├── .github/workflows/ci.yml     # 迁自 PictureViewer2
├── lib/
│   ├── main.dart
│   ├── db/
│   │   ├── database.dart
│   │   ├── folder_dao.dart
│   │   ├── media_dao.dart       # 新建：合并 track_dao 与 image_dao
│   │   ├── sql_like.dart        # 迁自 PictureViewer2
│   │   ├── tables.dart          # 重写为 v5
│   │   ├── tag_dao.dart
│   │   └── work_dao.dart
│   ├── pages/
│   │   ├── about_page.dart
│   │   ├── home_page.dart
│   │   ├── settings_page.dart
│   │   └── subtitle_page.dart
│   ├── services/
│   │   ├── cover_service.dart
│   │   ├── data_dir_service.dart
│   │   ├── exif_service.dart
│   │   ├── file_scanner.dart
│   │   ├── import_service.dart
│   │   ├── media_bridge.dart
│   │   ├── metadata_service.dart
│   │   ├── migration_service.dart   # 新建
│   │   ├── settings_service.dart
│   │   ├── subtitle_parser.dart
│   │   ├── thumbnail_cache.dart
│   │   └── video_launcher.dart      # 新建
│   ├── state/
│   │   ├── app_state.dart
│   │   └── player_controller.dart
│   ├── theme/
│   │   ├── app_theme.dart
│   │   └── catppuccin.dart
│   ├── utils/
│   │   ├── color_util.dart
│   │   ├── file_io.dart
│   │   ├── filter_expression.dart
│   │   ├── format.dart
│   │   ├── image_cache_util.dart
│   │   ├── log_util.dart
│   │   └── path_util.dart
│   └── widgets/
│       ├── color_picker_dialog.dart
│       ├── cover_image.dart
│       ├── dialogs.dart
│       ├── export_actions.dart
│       ├── filter_dialog.dart
│       ├── folder_browser.dart
│       ├── folder_panel.dart
│       ├── image_detail.dart
│       ├── image_grid.dart
│       ├── image_viewer.dart
│       ├── move_folder_dialog.dart
│       ├── player_bar.dart
│       ├── tag_panel.dart
│       ├── tag_picker_dialog.dart
│       ├── video_grid.dart          # 新建
│       └── works_grid.dart
├── scripts/
│   ├── build_android.sh
│   ├── build_linux.sh
│   ├── build_windows.ps1
│   ├── build_windows_remote.sh
│   └── pack_for_windows.sh
├── tool/
│   └── migrate_check.dart           # 新建
└── test/
    ├── db/
    ├── perf/
    ├── services/
    ├── state/
    ├── support/
    ├── utils/
    └── widget/
```

data/ 与 logs/ 是运行期目录，不入库。

## 5 依赖合并

### 5.1 版本表

| 依赖 | AudioShelf | PictureViewer2 | MediaShelf |
|---|---|---|---|
| flutter SDK | ^3.12.0 | ^3.12.2 | ^3.12.2 |
| cupertino_icons | ^1.0.8 | ^1.0.8 | ^1.0.8 |
| provider | ^6.1.5+1 | ^6.1.5+1 | ^6.1.5+1 |
| sqflite | ^2.4.3 | ^2.4.3 | ^2.4.3 |
| sqflite_common_ffi | ^2.4.2+1 | ^2.4.2 | ^2.4.2+1 |
| path_provider | ^2.1.6 | ^2.1.6 | ^2.1.6 |
| path | ^1.9.1 | ^1.9.1 | ^1.9.1 |
| file_picker | ^12.1.2 | ^11.0.2 | ^12.1.2 |
| shared_preferences | ^2.5.5 | ^2.5.0 | ^2.5.5 |
| audio_metadata_reader | ^1.7.1 | 无 | ^1.7.1 |
| flutter_soloud | ^4.1.7 | 无 | ^4.1.7 |
| crypto | 无 | ^3.0.7 | ^3.0.7 |
| image | 无 | ^4.9.1 | ^4.9.1 |
| desktop_drop | 无 | ^0.4.4 | ^0.4.4 |
| exif | 无 | ^3.3.0 | ^3.3.0 |
| flutter_lints (dev) | ^6.0.0 | ^6.0.0 | ^6.0.0 |
| path_provider_platform_interface (dev) | ^2.1.3 | 无 | ^2.1.3 |

锁文件里解析到的版本：
file_picker 在 AudioShelf 是 12.1.2，在 PictureViewer2 是 11.0.3。
sqflite_common_ffi 在 AudioShelf 是 2.4.2+1，在 PictureViewer2 是 2.4.2。

### 5.2 file_picker 升级

两边都用静态调用形式。

- PictureViewer2/lib/widgets/folder_panel.dart:336 用 FilePicker.pickFiles。
- PictureViewer2/lib/widgets/image_grid.dart:151 用 FilePicker.getDirectoryPath。
- AudioShelf/lib/widgets/dialogs.dart:43 用 FilePicker.pickFile。
- AudioShelf/lib/widgets/dialogs.dart:59 用 FilePicker.getDirectoryPath。

调用形式相同，升级风险低。
迁入后跑 flutter analyze 确认。

### 5.3 sqlite3 来源

两边的写法不同。

AudioShelf/pubspec.yaml:26 到 :30：

```yaml
hooks:
  user_defines:
    sqlite3:
      source: system
      name_windows: winsqlite3
```

PictureViewer2/pubspec.yaml:105 到 :111：

```yaml
hooks:
  user_defines:
    sqlite3:
      source:
        windows: sqlite3
        linux: system
        macos: system
```

采用 AudioShelf 的写法。
原因：Windows 上用系统 winsqlite3.dll，构建不访问 GitHub。
PictureViewer2 的 Windows 分支要求 sqlite3.dll 就位。
那是 scripts/build_windows.ps1 下载的。
迁入打包脚本时删掉那段下载。

## 6 平台与构建

### 6.1 本机环境

Flutter 3.47.5 与 Dart 3.13.4 装在 ~/flutter。
构建前先导出：

```bash
export PATH="$HOME/flutter/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib"
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

DSH 的 bash 工具不读 ~/.zshrc。
每次都要在命令里导出。

### 6.2 Linux

必须导出 NO_XIPH_LIBS=1。
AudioShelf/scripts/build_linux.sh:17 已有这一行。
原因：flutter_soloud 自带的 libopus 在 glibc 2.43 上编译。
Ubuntu 24.04 只有 glibc 2.39。
禁用后规避运行时加载失败。

构建脚本以 PictureViewer2/scripts/build_linux.sh 为底。
它有 259 行，带参数解析、日志与 sqlite3 探测。
选项说明见该文件第 10 行。
--sqlite 的取值见第 44 行。
默认取值 system，不访问 GitHub。
产物在 build/linux/<架构>/<模式>/bundle/。

合并时保留 NO_XIPH_LIBS，删除 --sqlite download 分支。

### 6.3 Windows

sqlite3 用 winsqlite3.dll，见第 5.3 节。
打包脚本迁 PictureViewer2/scripts/pack_for_windows.sh。
构建脚本用 scripts/build_windows.ps1。
删掉下载 sqlite3.dll 的步骤。

### 6.4 Android（延后）

保留 android/ 目录。
保留的权限见 AudioShelf/android/app/src/main/AndroidManifest.xml：
第 3 行所有文件访问，第 14 行与第 15 行前台服务，第 16 行通知。
保留 AudioShelf/android/app/src/main/kotlin/com/audioshelf/audioshelf/PlaybackService.kt。
首版只做改名，不验收。

### 6.5 CI

迁 PictureViewer2/.github/workflows/ci.yml。
它装 libsqlite3-dev，见第 22 行。
它固定 Flutter 3.47.5，见第 27 行。
它用 --no-fatal-infos 放行 info，见第 36 行。
它跑 flutter test，见第 39 行。

## 7 数据层设计

### 7.1 决策

- 用单表 media 存音频、图片与视频。
- 标签表 tags 与关联表 media_tags 通用。
- folders 保留 work_id 列，取值可空。
- 不保留 tracks 表与 images 表。

原因：标签、筛选、排序、文件夹树、选择集只写一套代码。
分三张表会把 AppState 的双套逻辑变成三套。

### 7.2 版本策略

Tables.version 从 5 开始。
createStatements 写入合并后的完整 DDL。
migrations 只保留 5 之后的增量。
老库不做就地升级，走第 8 节的导入流程。
原因：两边版本号都是 4，但语义不同。

### 7.3 DDL（v5）

```sql
CREATE TABLE works (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT    NOT NULL,
  cover_path  TEXT,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);

CREATE TABLE media (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  path          TEXT    NOT NULL UNIQUE,
  media_type    TEXT    NOT NULL CHECK (media_type IN ('audio', 'image', 'video')),
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
  cover_path    TEXT
);
CREATE INDEX IF NOT EXISTS idx_media_type ON media(media_type);
CREATE INDEX IF NOT EXISTS idx_media_hash ON media(hash);
CREATE INDEX IF NOT EXISTS idx_media_added_at ON media(added_at DESC);
CREATE INDEX IF NOT EXISTS idx_media_title ON media(title);

CREATE TABLE tags (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  namespace  TEXT    NOT NULL DEFAULT 'general',
  name       TEXT    NOT NULL,
  color      TEXT    NOT NULL DEFAULT '#cba6f7',
  UNIQUE(namespace, name)
);
CREATE INDEX IF NOT EXISTS idx_tags_namespace ON tags(namespace);
CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name);

CREATE TABLE media_tags (
  media_id INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  tag_id   INTEGER NOT NULL REFERENCES tags(id)  ON DELETE CASCADE,
  PRIMARY KEY (media_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_media_tags_tag ON media_tags(tag_id);

CREATE TABLE folders (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,
  name    TEXT    NOT NULL,
  parent  INTEGER REFERENCES folders(id),
  work_id INTEGER REFERENCES works(id) ON DELETE SET NULL,
  UNIQUE(name, parent)
);

CREATE TABLE folder_paths (
  folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  path      TEXT    NOT NULL,
  recursive INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_folder_paths_path ON folder_paths(path);
CREATE UNIQUE INDEX IF NOT EXISTS idx_folder_paths_unique
  ON folder_paths(folder_id, path);

CREATE TABLE folder_tags (
  folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
  tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
  PRIMARY KEY (folder_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id);

CREATE TABLE play_history (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  media_id  INTEGER NOT NULL REFERENCES media(id) ON DELETE CASCADE,
  played_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_play_history_media ON play_history(media_id);
CREATE INDEX IF NOT EXISTS idx_play_history_time ON play_history(played_at);
```

与两边的差异清单：

| 项 | 处置 |
|---|---|
| tracks 与 images | 合并为 media，新增 media_type |
| track_tags 与 image_tags | 合并为 media_tags |
| play_history.track_id | 改名 media_id |
| folders.work_id | 保留 |
| folder_paths 默认值 | 取 1，与 PictureViewer2 一致 |
| 唯一索引名 | 统一用 idx_folder_paths_unique |
| tags 与 folder_tags | 与两边一致，不改 |

### 7.4 过渡视图（可选）

阶段 2 到阶段 5 之间可建两个只读视图。
这样能先跑通查询，再改写入路径。

```sql
CREATE VIEW tracks AS SELECT * FROM media WHERE media_type = 'audio';
CREATE VIEW images AS SELECT * FROM media WHERE media_type = 'image';
```

视图不能写。
写入必须走 MediaDao。
阶段 6 结束前删掉视图。

### 7.5 模型类

lib/db/media_dao.dart 定义 MediaType 与 MediaItem。
字段与 media 表一一对应。
可参考 AudioShelf/lib/db/track_dao.dart:5 与 PictureViewer2/lib/db/image_dao.dart:6。

## 8 迁移方案

### 8.1 输入

| 来源 | 库文件名 | 默认位置 |
|---|---|---|
| AudioShelf | audioshelf.db | <应用支持目录>/AudioShelf |
| PictureViewer2 | pv2.db | <文档目录>/PictureViewer |

实际位置先读默认根下的 .datadir 指针文件。
指针文件机制见 AudioShelf/lib/services/data_dir_service.dart:33。

### 8.2 路线

新建 lib/services/migration_service.dart。
它在 Dart 侧跨库读取：只读打开老库，逐表 SELECT，事务内写新库。
不用 SQLite 的 ATTACH。
原因：便于单测，也避开 sqflite 的方言差异。

对齐键：

- media 用 path。path 在两边都有 UNIQUE 约束。
- tags 用 (namespace, name)。

导入顺序：

先导结构，顺序如下。

1. tags。
2. works。只来自 AudioShelf。
3. folders。
4. folder_paths。
5. folder_tags。

再导媒体，顺序如下。

1. media。AudioShelf 的 tracks 记为 audio，PictureViewer2 的 images 记为 image。
2. media_tags。
3. play_history。

每步都要 old_id 到 new_id 的映射表。

### 8.3 folders 的冲突处置

folders 的 UNIQUE(name, parent) 会撞。
处置：PictureViewer2 的整棵树挂到一个新建根下。

- 新建一个根文件夹，名字取「图片库」，work_id 为空。
- PictureViewer2 的顶层文件夹的 parent 改指向该根。
- AudioShelf 的文件夹树按原结构导入。
- folder_paths 与 folder_tags 的 folder_id 按映射改写。

这样两边的路径映射与文件夹标签都能保住。

### 8.4 冲突与失败处置

- 同一 path 出现在两个老库：保留先到者，写一条日志。
- media_type 与扩展名不符：按扩展名判定，写日志。
- 老库缺表或缺列：跳过该表，写日志，不中断整体迁移。
- 迁移不改老库。开始前把老库复制到 <老数据目录>/migration-backup-<时间戳>/。

### 8.5 校验

新建 tool/migrate_check.dart。
它报告并断言这些项：

- 源库的 path 集合与目标库的 path 集合相等。
- media 行数等于 tracks 行数加 images 行数。
- media_tags 行数等于 track_tags 行数加 image_tags 行数。
- 每条 media 记录的 media_type 与扩展名判定一致。
- PRAGMA integrity_check 返回 ok。

运行方式：

```bash
dart run tool/migrate_check.dart \
  --src-a "$HOME/.local/share/AudioShelf/audioshelf.db" \
  --src-b "$HOME/Documents/PictureViewer/pv2.db" \
  --dst "$HOME/.local/share/MediaShelf/mediashelf.db"
```

路径按第 8.1 节的实际值填。

## 9 视频能力（v1）

### 9.1 扩展名

视频集合放在 lib/services/file_scanner.dart。
与 AudioShelf/lib/services/file_scanner.dart:9 的音频集合并列。

```dart
const videoExtensions = {
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.m4v',
  '.flv', '.wmv', '.mpg', '.mpeg', '.ts', '.3gp',
};
```

音频集合保持 {'.mp3', '.wav'}。
图片集合保持 PictureViewer2/lib/services/file_scanner.dart:6 的 9 个扩展名。

### 9.2 类型判定

加一个函数 mediaTypeOfPath。
输入路径，返回 audio、image、video 或 null。
扫描与导入都调它。

### 9.3 卡片

- 用统一图标 Icons.movie。
- 显示文件名、格式、文件大小。
- 不显示时长，也不显示分辨率。
- 双击卡片调 VideoLauncher。
- 卡片数据来自 media 表，media_type 为 video。

### 9.4 外链接口

新建 lib/services/video_launcher.dart。

```dart
enum LaunchResult { ok, unsupportedPlatform, failed }

class VideoLauncher {
  VideoLauncher({Future<Process> Function(String, List<String>)? start})
      : _start = start ?? Process.start;

  final Future<Process> Function(String, List<String>) _start;

  Future<LaunchResult> open(String path) async {
    // 见下面的分派表
  }
}
```

分派表：

| 平台 | 命令 | 参数 |
|---|---|---|
| Windows | cmd | /c start "" <路径> |
| Linux | xdg-open | <路径> |
| 其他 | 无 | 返回 unsupportedPlatform |

要点：

- 用参数数组，不拼 shell 字符串。路径含空格或中文时安全。
- Windows 的 start 命令第一个参数是窗口标题，传空串占位。
- 返回 ok 只表示已交给系统，不代表播放结束。
- 进程启动失败时捕获 ProcessException，返回 failed。
- 失败要写日志，界面弹提示，不静默。

### 9.5 Android 预留

平台分支留一个 case，返回 unsupportedPlatform。
后续实现用 Intent.ACTION_VIEW。
MIME 类型由扩展名给出。
URI 用 FileProvider 生成。
不要用 file:// URI 直接交给外部播放器。

### 9.6 测试

新建 test/services/video_launcher_test.dart。
注入假的 start 函数。
断言命令名与参数数组。
不真起播放器。

## 10 模块映射

### 10.1 来自 PictureViewer2

| 源 | 目标 | 处置 |
|---|---|---|
| lib/db/image_dao.dart | lib/db/media_dao.dart | 与 track_dao 合并 |
| lib/db/sql_like.dart | lib/db/sql_like.dart | 直接迁入 |
| lib/db/tag_dao.dart | lib/db/tag_dao.dart | 与 AudioShelf 版合并 |
| lib/db/folder_dao.dart | lib/db/folder_dao.dart | 与 AudioShelf 版合并 |
| lib/services/thumbnail_cache.dart | 同名 | 直接迁入 |
| lib/services/exif_service.dart | 同名 | 直接迁入 |
| lib/services/import_service.dart | 同名 | 与 AudioShelf 版合并 |
| lib/services/file_scanner.dart | 同名 | 合并并加视频判定 |
| lib/services/settings_service.dart | 同名 | 与 AudioShelf 版合并 |
| lib/services/data_dir_service.dart | 同名 | 改用 AudioShelf 版为底 |
| lib/state/app_state.dart | 同名 | 作为统一状态底本 |
| lib/utils/filter_expression.dart | 同名 | 直接迁入，带深度护栏 |
| lib/utils/log_util.dart | 同名 | 两边合并为一份 |
| lib/utils/path_util.dart | 同名 | 直接迁入 |
| lib/utils/file_io.dart | 同名 | 直接迁入 |
| lib/utils/color_util.dart | 同名 | 直接迁入 |
| lib/utils/image_cache_util.dart | 同名 | 直接迁入 |
| lib/theme/catppuccin.dart | 同名 | 备选主题 |
| lib/pages/about_page.dart | 同名 | 直接迁入 |
| lib/pages/home_page.dart | 同名 | 与 AudioShelf 版合并 |
| lib/pages/settings_page.dart | 同名 | 与 AudioShelf 版合并 |
| lib/widgets/image_viewer.dart | 同名 | 直接迁入 |
| lib/widgets/image_grid.dart | 同名 | 直接迁入 |
| lib/widgets/image_detail.dart | 同名 | 直接迁入 |
| lib/widgets/folder_panel.dart | 同名 | 直接迁入 |
| lib/widgets/filter_dialog.dart | 同名 | 直接迁入 |
| lib/widgets/color_picker_dialog.dart | 同名 | 直接迁入 |
| lib/widgets/move_folder_dialog.dart | 同名 | 直接迁入 |
| lib/widgets/export_actions.dart | 同名 | 直接迁入 |
| lib/widgets/tag_picker_dialog.dart | 同名 | 直接迁入 |
| lib/widgets/tag_panel.dart | lib/widgets/tag_panel.dart | 与 AudioShelf 版合并 |
| test/ | test/ | 按目录迁入，改导入前缀 |
| scripts/build_linux.sh | 同名 | 作为底本 |
| scripts/build_windows.ps1 | 同名 | 作为底本 |
| scripts/pack_for_windows.sh | 同名 | 作为底本，删 sqlite3 下载 |
| .github/workflows/ci.yml | 同名 | 直接迁入 |
| .gitignore | 同名 | 作为底本，加 data/ 与 logs/ |

### 10.2 保留 AudioShelf

| 位置 | 处置 |
|---|---|
| lib/state/player_controller.dart | 保留 |
| lib/services/media_bridge.dart | 保留，改 MethodChannel 名前缀 |
| lib/services/subtitle_parser.dart | 保留 |
| lib/services/metadata_service.dart | 保留 |
| lib/services/cover_service.dart | 保留 |
| lib/db/work_dao.dart | 保留 |
| lib/pages/subtitle_page.dart | 保留 |
| lib/widgets/player_bar.dart | 保留 |
| lib/widgets/cover_image.dart | 保留 |
| lib/widgets/works_grid.dart | 保留 |
| lib/widgets/folder_browser.dart | 保留，与 folder_panel 对齐 |
| lib/widgets/dialogs.dart | 保留，改 file_picker 调用 |
| lib/utils/format.dart | 保留 |
| lib/theme/app_theme.dart | 保留为默认主题 |
| android/ | 保留，改包名 |
| scripts/build_android.sh | 保留 |
| scripts/build_windows_remote.sh | 保留 |
| pubspec.yaml 的 hooks 段 | 保留 |

### 10.3 丢弃

- PictureViewer2 的 ios/、macos/、web/ 目录。
- AudioShelf 的 PROJECT_LOG.md，改由新的 PROJECTLOG.md 记录。
- PictureViewer2 的 scripts/*.projectlog.md。
- 两边的 docs/ 工作稿，需要时再抄进新仓库。
- AudioShelf/lib/db/track_dao.dart 与 PictureViewer2/lib/db/image_dao.dart 合并后不再单独存在。

## 11 阶段计划

每阶段的命令都在这两行导出之后跑：

```bash
export PATH="$HOME/flutter/bin:$PATH" LD_LIBRARY_PATH="$HOME/.local/lib"
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn PUB_HOSTED_URL=https://pub.flutter-io.cn
```

### 阶段 0 建仓与改名

动作：

1. 复制 AudioShelf 到 /home/hoshi/code/MediaShelf。
2. 删掉 .git，重新 git init，分支 master。
3. 按第 3 节改名。

验收：

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

通过标准：analyze 无 error。
test 通过数不低于 72。

### 阶段 1 依赖合并

动作：按第 5 节写 pubspec.yaml。

验收：

```bash
flutter pub get
grep -A3 '^  file_picker:' pubspec.lock
grep -A3 '^  sqflite_common_ffi:' pubspec.lock
flutter analyze --no-fatal-infos
```

通过标准：file_picker 为 12.1.2。
sqflite_common_ffi 为 2.4.2+1。

### 阶段 2 数据层统一

动作：

1. 写 lib/db/tables.dart 的 v5 内容。
2. 新建 lib/db/media_dao.dart。
3. 合并 lib/db/tag_dao.dart 与 lib/db/folder_dao.dart。
4. 改 database.dart 的库文件名与 PRAGMA 写法。

验收：

```bash
flutter test test/db
```

通过标准：建库成功，PRAGMA integrity_check 返回 ok。
老 db 用例改到 media 之后全部通过。

### 阶段 3 迁移服务

动作：新建 migration_service.dart 与 tool/migrate_check.dart。

验收：

```bash
dart run tool/migrate_check.dart --src-a <老库 A> --src-b <老库 B> --dst <新库>
```

通过标准：五类检查全部通过，见第 8.5 节。

### 阶段 4 图片栈迁入

动作：按第 10.1 节迁入图片相关模块。

验收：

```bash
flutter test test/services test/utils
flutter analyze --no-fatal-infos
```

通过标准：缩略图与 EXIF 用例通过。
手动打开一张图片，缩略图与 EXIF 面板正常。

### 阶段 5 视频识别与外链

动作：

1. 加 videoExtensions 与 mediaTypeOfPath。
2. 新建 video_launcher.dart。
3. 新建 video_grid.dart 并接入卡片。
4. 写 video_launcher_test.dart。

验收：

```bash
flutter test test/services/video_launcher_test.dart
```

通过标准：假 runner 的断言通过。
Windows 与 Linux 各手动拉起一次外部播放器。

### 阶段 6 统一 AppState

动作：

1. 以 PictureViewer2/lib/state/app_state.dart 为底。
2. 并入 AudioShelf 的作品集、字幕、播放队列、选择集。
3. 删掉第 7.4 节的过渡视图。

验收：

```bash
flutter test test/state test/widget
```

通过标准：tag_filter 用例通过。
app_smoke_test 与 narrow_window_test 通过。

### 阶段 7 设置、主题与页面

动作：

1. 合并 settings_page 与 home_page。
2. 主题先用 AudioShelf/lib/theme/app_theme.dart。
3. Catppuccin 留作可选主题。

验收：

```bash
flutter analyze --no-fatal-infos
flutter test
```

通过标准：设置页能改主题与缓存上限。
切换数据目录并重启后，新目录生效。

### 阶段 8 打包与 CI

动作：迁入第 6.2 节与第 6.3 节的脚本，迁入 ci.yml。

验收：

```bash
bash scripts/build_linux.sh --mode release
ls build/linux/x64/release/bundle/
```

通过标准：bundle 目录存在，可执行文件能启动。
CI 在远端跑绿。

### 阶段 9 Android（延后）

动作：

1. 改包名与 Kotlin 目录。
2. 补 Intent 与 FileProvider 分派。
3. 验证所有文件访问权限下的扫描。

验收：

```bash
flutter build apk --release
```

通过标准：实机能扫描一个目录，能拉起外部播放器。

## 12 UI 布局（占位）

等用户给出布局后填写本节。
需要覆盖的界面：

| 界面 | 要点 |
|---|---|
| 主窗口与导航结构 | 待定 |
| 网格视图与列表视图 | 待定 |
| 左侧文件夹面板 | 待定 |
| 右侧标签面板 | 待定 |
| 底部播放条 | 待定 |
| 图片查看器 | 待定 |
| 视频卡片与播放按钮 | 待定 |
| 设置页与关于页 | 待定 |

布局常量先集中在 lib/theme/app_theme.dart。

## 13 工程约定

| 类别 | 约定 |
|---|---|
| 记录 | 应用根建 PROJECTLOG.md，只追加 |
| 记录 | 每条记录写日期、目标、动作、验证 |
| 日志 | 走统一入口 lib/utils/log_util.dart |
| 日志 | 带时间戳、级别与模块名 |
| 日志 | 关键路径打点，错误分支不静默 |
| 日志 | 敏感信息不进日志，例如完整路径里的用户名 |
| 存储 | 持久化落 <应用根>/data/，日志落 <应用根>/logs/ |
| 存储 | 路径只从 DataDirService 解析，不在各处拼路径 |
| 存储 | 支持 APP_DATA_DIR 与 APP_LOG_DIR 覆盖 |
| 存储 | data/ 与 logs/ 进 .gitignore |
| 文档 | 中文正文按 ASD-STE100 中文版写 |

## 14 已知坑

| 坑 | 依据 |
|---|---|
| Linux 构建必须 NO_XIPH_LIBS=1 | AudioShelf/scripts/build_linux.sh:17 |
| WAL 语句要用 rawQuery 执行，Android 上 execSQL 会报错 | AudioShelf/lib/db/database.dart:77；PictureViewer2/lib/db/database.dart:62 用了 execute，迁入时必须改 |
| FFI 初始化只在 Windows 与 Linux 上做 | AudioShelf/lib/db/database.dart:42 到 :45；PictureViewer2/lib/db/database.dart:28 到 :29 无条件调用，迁入时必须加平台守卫 |
| 外键开关放在 onConfigure 里 | AudioShelf/lib/db/database.dart:55 |
| 启动失败要显示错误页，避免白屏 | AudioShelf/lib/main.dart:45 到 :48 |
| 老库不要就地升级，两边版本号都是 4 但表结构不同 | 第 8 节 |
| 缩略图目录里有几万个小文件，回收放后台不阻塞启动 | PictureViewer2/lib/main.dart:30 |
| 两边的数据根不同，迁移前先读 .datadir 指针文件 | 第 8.1 节 |
| Android 外部播放器不能用 file:// URI | 第 9.5 节 |
| 文件删除时的曲目清理逻辑依赖 tracks 表名，合并后要跟着改 | AudioShelf/lib/state/app_state.dart:534 |

## 15 未决项

| 项 | 现状 | 需要用户确认 |
|---|---|---|
| UI 布局 | 未给 | 布局与交互细节 |
| 许可证 | 暂定 MIT | 是否保留 BSD 3-Clause 的署名 |
| 远端仓库 | 未定 | 所有者与仓库名 |
| 主题 | 暂用原创主题 | 还是 Catppuccin |
| Android | 首版不验收 | 何时补 |
| 数据目录 | 暂用 AudioShelf 的支持目录 | 是否统一到新目录名 |
| 设置存储 | 两边都用 settings.json | 是否改用 shared_preferences |

folder_paths.recursive 的默认值已定，取 1。
AudioShelf 的老数据按原值导入。

## 16 附录：文件行数对照

### 16.1 AudioShelf lib

| 文件 | 行数 |
|---|---|
| lib/db/database.dart | 92 |
| lib/db/folder_dao.dart | 308 |
| lib/db/tables.dart | 190 |
| lib/db/tag_dao.dart | 351 |
| lib/db/track_dao.dart | 350 |
| lib/db/work_dao.dart | 96 |
| lib/main.dart | 90 |
| lib/pages/home_page.dart | 164 |
| lib/pages/settings_page.dart | 167 |
| lib/pages/subtitle_page.dart | 283 |
| lib/services/cover_service.dart | 162 |
| lib/services/data_dir_service.dart | 163 |
| lib/services/file_scanner.dart | 137 |
| lib/services/import_service.dart | 239 |
| lib/services/media_bridge.dart | 232 |
| lib/services/metadata_service.dart | 81 |
| lib/services/settings_service.dart | 142 |
| lib/services/subtitle_parser.dart | 212 |
| lib/state/app_state.dart | 1172 |
| lib/state/player_controller.dart | 311 |
| lib/theme/app_theme.dart | 214 |
| lib/utils/filter_expression.dart | 263 |
| lib/utils/format.dart | 10 |
| lib/utils/log_util.dart | 76 |
| lib/widgets/cover_image.dart | 57 |
| lib/widgets/dialogs.dart | 308 |
| lib/widgets/folder_browser.dart | 499 |
| lib/widgets/player_bar.dart | 236 |
| lib/widgets/tag_panel.dart | 816 |
| lib/widgets/works_grid.dart | 145 |
| 合计 | 7566 |

### 16.2 PictureViewer2 lib

| 文件 | 行数 |
|---|---|
| lib/db/database.dart | 80 |
| lib/db/folder_dao.dart | 274 |
| lib/db/image_dao.dart | 516 |
| lib/db/sql_like.dart | 17 |
| lib/db/tables.dart | 119 |
| lib/db/tag_dao.dart | 386 |
| lib/main.dart | 85 |
| lib/pages/about_page.dart | 114 |
| lib/pages/home_page.dart | 728 |
| lib/pages/settings_page.dart | 562 |
| lib/services/data_dir_service.dart | 113 |
| lib/services/exif_service.dart | 273 |
| lib/services/file_scanner.dart | 77 |
| lib/services/import_service.dart | 343 |
| lib/services/settings_service.dart | 179 |
| lib/services/thumbnail_cache.dart | 339 |
| lib/state/app_state.dart | 1085 |
| lib/theme/catppuccin.dart | 195 |
| lib/utils/color_util.dart | 48 |
| lib/utils/file_io.dart | 77 |
| lib/utils/filter_expression.dart | 317 |
| lib/utils/image_cache_util.dart | 45 |
| lib/utils/log_util.dart | 83 |
| lib/utils/path_util.dart | 59 |
| lib/widgets/color_picker_dialog.dart | 427 |
| lib/widgets/export_actions.dart | 122 |
| lib/widgets/filter_dialog.dart | 244 |
| lib/widgets/folder_panel.dart | 753 |
| lib/widgets/image_detail.dart | 827 |
| lib/widgets/image_grid.dart | 388 |
| lib/widgets/image_viewer.dart | 754 |
| lib/widgets/move_folder_dialog.dart | 218 |
| lib/widgets/tag_panel.dart | 821 |
| lib/widgets/tag_picker_dialog.dart | 137 |
| 合计 | 10805 |

## 17 媒体类型判定与查找（建议）

本节补第 9.2 节的类型判定与第 7 节的查找设计。表内命中行数都是实测结果，复现方式见 PROJECTLOG.md。

### 17.1 判定分两层

第一层看扩展名，第二层看文件头魔数。v1 只做第一层。

| 层 | 做法 | 代价 |
| --- | --- | --- |
| 扩展名 | 三张集合表加一个 `mediaTypeOfPath` | 零 IO |
| 魔数 | 读前 16 字节比对签名 | 每文件一次 open |

扩展名集合的唯一来源是 `lib/services/file_scanner.dart`。扫描、导入、拖放三处都调 `mediaTypeOfPath`，不要各写一份判断。`path.toLowerCase()` 要保留，Windows 上扩展名大小写不定。

### 17.2 歧义与边界

| 输入 | 判定 | 说明 |
| --- | --- | --- |
| `a.MP4` | video | 先转小写 |
| `a.tar.gz` | null | 只取最后一段扩展名 |
| `.mp3.txt` | null | 扩展名是 txt |
| 无扩展名 | null | 不做魔数探测时返回 null |
| `.ts` | video | 与 TypeScript 源文件重名，桌面端按视频处理 |

### 17.3 分类存放

单表 `media` 加 `media_type` 列，见第 7 节。查找按列走，不要用 `path LIKE '%.mp4'`，前缀通配符用不上索引。

建议加索引：

| 索引 | 列 | 用途 |
| --- | --- | --- |
| `idx_media_type` | `media_type` | 按类型分栏与计数 |
| `idx_media_folder_type` | `folder_id, media_type` | 文件夹内按类型列 |
| `idx_media_name_lower` | `name_lower` | 文件名前缀搜索 |

`name_lower` 是冗余列，写入时存小写文件名。

### 17.4 查找

文件名前缀搜索用 `name_lower LIKE 'abc%'`，这种写法能走索引。`LIKE '%abc%'` 走不了，会全表扫。

中文子串搜索要 FTS5。系统库 3.46.1 上三种方式的实测命中行数：

| 查询 | unicode61 | trigram | LIKE |
| --- | --- | --- | --- |
| 音乐 | 0 | 0 | 1 |
| 播放器 | 0 | 1 | 1 |
| 音乐播放 | 0 | 1 | 未测 |
| avorit | 0 | 1 | 1 |
| favorite | 1 | 1 | 未测 |
| favor* | 1 | 1 | 未测 |

读法：unicode61 把连续汉字当成一个词，查询字符串比词短就不命中。trigram 支持中文子串，但查询短于三字同样不命中。`LIKE` 任何子串都能命中，代价是全表扫。

结论：中文搜索用 `tokenize='trigram'`，长度不足三字的查询交给 `LIKE`。`name_lower` 上的索引负责前缀，FTS5 表只放文件名与标签。

### 17.5 扫描一次遍历

`FileScanner._scan` 现在只返回音频、字幕、封面三样。加图片与视频时建议把结果改成按类型分组的映射，同一棵树不要遍历三遍。封面图的文件名白名单（`cover`、`folder`、`front` 等）只在音频目录里生效。

### 17.6 待验证

Android 与 Windows 上的 FTS5 可用性没验。Android 走系统 SQLite，版本随设备。建议启动时探测一次：建一张 FTS5 临时表，失败就退回 `LIKE`。
