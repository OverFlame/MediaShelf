import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/tag_dao.dart';
import '../services/media_bridge.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'dialogs.dart';

/// 左侧面板：导入 + 作品集 + 标签（对标 PictureViewer 的标签面板）
class TagPanel extends StatefulWidget {
  /// 导航后回调（窄屏抽屉里用于关闭抽屉）
  final VoidCallback? onNavigate;
  const TagPanel({super.key, this.onNavigate});

  @override
  State<TagPanel> createState() => _TagPanelState();
}

class _TagPanelState extends State<TagPanel> {
  final _pathController = TextEditingController();
  final _tagSearchCtrl = TextEditingController();
  String _tagSearch = '';

  @override
  void dispose() {
    _pathController.dispose();
    _tagSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Column(
      children: [
        _importSection(appState),
        const Divider(height: 1),
        _librarySection(appState),
        const Divider(height: 1),
        Expanded(child: _tagSection(appState)),
      ],
    );
  }

  // ── 导入 ──
  Widget _importSection(AppState appState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _pathController,
                    enabled: !appState.importing,
                    onSubmitted: (_) => _addFromPath(appState),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '输入文件夹路径，回车添加',
                      hintStyle: TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedLightOf(context)),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 32,
                child: IconButton(
                  onPressed:
                      appState.importing ? null : () => _addFromPath(appState),
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: '从路径添加',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    backgroundColor: AppColors.surfaceOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed:
                  appState.importing ? null : () => _pickFolder(appState),
              icon: Icon(
                appState.importing
                    ? Icons.hourglass_empty
                    : Icons.create_new_folder,
                size: 14,
              ),
              label: Text(
                appState.importing ? '导入中...' : '添加文件夹',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
          if (appState.importing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: appState.importProgress,
                backgroundColor: AppColors.surfaceOf(context),
                color: AppColors.accent,
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }

  /// 导入失败时把原因弹出来。调用方是按钮回调，没有别的错误出口。
  void _showImportError(AppState appState) {
    final err = appState.importError;
    if (err == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('导入失败：$err')));
  }

  Future<void> _addFromPath(AppState appState) async {
    if (!await _ensureAllFilesAccess()) return;
    final text = _pathController.text.trim();
    if (text.isEmpty) return;
    _pathController.clear();
    await appState.importDirectory(text);
    _showImportError(appState);
  }

  Future<void> _pickFolder(AppState appState) async {
    if (!await _ensureAllFilesAccess()) return;
    final result = await pickDirectoryPath(title: '选择包含音频的文件夹');
    if (result != null) {
      await appState.importDirectory(result);
      _showImportError(appState);
    }
  }

  Future<bool> _ensureAllFilesAccess() async {
    final bridge = MediaBridge.instance;
    if (!bridge.isAndroid) return true;
    if (await bridge.hasAllFilesAccess()) return true;
    await bridge.requestAllFilesAccess();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('请在系统设置中授予「所有文件访问」权限后重试')),
      );
    }
    return false;
  }

  // ── 作品集 ──
  Widget _librarySection(AppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 2),
          child: Row(
            children: [
              Text('作品集',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedLightOf(context))),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                onPressed: () => _createWork(appState),
                icon: Icon(Icons.add_circle_outline,
                    size: 15, color: AppColors.mutedOf(context)),
                tooltip: '新建空作品',
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              _navEntry(
                selected: appState.currentWork == null,
                icon: Icons.home_outlined,
                label: '全部作品',
                onTap: () {
                  appState.goHome();
                  widget.onNavigate?.call();
                },
              ),
              for (final w in appState.works)
                _navEntry(
                  selected: appState.currentWork?.id == w.id,
                  icon: Icons.album_outlined,
                  label: w.name,
                  onTap: () {
                    appState.enterWork(w.id!);
                    widget.onNavigate?.call();
                  },
                ),
              for (final f in appState.unassignedFolders)
                _navEntry(
                  selected: appState.currentFolderId == f.id,
                  icon: Icons.folder_outlined,
                  label: '未归类 · ${f.name}',
                  onTap: () {
                    appState.enterFolder(f.id!);
                    widget.onNavigate?.call();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createWork(AppState appState) async {
    final name = await promptText(context, title: '新建空作品');
    if (name != null && name.isNotEmpty) {
      await appState.createWork(name);
    }
  }

  Widget _navEntry({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.surfaceOf(context) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(icon,
                size: 15, color: selected ? AppColors.accent : AppColors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? AppColors.textPrimaryOf(context)
                      : AppColors.textSecondaryOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 标签 ──
  Widget _tagSection(AppState appState) {
    final allTags = appState.allTags;
    final filter = appState.tagFilter;
    final activeIds = <int>{
      ...filter.andTagIds,
      ...filter.orTagIds,
      ...filter.notTagIds,
    };

    var filtered = _tagSearch.isEmpty
        ? allTags
        : allTags
            .where((t) =>
                t.name.toLowerCase().contains(_tagSearch.toLowerCase()) ||
                t.namespace.toLowerCase().contains(_tagSearch.toLowerCase()))
            .toList();

    final namespaces = <String, List<Tag>>{};
    for (final t in filtered) {
      final ns = t.namespace.isEmpty ? '(无命名空间)' : t.namespace;
      namespaces.putIfAbsent(ns, () => []).add(t);
    }
    final sortedNs = namespaces.keys.toList()
      ..sort((a, b) {
        if (a == '(无命名空间)') return 1;
        if (b == '(无命名空间)') return -1;
        return a.compareTo(b);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tagHeader(appState),
        const Divider(height: 1),
        _tagSearchBar(),
        if (activeIds.isNotEmpty) _activeFilterBar(appState),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: sortedNs.length,
            itemBuilder: (ctx, i) => _namespaceGroup(
                sortedNs[i], namespaces[sortedNs[i]]!, appState, filter),
          ),
        ),
      ],
    );
  }

  Widget _tagHeader(AppState appState) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text('标签',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context))),
          ),
          const Spacer(),
          IconButton(
            tooltip: '高级筛选表达式',
            onPressed: () => _advancedFilter(appState),
            icon: Icon(Icons.functions,
                size: 15,
                color: appState.hasAdvancedFilter
                    ? AppColors.accent
                    : AppColors.mutedOf(context)),
          ),
          IconButton(
            tooltip: '新建标签',
            onPressed: () => _showCreateTagDialog(appState),
            icon: Icon(Icons.add, size: 16, color: AppColors.mutedOf(context)),
          ),
          if (appState.tagFilter.active || appState.hasAdvancedFilter)
            IconButton(
              tooltip: '清除筛选',
              onPressed: () {
                appState.clearTagFilters();
                appState.clearAdvancedFilter();
              },
              icon: Icon(Icons.clear, size: 14, color: AppColors.mutedOf(context)),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _tagSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: SizedBox(
        height: 32,
        child: TextField(
          controller: _tagSearchCtrl,
          onChanged: (v) => setState(() => _tagSearch = v),
          style: TextStyle(fontSize: 12, color: AppColors.textPrimaryOf(context)),
          decoration: InputDecoration(
            hintText: '搜索标签...',
            hintStyle: TextStyle(
                fontSize: 12, color: AppColors.mutedLightOf(context)),
            prefixIcon: Icon(Icons.search,
                size: 14, color: AppColors.mutedLightOf(context)),
            suffixIcon: _tagSearch.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear,
                        size: 14, color: AppColors.mutedLightOf(context)),
                    onPressed: () {
                      _tagSearchCtrl.clear();
                      setState(() => _tagSearch = '');
                    },
                  )
                : null,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
      ),
    );
  }

  Widget _activeFilterBar(AppState appState) {
    final filter = appState.tagFilter;
    final tagMap = {for (final t in appState.allTags) t.id!: t};

    final chips = <Widget>[];
    for (final id in filter.andTagIds) {
      final tag = tagMap[id];
      if (tag == null) continue;
      chips.add(_filterChip('AND ${tag.name}', AppColors.success,
          () => appState.toggleAndFilter(id)));
    }
    for (final id in filter.orTagIds) {
      final tag = tagMap[id];
      if (tag == null) continue;
      chips.add(_filterChip('OR ${tag.name}', AppColors.warning,
          () => appState.toggleOrFilter(id)));
    }
    for (final id in filter.notTagIds) {
      final tag = tagMap[id];
      if (tag == null) continue;
      chips.add(_filterChip('NOT ${tag.name}', AppColors.danger,
          () => appState.toggleNotFilter(id)));
    }

    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppColors.surfaceOf(context),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Wrap(spacing: 4, runSpacing: 2, children: chips),
    );
  }

  Widget _filterChip(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(fontSize: 10, color: color)),
      ),
    );
  }

  Widget _namespaceGroup(
      String ns, List<Tag> tags, AppState appState, TagFilter filter) {
    tags.sort((a, b) => a.name.compareTo(b.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            ns,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.mutedLighter,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...tags.map((tag) => _tagItem(tag, appState, filter)),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _tagItem(Tag tag, AppState appState, TagFilter filter) {
    final andActive = filter.andTagIds.contains(tag.id);
    final orActive = filter.orTagIds.contains(tag.id);
    final notActive = filter.notTagIds.contains(tag.id);
    final anyActive = andActive || orActive || notActive;
    final dotColor = AppColors.parseColor(tag.color);

    return Material(
      color: anyActive ? AppColors.surfaceAltOf(context) : Colors.transparent,
      child: InkWell(
        onTap: () => appState.toggleAndFilter(tag.id!),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: anyActive
                      ? Border.all(color: dotColor, width: 2)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: anyActive
                        ? AppColors.textPrimaryOf(context)
                        : AppColors.textSecondaryOf(context),
                    fontWeight:
                        anyActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _filterPopup(tag, appState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterPopup(Tag tag, AppState appState) {
    final filter = appState.tagFilter;
    final andActive = filter.andTagIds.contains(tag.id);
    final orActive = filter.orTagIds.contains(tag.id);
    final notActive = filter.notTagIds.contains(tag.id);

    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      iconSize: 12,
      icon: Icon(
        Icons.more_horiz,
        size: 12,
        color: (andActive || orActive || notActive)
            ? AppColors.textPrimaryOf(context)
            : AppColors.mutedOf(context),
      ),
      tooltip: '筛选选项',
      onSelected: (action) {
        switch (action) {
          case 'and':
            appState.toggleAndFilter(tag.id!);
            break;
          case 'or':
            appState.toggleOrFilter(tag.id!);
            break;
          case 'not':
            appState.toggleNotFilter(tag.id!);
            break;
          case 'clear':
            appState.toggleAndFilter(tag.id!);
            appState.toggleOrFilter(tag.id!);
            appState.toggleNotFilter(tag.id!);
            break;
          case 'edit':
            _showEditTagDialog(tag, appState);
            break;
          case 'delete':
            _showDeleteTagDialog(tag, appState);
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'and',
          child: _popupItem('AND 交集', '必须拥有此标签', Icons.search, andActive),
        ),
        PopupMenuItem(
          value: 'or',
          child: _popupItem('OR 并集', '可以拥有此标签', Icons.filter_list, orActive),
        ),
        PopupMenuItem(
          value: 'not',
          child: _popupItem('NOT 排除', '不能拥有此标签', Icons.block, notActive),
        ),
        if (andActive || orActive || notActive) const PopupMenuDivider(),
        if (andActive || orActive || notActive)
          const PopupMenuItem(
              value: 'clear', child: Text('清除此标签筛选', style: TextStyle(fontSize: 12))),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'edit', child: Text('重命名/改色', style: TextStyle(fontSize: 12))),
        PopupMenuItem(
          value: 'delete',
          child: Text('删除标签',
              style: TextStyle(fontSize: 12, color: AppColors.danger)),
        ),
      ],
    );
  }

  Widget _popupItem(String title, String sub, IconData icon, bool active) {
    return Row(
      children: [
        Icon(icon,
            size: 14,
            color: active ? AppColors.accent : AppColors.mutedOf(context)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontSize: 12)),
            Text(sub,
                style: TextStyle(
                    fontSize: 10, color: AppColors.mutedOf(context))),
          ],
        ),
        if (active)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.check, size: 12, color: AppColors.accent),
          ),
      ],
    );
  }

  // ── 新建标签对话框 ──
  void _showCreateTagDialog(AppState appState) {
    final nameCtrl = TextEditingController();
    final nsCtrl = TextEditingController();
    String color = '#a98cf5';
    const presetColors = [
      '#a98cf5', '#f06e7f', '#f0a868', '#e2c275',
      '#9ccb86', '#63bfc8', '#6fb6ec', '#9fa6ef',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('新建标签'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: '标签名', hintText: '例如：纯音乐'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nsCtrl,
                  decoration: const InputDecoration(
                      labelText: '命名空间 (可选)', hintText: '例如：风格'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presetColors.map((c) {
                    final selected = color == c;
                    return GestureDetector(
                      onTap: () => setLocal(() => color = c),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.parseColor(c),
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: AppColors.textPrimaryOf(ctx), width: 2)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  appState.createTag(name,
                      namespace: nsCtrl.text.trim(), color: color);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 编辑标签对话框（重命名 / 改命名空间 / 改色）──
  void _showEditTagDialog(Tag tag, AppState appState) {
    final nameCtrl = TextEditingController(text: tag.name);
    final nsCtrl = TextEditingController(
        text: tag.namespace == 'general' ? '' : tag.namespace);
    String color = tag.color;
    const presetColors = [
      '#a98cf5', '#f06e7f', '#f0a868', '#e2c275',
      '#9ccb86', '#63bfc8', '#6fb6ec', '#9fa6ef',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('编辑标签'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '标签名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nsCtrl,
                  decoration: const InputDecoration(
                      labelText: '命名空间 (可选)', hintText: '留空为 general'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presetColors.map((c) {
                    final selected = color == c;
                    return GestureDetector(
                      onTap: () => setLocal(() => color = c),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.parseColor(c),
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: AppColors.textPrimaryOf(ctx), width: 2)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  final ns = nsCtrl.text.trim();
                  appState.updateTag(tag.id!, name,
                      namespace: ns.isEmpty ? 'general' : ns, color: color);
                  Navigator.pop(ctx);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteTagDialog(Tag tag, AppState appState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定删除「${tag.name}」？关联的曲目/文件夹标签也会被移除。',
            style: TextStyle(
                color: AppColors.textSecondaryOf(ctx), fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              appState.deleteTag(tag.id!);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _advancedFilter(AppState appState) async {
    final expr = await promptText(context,
        title: '高级筛选表达式',
        initial: appState.advancedFilter,
        hint: '例如 (A||B)&&!C');
    if (expr == null) return;
    try {
      await appState.setAdvancedFilter(expr);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('表达式错误：$e')));
      }
    }
  }
}
