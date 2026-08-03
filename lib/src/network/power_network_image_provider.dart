import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../common/power_image_loader.dart';
import '../common/power_image_provider.dart';
import '../options/power_image_request_options.dart';
import '../options/power_image_request_options_src.dart';
import 'power_image_network_controls.dart';
import 'power_image_task_scheduler.dart';

/// A single cached provider that downloads HTTP(S) bytes and hands them
/// directly to Flutter's codec. The codec identifies formats from content,
/// independent of URL suffixes, redirects and query strings.
class PowerNetworkImageProvider extends PowerImageProvider {
  PowerNetworkImageProvider(PowerImageRequestOptions options)
      : _targetWidth = null,
        _targetHeight = null,
        super(options);

  PowerNetworkImageProvider._(
    PowerImageRequestOptions options,
    this._targetWidth,
    this._targetHeight,
  ) : super(options);

  final int? _targetWidth;
  final int? _targetHeight;

  String get url => (options.src as PowerImageRequestOptionsSrcNormal).src;

  @override
  Future<PowerImageProvider> obtainKey(ImageConfiguration configuration) {
    final double devicePixelRatio = configuration.devicePixelRatio ?? 1.0;
    return SynchronousFuture<PowerImageProvider>(PowerNetworkImageProvider._(
      options,
      _physicalPixels(options.imageWidth, devicePixelRatio),
      _physicalPixels(options.imageHeight, devicePixelRatio),
    ));
  }

  @override
  ImageStreamCompleter loadImage(
    PowerImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final PowerNetworkImageProvider networkKey =
        key as PowerNetworkImageProvider;
    final StreamController<ImageChunkEvent> chunkEvents =
        StreamController<ImageChunkEvent>();
    final _PowerNetworkLoadController loadController =
        _PowerNetworkLoadController(networkKey.options.networkPriority);
    _registerLoad(networkKey, loadController);
    final Future<ui.Codec> codec = _loadAsync(
      networkKey,
      chunkEvents,
      decode,
      loadController,
    ).whenComplete(() {
      _unregisterLoad(networkKey, loadController);
    });
    return _PowerNetworkImageStreamCompleter(
      codec: codec,
      chunkEvents: chunkEvents.stream,
      scale: networkKey.scale,
      debugLabel: networkKey.url,
      onFirstFramePresented: loadController.onFirstFramePresented,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<PowerNetworkImageProvider>('Image key', networkKey),
      ],
    );
  }

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    PowerImageProvider key,
    ImageErrorListener handleError,
  ) {
    final PowerNetworkImageProvider networkKey =
        key as PowerNetworkImageProvider;
    if (networkKey.options.networkPriority ==
        PowerImageNetworkPriority.visible) {
      _promoteLoads(networkKey);
    }
    super.resolveStreamForKey(configuration, stream, key, handleError);
    if (networkKey.options.networkPriority ==
        PowerImageNetworkPriority.visible) {
      _promoteLoads(networkKey);
    }
  }

  // Keep one client so direct-codec requests can reuse HTTP connections.
  // autoUncompress=false matches Flutter's NetworkImage byte accounting.
  static final HttpClient _sharedHttpClient = HttpClient()
    ..autoUncompress = false;
  static final PowerImageTaskScheduler _networkScheduler =
      PowerImageTaskScheduler(maxConcurrentTasks: 6);
  static final PowerImageTaskScheduler _firstFrameDecodeScheduler =
      PowerImageTaskScheduler(maxConcurrentTasks: 6);
  static final Map<_RawBytesFlightKey, _RawBytesFlight> _rawBytesFlights =
      <_RawBytesFlightKey, _RawBytesFlight>{};
  static final Map<PowerNetworkImageProvider, Set<_PowerNetworkLoadController>>
      _activeLoads =
      <PowerNetworkImageProvider, Set<_PowerNetworkLoadController>>{};

  static HttpClient get _httpClient {
    HttpClient? client;
    assert(() {
      if (debugNetworkImageHttpClientProvider != null) {
        client = debugNetworkImageHttpClientProvider!();
      }
      return true;
    }());
    return client ?? _sharedHttpClient;
  }

  Future<ui.Codec> _loadAsync(
    PowerNetworkImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
    _PowerNetworkLoadController loadController,
  ) async {
    try {
      final PowerImageCancellationToken? token = key.options.cancellationToken;
      token?.throwIfCancelled();

      final PowerImageRawBytesCache? cache = key.options.cacheRawBytes
          ? PowerImageLoader.instance.rawBytesCache
          : null;
      final String rawCacheKey = key.options.cacheKey ?? key.url;

      if (cache != null) {
        if (cache is PowerImageRawBytesBufferCache) {
          final PowerImageRawBytesBufferCache bufferCache =
              cache as PowerImageRawBytesBufferCache;
          final ui.ImmutableBuffer? cachedBuffer = await _readCacheBuffer(
            bufferCache,
            rawCacheKey,
            token,
          );
          if (token?.isCancelled ?? false) {
            cachedBuffer?.dispose();
            token!.throwIfCancelled();
          }
          if (cachedBuffer != null) {
            try {
              final ui.Codec codec = await _decodeBuffer(
                key,
                cachedBuffer,
                decode,
                loadController,
              );
              loadController.deferTouch(cache, rawCacheKey);
              return codec;
            } on PowerImageRequestCancelledException {
              rethrow;
            } catch (_) {
              // A corrupt/stale entry must not permanently poison the request.
              await _evictCache(cache, rawCacheKey);
              token?.throwIfCancelled();
            }
          }
        } else {
          final Uint8List? cachedBytes = await _readCache(
            cache,
            rawCacheKey,
            token,
          );
          token?.throwIfCancelled();
          if (cachedBytes != null && cachedBytes.isNotEmpty) {
            try {
              final ui.Codec codec = await _decodeBytes(
                key,
                cachedBytes,
                decode,
                loadController,
              );
              loadController.deferTouch(cache, rawCacheKey);
              return codec;
            } on PowerImageRequestCancelledException {
              rethrow;
            } catch (_) {
              // A corrupt/stale entry must not permanently poison the request.
              await _evictCache(cache, rawCacheKey);
              token?.throwIfCancelled();
            }
          }
        }
      }

      final Uint8List bytes = await _downloadSingleFlight(
        key,
        chunkEvents,
        loadController,
      );
      final ui.Codec codec = await _decodeBytes(
        key,
        bytes,
        decode,
        loadController,
      );

      // A first display must never wait for a disk write. Also cache only bytes
      // already accepted by Flutter's codec.
      if (cache != null) {
        loadController.deferWrite(cache, rawCacheKey, bytes);
      }
      return codec;
    } catch (_) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  Future<ui.Codec> _decodeBuffer(
    PowerNetworkImageProvider key,
    ui.ImmutableBuffer buffer,
    ImageDecoderCallback decode,
    _PowerNetworkLoadController loadController,
  ) async {
    final ui.Codec codec = await _decodeBufferNow(key, buffer, decode);
    return PowerImageFirstFrameCodec(
      codec: codec,
      scheduler: _firstFrameDecodeScheduler,
      priority: () => loadController.priority,
      onTaskScheduled: loadController.track,
    );
  }

  Future<ui.Codec> _decodeBufferNow(
    PowerNetworkImageProvider key,
    ui.ImmutableBuffer buffer,
    ImageDecoderCallback decode,
  ) async {
    if (key.options.cancellationToken?.isCancelled ?? false) {
      buffer.dispose();
      key.options.cancellationToken!.throwIfCancelled();
    }
    final int? targetWidth = key._targetWidth;
    final int? targetHeight = key._targetHeight;
    final ui.Codec codec = await decode(
      buffer,
      getTargetSize: targetWidth == null && targetHeight == null
          ? null
          : (int intrinsicWidth, int intrinsicHeight) => _fitTarget(
                intrinsicWidth,
                intrinsicHeight,
                targetWidth,
                targetHeight,
              ),
    );
    if (key.options.cancellationToken?.isCancelled ?? false) {
      codec.dispose();
      key.options.cancellationToken!.throwIfCancelled();
    }
    return codec;
  }

  Future<ui.Codec> _decodeBytes(
    PowerNetworkImageProvider key,
    Uint8List bytes,
    ImageDecoderCallback decode,
    _PowerNetworkLoadController loadController,
  ) async {
    final ui.Codec codec = await _decodeBytesNow(key, bytes, decode);
    return PowerImageFirstFrameCodec(
      codec: codec,
      scheduler: _firstFrameDecodeScheduler,
      priority: () => loadController.priority,
      onTaskScheduled: loadController.track,
    );
  }

  Future<ui.Codec> _decodeBytesNow(
    PowerNetworkImageProvider key,
    Uint8List bytes,
    ImageDecoderCallback decode,
  ) async {
    key.options.cancellationToken?.throwIfCancelled();
    final ui.ImmutableBuffer buffer =
        await ui.ImmutableBuffer.fromUint8List(bytes);
    return _decodeBufferNow(key, buffer, decode);
  }

  Future<Uint8List> _downloadSingleFlight(
    PowerNetworkImageProvider key,
    StreamController<ImageChunkEvent> chunkEvents,
    _PowerNetworkLoadController loadController,
  ) {
    final _RawBytesFlightKey flightKey = _RawBytesFlightKey.fromProvider(key);
    _RawBytesFlight? flight = _rawBytesFlights[flightKey];
    if (flight == null) {
      flight = _RawBytesFlight(
        scheduler: _networkScheduler,
        priority: loadController.priority,
        operation: (
          PowerImageCancellationToken token,
          void Function(int, int?) onProgress,
        ) {
          return _downloadWithRetry(key, onProgress, token);
        },
      );
      _rawBytesFlights[flightKey] = flight;
      final _RawBytesFlight registeredFlight = flight;
      flight.future.then<void>(
        (_) => _removeFlight(flightKey, registeredFlight),
        onError: (Object _, StackTrace __) {
          _removeFlight(flightKey, registeredFlight);
        },
      );
    }
    loadController.trackPromotion(flight.promote);
    return flight.join(key.options.cancellationToken, chunkEvents);
  }

  Future<Uint8List> _downloadWithRetry(
    PowerNetworkImageProvider key,
    void Function(int cumulative, int? total) onProgress,
    PowerImageCancellationToken token,
  ) async {
    int attempt = 0;
    while (true) {
      token.throwIfCancelled();
      try {
        return await _downloadOnce(key, onProgress, token);
      } catch (error) {
        token.throwIfCancelled();
        if (attempt >= key.options.retryCount || !_isRetryable(error)) {
          rethrow;
        }
        attempt += 1;
        await _waitBeforeRetry(key.options, token);
      }
    }
  }

  Future<Uint8List> _downloadOnce(
    PowerNetworkImageProvider key,
    void Function(int cumulative, int? total) onProgress,
    PowerImageCancellationToken token,
  ) {
    final Uri resolved = Uri.base.resolve(key.url);
    HttpClientRequest? request;
    bool stopped = false;
    Object? stopError;
    StackTrace? stopStack;

    void stop(Object error, [StackTrace? stackTrace]) {
      if (stopped) {
        return;
      }
      stopped = true;
      stopError = error;
      stopStack = stackTrace ?? StackTrace.current;
      request?.abort(error, stopStack);
    }

    Never throwStopped() {
      Error.throwWithStackTrace(stopError!, stopStack!);
    }

    final Future<Uint8List> operation = () async {
      request = await _httpClient.getUrl(resolved);
      if (stopped) {
        request!.abort(stopError, stopStack);
        throwStopped();
      }
      token.throwIfCancelled();
      key.options.headers?.forEach((String name, String value) {
        request!.headers.set(name, value);
      });
      final HttpClientResponse response = await request!.close();
      if (stopped) {
        throwStopped();
      }
      token.throwIfCancelled();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<List<int>>(<int>[]);
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: resolved,
        );
      }
      final Uint8List bytes = await consolidateHttpClientResponseBytes(
        response,
        onBytesReceived: (int cumulative, int? total) {
          onProgress(cumulative, total);
        },
      );
      if (stopped) {
        throwStopped();
      }
      token.throwIfCancelled();
      if (bytes.isEmpty) {
        throw StateError('PowerImage network response is empty: $resolved');
      }
      return bytes;
    }();

    VoidCallback? cancellationListener;
    final Completer<Uint8List> cancellationResult = Completer<Uint8List>.sync();
    cancellationListener = () {
      final PowerImageRequestCancelledException error =
          PowerImageRequestCancelledException(token.reason);
      final StackTrace stackTrace = StackTrace.current;
      stop(error, stackTrace);
      if (!cancellationResult.isCompleted) {
        cancellationResult.completeError(error, stackTrace);
      }
    };
    token.addListener(cancellationListener);

    Future<Uint8List> controlled = Future.any<Uint8List>(<Future<Uint8List>>[
      operation,
      cancellationResult.future,
    ]);
    final Duration? timeout = key.options.timeout;
    if (timeout != null) {
      controlled = controlled.timeout(timeout, onTimeout: () {
        final TimeoutException error = TimeoutException(
          'PowerImage network request timed out: $resolved',
          timeout,
        );
        stop(error);
        throw error;
      });
    }
    return controlled.whenComplete(() {
      final VoidCallback? listener = cancellationListener;
      if (listener != null) {
        token.removeListener(listener);
      }
    });
  }

  static bool _isRetryable(Object error) {
    if (error is PowerImageRequestCancelledException) {
      return false;
    }
    if (error is TimeoutException || error is IOException) {
      return true;
    }
    if (error is NetworkImageLoadException) {
      return error.statusCode == HttpStatus.requestTimeout ||
          error.statusCode == 429 ||
          error.statusCode >= HttpStatus.internalServerError;
    }
    return false;
  }

  static Future<void> _waitBeforeRetry(
    PowerImageRequestOptions options,
    PowerImageCancellationToken token,
  ) async {
    token.throwIfCancelled();
    if (options.retryDelay == Duration.zero) {
      return;
    }
    await _withCancellation<void>(
      Future<void>.delayed(options.retryDelay),
      token,
    );
  }

  static Future<ui.ImmutableBuffer?> _readCacheBuffer(
    PowerImageRawBytesBufferCache cache,
    String key,
    PowerImageCancellationToken? token,
  ) async {
    try {
      final Future<ui.ImmutableBuffer?> read = cache.readBuffer(key);
      if (token == null) {
        return await read;
      }
      return await _withCancellation<ui.ImmutableBuffer?>(
        read,
        token,
        onDiscard: (ui.ImmutableBuffer? buffer) => buffer?.dispose(),
      );
    } on PowerImageRequestCancelledException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _readCache(
    PowerImageRawBytesCache cache,
    String key,
    PowerImageCancellationToken? token,
  ) async {
    try {
      final Future<Uint8List?> read = cache.read(key);
      if (token == null) {
        return await read;
      }
      return await _withCancellation<Uint8List?>(
        read,
        token,
      );
    } on PowerImageRequestCancelledException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  static Future<T> _withCancellation<T>(
    Future<T> source,
    PowerImageCancellationToken token, {
    void Function(T value)? onDiscard,
  }) {
    final Completer<T> result = Completer<T>.sync();
    late final VoidCallback listener;

    void removeListener() {
      token.removeListener(listener);
    }

    listener = () {
      removeListener();
      if (!result.isCompleted) {
        result.completeError(
          PowerImageRequestCancelledException(token.reason),
          StackTrace.current,
        );
      }
    };
    token.addListener(listener);
    source.then<void>(
      (T value) {
        removeListener();
        if (!result.isCompleted) {
          result.complete(value);
        } else {
          onDiscard?.call(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        removeListener();
        if (!result.isCompleted) {
          result.completeError(error, stackTrace);
        }
      },
    );
    return result.future;
  }

  static Future<void> _evictCache(
    PowerImageRawBytesCache cache,
    String key,
  ) async {
    try {
      await cache.evict(key);
    } catch (_) {
      // The network fallback can still recover this request.
    }
  }

  static void _registerLoad(
    PowerNetworkImageProvider key,
    _PowerNetworkLoadController controller,
  ) {
    _activeLoads
        .putIfAbsent(key, () => <_PowerNetworkLoadController>{})
        .add(controller);
  }

  static void _unregisterLoad(
    PowerNetworkImageProvider key,
    _PowerNetworkLoadController controller,
  ) {
    final Set<_PowerNetworkLoadController>? loads = _activeLoads[key];
    loads?.remove(controller);
    if (loads != null && loads.isEmpty) {
      _activeLoads.remove(key);
    }
  }

  static void _promoteLoads(PowerNetworkImageProvider key) {
    final Set<_PowerNetworkLoadController>? loads = _activeLoads[key];
    if (loads == null) {
      return;
    }
    for (final _PowerNetworkLoadController load
        in loads.toList(growable: false)) {
      load.promote();
    }
  }

  static void _removeFlight(
    _RawBytesFlightKey key,
    _RawBytesFlight flight,
  ) {
    if (identical(_rawBytesFlights[key], flight)) {
      _rawBytesFlights.remove(key);
    }
  }

  @override
  FutureOr<ImageInfo> createImageInfo(Map map) {
    throw UnsupportedError(
      'PowerNetworkImageProvider decodes bytes directly in loadImage.',
    );
  }

  static int? _physicalPixels(double? logicalPixels, double devicePixelRatio) {
    if (logicalPixels == null || logicalPixels <= 0) {
      return null;
    }
    return math.max(1, (logicalPixels * devicePixelRatio).round());
  }

  static ui.TargetImageSize _fitTarget(
    int intrinsicWidth,
    int intrinsicHeight,
    int? requestedWidth,
    int? requestedHeight,
  ) {
    double resizeScale = 1.0;
    if (requestedWidth != null) {
      resizeScale = math.min(resizeScale, requestedWidth / intrinsicWidth);
    }
    if (requestedHeight != null) {
      resizeScale = math.min(resizeScale, requestedHeight / intrinsicHeight);
    }
    return ui.TargetImageSize(
      width: math.max(1, (intrinsicWidth * resizeScale).round()),
      height: math.max(1, (intrinsicHeight * resizeScale).round()),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PowerNetworkImageProvider &&
        other.options == options &&
        other.scale == scale &&
        other._targetWidth == _targetWidth &&
        other._targetHeight == _targetHeight;
  }

  @override
  int get hashCode => Object.hash(options, scale, _targetWidth, _targetHeight);
}

class _PowerNetworkImageStreamCompleter extends MultiFrameImageStreamCompleter {
  _PowerNetworkImageStreamCompleter({
    required super.codec,
    required super.scale,
    required super.chunkEvents,
    required super.debugLabel,
    required super.informationCollector,
    required this.onFirstFramePresented,
  });

  final VoidCallback onFirstFramePresented;
  bool _firstFrameScheduled = false;

  @override
  void setImage(ImageInfo image) {
    super.setImage(image);
    if (_firstFrameScheduled) {
      return;
    }
    _firstFrameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      onFirstFramePresented();
    }, debugLabel: 'PowerImage.rawBytesCacheAfterFirstFrame');
  }
}

class _PowerNetworkLoadController {
  _PowerNetworkLoadController(this.priority);

  PowerImageNetworkPriority priority;
  final Set<VoidCallback> _promotions = <VoidCallback>{};
  final Map<PowerImageRawBytesCache, _DeferredCacheMutation> _cacheMutations =
      <PowerImageRawBytesCache, _DeferredCacheMutation>{};
  bool _maintenanceSubmitted = false;

  void track<T>(PowerImageScheduledTask<T> task) {
    trackPromotion(task.promote);
  }

  void trackPromotion(VoidCallback promotion) {
    _promotions.add(promotion);
    if (priority == PowerImageNetworkPriority.visible) {
      promotion();
    }
  }

  void promote() {
    if (priority == PowerImageNetworkPriority.visible) {
      return;
    }
    priority = PowerImageNetworkPriority.visible;
    for (final VoidCallback promotion in _promotions.toList(growable: false)) {
      promotion();
    }
  }

  void deferWrite(
    PowerImageRawBytesCache cache,
    String key,
    Uint8List bytes,
  ) {
    _cacheMutations.putIfAbsent(cache, _DeferredCacheMutation.new).writes[key] =
        bytes;
  }

  void deferTouch(PowerImageRawBytesCache cache, String key) {
    _cacheMutations
        .putIfAbsent(cache, _DeferredCacheMutation.new)
        .touches
        .add(key);
  }

  void onFirstFramePresented() {
    if (_maintenanceSubmitted) {
      return;
    }
    _maintenanceSubmitted = true;
    for (final MapEntry<PowerImageRawBytesCache, _DeferredCacheMutation> entry
        in _cacheMutations.entries) {
      _PowerImageCacheMaintenanceQueue.enqueue(entry.key, entry.value);
    }
    _cacheMutations.clear();
    _promotions.clear();
  }
}

class _DeferredCacheMutation {
  final Map<String, Uint8List> writes = <String, Uint8List>{};
  final Set<String> touches = <String>{};

  void add(_DeferredCacheMutation other) {
    writes.addAll(other.writes);
    touches.addAll(other.touches);
  }
}

class _PowerImageCacheMaintenanceQueue {
  static final Map<PowerImageRawBytesCache, _DeferredCacheMutation> _pending =
      <PowerImageRawBytesCache, _DeferredCacheMutation>{};
  static final Map<PowerImageRawBytesCache, Future<void>> _workers =
      <PowerImageRawBytesCache, Future<void>>{};
  static bool _flushScheduled = false;

  static void enqueue(
    PowerImageRawBytesCache cache,
    _DeferredCacheMutation mutation,
  ) {
    _pending.putIfAbsent(cache, _DeferredCacheMutation.new).add(mutation);
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  static void _flush() {
    final Map<PowerImageRawBytesCache, _DeferredCacheMutation> batch =
        Map<PowerImageRawBytesCache, _DeferredCacheMutation>.from(_pending);
    _pending.clear();
    _flushScheduled = false;
    for (final MapEntry<PowerImageRawBytesCache, _DeferredCacheMutation> entry
        in batch.entries) {
      final Future<void> previous = _workers[entry.key] ?? Future<void>.value();
      late final Future<void> worker;
      worker = previous.then<void>((_) => _runBatch(entry.key, entry.value));
      _workers[entry.key] = worker;
      unawaited(worker.whenComplete(() {
        if (identical(_workers[entry.key], worker)) {
          _workers.remove(entry.key);
        }
      }));
    }
  }

  static Future<void> _runBatch(
    PowerImageRawBytesCache cache,
    _DeferredCacheMutation mutation,
  ) async {
    try {
      final Set<String> touches = mutation.touches
        ..removeAll(mutation.writes.keys);
      if (cache is PowerImageRawBytesCacheBatch) {
        final PowerImageRawBytesCacheBatch batchCache =
            cache as PowerImageRawBytesCacheBatch;
        if (touches.isNotEmpty) {
          await batchCache.touchAll(touches);
        }
        if (mutation.writes.isNotEmpty) {
          await batchCache.writeAll(mutation.writes);
        }
      } else if (mutation.writes.isNotEmpty) {
        for (final MapEntry<String, Uint8List> entry
            in mutation.writes.entries) {
          await cache.write(entry.key, entry.value);
        }
      }
    } catch (_) {
      // Cache maintenance must not turn a displayed image into a load failure.
    }
  }
}

class _RawBytesFlightKey {
  const _RawBytesFlightKey({
    required this.url,
    required this.headers,
    required this.timeout,
    required this.retryCount,
    required this.retryDelay,
  });

  factory _RawBytesFlightKey.fromProvider(PowerNetworkImageProvider provider) {
    final List<MapEntry<String, String>> headers =
        provider.options.headers?.entries.toList() ??
            <MapEntry<String, String>>[];
    headers
        .sort((MapEntry<String, String> left, MapEntry<String, String> right) {
      final int nameOrder =
          left.key.toLowerCase().compareTo(right.key.toLowerCase());
      return nameOrder != 0 ? nameOrder : left.value.compareTo(right.value);
    });
    final String headerSignature =
        headers.map((MapEntry<String, String> entry) {
      final String name = entry.key.toLowerCase();
      return '${name.length}:$name:${entry.value.length}:${entry.value}';
    }).join('|');
    return _RawBytesFlightKey(
      url: Uri.base.resolve(provider.url).toString(),
      headers: headerSignature,
      timeout: provider.options.timeout,
      retryCount: provider.options.retryCount,
      retryDelay: provider.options.retryDelay,
    );
  }

  final String url;
  final String headers;
  final Duration? timeout;
  final int retryCount;
  final Duration retryDelay;

  @override
  bool operator ==(Object other) {
    return other is _RawBytesFlightKey &&
        other.url == url &&
        other.headers == headers &&
        other.timeout == timeout &&
        other.retryCount == retryCount &&
        other.retryDelay == retryDelay;
  }

  @override
  int get hashCode =>
      Object.hash(url, headers, timeout, retryCount, retryDelay);
}

typedef _RawBytesOperation = Future<Uint8List> Function(
  PowerImageCancellationToken token,
  void Function(int cumulative, int? total) onProgress,
);

class _RawBytesFlight {
  _RawBytesFlight({
    required PowerImageTaskScheduler scheduler,
    required PowerImageNetworkPriority priority,
    required _RawBytesOperation operation,
  }) {
    _task = scheduler.schedule<Uint8List>(
      () => operation(_cancellationToken, _emitProgress),
      priority: priority,
    );
    future = _task.future;
    future.then<void>(
      (_) => _markCompleted(),
      onError: (Object _, StackTrace __) => _markCompleted(),
    );
  }

  final PowerImageCancellationToken _cancellationToken =
      PowerImageCancellationToken();
  final Set<StreamController<ImageChunkEvent>> _subscribers =
      <StreamController<ImageChunkEvent>>{};
  late final PowerImageScheduledTask<Uint8List> _task;
  late final Future<Uint8List> future;
  bool _completed = false;

  void promote() => _task.promote();

  Future<Uint8List> join(
    PowerImageCancellationToken? token,
    StreamController<ImageChunkEvent> chunkEvents,
  ) {
    _subscribers.add(chunkEvents);
    final Future<Uint8List> joined = token == null
        ? future
        : PowerNetworkImageProvider._withCancellation<Uint8List>(future, token);
    return joined.whenComplete(() {
      _subscribers.remove(chunkEvents);
      if (_subscribers.isEmpty && !_completed) {
        _cancellationToken.cancel('No raw-byte flight subscribers remain.');
      }
    });
  }

  void _emitProgress(int cumulative, int? total) {
    final ImageChunkEvent event = ImageChunkEvent(
      cumulativeBytesLoaded: cumulative,
      expectedTotalBytes: total,
    );
    for (final StreamController<ImageChunkEvent> subscriber
        in _subscribers.toList(growable: false)) {
      if (!subscriber.isClosed) {
        subscriber.add(event);
      }
    }
  }

  void _markCompleted() {
    _completed = true;
    _subscribers.clear();
  }
}
