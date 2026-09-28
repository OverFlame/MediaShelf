import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/work_dao.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';
import 'dialogs.dart';
import 'launch_result_snack.dart';

/// 主页作品集网格。
///
/// [library] 为空时展示全部作品（音频库沿用这一行为，界面不变）。
/// 传 `image` / `video` 时只展示该库的作品，并给出对应库的导入入口。
class WorksGrid extends StatelessWidget {
  final String? library;

  const WorksGrid({super.key, this.library});

  bool get _isImage => library == 'image';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final works = library == null
        ? appState.works
        : appState.works.where((w) => w.library == library).toList();

    if (works.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                library == null
                    ? Icons.album_outlined
                    : (_isImage
                        ? Icons.photo_library_outlined
                        : Icons.movie_outlined),
                size: 56,
                color: AppColors.mutedOf(context)),
            const SizedBox(height: 12),
            Text(
                library == null
                    ? '还没有作品'
                    : (_isImage ? '还没有图片作品' : '还没有视频作品'),
                style: TextStyle(
                    color: AppColors.textSecondaryOf(context), fontSize: 14)),
            const SizedBox(height: 4),
            Text(
                library == null
                    ? '在左侧点击「添加文件夹」导入音频，自动生成作品'
                    : (_isImage
                        ? '点击下面的「添加文件夹」导入图片，自动生成作品'
                        : '点击下面的「添加文件夹」导入视频，自动生成作品'),
                style: TextStyle(color: AppColors.mutedOf(context), fontSize: 12)),
            if (library != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                key: const ValueKey('works-empty-add-folder'),
                onPressed: () => _pickFolder(context),
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('添加文件夹'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.surfaceAlt),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / 200).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.82,
          ),
          itemCount: works.length,
          itemBuilder: (_, i) => _WorkCard(
            key: ValueKey('work-card-${works[i].id}'),
            work: works[i],
            library: library,
          ),
        );
      },
    );
  }

  /// 空态里的导入入口：选目录 -> 按本库落库（走 AppState 现成导入通道）
  Future<void> _pickFolder(BuildContext context) async {
    final lib = library;
    if (lib == null) return;
    final appState = context.read<AppState>();
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: _isImage ? '选择包含图片的文件夹' : '选择包含视频的文件夹',
    );
    if (result != null && result.isNotEmpty && context.mounted) {
      await appState.importDirectory(result, library: lib);
    }
  }
}

class _WorkCard extends StatelessWidget {
  final Work work;

  /// 所属库：null = 音频库（行为与改造前一致）。
  final String? library;

  const _WorkCard({super.key, required this.work, this.library});

  /// 「播放全部」只对音频有效（视频不做应用内解码）
  bool get _playAll => library == null;

  /// 「用外部播放器播放」对音频与视频都成立（图片没有播放语义）
  bool get _playExternal => library == null || library == 'video';

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => appState.enterWork(work.id!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverImage(
                  path: work.coverPath,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: 10,
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _menu(context, appState),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            work.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.textPrimaryOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, AppState appState) {
    return Material(
      color: Colors.black45,
      borderRadius: BorderRadius.circular(6),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 16, color: Colors.white),
        tooltip: '作品操作',
        onSelected: (v) => _onMenu(context, appState, v),
        itemBuilder: (_) => [
          if (_playAll)
            const PopupMenuItem(value: 'playAll', child: Text('播放全部', style: TextStyle(fontSize: 13))),
          if (_playExternal)
            const PopupMenuItem(value: 'playExternal', child: Text('用外部播放器播放', style: TextStyle(fontSize: 13))),
          const PopupMenuItem(value: 'rename', child: Text('重命名', style: TextStyle(fontSize: 13))),
          const PopupMenuItem(value: 'cover', child: Text('设置封面', style: TextStyle(fontSize: 13))),
          const PopupMenuDivider(),
          const PopupMenuItem(
              value: 'delete',
              child: Text('删除作品', style: TextStyle(fontSize: 13, color: AppColors.danger))),
        ],
      ),
    );
  }

  Future<void> _onMenu(
      BuildContext context, AppState appState, String v) async {
    switch (v) {
      case 'playAll':
        await appState.playWorkAll(work.id!);
        break;
      case 'playExternal':
        final r = await appState.playWorkExternal(work.id!);
        if (context.mounted) showLaunchResult(context, r);
        break;
      case 'rename':
        final name = await promptText(context,
            title: '重命名作品', initial: work.name);
        if (name != null && name.isNotEmpty) {
          await appState.renameWork(work.id!, name);
        }
        break;
      case 'cover':
        await showImportCoverDialog(context, work.id!);
        break;
      case 'delete':
        final count = await appState.countMediaUnderWork(work.id!);
        if (!context.mounted) return;
        final ok = await confirmDialog(context,
            title: '删除作品「${work.name}」？',
            content: '将从软件里移除这个作品、它下面的文件夹，以及其中的 '
                '$count 条媒体记录（音频、图片、视频、字幕都算）。\n'
                '磁盘文件不会被删除，之后可以重新导入。');
        if (ok == true) {
          await appState.deleteWorkDeep(work.id!);
        }
        break;
    }
  }
}
