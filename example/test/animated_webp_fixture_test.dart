import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:power_image_example/animated_webp_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('benchmark uses 20 visually distinct animated WebP files', () async {
    expect(benchmarkAnimatedWebpAssets, hasLength(benchmarkAnimatedWebpCount));
    expect(benchmarkAnimatedWebpAnimalNames,
        hasLength(benchmarkAnimatedWebpCount));
    expect(benchmarkAnimatedWebpAnimalNames.toSet(),
        hasLength(benchmarkAnimatedWebpCount));

    final Set<String> encodedFiles = <String>{};
    final Set<String> animations = <String>{};
    for (int index = 0; index < benchmarkAnimatedWebpCount; index++) {
      final String asset = benchmarkAnimatedWebpAssets[index];
      final String animal = benchmarkAnimatedWebpAnimalNames[index];
      expect(
          asset, endsWith('_${index.toString().padLeft(2, '0')}_$animal.webp'));
      final ByteData data = await rootBundle.load(asset);
      final Uint8List bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      encodedFiles.add(_fingerprint(bytes));

      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      expect(codec.frameCount, greaterThan(1),
          reason: '$asset is not animated');
      expect(codec.repetitionCount, isNot(0),
          reason: '$asset does not loop as an animation');

      final Set<String> framePixels = <String>{};
      final List<String> frameSequence = <String>[];
      bool hasVisiblePixel = false;
      for (int frameIndex = 0; frameIndex < codec.frameCount; frameIndex++) {
        final ui.FrameInfo frame = await codec.getNextFrame();
        expect(frame.image.width, 512);
        expect(frame.image.height, 512);

        final _PixelFingerprint pixels = await _rgbaFingerprint(frame.image);
        framePixels.add(pixels.hash);
        frameSequence.add('${frame.duration.inMicroseconds}:${pixels.hash}');
        hasVisiblePixel |= pixels.hasVisiblePixel;
        frame.image.dispose();
      }
      expect(framePixels.length, greaterThan(1),
          reason: '$asset has no visible frame changes');
      expect(hasVisiblePixel, isTrue, reason: '$asset is fully transparent');
      animations.add(frameSequence.join('|'));
      codec.dispose();
    }

    expect(encodedFiles, hasLength(benchmarkAnimatedWebpCount),
        reason: 'Every benchmark item must use different encoded bytes');
    expect(animations, hasLength(benchmarkAnimatedWebpCount),
        reason: 'Every benchmark item must have a different frame sequence');
  });

  test('loopback server returns the requested unique WebP fixture', () async {
    final AnimatedWebpFixture fixture = await AnimatedWebpFixture.start();
    final Set<String> responses = <String>{};
    try {
      for (int item = 0; item < benchmarkAnimatedWebpCount; item++) {
        final Uri uri = Uri.parse('${fixture.url}?library=test&item=$item');
        final List<int> bytes = await _getFixtureWithSocket(
          uri,
          item,
          benchmarkAnimatedWebpAnimalNames[item],
        );
        responses.add(_fingerprint(Uint8List.fromList(bytes)));
      }
    } finally {
      await fixture.close();
    }

    expect(responses, hasLength(benchmarkAnimatedWebpCount),
        reason: 'The HTTP benchmark must serve 20 different files');
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
