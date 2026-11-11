import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/widgets/cover_actions.dart';

/// 放一个按钮，点了弹封面菜单，把用户选的结果记进 [picked]。
Future<void> pumpPicker(
  WidgetTester tester,
  List<CoverAction?> picked, {
  required bool allowCamera,
  required bool hasImage,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async {
              final a = await showCoverActions(
                ctx,
                allowCamera: allowCamera,
                hasImage: hasImage,
              );
              picked.add(a);
            },
            child: const Text('换封面'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('换封面'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('手机上有图时三项都在，点拍一张返回 camera', (tester) async {
    final picked = <CoverAction?>[];
    await pumpPicker(tester, picked, allowCamera: true, hasImage: true);

    expect(find.text('拍一张'), findsOneWidget);
    expect(find.text('从相册/文件选'), findsOneWidget);
    expect(find.text('移除图片'), findsOneWidget);

    await tester.tap(find.text('拍一张'));
    await tester.pumpAndSettle();

    expect(picked, <CoverAction?>[CoverAction.camera]);
    expect(find.text('拍一张'), findsNothing);
  });

  testWidgets('桌面端没有拍一张', (tester) async {
    final picked = <CoverAction?>[];
    await pumpPicker(tester, picked, allowCamera: false, hasImage: true);

    expect(find.text('拍一张'), findsNothing);
    expect(find.text('从相册/文件选'), findsOneWidget);
    expect(find.text('移除图片'), findsOneWidget);
  });

  testWidgets('没有封面时不显示移除图片，选相册返回 gallery', (tester) async {
    final picked = <CoverAction?>[];
    await pumpPicker(tester, picked, allowCamera: true, hasImage: false);

    expect(find.text('移除图片'), findsNothing);

    await tester.tap(find.text('从相册/文件选'));
    await tester.pumpAndSettle();

    expect(picked, <CoverAction?>[CoverAction.gallery]);
  });

  testWidgets('有封面时点移除返回 remove', (tester) async {
    final picked = <CoverAction?>[];
    await pumpPicker(tester, picked, allowCamera: true, hasImage: true);

    await tester.tap(find.text('移除图片'));
    await tester.pumpAndSettle();

    expect(picked, <CoverAction?>[CoverAction.remove]);
  });

  testWidgets('点空白遮罩关掉，返回 null', (tester) async {
    final picked = <CoverAction?>[];
    await pumpPicker(tester, picked, allowCamera: true, hasImage: true);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(picked, <CoverAction?>[null]);
  });
}
