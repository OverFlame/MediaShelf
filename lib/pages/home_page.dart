import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/thumbnail_cache.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/dialogs.dart' show confirmDialog;
import '../widgets/filter_dialog.dart';
import '../widgets/folder_browser.dart';
import '../widgets/folder_panel.dart';
import '../widgets/image_detail.dart';
import '../widgets/image_grid.dart';
import '../widgets/image_viewer.dart';
import '../widgets/player_bar.dart';
import '../widgets/tag_panel.dart';
import '../widgets/tag_picker_dialog.dart';
import '../widgets/works_grid.dart';
import 'settings_page.dart';

/// 音频库的库名。图片、视频库的常量在 `folder_panel.dart` 里（与 `folders.library`
/// 和 `media.media_type` 同一套取值），这里 import 过来复用。
const String kAudioLibrary = 'audio';

/// 主页面：顶部先选库（音频 / 图片 / 视频），再渲染该库的面板。
/// - 宽屏（>=720）：左侧面板 + 中间内容（图片库还能展开右侧详情面板）
/// - 窄屏（手机）：抽屉（汉堡菜单）+ 中间内容
///
/// 音频库沿用合并前的布局与行为（作品网格 + 文件夹树 + 播放条）；
/// 图片、视频库换成 `FolderPanel` + `ImageGrid` 这套资源管理器式界面。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 当前库：`audio` / `image` / `video`
  String _library = kAudioLibrary;

  /// 图片库右侧详情面板是否展开（窄屏改成推一个页面）
  bool _detailOpen = false;

  bool get _isVisual => _library != kAudioLibrary;

  Future<void> _switchLibrary(String lib) async {
    if (lib == _library) return;
    final appState = context.read<AppState>();
    setState(() => _library = lib);
    // 换库必须丢掉上一个库的导航位置，否则中间区会拿着另一个库的 currentWork
    await appState.goHome();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isWide = MediaQuery.of(context).size.width >= 720;
    final showSearch = _library != kVideoLibrary;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: isWide || !showSearch
                ? const Text('MediaShelf',
                    style: TextStyle(fontWeight: FontWeight.bold))
                : _searchField(appState),
            actions: [
              if (isWide && showSearch)
                SizedBox(width: 220, child: _searchField(appState)),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: _LibrarySwitcher(
                current: _library,
                onSelect: _switchLibrary,
              ),
            ),
          ),
          drawer: isWide ? null : _buildDrawer(),
          body: isWide
              ? Row(
                  children: [
                    Container(
                      width: 260,
                      color: AppColors.panelOf(context),
                      child: _buildLeftPanel(),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildCenter(appState, isWide)),
                  ],
                )
              : _buildCenter(appState, isWide),
          bottomNavigationBar: const PlayerBar(),
        ),
        // 查看器是覆盖层：双击图片磁贴后由 ImageGrid -> AppState.openViewer 打开
        if (_isVisual && appState.showViewer) ImageViewer(state: appState),
      ],
    );
  }

  // ── 左栏：音频库是标签面板，图片/视频库是文件夹面板 ──
  Widget _buildLeftPanel() {
    switch (_library) {
      case kImageLibrary:
        return const FolderPanel(library: kImageLibrary);
      case kVideoLibrary:
        return const FolderPanel(library: kVideoLibrary);
      default:
        return const TagPanel();
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      width: 290,
      child: SafeArea(
        child: Builder(
          builder: (drawerCtx) => _library == kAudioLibrary
              ? TagPanel(onNavigate: () => Navigator.of(drawerCtx).pop())
              : _buildLeftPanel(),
        ),
      ),
    );
  }

  // ── 中间区域：按库分派 ──
  Widget _buildCenter(AppState appState, bool isWide) {
    if (_library == kAudioLibrary) {
      if (appState.loading) {
        return const Center(
            child: CircularProgressIndicator(color: AppColors.accent));
      }
      return appState.currentWork == null
          ? Column(
              children: [
                if (appState.recentTracks.isNotEmpty)
                  _RecentBar(appState: appState),
                const Expanded(child: WorksGrid(library: 'audio')),
              ],
            )
          : const FolderBrowser();
    }

    final centerColumn = Column(
      children: [
        _VisualToolbar(
          library: _library,
          detailOpen: _detailOpen,
          onToggleDetail: () => _openDetail(context, isWide),
        ),
        const Divider(height: 1),
        if (appState.currentFolder != null) const _BreadcrumbBar(),
        if (appState.hasAdvancedFilter) const _AdvancedFilterBar(),
        if (appState.selectedIds.isNotEmpty)
          _SelectionBar(library: _library),
        Expanded(
          child: appState.currentWork == null
              ? WorksGrid(library: _library)
              : ImageGrid(library: _library),
        ),
      ],
    );

    if (_library != kImageLibrary || !_detailOpen || !isWide) {
      return centerColumn;
    }
    return Row(
      children: [
        Expanded(child: centerColumn),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 320,
          child: Container(
            color: AppColors.panelOf(context),
            child: const ImageDetail(),
          ),
        ),
      ],
    );
  }

  /// 详情入口：宽屏开右侧面板（可收），窄屏推一个独立页面
  void _openDetail(BuildContext context, bool isWide) {
    if (!isWide) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('图片详情')),
            body: const ImageDetail(),
          ),
        ),
      );
      return;
    }
    setState(() => _detailOpen = !_detailOpen);
  }

  Widget _searchField(AppState appState) {
    final hint = switch (_library) {
      kImageLibrary => '搜索图片...',
      kVideoLibrary => '搜索视频...',
      _ => '搜索曲目...',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: appState.setSearchQuery,
      ),
    );
  }
}

/// 顶部库切换条：音频 / 图片 / 视频，当前库高亮 + 下划线
class _LibrarySwitcher extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelect;

  const _LibrarySwitcher({required this.current, required this.onSelect});

  static const List<({String id, String label, IconData icon})> _tabs = [
    (id: kAudioLibrary, label: '音频', icon: Icons.library_music_outlined),
    (id: kImageLibrary, label: '图片', icon: Icons.photo_outlined),
    (id: kVideoLibrary, label: '视频', icon: Icons.movie_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (final tab in _tabs)
            Expanded(
              child: InkWell(
                key: ValueKey('library-tab-${tab.id}'),
                onTap: () => onSelect(tab.id),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: current == tab.id
                            ? AppColors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        tab.icon,
                        size: 16,
                        color: current == tab.id
                            ? AppColors.accent
                            : AppColors.mutedLightOf(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: current == tab.id
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: current == tab.id
                              ? AppColors.accent
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 图片/视频库的工具条：网格列数、视图模式、多选、标签筛选、高级筛选、
/// 刷新、清理缩略图缓存、图片详情开关。
///
/// 标签筛选入口图片库与视频库都有：标签查询按 `MediaType` 分型之后，
/// 视频同样能走 `media_tags`。
class _VisualToolbar extends StatelessWidget {
  final String library;
  final bool detailOpen;
  final VoidCallback onToggleDetail;

  const _VisualToolbar({
    required this.library,
    required this.detailOpen,
    required this.onToggleDetail,
  });

  bool get _isImage => library == kImageLibrary;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 中间区被左栏和详情面板挤窄时，尾部按钮收进「更多」菜单，
          // 否则 Row 会 RenderFlex overflow（800 宽窗口 + 详情面板时只剩约 220）。
          final compact = constraints.maxWidth < 430;
          return Row(
            children: [
              const SizedBox(width: 4),
              PopupMenuButton<int>(
                key: ValueKey('$library-toolbar-columns'),
                tooltip: '网格列数',
                icon: const Icon(Icons.grid_on_outlined, size: 18),
                onSelected: (v) => appState.setGridColumns(v),
                itemBuilder: (_) => [
                  for (var c = 2; c <= 8; c++)
                    PopupMenuItem(
                        value: c,
                        child:
                            Text('$c 列', style: const TextStyle(fontSize: 13))),
                ],
              ),
              if (!compact)
                Text('${appState.gridColumns} 列',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.mutedLightOf(context))),
              IconButton(
                key: ValueKey('$library-toolbar-viewmode'),
                tooltip:
                    appState.viewMode == 'grid' ? '切换为列表视图' : '切换为网格视图',
                icon: Icon(
                  appState.viewMode == 'grid'
                      ? Icons.view_list_outlined
                      : Icons.grid_view,
                  size: 18,
                ),
                onPressed: () => appState
                    .setViewMode(appState.viewMode == 'grid' ? 'list' : 'grid'),
              ),
              IconButton(
                key: ValueKey('$library-toolbar-select'),
                tooltip: appState.visualSelectionMode ? '退出多选' : '多选',
                icon: Icon(
                  appState.visualSelectionMode
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 18,
                  color:
                      appState.visualSelectionMode ? AppColors.accent : null,
                ),
                onPressed: () => appState.visualSelectionMode
                    ? appState.exitVisualSelectionMode()
                    : appState.enterVisualSelectionMode(),
              ),
              if (!compact) ...[
                IconButton(
                  key: ValueKey('$library-toolbar-tags'),
                  tooltip: '标签筛选',
                  icon: Icon(Icons.label_outline,
                      size: 18,
                      color: appState.activeTagIds.isEmpty
                          ? null
                          : AppColors.accent),
                  onPressed: () => _showTagFilter(context),
                ),
                IconButton(
                  key: ValueKey('$library-toolbar-advanced-filter'),
                  tooltip: '高级筛选',
                  icon: Icon(Icons.filter_alt_outlined,
                      size: 18,
                      color:
                          appState.hasAdvancedFilter ? AppColors.accent : null),
                  onPressed: () => AdvancedFilterDialog.show(context),
                ),
              ],
              const Spacer(),
              if (!compact) ...[
                IconButton(
                  key: ValueKey('$library-toolbar-refresh'),
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => appState.refresh(),
                ),
                IconButton(
                  key: ValueKey('$library-toolbar-clear-thumbs'),
                  tooltip: '清理缩略图缓存',
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  onPressed: () => _clearThumbCaches(context),
                ),
              ],
              if (_isImage && !compact)
                IconButton(
                  key: const ValueKey('image-toolbar-detail'),
                  tooltip: '图片详情',
                  icon: Icon(Icons.info_outline,
                      size: 18, color: detailOpen ? AppColors.accent : null),
                  onPressed: onToggleDetail,
                ),
              if (compact)
                PopupMenuButton<String>(
                  key: ValueKey('$library-toolbar-more'),
                  tooltip: '更多操作',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (v) => _onMore(context, v),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        key: ValueKey('$library-toolbar-refresh'),
                        value: 'refresh',
                        child: const Text('刷新',
                            style: TextStyle(fontSize: 13))),
                    PopupMenuItem(
                        key: ValueKey('$library-toolbar-clear-thumbs'),
                        value: 'clearThumbs',
                        child: const Text('清理缩略图缓存',
                            style: TextStyle(fontSize: 13))),
                    PopupMenuItem(
                        key: ValueKey('$library-toolbar-tags'),
                        value: 'tags',
                        child: const Text('标签筛选',
                            style: TextStyle(fontSize: 13))),
                    PopupMenuItem(
                        key: ValueKey('$library-toolbar-advanced-filter'),
                        value: 'advancedFilter',
                        child: const Text('高级筛选',
                            style: TextStyle(fontSize: 13))),
                    if (_isImage)
                      PopupMenuItem(
                          key: const ValueKey('image-toolbar-detail'),
                          value: 'detail',
                          child: Text(detailOpen ? '关闭图片详情' : '打开图片详情',
                              style: const TextStyle(fontSize: 13))),
                  ],
                ),
              const SizedBox(width: 4),
            ],
          );
        },
      ),
    );
  }

  void _onMore(BuildContext context, String action) {
    final appState = context.read<AppState>();
    switch (action) {
      case 'refresh':
        appState.refresh();
        break;
      case 'clearThumbs':
        _clearThumbCaches(context);
        break;
      case 'tags':
        _showTagFilter(context);
        break;
      case 'advancedFilter':
        AdvancedFilterDialog.show(context);
        break;
      case 'detail':
        onToggleDetail();
        break;
    }
  }

  void _showTagFilter(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(
          width: 320,
          height: 480,
          child: TagPanel(filterOnly: true),
        ),
      ),
    );
  }

  Future<void> _clearThumbCaches(BuildContext context) async {
    final appState = context.read<AppState>();
    final ok = await confirmDialog(
      context,
      title: '清理缩略图缓存？',
      content: '删除本机已生成的缩略图文件，之后浏览会重新生成。',
    );
    if (ok != true) return;
    final removed = await ThumbnailService.instance.evictDiskCache(maxSizeMB: 0);
    ThumbnailService.instance.clearMemoryCache();
    // 自增 thumbEpoch，网格里的卡片据此丢弃旧缩略图并重建
    appState.markThumbnailsCleared();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已清理 $removed 个缩略图缓存文件')),
    );
  }
}

/// 面包屑：上一级 + 「全部图片/全部视频」+ 逐级文件夹
class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final crumb = appState.breadcrumb;
    final rootLabel = appState.currentWork?.library == kVideoLibrary
        ? '全部视频'
        : '全部图片';
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            tooltip: '上一级',
            onPressed: crumb.isEmpty ? null : () => appState.goUp(),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                TextButton(
                  key: const ValueKey('breadcrumb-root'),
                  onPressed: () => _goRoot(appState),
                  child: Text(rootLabel, style: const TextStyle(fontSize: 12)),
                ),
                for (final f in crumb) ...[
                  Icon(Icons.chevron_right,
                      size: 14, color: AppColors.mutedLightOf(context)),
                  TextButton(
                    onPressed: f.id == null
                        ? null
                        : () {
                            // 面包屑首层是作品占位（id = -1），点它回作品层
                            if (f.id! < 0 && f.workId != null) {
                              appState.enterWork(f.workId!);
                            } else if (f.id! >= 0) {
                              appState.enterFolder(f.id!);
                            }
                          },
                    child: Text(f.name, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// AppState 没有 goRoot，用 goUp 循环回到顶层
  Future<void> _goRoot(AppState appState) async {
    var guard = 0;
    while (appState.currentFolderId != null && guard++ < 64) {
      await appState.goUp();
    }
  }
}

/// 高级筛选生效时的横条
class _AdvancedFilterBar extends StatelessWidget {
  const _AdvancedFilterBar();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: AppColors.surface,
      child: Row(
        children: [
          const Text('高级筛选',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedLight)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              appState.advancedFilter,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            tooltip: '编辑高级筛选',
            onPressed: () => AdvancedFilterDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: '清除高级筛选',
            onPressed: () => appState.clearAdvancedFilter(),
          ),
        ],
      ),
    );
  }
}

/// 多选生效时的横条：批量标签与批量移除记录
class _SelectionBar extends StatelessWidget {
  final String library;

  const _SelectionBar({required this.library});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final ids = appState.selectedIds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      color: AppColors.surface,
      child: Row(
        children: [
          Text('已选 ${ids.length} 项',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textPrimary)),
          const Spacer(),
          TextButton.icon(
            key: const ValueKey('selection-select-all'),
            onPressed: appState.selectAllImages,
            icon: const Icon(Icons.select_all, size: 16),
            label: const Text('全选', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: () => _addTags(context, appState, ids),
            icon: const Icon(Icons.label_outline, size: 16),
            label: const Text('添加标签', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: () => _removeTags(context, appState, ids),
            icon: const Icon(Icons.label_off_outlined, size: 16),
            label: const Text('移除标签', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            key: const ValueKey('selection-delete'),
            onPressed: () => _removeRecords(context, appState, ids),
            icon: const Icon(Icons.playlist_remove, size: 16),
            label: Text('移除记录',
                style: TextStyle(fontSize: 12, color: AppColors.danger)),
          ),
          TextButton.icon(
            onPressed: appState.clearSelection,
            icon: const Icon(Icons.deselect, size: 16),
            label: const Text('清除选择', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 从软件移除选中记录：只删库里的行，磁盘文件保持原样。
  Future<void> _removeRecords(
      BuildContext context, AppState appState, Set<int> ids) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除记录'),
        content: Text(
            '从软件里移除选中的 ${ids.length} 项？\n'
            '磁盘上的文件不会被删除，标签关联会一起解除。',
            style: TextStyle(
                color: AppColors.textSecondaryOf(ctx), fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('移除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await appState.deleteMediaByIds(ids);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已移除 $deleted 条记录，磁盘文件未改动')));
  }

  Future<void> _addTags(
      BuildContext context, AppState appState, Set<int> ids) async {
    final tags = await showTagPickerDialog(context, title: '批量添加标签');
    if (tags == null || tags.isEmpty) return;
    await appState.addTagsToMedia(ids, tags);
  }

  Future<void> _removeTags(
      BuildContext context, AppState appState, Set<int> ids) async {
    final current = await appState.getTagIdsOnMedia(ids);
    if (!context.mounted) return;
    final tags = await showTagPickerDialog(context,
        title: '批量移除标签', filterTagIds: current);
    if (tags == null || tags.isEmpty) return;
    await appState.removeTagsFromMedia(ids, tags);
  }
}

/// 最近播放横条
class _RecentBar extends StatelessWidget {
  final AppState appState;
  const _RecentBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    final tracks = appState.recentTracks;
    return SizedBox(
      height: 122,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text('最近播放',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context))),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: tracks.length,
              itemBuilder: (ctx, i) {
                final t = tracks[i];
                return InkWell(
                  onTap: () => appState.playRecentTracks(i),
                  child: SizedBox(
                    width: 100,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoverImage(
                              path: t.coverPath,
                              width: 72,
                              height: 72,
                              borderRadius: 8),
                          const SizedBox(height: 4),
                          Text(
                            t.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
