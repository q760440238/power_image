import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:power_image_example/animated_webp_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('benchmark uses 100 unique animals in all three formats', () async {
    final List<dynamic> manifest = jsonDecode(
      await rootBundle.loadString('assets/benchmark/manifest.json'),
    ) as List<dynamic>;
    expect(manifest, hasLength(benchmarkAnimalCount));
    expect(
      manifest.map((dynamic item) => item['name']).toSet(),
      hasLength(benchmarkAnimalCount),
    );
    expect(
      manifest.map((dynamic item) => item['codepoint']).toSet(),
      hasLength(benchmarkAnimalCount),
    );
    expect(benchmarkAnimalNames.toSet(), hasLength(benchmarkAnimalCount));

    final List<List<String>> assetSets = <List<String>>[
      benchmarkStaticWebpAssets,
      benchmarkAnimatedWebpAssets,
      benchmarkGifAssets,
    ];
    for (final List<String> assets in assetSets) {
      expect(assets, hasLength(benchmarkAnimalCount));
      final Set<String> encodedFiles = <String>{};
      for (final String asset in assets) {
        final ByteData data = await rootBundle.load(asset);
        encodedFiles.add(_fingerprint(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ));
      }
      expect(encodedFiles, hasLength(benchmarkAnimalCount),
          reason: 'Every $assets item must use different encoded bytes');
    }

    final Set<String> staticFirstFrames = <String>{};
    for (final String asset in benchmarkStaticWebpAssets) {
      final ByteData data = await rootBundle.load(asset);
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      expect(codec.frameCount, 1, reason: '$asset is not static');
      final ui.FrameInfo frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 512);
      final _PixelFingerprint pixels = await _rgbaFingerprint(frame.image);
      expect(pixels.hasVisiblePixel, isTrue, reason: '$asset is transparent');
      staticFirstFrames.add(pixels.hash);
      frame.image.dispose();
      codec.dispose();
    }
    expect(staticFirstFrames, hasLength(benchmarkAnimalCount),
        reason: 'All 100 animals must have visibly different first frames');

    for (final List<String> assets in <List<String>>[
      benchmarkAnimatedWebpAssets,
      benchmarkGifAssets,
    ]) {
      for (int index = 0; index < benchmarkAnimalCount; index += 10) {
        final String asset = assets[index];
        final ByteData data = await rootBundle.load(asset);
        final ui.Codec codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        expect(codec.frameCount, 12, reason: '$asset is not a 12-frame image');
        expect(codec.repetitionCount, isNot(0), reason: '$asset does not loop');
        final ui.FrameInfo first = await codec.getNextFrame();
        final ui.FrameInfo second = await codec.getNextFrame();
        expect(first.image.width, 512);
        expect(first.image.height, 512);
        expect(
          (await _rgbaFingerprint(first.image)).hash,
          isNot((await _rgbaFingerprint(second.image)).hash),
          reason: '$asset has no visible animation',
        );
        first.image.dispose();
        second.image.dispose();
        codec.dispose();
      }
    }
  });

  test('loopback server returns 100 unique fixtures per format', () async {
    final AnimatedWebpFixture fixture = await AnimatedWebpFixture.start();
    try {
      for (final String baseUrl in <String>[
        fixture.staticWebpUrl,
        fixture.url,
        fixture.gifUrl,
      ]) {
        final Set<String> responses = <String>{};
        for (int item = 0; item < benchmarkAnimalCount; item++) {
          final Uri uri = Uri.parse('$baseUrl?library=test&item=$item');
          final List<int> bytes = await _getFixtureWithSocket(
            uri,
            item,
            benchmarkAnimalNames[item],
          );
          responses.add(_fingerprint(Uint8List.fromList(bytes)));
        }
        expect(responses, hasLength(benchmarkAnimalCount),
            reason: '$baseUrl must serve 100 different files');
      }
    } finally {
      await fixture.close();
    }
  });
}

Future<_PixelFingerprint> _rgbaFingerprint(ui.Image image) async {
  final ByteData? pixels =
      await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  expect(pixels, isNotNull);
  final Uint8List rgba =
      pixels!.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes);
  bool hasVisiblePixel = false;
  for (int index = 3; index < rgba.length; index += 4) {
    if (rgba[index] != 0) {
      hasVisiblePixel = true;
      break;
    }
  }
  return _PixelFingerprint(_fingerprint(rgba), hasVisiblePixel);
}

String _fingerprint(Uint8List bytes) {
  // FNV-1a is sufficient here: source SHA-256 values are pinned by the
  // downloader, while this compact hash keeps test failures readable.
  int hash = 0xcbf29ce484222325;
  for (final int byte in bytes) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

class _PixelFingerprint {
  const _PixelFingerprint(this.hash, this.hasVisiblePixel);

  final String hash;
  final bool hasVisiblePixel;
}

Future<List<int>> _getFixtureWithSocket(
    Uri uri, int item, String animal) async {
  final Socket socket = await Socket.connect(uri.host, uri.port);
  try {
    socket.add(utf8.encode(
      'GET ${uri.path}?${uri.query} HTTP/1.1\r\n'
      'Host: ${uri.host}:${uri.port}\r\n'
      'Connection: close\r\n\r\n',
    ));
    await socket.flush();
    final List<int> response = await socket.fold<List<int>>(
      <int>[],
      (List<int> output, List<int> chunk) => output..addAll(chunk),
    );
    final int headerEnd = _indexOfHeaderEnd(response);
    expect(headerEnd, greaterThanOrEqualTo(0));
    final String headers = ascii.decode(response.sublist(0, headerEnd));
    expect(headers, startsWith('HTTP/1.1 200'));
    expect(
      headers.toLowerCase(),
      contains('x-power-image-fixture: $item'),
    );
    expect(
      headers.toLowerCase(),
      contains('x-power-image-animal: $animal'),
    );
    return response.sublist(headerEnd + 4);
  } finally {
    socket.destroy();
  }
}

int _indexOfHeaderEnd(List<int> bytes) {
  for (int index = 0; index <= bytes.length - 4; index++) {
    if (bytes[index] == 13 &&
        bytes[index + 1] == 10 &&
        bytes[index + 2] == 13 &&
        bytes[index + 3] == 10) {
      return index;
    }
  }
  return -1;
}
