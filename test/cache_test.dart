import 'package:flutter/cupertino.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    WidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    imageCache!
      ..clear()
      ..clearLiveImages()
      ..maximumSize = 1000
      ..maximumSizeBytes = 10485760;
  });

  group('cache_test', () {
    setUp(() {});

    test('uses Flutter standard ImageCache without a custom binding', () {
      expect(imageCache, isA<ImageCache>());
    });
  });
}
