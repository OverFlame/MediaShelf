import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dialogs.dart';

/// 设置页
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('外观'),
          SwitchListTile(
            title: const Text('深色主题'),
            subtitle: const Text('关闭后跟随系统或使用浅色'),
            value: appState.themeMode == ThemeMode.dark,
            onChanged: (v) => appState
                .setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
          ),
          const Divider(height: 1),
          const _SectionHeader('高级筛选'),
          ListTile(
            leading: const Icon(Icons.history, size: 18),
            title: const Text('清除表达式历史'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () async {
              await SettingsService.instance.clearExpressionHistory();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清除表达式历史')));
              }
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('数据'),
          ListTile(
            leading: const Icon(Icons.folder_outlined, size: 18),
            title: const Text('数据目录'),
            subtitle: FutureBuilder<String>(
              future: appState.getDataDir(),
              builder: (context, snap) => Text(
                snap.data ?? '...',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outlined, size: 18),
            title: const Text('迁移数据目录'),
            subtitle: const Text('把数据库、封面缓存、设置整体迁移到其它位置'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => _migrateDataDir(context, appState),
          ),
          const Divider(height: 1),
          const _SectionHeader('封面缓存'),
          ListTile(
            leading: const Icon(Icons.image_outlined, size: 18),
            title: const Text('内嵌封面缓存'),
            subtitle: FutureBuilder<int>(
              future: appState.getCoverCacheSizeBytes(),
              builder: (context, snap) => Text(
                '${_fmtMB(snap.data ?? 0)} MB',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context)),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tune, size: 18),
            title: const Text('缓存上限'),
            trailing: DropdownButton<int>(
              value: appState.coverCacheLimitMB,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 128, child: Text('128 MB')),
                DropdownMenuItem(value: 256, child: Text('256 MB')),
                DropdownMenuItem(value: 512, child: Text('512 MB')),
                DropdownMenuItem(value: 1024, child: Text('1 GB')),
                DropdownMenuItem(value: 2048, child: Text('2 GB')),
                DropdownMenuItem(value: 0, child: Text('不限制')),
              ],
              onChanged: (v) {
                if (v != null) appState.setCoverCacheLimit(v);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined, size: 18),
            title: const Text('清理封面缓存'),
            subtitle: const Text('删除内嵌封面缓存（可重新生成），保留自定义封面'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () async {
              final freed = await appState.clearCoverCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已清理，释放 ${_fmtMB(freed)} MB')));
              }
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline, size: 18),
            title: Text('MediaShelf'),
            subtitle: Text('本地音频播放器 · Windows / Linux / Android'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.accent)),
    );
  }
}

String _fmtMB(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

/// 迁移数据目录：选择新目录 → 确认 → 整体迁移 → 提示
Future<void> _migrateDataDir(BuildContext context, AppState appState) async {
  final dir = await pickDirectoryPath(title: '选择新的数据目录');
  if (dir == null) return;
  if (!context.mounted) return;
  final ok = await confirmDialog(
    context,
    title: '迁移数据目录',
    content: '将把数据库、封面缓存、设置整体迁移到：\n$dir\n\n原目录会保留，不会删除。',
  );
  if (ok != true) return;
  try {
    await appState.migrateDataDir(dir);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('迁移失败：$e')));
    }
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('数据已迁移到：$dir')));
  }
}
