import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:power_image/power_image.dart';
import 'package:power_image/src/common/power_image_channel.dart';
import 'package:power_image/src/common/power_image_request.dart';

Uint8List get _onePixelPng => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

void main() {
  test('decode size buckets share nearby physical-size keys', () async {
    PowerImageProvider provider(double width, int bucket) {
      return PowerImageProvider.options(PowerImageRequestOptions.network(
        'https://images.test/bucket.webp',
        renderingType: renderingTypeTexture,
        imageWidth: width,
        imageHeight: width,
        decodeSizeBucket: bucket,
      ));
    }

    final PowerImageProvider bucketedFirst = await provider(50, 16).obtainKey(
      const ImageConfiguration(devicePixelRatio: 1),
    );
    final PowerImageProvider bucketedSecond = await provider(60, 16).obtainKey(
      const ImageConfiguration(devicePixelRatio: 1),
    );
    final PowerImageProvider exactFirst = await provider(50, 1).obtainKey(
      const ImageConfiguration(devicePixelRatio: 1),
    );
    final PowerImageProvider exactSecond = await provider(60, 1).obtainKey(
      const ImageConfiguration(devicePixelRatio: 1),
    );

    expect(bucketedFirst, bucketedSecond);
    expect(exactFirst, isNot(exactSecond));
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryRawBytesCache cache;
  late _TestHttpClient client;

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    cache = _MemoryRawBytesCache();
    client = _TestHttpClient();
    debugNetworkImageHttpClientProvider = () => client;
    PowerImageLoader.instance.channel.impl = _NoopChannel();
    PowerImageLoader.instance.setup(PowerImageSetupOptions(
      renderingTypeTexture,
      rawBytesCache: cache,
    ));
  });

  tearDown(() {
    debugNetworkImageHttpClientProvider = null;
    PowerImageLoader.instance.setup(
      PowerImageSetupOptions(renderingTypeTexture),
    );
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });

  test('raw-byte cache hit decodes without a network request', () async {
    cache.values['stable-avatar'] = _onePixelPng;

    final ImageInfo image = await _resolve(_provider(
      cacheKey: 'stable-avatar',
    ));

    expect(image.image.width, 1);
    expect(image.image.height, 1);
    expect(client.requestCount, 0);
    expect(cache.readKeys, <String>['stable-avatar']);
    expect(cache.touchKeys, isEmpty);
    _drawFrame();
    await Future<void>.delayed(Duration.zero);
    expect(cache.touchKeys, <String>['stable-avatar']);
    image.dispose();
  });

  test('buffer-capable cache bypasses the Uint8List read path', () async {
    final _BufferMemoryRawBytesCache bufferCache = _BufferMemoryRawBytesCache();
    bufferCache.values['stable-avatar'] = _onePixelPng;
    cache = bufferCache;
    PowerImageLoader.instance.setup(PowerImageSetupOptions(
      renderingTypeTexture,
      rawBytesCache: bufferCache,
    ));

    final ImageInfo image = await _resolve(_provider(
      cacheKey: 'stable-avatar',
    ));

    expect(image.image.width, 1);
    expect(client.requestCount, 0);
    expect(bufferCache.bufferReadKeys, <String>['stable-avatar']);
    expect(bufferCache.readKeys, isEmpty);
    image.dispose();
  });

  test('decode fit preserves contain, cover and exact geometry', () async {
    final Uint8List bytes = await _pngBytes(10, 5);
    cache.values.addAll(<String, Uint8List>{
      'contain': bytes,
      'cover': bytes,
      'exact': bytes,
    });

    final ImageInfo contain = await _resolve(_provider(
      cacheKey: 'contain',
      imageWidth: 4,
      imageHeight: 4,
      decodeSizeBucket: 1,
      decodeFit: PowerImageDecodeFit.contain,
    ));
    final ImageInfo cover = await _resolve(_provider(
      cacheKey: 'cover',
      imageWidth: 4,
      imageHeight: 4,
      decodeSizeBucket: 1,
      decodeFit: PowerImageDecodeFit.cover,
    ));
    final ImageInfo exact = await _resolve(_provider(
      cacheKey: 'exact',
      imageWidth: 4,
      imageHeight: 4,
      decodeSizeBucket: 1,
      decodeFit: PowerImageDecodeFit.exact,
    ));

    expect(<int>[contain.image.width, contain.image.height], <int>[4, 2]);
    expect(<int>[cover.image.width, cover.image.height], <int>[8, 4]);
    expect(<int>[exact.image.width, exact.image.height], <int>[4, 4]);
    contain.dispose();
    cover.dispose();
    exact.dispose();
  });

  test('headers are sent and cache write waits for the first frame', () async {
    client.handler = (_) async => _TestHttpClientResponse.ok(_onePixelPng);

    final ImageInfo image = await _resolve(_provider(
      headers: const <String, String>{
        HttpHeaders.authorizationHeader: 'Bearer test-token',
      },
      cacheKey: 'authorized-avatar',
    ));
    expect(cache.writeKeys, isEmpty);
    _drawFrame();
    await cache.firstWrite.future.timeout(const Duration(seconds: 2));

    expect(
      client.requests.single.headers.value(HttpHeaders.authorizationHeader),
      'Bearer test-token',
    );
    expect(cache.writeKeys, <String>['authorized-avatar']);
    expect(cache.values['authorized-avatar'], orderedEquals(_onePixelPng));
    image.dispose();
  });

  test('corrupt cached bytes are evicted before network fallback', () async {
    client.handler = (_) async => _TestHttpClientResponse.ok(_onePixelPng);
    cache.values['corrupt'] = Uint8List.fromList(<int>[1, 2, 3]);

    final ImageInfo image = await _resolve(_provider(cacheKey: 'corrupt'));
    expect(cache.writeKeys, isEmpty);
    _drawFrame();
    await cache.firstWrite.future.timeout(const Duration(seconds: 2));

    expect(client.requestCount, 1);
    expect(cache.evictKeys, <String>['corrupt']);
    expect(cache.values['corrupt'], orderedEquals(_onePixelPng));
    image.dispose();
  });

  test('retryCount retries transient HTTP failures only', () async {
    client.handler = (int attempt) async {
      return attempt < 3
          ? _TestHttpClientResponse(HttpStatus.internalServerError)
          : _TestHttpClientResponse.ok(_onePixelPng);
    };

    final ImageInfo image = await _resolve(_provider(retryCount: 2));

    expect(client.requestCount, 3);
    image.dispose();
  });

  test('timeout is applied to every attempt', () async {
    client.handler = (_) => Completer<HttpClientResponse>().future;

    await expectLater(
      _resolve(_provider(
        timeout: const Duration(milliseconds: 20),
        retryCount: 1,
      )),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.requestCount, 2);
    expect(client.requests.every((_TestHttpClientRequest r) => r.wasAborted),
        isTrue);
  });

  test('cancel aborts the request and never retries', () async {
    client.handler = (_) => Completer<HttpClientResponse>().future;
    final PowerImageCancellationToken token = PowerImageCancellationToken();
    final Future<ImageInfo> image = _resolve(_provider(
      retryCount: 3,
      cancellationToken: token,
    ));
    await client.firstRequest.future.timeout(const Duration(seconds: 2));

    token.cancel('screen disposed');

    await expectLater(
      image,
      throwsA(isA<PowerImageRequestCancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(client.requestCount, 1);
    expect(client.requests.single.wasAborted, isTrue);
  });

  test('concurrent raw-byte misses share one network transfer', () async {
    final Completer<HttpClientResponse> response =
        Completer<HttpClientResponse>();
    client.handler = (_) => response.future;

    final Future<ImageInfo> first = _resolve(_provider(imageWidth: 10));
    await client.firstRequest.future.timeout(const Duration(seconds: 2));
    final Future<ImageInfo> second = _resolve(_provider(imageWidth: 20));
    await Future<void>.delayed(Duration.zero);

    expect(client.requestCount, 1);
    response.complete(_TestHttpClientResponse.ok(_onePixelPng));
    final List<ImageInfo> images = await Future.wait<ImageInfo>(
      <Future<ImageInfo>>[first, second],
    );
    expect(client.requestCount, 1);
    for (final ImageInfo image in images) {
      image.dispose();
    }
  });

  test('network options participate in provider identity', () {
    final PowerImageCancellationToken token = PowerImageCancellationToken();
    final PowerImageRequestOptions first = PowerImageRequestOptions.network(
      'https://example.test/image',
      renderingType: renderingTypeTexture,
      headers: const <String, String>{'x-b': '2', 'x-a': '1'},
      cacheKey: 'image-key',
      timeout: const Duration(seconds: 2),
      retryCount: 2,
      retryDelay: const Duration(milliseconds: 10),
      cancellationToken: token,
      cacheRawBytes: false,
    );
    final PowerImageRequestOptions equal = PowerImageRequestOptions.network(
      'https://example.test/image',
      renderingType: renderingTypeTexture,
      headers: const <String, String>{'x-a': '1', 'x-b': '2'},
      cacheKey: 'image-key',
      timeout: const Duration(seconds: 2),
      retryCount: 2,
      retryDelay: const Duration(milliseconds: 10),
      cancellationToken: token,
      cacheRawBytes: false,
    );
    final PowerImageRequestOptions differentHeaders =
        PowerImageRequestOptions.network(
      'https://example.test/image',
      renderingType: renderingTypeTexture,
      headers: const <String, String>{'x-a': 'different', 'x-b': '2'},
      cacheKey: 'image-key',
      timeout: const Duration(seconds: 2),
      retryCount: 2,
      retryDelay: const Duration(milliseconds: 10),
      cancellationToken: token,
      cacheRawBytes: false,
    );

    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect(first, isNot(differentHeaders));
  });
}

PowerImageProvider _provider({
  Map<String, String>? headers,
  String? cacheKey,
  Duration? timeout,
  int retryCount = 0,
  PowerImageCancellationToken? cancellationToken,
  double? imageWidth,
  double? imageHeight,
  int decodeSizeBucket = 16,
  PowerImageDecodeFit decodeFit = PowerImageDecodeFit.contain,
}) {
  return PowerImageProvider.options(PowerImageRequestOptions.network(
    'https://example.test/image-no-suffix',
    renderingType: renderingTypeTexture,
    networkBackend: PowerImageNetworkBackend.flutterCodec,
    headers: headers,
    cacheKey: cacheKey,
    timeout: timeout,
    retryCount: retryCount,
    cancellationToken: cancellationToken,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    decodeSizeBucket: decodeSizeBucket,
    decodeFit: decodeFit,
  ));
}

Future<Uint8List> _pngBytes(int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF123456), ui.BlendMode.src);
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(width, height);
  final ByteData data =
      (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<ImageInfo> _resolve(PowerImageProvider provider) {
  final Completer<ImageInfo> completer = Completer<ImageInfo>();
  final ImageStream stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (ImageInfo image, bool synchronousCall) {
      if (!completer.isCompleted) {
        completer.complete(image);
      }
      stream.removeListener(listener);
    },
    onError: (Object error, StackTrace? stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 5));
}

void _drawFrame() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  binding.handleBeginFrame(Duration.zero);
  binding.handleDrawFrame();
}

class _MemoryRawBytesCache
    implements PowerImageRawBytesCache, PowerImageRawBytesCacheBatch {
  final Map<String, Uint8List> values = <String, Uint8List>{};
  final List<String> readKeys = <String>[];
  final List<String> writeKeys = <String>[];
  final List<String> evictKeys = <String>[];
  final List<String> touchKeys = <String>[];
  final Completer<void> firstWrite = Completer<void>();

  @override
  Future<Uint8List?> read(String key) async {
    readKeys.add(key);
    return values[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writeKeys.add(key);
    values[key] = Uint8List.fromList(bytes);
    if (!firstWrite.isCompleted) {
      firstWrite.complete();
    }
  }

  @override
  Future<void> writeAll(Map<String, Uint8List> entries) async {
    for (final MapEntry<String, Uint8List> entry in entries.entries) {
      await write(entry.key, entry.value);
    }
  }

  @override
  Future<void> touchAll(Iterable<String> keys) async {
    touchKeys.addAll(keys);
  }

  @override
  Future<void> evict(String key) async {
    evictKeys.add(key);
    values.remove(key);
  }
}

class _BufferMemoryRawBytesCache extends _MemoryRawBytesCache
    implements PowerImageRawBytesBufferCache {
  final List<String> bufferReadKeys = <String>[];

  @override
  Future<ui.ImmutableBuffer?> readBuffer(String key) async {
    bufferReadKeys.add(key);
    final Uint8List? bytes = values[key];
    return bytes == null ? null : ui.ImmutableBuffer.fromUint8List(bytes);
  }
}

typedef _ResponseHandler = Future<HttpClientResponse> Function(int attempt);

class _TestHttpClient extends Fake implements HttpClient {
  _ResponseHandler handler = (_) async =>
      throw StateError('Unexpected PowerImage network request in test.');
  final List<_TestHttpClientRequest> requests = <_TestHttpClientRequest>[];
  final Completer<void> firstRequest = Completer<void>();

  int get requestCount => requests.length;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final int attempt = requests.length + 1;
    final _TestHttpClientRequest request = _TestHttpClientRequest(
      () => handler(attempt),
    );
    requests.add(request);
    if (!firstRequest.isCompleted) {
      firstRequest.complete();
    }
    return request;
  }
}

class _TestHttpClientRequest extends Fake implements HttpClientRequest {
  _TestHttpClientRequest(this._close);

  final Future<HttpClientResponse> Function() _close;
  final _TestHttpHeaders _headers = _TestHttpHeaders();
  bool wasAborted = false;

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() => _close();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    wasAborted = true;
  }
}

class _TestHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, String> _values = <String, String>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => _values[name.toLowerCase()];
}

class _TestHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _TestHttpClientResponse(this.statusCode, [Uint8List? bytes])
      : _bytes = bytes ?? Uint8List(0);

  _TestHttpClientResponse.ok(Uint8List bytes) : this(HttpStatus.ok, bytes);

  final Uint8List _bytes;

  @override
  final int statusCode;

  @override
  int get contentLength => _bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopChannel implements PowerImageChannelImpl {
  @override
  void releaseImageRequests(List<PowerImageRequest> requests) {}

  @override
  void setDebugLogging(bool enabled) {}

  @override
  void setImageAnimationActive(String uniqueKey, bool active) {}

  @override
  void setup() {}

  @override
  void startImageRequests(List<PowerImageRequest> requests) {}
}
