/// 文件写入与复制的安全封装。
///
/// 这里的两件事都围绕同一个风险：写坏或清空已有数据。
/// `AtomicFileWriter` 保证目标文件要么是完整的旧内容，要么是完整的新内容；
/// [safeCopyFile] 保证源与目标相同时不会把源文件截断。
library;

import 'dart:io';

import 'package:mediashelf/utils/path_util.dart';

/// 串行化并原子替换的文本写入器。
///
/// 并发调用 [write] 时按调用顺序排队，每次写入先落 `<path>.tmp`，
/// 再把旧文件改名为 `<path>.bak`，最后 rename 覆盖目标。
/// 同目录内的 rename 是原子操作，进程中途被杀不会留下半截 JSON。
class AtomicFileWriter {
  AtomicFileWriter(this.path);

  /// 目标文件路径。
  final String path;

  Future<void> _pending = Future<void>.value();

  /// 写入 [content]。
  ///
  /// 返回的 Future 会把本次失败抛给调用方；排队链条本身吞掉错误，
  /// 避免一次写入失败让后续写入全部失效。
  Future<void> write(String content) {
    final next = _pending.then((_) => _writeNow(content));
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeNow(String content) async {
    final target = File(path);
    await target.parent.create(recursive: true);

    final tmp = File('$path.tmp');
    await tmp.writeAsString(content, flush: true);

    if (await target.exists()) {
      final bak = File('$path.bak');
      if (await bak.exists()) await bak.delete();
      await target.rename(bak.path);
    }
    await tmp.rename(path);
  }
}

/// 复制文件并校验结果。
///
/// 源与目标同一个位置时直接返回，不触碰文件：`File.copy` 在这种情况下
/// 会先删掉目标（也就是源），再把空内容写回去，文件变成 0 字节且不报错。
/// 复制过程先落 `<dst>.migrating`，确认非空后再改名到 [dst]。
Future<void> safeCopyFile(String src, String dst) async {
  final s = File(src);
  if (!s.existsSync()) return;
  if (isSamePath(src, dst)) return;

  final target = File(dst);
  await target.parent.create(recursive: true);

  final tmp = File('$dst.migrating');
  if (await tmp.exists()) await tmp.delete();
  await s.copy(tmp.path);

  final srcLen = await s.length();
  final tmpLen = await tmp.length();
  if (srcLen > 0 && tmpLen == 0) {
    await tmp.delete();
    throw FileSystemException('复制结果为空，已中止', src);
  }

  if (await target.exists()) await target.delete();
  await tmp.rename(dst);
}
