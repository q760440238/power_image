import 'dart:io';

import 'package:flutter/services.dart';

const int benchmarkAnimatedWebpCount = 20;

const List<String> benchmarkAnimatedWebpAnimalNames = <String>[
  'dog',
  'cow',
  'unicorn',
  'lizard',
  'dragon',
  'trex',
  'turtle',
  'crocodile',
  'snake',
  'frog',
  'rabbit',
  'rat',
  'pig',
  'horse',
  'kangaroo',
  'gorilla',
  'bird',
  'owl',
  'dolphin',
  'butterfly',
];

const List<String> benchmarkAnimatedWebpAssets = <String>[
  'assets/benchmark/animal_00_dog.webp',
  'assets/benchmark/animal_01_cow.webp',
  'assets/benchmark/animal_02_unicorn.webp',
  'assets/benchmark/animal_03_lizard.webp',
  'assets/benchmark/animal_04_dragon.webp',
  'assets/benchmark/animal_05_trex.webp',
  'assets/benchmark/animal_06_turtle.webp',
  'assets/benchmark/animal_07_crocodile.webp',
  'assets/benchmark/animal_08_snake.webp',
  'assets/benchmark/animal_09_frog.webp',
  'assets/benchmark/animal_10_rabbit.webp',
  'assets/benchmark/animal_11_rat.webp',
  'assets/benchmark/animal_12_pig.webp',
  'assets/benchmark/animal_13_horse.webp',
  'assets/benchmark/animal_14_kangaroo.webp',
  'assets/benchmark/animal_15_gorilla.webp',
  'assets/benchmark/animal_16_bird.webp',
  'assets/benchmark/animal_17_owl.webp',
  'assets/benchmark/animal_18_dolphin.webp',
  'assets/benchmark/animal_19_butterfly.webp',
];

class AnimatedWebpFixture {
  AnimatedWebpFixture._(this._server, this._images);

  final HttpServer _server;
  final List<Uint8List> _images;

  String get url => 'http://127.0.0.1:${_server.port}/animated.webp';

  static Future<AnimatedWebpFixture> start() async {
    if (benchmarkAnimatedWebpAssets.length != benchmarkAnimatedWebpCount ||
        benchmarkAnimatedWebpAnimalNames.length != benchmarkAnimatedWebpCount) {
      throw StateError('The benchmark requires exactly 20 WebP fixtures.');
    }
    final List<Uint8List> images = await Future.wait(
      benchmarkAnimatedWebpAssets.map((String asset) async {
        final ByteData data = await rootBundle.load(asset);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }),
    );
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0, shared: true);
    final AnimatedWebpFixture fixture = AnimatedWebpFixture._(server, images);
    server.listen(fixture._serve);
    return fixture;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve(HttpRequest request) async {
    final int? item = int.tryParse(request.uri.queryParameters['item'] ?? '');
    if (request.uri.path != '/animated.webp' ||
        item == null ||
        item < 0 ||
        item >= _images.length) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final Uint8List bytes = _images[item];
    request.response.headers.contentType = ContentType('image', 'webp');
    request.response.headers
        .set(HttpHeaders.cacheControlHeader, 'public,max-age=31536000');
    request.response.headers.set('x-power-image-fixture', item.toString());
    request.response.headers
        .set('x-power-image-animal', benchmarkAnimatedWebpAnimalNames[item]);
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }
}
