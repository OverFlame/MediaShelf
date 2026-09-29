import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 封面图组件：本地文件优先，否则占位
class CoverImage extends StatelessWidget {
  final String? path;
  final double width;
  final double height;
  final double borderRadius;
  final BoxFit fit;

  const CoverImage({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final p = path;
    Widget child;
    if (p != null && File(p).existsSync()) {
      child = Image.file(
        File(p),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    } else {
      child = _placeholder(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _placeholder(BuildContext context) {
    // 调用方可能传 double.infinity（作品卡片就是这么用的），图标尺寸要收成有限值
    final iconSize = width.isFinite ? width * 0.4 : 32.0;
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceOf(context),
      child: Icon(
        Icons.music_note,
        size: iconSize,
        color: AppColors.mutedOf(context),
      ),
    );
  }
}
