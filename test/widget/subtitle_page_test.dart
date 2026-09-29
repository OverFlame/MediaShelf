import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediashelf/db/track_dao.dart';
import 'package:mediashelf/pages/subtitle_page.dart';
import 'package:mediashelf/state/app_state.dart';
import 'package:mediashelf/state/player_controller.dart';
import 'package:provider/provider.dart';

/// 字幕页的三件事：当前句停在视口正中、不在本句的更透明、
/// 用户滑动之后先留住视线再恢复跟随。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late PlayerController player;
  late AppState app;
  late TrackItem track;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mediashelf_subtitle_page');
    // 8 句，每句 4 秒：第 n 句从 (n-1)*4 秒开始
    final srt = StringBuffer();
    for (var i = 1; i <= 8; i++) {
      srt.writeln('$i\n${_ts((i - 1) * 4)} --> ${_ts(i * 4)}\n第 $i 句\n');
    }
    final file = await File('${tmp.path}/a.srt').writeAsString(srt.toString());
    track = TrackItem(
      id: 1,
      path: '${tmp.path}/a.mp3',
      filename: 'a.mp3',
      subtitlePath: file.path,
      addedAt: 1,
    );
    player = PlayerController();
    app = AppState(player: player);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester, Duration position) async {
    player.debugSeedQueue([track]);
    player.debugSetPosition(position);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<AppState>.value(value: app),
      ],
      child: const MaterialApp(home: SubtitlePage()),
    ));
    await tester.pumpAndSettle();
  }

  double offsetOf(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!.offset;

  testWidgets('正在播放的这一句停在视口正中', (tester) async {
    // 第 6 句（20 秒起）：旧实现把它停在视口底部
    await pumpPage(tester, const Duration(seconds: 20));
    final viewport = tester.getRect(find.byType(ListView));
    final active = tester.getRect(find.text('第 6 句'));
    expect(active.center.dy, closeTo(viewport.center.dy, 1.0));
  });

  testWidgets('不在本句的字幕更透明', (tester) async {
    await pumpPage(tester, const Duration(seconds: 20));
    final active = tester.widget<Text>(find.text('第 6 句')).style!;
    final other = tester.widget<Text>(find.text('第 5 句')).style!;
    expect(active.color!.a, 1.0);
    expect(other.color!.a, lessThan(0.38));
  });

  testWidgets('滑动之后先留住用户的视线，过了保留时间再把当前句拉回中间',
      (tester) async {
    await pumpPage(tester, const Duration(seconds: 20));
    final viewport = tester.getRect(find.byType(ListView));

    // 用户往上拖：内容下移，回头看更早的句子
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    final dragged = offsetOf(tester);

    // 当前句换了一句，但保留时间内不能自己跑回去（旧实现 3 秒就恢复跟随）
    player.debugSetPosition(const Duration(seconds: 24));
    await tester.pump(const Duration(seconds: 5));
    await _settleScroll(tester);
    expect(offsetOf(tester), closeTo(dragged, 0.5),
        reason: '保留时间内不该自动滚走');

    // 过了保留时间：当前句回到视口正中
    await tester.pump(const Duration(seconds: 4));
    await _settleScroll(tester);
    expect(tester.getRect(find.text('第 7 句')).center.dy,
        closeTo(viewport.center.dy, 1.0));
  });
}

/// 让自动滚动的那段动画跑完（动画的第一帧只是起点，得再来一帧）。
Future<void> _settleScroll(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

String _ts(int seconds) {
  final h = (seconds ~/ 3600).toString().padLeft(2, '0');
  final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s,000';
}
