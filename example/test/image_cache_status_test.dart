import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:power_image_example/examples/image_cache_status.dart';

void main() {
  testWidgets('stops refreshing after it is removed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ImageCacheStatusWidget()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
  });
}
