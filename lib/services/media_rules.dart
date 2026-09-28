/// 媒体类型白名单与路径归一化的唯一来源（BUILD_GUIDE 第 9.2、20.3 节）。
///
/// 扫描、导入、迁移与校验工具都从这里取规则，扩展名集合不许在别处再写一份。
/// 这个文件不依赖 Flutter，`dart run tool/migrate_check.dart` 才能跑纯 Dart 入口。
library;

/// 支持的音频格式
const audioExtensions = {
  '.mp3',
  '.wav',
  '.flac',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
};

/// 支持的图片格式
const imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.bmp',
  '.webp',
  '.tiff',
  '.tif',
  '.ico',
  '.heic',
  '.avif',
};

/// 支持的视频格式
const videoExtensions = {
  '.mp4',
  '.mkv',
  '.avi',
  '.mov',
  '.webm',
  '.m4v',
  '.flv',
  '.wmv',
  '.mpg',
  '.mpeg',
  '.ts',
  '.3gp',
};

/// 现在能解析的字幕格式
const subtitleExtensions = {'.vtt', '.srt', '.lrc'};

bool isAudioFile(String path) => _hasAny(path, audioExtensions);

bool isImageFile(String path) => _hasAny(path, imageExtensions);

bool isVideoFile(String path) => _hasAny(path, videoExtensions);

bool isSubtitleFile(String path) => _hasAny(path, subtitleExtensions);

/// 按扩展名判定媒体类型，返回 `audio` / `image` / `video`，认不出返回 null。
///
/// 字幕不在返回值里：扫描侧用 [isSubtitleFile] 判断，媒体类型四值里的
/// `subtitle` 由字幕模块显式写入（BUILD_GUIDE 第 23 节）。
String? mediaTypeOfPath(String path) {
  if (isAudioFile(path)) return 'audio';
  if (isImageFile(path)) return 'image';
  if (isVideoFile(path)) return 'video';
  return null;
}

/// 取小写扩展名（含点）。没有扩展名或点在目录名里时返回空串。
///
/// `a` 与 `.gitignore` 返回空串，`a.tar.gz` 返回 `.gz`。
String extOfPath(String path) {
  final slash = path.lastIndexOf(RegExp(r'[\\/]'));
  final dot = path.lastIndexOf('.');
  if (dot <= slash + 1) return '';
  return path.substring(dot).toLowerCase();
}

/// 归一化路径，供 `media.name_lower` 模糊匹配用。
String nameLowerOfPath(String path) => path.toLowerCase();

bool _hasAny(String path, Set<String> exts) {
  final lower = path.toLowerCase();
  return exts.any((e) => lower.endsWith(e));
}
