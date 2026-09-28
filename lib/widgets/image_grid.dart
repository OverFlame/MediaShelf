import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../db/database.dart';
import '../db/folder_dao.dart';
import '../db/media_dao.dart';
import '../services/thumbnail_cache.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/log_util.dart';
import 'launch_result_snack.dart';
import 'scan_access_snack.dart';
import 'tag_picker_dialog.dart';

/// 中间栏：资源管理器式浏览（子文件夹 + 直接媒体），支持网格/列表视图与多选。
///
/// [library] 决定这一栏展示哪个库：
/// - `image`（默认）：文件夹层直接用 `AppState.images`（图片库由 AppState 装填）；
///   作品层（进了作品但还没进文件夹）AppState 只装填虚拟文件夹，这里自己补一次
///   按作品的媒体查询。
/// - `video`：文件夹层与搜索由 AppState 按 `MediaType.video` 装填。视频卡片用
///   `Icons.movie` 与文件名，不做应用内解码；双击或卡片菜单走
///   `AppState.playFolderExternal` / `playWorkExternal`。
///
/// 图片库的既有语义保持不变：`ValueKey('image-tile-$id')`、`ValueKey('folder-tile-$id')`
/// 与单击/Ctrl/Shift/双击行为都不动。
class ImageGrid extends StatefulWidget {
  final String library;

  const ImageGrid({super.key, this.library = 'image'});

  @override
  State<ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<ImageGrid> {
  /// 作品层自己查出来的媒体行：null = 还没查，空列表 = 查过确实没有
  List<MediaItem>? _workItems;

  /// 已加载数据的归属签名（`<库>:<作品id>`）；作品或库一变就重新查
  String? _loadedKey;

  bool get _isVideo => widget.library == 'video';

  MediaType get _mediaType => _isVideo ? MediaType.video : MediaType.image;

  void _openViewer(AppState appState, List<MediaItem> images, int index) {
    if (images.isEmpty) return;
    logInfo('Grid', 'Opening viewer at index $index (${images.length} images)');
    appState.openViewer(images, index);
  }

  /// 视频：把播放交给已有的外链通道（在文件夹里播这个文件夹，否则播整个作品）
  Future<void> _playExternal(AppState appState) async {
    final folderId = appState.currentFolderId;
    final workId = appState.currentWork?.id;
    if (folderId == null && workId == null) return;
    final result = folderId != null
        ? await appState.playFolderExternal(folderId)
        : await appState.playWorkExternal(workId!);
    if (mounted) showLaunchResult(context, result);
  }

  /// 视频卡片的「标签...」：勾选状态为当前已绑定标签，确认后整集覆盖。
  Future<void> _editVideoTags(AppState appState, MediaItem video) async {
    final id = video.id;
    if (id == null) return;
    final existing = (await appState.getTagsForMedia(id))
        .map((t) => t.id)
        .whereType<int>()
        .toSet();
    if (!mounted) return;
    final tags = await showTagPickerDialog(
      context,
      title: '为视频选择标签',
      selectedTagIds: existing,
    );
    if (tags == null) return;
    await appState.setMediaTags(id, tags);
  }

  /// 作品层的媒体行自己查：`FolderDao.getPathsByWork` 拿作品的目录，
  /// 再按库的类型取这些目录里的直接媒体（与 `playWorkExternal` 同一套取法）。
  Future<void> _loadWorkItems(int workId) async {
    final key = '${widget.library}:$workId';
    try {
      final dirs =
          await FolderDao(DatabaseManager.instance.db).getPathsByWork(workId);
      final rows = dirs.isEmpty
          ? <MediaItem>[]
          : await MediaDao(DatabaseManager.instance.db)
              .queryByDirs(dirs, type: _mediaType);
      final items = [...rows]..sort((a, b) => a.filename.compareTo(b.filename));
      if (!mounted || _loadedKey != key) return;
      setState(() => _workItems = items);
    } catch (e) {
      logDebug('Grid', 'load work items failed (work=$workId): $e');
      if (!mounted || _loadedKey != key) return;
      setState(() => _workItems = const []);
    }
  }

  /// 根据修饰键决定选择行为：Shift=区间、Ctrl=切换、否则单选
  void _handleImageTap(AppState appState, int id) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift = keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final ctrl = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight);
    if (shift) {
      appState.rangeSelect(id);
    } else if (ctrl) {
      appState.toggleSelect(id);
    } else {
      appState.selectImage(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final folders = appState.centerFolders;
    final work = appState.currentWork;
    final atFolderLevel = appState.currentFolderId != null;

    // 作品层：换作品或换库就丢掉缓存并排到下一帧重查（build 里不能 setState）。
    // 搜索生效时 AppState 已经把命中结果装进 images，这里不再自己查。
    final searching = appState.searchQuery.trim().isNotEmpty;
    final key = work == null || atFolderLevel || searching
        ? null
        : '${widget.library}:${work.id}';
    if (key != _loadedKey) {
      _loadedKey = key;
      _workItems = null;
      if (key != null) {
        final workId = work!.id!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadWorkItems(workId);
        });
      }
    }

    final images = atFolderLevel || searching
        ? appState.images
        : (_workItems ?? const <MediaItem>[]);
    final loading = appState.loading || (key != null && _workItems == null);

    if (!loading && folders.isEmpty && images.isEmpty) {
      return _buildEmptyState(context);
    }
    if (loading && folders.isEmpty && images.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
      );
    }

    if (appState.viewMode == 'list') {
      return _buildList(appState, folders, images);
    }
    return _buildGrid(appState, folders, images);
  }

  // ── 网格 ──
  Widget _buildGrid(AppState appState, List<VirtualFolder> folders,
      List<MediaItem> images) {
    final total = folders.length + images.length;
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: appState.gridColumns,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: total,
      itemBuilder: (ctx, i) {
        if (i < folders.length) {
          return _FolderTile(
            key: ValueKey('folder-tile-${folders[i].id}'),
            folder: folders[i],
            compact: true,
          );
        }
        final img = images[i - folders.length];
        if (_isVideo) {
          return _VideoTile(
            key: ValueKey('video-tile-${img.id}'),
            video: img,
            selected: appState.isSelected(img.id ?? -1),
            compact: true,
            onTap: () => _handleImageTap(appState, img.id!),
            onDoubleTap: () => _playExternal(appState),
            onPlayExternal: () => _playExternal(appState),
            onEditTags: () => _editVideoTags(appState, img),
          );
        }
        return _ThumbnailCard(
          key: ValueKey('image-tile-${img.id}'),
          image: img,
          selected: appState.isSelected(img.id ?? -1),
          onTap: () => _handleImageTap(appState, img.id!),
          onDoubleTap: () => _openViewer(appState, images, i - folders.length),
          compact: true,
          cacheEpoch: appState.thumbEpoch,
        );
      },
    );
  }

  // ── 列表 ──
  Widget _buildList(AppState appState, List<VirtualFolder> folders,
      List<MediaItem> images) {
    final total = folders.length + images.length;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: total,
      itemBuilder: (ctx, i) {
        if (i < folders.length) {
          return _FolderTile(
            key: ValueKey('folder-tile-${folders[i].id}'),
            folder: folders[i],
            compact: false,
          );
        }
        final img = images[i - folders.length];
        if (_isVideo) {
          return _VideoTile(
            key: ValueKey('video-tile-${img.id}'),
            video: img,
            selected: appState.isSelected(img.id ?? -1),
            compact: false,
            onTap: () => _handleImageTap(appState, img.id!),
            onDoubleTap: () => _playExternal(appState),
            onPlayExternal: () => _playExternal(appState),
            onEditTags: () => _editVideoTags(appState, img),
          );
        }
        return _ThumbnailCard(
          key: ValueKey('image-tile-${img.id}'),
          image: img,
          selected: appState.isSelected(img.id ?? -1),
          onTap: () => _handleImageTap(appState, img.id!),
          onDoubleTap: () => _openViewer(appState, images, i - folders.length),
          compact: false,
          cacheEpoch: appState.thumbEpoch,
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final appState = context.read<AppState>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, size: 64, color: AppColors.muted),
          const SizedBox(height: 16),
          Text(_isVideo ? '这里还没有视频' : '这里还没有内容',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(_isVideo ? '添加文件夹或拖拽视频开始导入' : '添加文件夹或拖拽图片开始导入',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const ValueKey('grid-empty-add-folder'),
            onPressed: () => _pickFolder(context, appState),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('添加文件夹'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: const BorderSide(color: AppColors.surfaceAlt),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder(BuildContext context, AppState appState) async {
    if (!await ensureScanAccessOrPrompt(context)) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: _isVideo ? '选择包含视频的文件夹' : '选择包含图片的文件夹',
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      await appState.importDirectory(result, library: widget.library);
    }
  }
}

/// 文件夹瓦片（网格/列表）
class _FolderTile extends StatelessWidget {
  final VirtualFolder folder;
  final bool compact;

  const _FolderTile({super.key, required this.folder, required this.compact});

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    if (compact) {
      return GestureDetector(
        onTap: () => appState.enterFolder(folder.id!),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 格子小（列数多或中间区窄）时图标跟着缩，避免溢出
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Icon(Icons.folder, size: 44, color: AppColors.warning),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.folder, size: 22, color: AppColors.warning),
      title: Text(folder.name,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      onTap: () => appState.enterFolder(folder.id!),
    );
  }
}

/// 图片卡片（网格/列表），懒加载缩略图，支持多选高亮
class _ThumbnailCard extends StatefulWidget {
  final MediaItem image;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final bool compact;

  /// 缩略图缓存被清空时会自增；卡片靠它重新生成缩略图
  final int cacheEpoch;

  const _ThumbnailCard({
    super.key,
    required this.image,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    required this.compact,
    required this.cacheEpoch,
  });

  @override
  State<_ThumbnailCard> createState() => _ThumbnailCardState();
}

class _ThumbnailCardState extends State<_ThumbnailCard> {
  bool _thumbReady = false;

  /// 缩略图文件是否还没生成。由 [_checkAndGenerate] 异步确认，
  /// build 里不再做任何文件系统调用。
  bool _thumbMissing = true;

  /// 生成中的标记，避免 build 触发和 initState 触发撞在一起重复解码
  bool _generating = false;

  /// 计算好的缩略图文件（路径要 stat 源文件拿 mtime，
  /// 所以只在异步路径上算，build 里不碰文件系统）
  File? _thumbFile;

  @override
  void initState() {
    super.initState();
    _checkAndGenerate();
  }

  @override
  void didUpdateWidget(_ThumbnailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image.path != widget.image.path ||
        oldWidget.cacheEpoch != widget.cacheEpoch) {
      _thumbReady = false;
      _thumbMissing = true;
      _checkAndGenerate();
    }
  }

  Future<void> _checkAndGenerate() async {
    if (_generating) return;
    _generating = true;
    final path = widget.image.path;
    // thumbPath 内部要 stat 源文件拿 mtime，所以只在异步路径上算
    final thumbPath = ThumbnailService.instance.thumbPath(path, size: 300);
    final thumbFile = File(thumbPath);
    try {
      if (!await thumbFile.exists()) {
        await ThumbnailService.instance.ensureThumbnail(path, size: 300);
      }
      if (mounted) {
        setState(() {
          _thumbFile = thumbFile;
          _thumbMissing = false;
          _thumbReady = true;
        });
      }
    } catch (e) {
      logDebug('Grid', 'Thumbnail generate failed: $path ($e)');
      if (mounted) {
        setState(() {
          _thumbFile = thumbFile;
          _thumbReady = false;
        });
      }
    } finally {
      _generating = false;
    }
  }

  String get _displayName => widget.image.alias ?? widget.image.filename;

  @override
  Widget build(BuildContext context) {
    // build 里不做 IO：路径、存在性都由 _checkAndGenerate 异步落进 State
    final thumbFile = _thumbFile;
    final canShowThumb = thumbFile != null && _thumbReady && !_thumbMissing;

    if (!widget.compact) {
      // 列表行
      return InkWell(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        child: Container(
          color: widget.selected ? AppColors.surface : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: canShowThumb
                    ? Image.file(thumbFile, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _placeholder())
                    : _placeholder(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    if (widget.image.alias != null)
                      Text(widget.image.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 网格卡片
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: widget.selected ? AppColors.accent : Colors.transparent,
            width: widget.selected ? 2 : 0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (canShowThumb)
              Image.file(thumbFile, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholder())
            else
              _placeholder(),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return const Center(
      child: Icon(Icons.image_outlined, color: AppColors.muted, size: 32),
    );
  }
}

/// 视频卡片（网格/列表）：只画图标与文件名，不做应用内解码。
/// 双击或右上角菜单调用 [onPlayExternal]（AppState 的外链播放通道）。
class _VideoTile extends StatelessWidget {
  final MediaItem video;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onPlayExternal;
  final VoidCallback onEditTags;

  const _VideoTile({
    super.key,
    required this.video,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onDoubleTap,
    required this.onPlayExternal,
    required this.onEditTags,
  });

  String get _displayName => video.alias ?? video.filename;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          color: selected ? AppColors.surface : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.movie, size: 22, color: AppColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textPrimary)),
              ),
              IconButton(
                key: ValueKey('video-tags-${video.id}'),
                icon: const Icon(Icons.label_outline, size: 18),
                tooltip: '标签...',
                onPressed: onEditTags,
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_outline, size: 18),
                tooltip: '用外部播放器播放',
                onPressed: onPlayExternal,
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: selected ? 2 : 0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(
              child: Icon(Icons.movie, color: AppColors.blue, size: 40),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(4),
                child: PopupMenuButton<String>(
                  key: ValueKey('video-menu-${video.id}'),
                  icon: const Icon(Icons.more_vert, size: 14, color: Colors.white),
                  tooltip: '视频操作',
                  padding: EdgeInsets.zero,
                  onSelected: (v) {
                    if (v == 'tags') {
                      onEditTags();
                    } else {
                      onPlayExternal();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'playExternal',
                      child: Text('用外部播放器播放',
                          style: TextStyle(fontSize: 13)),
                    ),
                    PopupMenuItem(
                      key: ValueKey('video-tags-menu-${video.id}'),
                      value: 'tags',
                      child: const Text('标签...',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                color: Colors.black54,
                child: Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
