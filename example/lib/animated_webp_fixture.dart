import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

const int benchmarkAnimalCount = 100;

final List<String> benchmarkAnimalNames = List<String>.generate(
  benchmarkAnimalCount,
  (int index) => 'animal_${index.toString().padLeft(3, '0')}',
  growable: false,
);

final List<String> benchmarkStaticWebpAssets = _benchmarkAssets(
  directory: 'static_webp',
  extension: 'webp',
);
final List<String> benchmarkAnimatedWebpAssets = _benchmarkAssets(
  directory: 'animated_webp',
  extension: 'webp',
);
final List<String> benchmarkGifAssets = _benchmarkAssets(
  directory: 'gif',
  extension: 'gif',
);

List<String> _benchmarkAssets({
  required String directory,
  required String extension,
}) {
  return List<String>.generate(
    benchmarkAnimalCount,
    (int index) => 'assets/benchmark/$directory/'
        'animal_${index.toString().padLeft(3, '0')}.$extension',
    growable: false,
  );
}

class AnimatedWebpFixture {
  AnimatedWebpFixture._(
    this._server,
    this._staticAnimalWebps,
    this._animatedAnimalWebps,
    this._animalGifs,
    this._png,
  );

  final HttpServer _server;
  final List<Uint8List> _staticAnimalWebps;
  final List<Uint8List> _animatedAnimalWebps;
  final List<Uint8List> _animalGifs;
  final Uint8List _png;

  String get url => 'http://127.0.0.1:${_server.port}/animals/animated.webp';
  String get pngUrl => 'http://127.0.0.1:${_server.port}/static.png';
  String get gifUrl => 'http://127.0.0.1:${_server.port}/animals/animated.gif';
  String get staticWebpUrl =>
      'http://127.0.0.1:${_server.port}/animals/static.webp';

  static Future<AnimatedWebpFixture> start() async {
    final List<List<String>> assetSets = <List<String>>[
      benchmarkStaticWebpAssets,
      benchmarkAnimatedWebpAssets,
      benchmarkGifAssets,
    ];
    if (benchmarkAnimalNames.length != benchmarkAnimalCount ||
        assetSets.any(
            (List<String> assets) => assets.length != benchmarkAnimalCount)) {
      throw StateError(
          'The benchmark requires exactly 100 fixtures per format.');
    }
    final List<List<Uint8List>> images = await Future.wait(
      assetSets.map(_loadAssets),
    );
    final ByteData pngData =
        await rootBundle.load('assets/images/flutter_asset_lena_png.png');
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
    final AnimatedWebpFixture fixture = AnimatedWebpFixture._(
      server,
      images[0],
      images[1],
      images[2],
      pngData.buffer.asUint8List(
        pngData.offsetInBytes,
        pngData.lengthInBytes,
      ),
    );
    server.listen(fixture._serve);
    return fixture;
  }

  static Future<List<Uint8List>> _loadAssets(List<String> assets) {
    return Future.wait(
      assets.map((String asset) async {
        final ByteData data = await rootBundle.load(asset);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }),
    );
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    final int? item = int.tryParse(request.uri.queryParameters['item'] ?? '');
    late final Uint8List bytes;
    late final ContentType contentType;
    late final String fixtureName;

    if (item != null &&
        item >= 0 &&
        item < benchmarkAnimalCount &&
        request.uri.path == '/animals/static.webp') {
      bytes = _staticAnimalWebps[item];
      contentType = ContentType('image', 'webp');
      fixtureName = 'static_webp';
      _setAnimalHeaders(request.response, item);
    } else if (item != null &&
        item >= 0 &&
        item < benchmarkAnimalCount &&
        request.uri.path == '/animals/animated.webp') {
      bytes = _animatedAnimalWebps[item];
      contentType = ContentType('image', 'webp');
      fixtureName = 'animated_webp';
      _setAnimalHeaders(request.response, item);
    } else if (item != null &&
        item >= 0 &&
        item < benchmarkAnimalCount &&
        request.uri.path == '/animals/animated.gif') {
      bytes = _animalGifs[item];
      contentType = ContentType('image', 'gif');
      fixtureName = 'animated_gif';
      _setAnimalHeaders(request.response, item);
    } else if (request.uri.path == '/static.png') {
      bytes = _png;
      contentType = ContentType('image', 'png');
      fixtureName = 'static_png';
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response.headers.contentType = contentType;
    request.response.headers
        .set(HttpHeaders.cacheControlHeader, 'public,max-age=31536000');
    request.response.headers.set('x-power-image-format', fixtureName);
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }

  void _setAnimalHeaders(HttpResponse response, int item) {
    response.headers.set('x-power-image-fixture', item.toString());
    response.headers.set(
      'x-power-image-animal',
      benchmarkAnimalNames[item],
    );
  }
}
