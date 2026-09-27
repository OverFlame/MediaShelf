import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/work_dao.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';
import 'dialogs.dart';

/// 主页作品集网格
class WorksGrid extends StatelessWidget {
  const WorksGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final works = appState.works;

    if (works.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.album_outlined, size: 56, color: AppColors.mutedOf(context)),
            const SizedBox(height: 12),
            Text('还没有作品',
                style: TextStyle(
                    color: AppColors.textSecondaryOf(context), fontSize: 14)),
            const SizedBox(height: 4),
            Text('在左侧点击「添加文件夹」导入音频，自动生成作品',
                style: TextStyle(color: AppColors.mutedOf(context), fontSize: 12)),
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
          itemBuilder: (_, i) => _WorkCard(work: works[i]),
        );
      },
    );
  }
}

class _WorkCard extends StatelessWidget {
  final Work work;
  const _WorkCard({required this.work});

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
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('重命名', style: TextStyle(fontSize: 13))),
          PopupMenuItem(value: 'cover', child: Text('设置封面', style: TextStyle(fontSize: 13))),
          PopupMenuDivider(),
          PopupMenuItem(
              value: 'delete',
              child: Text('删除作品', style: TextStyle(fontSize: 13, color: AppColors.danger))),
        ],
      ),
    );
  }

  Future<void> _onMenu(
      BuildContext context, AppState appState, String v) async {
    switch (v) {
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
        final ok = await confirmDialog(context,
            title: '删除作品「${work.name}」？',
            content: '仅删除作品分组，文件夹与磁盘文件保留（文件夹变为未归类）。');
        if (ok == true) {
          await appState.deleteWork(work.id!);
        }
        break;
    }
  }
}
