import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

const int benchmarkAnimalCount = 100;

const List<String> benchmarkGiphyAnimatedWebpAssets = <String>[
  'assets/benchmark/giphy_webp/giphy_01_IRFQYGCokErS0.webp',
  'assets/benchmark/giphy_webp/giphy_02_3ohhwFhUCOXOJfuttC.webp',
  'assets/benchmark/giphy_webp/giphy_03_KG4PMQ0jyimywxNt8i.webp',
  'assets/benchmark/giphy_webp/giphy_04_11ASZtb7vdJagM.webp',
  'assets/benchmark/giphy_webp/giphy_05_xThuWu82QD3pj4wvEQ.webp',
  'assets/benchmark/giphy_webp/giphy_06_OwlW7RLoPdPCB2MNQ8.webp',
  'assets/benchmark/giphy_webp/giphy_07_51LroAULHlkqY.webp',
  'assets/benchmark/giphy_webp/giphy_08_T8Dhl1KPyzRqU.webp',
  'assets/benchmark/giphy_webp/giphy_09_BcQDiC3iLcbjG.webp',
  'assets/benchmark/giphy_webp/giphy_10_6LygV2CaXxxaDDCopf.webp',
  'assets/benchmark/giphy_webp/giphy_11_4EFt4UAegpqTy3nVce.webp',
  'assets/benchmark/giphy_webp/giphy_12_OhkMiKX0uMmLC.webp',
  'assets/benchmark/giphy_webp/giphy_13_nv99yd56AMNDa.webp',
  'assets/benchmark/giphy_webp/giphy_14_8TkagzJHXLWmI.webp',
  'assets/benchmark/giphy_webp/giphy_15_3oEjI6SIIHBdRxXI40.webp',
  'assets/benchmark/giphy_webp/giphy_16_FDBoszbe5ZVmY8nj8E.webp',
  'assets/benchmark/giphy_webp/giphy_17_l0HlTF1SDqER7VBCM.webp',
  'assets/benchmark/giphy_webp/giphy_18_AWNxDbtHGIJDW.webp',
  'assets/benchmark/giphy_webp/giphy_19_brEis8EBTBO4flSV8i.webp',
  'assets/benchmark/giphy_webp/giphy_20_PaSSGJlzQCwTlvG29p.webp',
];

/// Stable shortest-loop-first order used by every steady-state implementation.
/// It lets the bounded frame-cache prototype spend its budget on animations
/// that actually repeat during the sampling window without changing inputs.
const List<int> benchmarkGiphyShortestLoopFirst = <int>[
  16,
  0,
  2,
  11,
  14,
  1,
  4,
  12,
  15,
  19,
  6,
  10,
  17,
  8,
  5,
  7,
  18,
  9,
  13,
  3,
];

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
    this._giphyAnimatedWebps,
    this._png,
  );

  final HttpServer _server;
  final List<Uint8List> _staticAnimalWebps;
  final List<Uint8List> _animatedAnimalWebps;
  final List<Uint8List> _animalGifs;
  final List<Uint8List> _giphyAnimatedWebps;
  final Uint8List _png;

  String get url => 'http://127.0.0.1:${_server.port}/animals/animated.webp';
  String get pngUrl => 'http://127.0.0.1:${_server.port}/static.png';
  String get gifUrl => 'http://127.0.0.1:${_server.port}/animals/animated.gif';
  String get staticWebpUrl =>
      'http://127.0.0.1:${_server.port}/animals/static.webp';
  String get giphyWebpUrl =>
      'http://127.0.0.1:${_server.port}/giphy/animated.webp';

  static Future<AnimatedWebpFixture> start() async {
    final List<List<String>> assetSets = <List<String>>[
      benchmarkStaticWebpAssets,
      benchmarkAnimatedWebpAssets,
      benchmarkGifAssets,
      benchmarkGiphyAnimatedWebpAssets,
    ];
    if (benchmarkAnimalNames.length != benchmarkAnimalCount ||
        assetSets.take(3).any(
            (List<String> assets) => assets.length != benchmarkAnimalCount)) {
      throw StateError(
          'The benchmark requires exactly 100 fixtures per format.');
    }
    if (benchmarkGiphyAnimatedWebpAssets.length != 20) {
      throw StateError('The steady-state benchmark requires 20 GIPHY files.');
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
      images[3],
      pngData.buffer.asUint8List(
        pngData.offsetInBytes,
        pngData.lengthInBytes,
      ),
    );
    server.listen(fixture._serve);
    return fixture;
  }

  static Future<AnimatedWebpFixture> startGiphyOnly() async {
    if (benchmarkGiphyAnimatedWebpAssets.length != 20) {
      throw StateError('The steady-state benchmark requires 20 GIPHY files.');
    }
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
    final AnimatedWebpFixture fixture = AnimatedWebpFixture._(
      server,
      <Uint8List>[],
      <Uint8List>[],
      <Uint8List>[],
      <Uint8List>[],
      Uint8List(0),
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
        item < benchmarkGiphyAnimatedWebpAssets.length &&
        request.uri.path == '/giphy/animated.webp') {
      if (_giphyAnimatedWebps.isEmpty) {
        final ByteData data =
            await rootBundle.load(benchmarkGiphyAnimatedWebpAssets[item]);
        bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } else {
        bytes = _giphyAnimatedWebps[item];
      }
      contentType = ContentType('image', 'webp');
      fixtureName = 'giphy_animated_webp';
      request.response.headers.set('x-power-image-fixture', item.toString());
    } else if (item != null &&
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
