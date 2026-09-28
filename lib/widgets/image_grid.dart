import 'dart:async';
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
import '../utils/latest_only_runner.dart';
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
  int _loadedRevision = -1;

  /// 已经在哪个上下文触发过后台缩略图补齐（`<库>:<文件夹id>:<作品id>`）
  String? _warmedThumbKey;

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

  /// 单条媒体的标签增删（图片/视频磁贴右上角 ⋮ 菜单）。
  ///
  /// [add] 为 false 时先取这条媒体已有的标签收窄候选，免得让用户从全库标签里
  /// 挑一个根本不在这张图上的来「移除」。
  Future<void> _editMediaTags(
    AppState appState,
    MediaItem item, {
    required bool add,
  }) async {
    final id = item.id;
    if (id == null || !mounted) return;
    final what = _isVideo ? '这个视频' : '这张图';
    Set<int>? current;
    if (!add) {
      current = await appState.getTagIdsOnMedia([id]);
      if (!mounted) return;
      if (current.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$what还没有标签')));
        return;
      }
    }
    final tags = await showTagPickerDialog(
      context,
      title: add ? '添加标签' : '移除标签',
      filterTagIds: current,
    );
    if (tags == null || tags.isEmpty || !mounted) return;
    if (add) {
      await appState.addTagsToMedia([id], tags);
    } else {
      await appState.removeTagsFromMedia([id], tags);
    }
  }

  /// 作品层的媒体行自己查：`FolderDao.getPathsByWork` 拿作品的目录，
  /// 再按库的类型取这些目录里的直接媒体（与 `playWorkExternal` 同一套取法）。
  ///
  /// [sort] 是 AppState 当前视觉库的排序比较器：默认的自然序让 `第2话` 排在
  /// `第10话` 前面（按文件名字符串比会把 10 排到 2 前面）。
  Future<void> _loadWorkItems(
      int workId, int Function(MediaItem, MediaItem) sort) async {
    final key = '${widget.library}:$workId';
    try {
      final dirs =
          await FolderDao(DatabaseManager.instance.db).getPathsByWork(workId);
      final rows = dirs.isEmpty
          ? <MediaItem>[]
          : await MediaDao(DatabaseManager.instance.db)
              .queryByDirs(dirs, type: _mediaType);
      final items = [...rows]..sort(sort);
      if (!mounted || _loadedKey != key) return;
      setState(() => _workItems = items);
    } catch (e) {
      logDebug('Grid', 'load work items failed (work=$workId): $e');
      if (!mounted || _loadedKey != key) return;
      setState(() => _workItems = const []);
    }
  }

  /// 根据修饰键决定选择行为：Shift=区间、Ctrl=切换、否则单选
  ///
  /// 多选模式下没有修饰键的单击也当作勾选，长按磁贴会先进多选模式。
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
    } else if (appState.visualSelectionMode) {
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
    final revision = appState.mediaRevision;
    if (key != _loadedKey || revision != _loadedRevision) {
      _loadedKey = key;
      _loadedRevision = revision;
      _workItems = null;
      if (key != null) {
        final workId = work!.id!;
        final sort = appState.visualSortComparator;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadWorkItems(workId, sort);
        });
      }
    }

    final images = atFolderLevel || searching
        ? appState.images
        : (_workItems ?? const <MediaItem>[]);
    // 作品层这里自己查媒体行，AppState 那一层只有文件夹：把当前真正画出来的
    // 媒体行登记回去，「全选」「Shift 区间选」和图片详情才有据可依。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) appState.reportVisibleMedia(images);
    });
    // 老库（1.3.0 之前导入的图片）磁盘上没有缩略图：进到某个上下文时补一次，
    // 免得用户以为「必须重启才有图」。按上下文只触发一次，生成走 AppState 的
    // 后台队列，卡片自己也会按需生成，两边都命中磁盘则直接返回。
    final warmKey = '${widget.library}:${appState.currentFolderId}:${work?.id}';
    if (images.isNotEmpty && _warmedThumbKey != warmKey) {
      _warmedThumbKey = warmKey;
      unawaited(appState.backfillThumbnails(images.map((i) => i.path)));
    }

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
            onLongPress: () => appState.enterVisualSelectionMode(img.id),
            onPlayExternal: () => _playExternal(appState),
            onEditTags: () => _editVideoTags(appState, img),
            onRemoveTags: () => _editMediaTags(appState, img, add: false),
          );
        }
        return _ThumbnailCard(
          key: ValueKey('image-tile-${img.id}'),
          image: img,
          selected: appState.isSelected(img.id ?? -1),
          onTap: () => _handleImageTap(appState, img.id!),
          onDoubleTap: () => _openViewer(appState, images, i - folders.length),
          onLongPress: () => appState.enterVisualSelectionMode(img.id),
          compact: true,
          cacheEpoch: appState.thumbEpoch,
          onEditTags: () => _editMediaTags(appState, img, add: true),
          onRemoveTags: () => _editMediaTags(appState, img, add: false),
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
            onLongPress: () => appState.enterVisualSelectionMode(img.id),
            onPlayExternal: () => _playExternal(appState),
            onEditTags: () => _editVideoTags(appState, img),
            onRemoveTags: () => _editMediaTags(appState, img, add: false),
          );
        }
        return _ThumbnailCard(
          key: ValueKey('image-tile-${img.id}'),
          image: img,
          selected: appState.isSelected(img.id ?? -1),
          onTap: () => _handleImageTap(appState, img.id!),
          onDoubleTap: () => _openViewer(appState, images, i - folders.length),
          onLongPress: () => appState.enterVisualSelectionMode(img.id),
          compact: false,
          cacheEpoch: appState.thumbEpoch,
          onEditTags: () => _editMediaTags(appState, img, add: true),
          onRemoveTags: () => _editMediaTags(appState, img, add: false),
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
           Icon(Icons.folder_open, size: 64, color: AppColors.mutedOf(context)),
          const SizedBox(height: 16),
          Text(_isVideo ? '这里还没有视频' : '这里还没有内容',
              style:  TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(_isVideo ? '添加文件夹或拖拽视频开始导入' : '添加文件夹或拖拽图片开始导入',
              style:  TextStyle(color: AppColors.mutedOf(context), fontSize: 12)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const ValueKey('grid-empty-add-folder'),
            onPressed: () => _pickFolder(context, appState),
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: const Text('添加文件夹'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side:  BorderSide(color: AppColors.surfaceAltOf(context)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: const ValueKey('grid-empty-batch-import'),
            onPressed: () => _pickBatchFolder(context, appState),
            icon: const Icon(Icons.library_add_outlined, size: 16),
            label: const Text(
              '批量导入：每个子文件夹一个作品',
              style: TextStyle(fontSize: 12),
            ),
            style: TextButton.styleFrom(foregroundColor: AppColors.teal),
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

  /// 批量导入：选父目录，里面的每个子文件夹各建一个作品。
  Future<void> _pickBatchFolder(BuildContext context, AppState appState) async {
    if (!await ensureScanAccessOrPrompt(context)) return;
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: _isVideo ? '选择父文件夹（每个子文件夹一个视频作品）' : '选择父文件夹（每个子文件夹一个图片作品）',
    );
    if (result == null || result.isEmpty || !context.mounted) return;
    final created = await appState.importSubdirectoriesAsWorks(
      result,
      library: widget.library,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created > 0 ? '批量导入完成：新建 $created 个作品' : '没有发现可导入的子文件夹（或里面的媒体都已在库里）',
        ),
      ),
    );
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
            color: AppColors.surfaceOf(context),
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
                    style:  TextStyle(fontSize: 11, color: AppColors.textPrimaryOf(context)),
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
          style:  TextStyle(fontSize: 13, color: AppColors.textPrimaryOf(context))),
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
  final VoidCallback? onLongPress;
  final bool compact;

  /// 缩略图缓存被清空时会自增；卡片靠它重新生成缩略图
  final int cacheEpoch;

  /// 右上角 ⋮ 菜单：添加/移除这条媒体的标签
  final VoidCallback onEditTags;
  final VoidCallback onRemoveTags;

  const _ThumbnailCard({
    super.key,
    required this.image,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    this.onLongPress,
    required this.compact,
    required this.cacheEpoch,
    required this.onEditTags,
    required this.onRemoveTags,
  });

  @override
  State<_ThumbnailCard> createState() => _ThumbnailCardState();
}

class _ThumbnailCardState extends State<_ThumbnailCard> {
  bool _thumbReady = false;

  /// 缩略图文件是否还没生成。由 [_checkAndGenerate] 异步确认，
  /// build 里不再做任何文件系统调用。
  bool _thumbMissing = true;

  /// 生成串行器：同一时刻只解码一张，跑的过程中换了图就在收尾时补跑一次。
  /// 早先用一个布尔量直接 return，换图时新请求被丢掉，磁贴会一直空着。
  final LatestOnlyRunner _runner = LatestOnlyRunner();

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

  Future<void> _checkAndGenerate() => _runner.run(_generateOnce);

  Future<void> _generateOnce() async {
    final path = widget.image.path;
    // thumbPath 内部要 stat 源文件拿 mtime，所以只在异步路径上算。
    // 放在 try 里：缓存目录没准备好时也要落成「没有缩略图」，
    // 不能让异常从 initState 发起的 Future 里逃出去。
    File? thumbFile;
    try {
      thumbFile = File(ThumbnailService.instance.thumbPath(path, size: 300));
      if (!await thumbFile.exists()) {
        await ThumbnailService.instance.ensureThumbnail(path, size: 300);
      }
      // 等的这段时间里卡片可能已经被复用给另一张图（`didUpdateWidget` 已经把
      // 状态退回「没缩略图」并登记了重跑），旧图的结果不能盖上去。
      if (!mounted || widget.image.path != path) return;
      setState(() {
        _thumbFile = thumbFile;
        _thumbMissing = false;
        _thumbReady = true;
      });
    } catch (e) {
      logDebug('Grid', 'Thumbnail generate failed: $path ($e)');
      if (!mounted || widget.image.path != path) return;
      setState(() {
        _thumbFile = thumbFile;
        _thumbReady = false;
      });
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
        onLongPress: widget.onLongPress,
        child: Container(
          color: widget.selected ? AppColors.surfaceOf(context) : null,
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
                        style:  TextStyle(fontSize: 13, color: AppColors.textPrimaryOf(context))),
                    if (widget.image.alias != null)
                      Text(widget.image.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:  TextStyle(fontSize: 10, color: AppColors.mutedOf(context))),
                  ],
                ),
              ),
              _tagsMenu(onDark: false),
            ],
          ),
        ),
      );
    }

    // 网格卡片
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
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
              top: 0,
              right: 0,
              child: Material(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(4),
                child: _tagsMenu(onDark: true),
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

  Widget _placeholder() {
    return  Center(
      child: Icon(Icons.image_outlined, color: AppColors.mutedOf(context), size: 32),
    );
  }

  /// 图片磁贴的 ⋮ 菜单：以前图片只有双击看图，标签只能在多选栏里整批改，
  /// 单张图想补一个标签没有入口。
  Widget _tagsMenu({required bool onDark}) {
    return PopupMenuButton<String>(
      key: ValueKey('image-menu-${widget.image.id}'),
      icon: Icon(
        Icons.more_vert,
        size: 14,
        color: onDark ? Colors.white : AppColors.mutedOf(context),
      ),
      tooltip: '图片操作',
      padding: EdgeInsets.zero,
      // 小磁贴（手机上是 80~90 像素见方）容不下 M3 默认的 48 见方触摸区，
      // 否则 ⋮ 会盖住大半个磁贴、把单击和长按都吃掉。
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(26),
        maximumSize: const Size.square(26),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      onSelected: (v) =>
          v == 'tags' ? widget.onEditTags() : widget.onRemoveTags(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'tags',
          child: Text('标签...', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'untag',
          child: Text('移除标签...', style: TextStyle(fontSize: 13)),
        ),
      ],
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
  final VoidCallback? onLongPress;
  final VoidCallback onPlayExternal;
  final VoidCallback onEditTags;
  final VoidCallback onRemoveTags;

  const _VideoTile({
    super.key,
    required this.video,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.onDoubleTap,
    this.onLongPress,
    required this.onPlayExternal,
    required this.onEditTags,
    required this.onRemoveTags,
  });

  String get _displayName => video.alias ?? video.filename;

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return InkWell(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: Container(
          color: selected ? AppColors.surfaceOf(context) : null,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.movie, size: 22, color: AppColors.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(
                        fontSize: 13, color: AppColors.textPrimaryOf(context))),
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
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
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
                    switch (v) {
                      case 'tags':
                        onEditTags();
                      case 'untag':
                        onRemoveTags();
                      default:
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
                    PopupMenuItem(
                      key: ValueKey('video-untag-menu-${video.id}'),
                      value: 'untag',
                      child: const Text(
                        '移除标签...',
                        style: TextStyle(fontSize: 13),
                      ),
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
