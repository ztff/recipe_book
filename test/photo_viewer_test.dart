import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/widgets/photo_viewer.dart';

void main() {
  testWidgets('点开步骤配图弹出大图，能关闭', (tester) async {
    final dir = Directory.systemTemp.createTempSync('photo_viewer_test');
    final file = File(dir.path + '/step.png');
    file.writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ));

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showPhotoViewer(ctx, file.path, caption: '第 2 步'),
              child: const Text('看大图'),
            ),
          ),
        ),
      ),
    ));

    expect(find.text('关闭'), findsNothing);
    await tester.tap(find.text('看大图'));
    await tester.pumpAndSettle();

    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('第 2 步'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('关闭'), findsNothing);

    dir.deleteSync(recursive: true);
  });
}
