import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:power_image/src/common/power_image_provider.dart';
import 'package:power_image/src/options/power_image_request_options.dart';
import 'package:power_image_ext/image_info_ext.dart';

import '../../power_image.dart';

class PowerTextureImageProvider extends PowerImageProvider {
  PowerTextureImageProvider(PowerImageRequestOptions options) : super(options);

  @override
  ImageStreamCompleter loadImage(
    PowerImageProvider key,
    ImageDecoderCallback decode,
  ) {
    bool requestReleased = false;

    void releaseRequest() {
      if (requestReleased) {
        return;
      }
      requestReleased = true;
      PowerImageLoader.instance.releaseImageRequest(options);
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
    }

    late final _PowerTextureImageStreamCompleter completer;
    completer = _PowerTextureImageStreamCompleter(
      result: loadNativeResult(key),
      decode: decode,
      createNativeImageInfo: createImageInfo,
      releaseRequest: releaseRequest,
    );
    return completer;
  }

  @override
  FutureOr<ImageInfo> createImageInfo(Map map) {
    return PowerTextureImageInfo.create(
      textureId: map['textureId'],
      width: map['width'],
      height: map['height'],
    );
  }
}

/// Switches between a real native texture image and a real Flutter codec
/// without publishing placeholder metadata or resolving a nested provider.
class _PowerTextureImageStreamCompleter extends ImageStreamCompleter {
  _PowerTextureImageStreamCompleter({
    required Future<Map> result,
    required ImageDecoderCallback decode,
    required FutureOr<ImageInfo> Function(Map map) createNativeImageInfo,
    required this.releaseRequest,
  }) {
    _load(result, decode, createNativeImageInfo);
  }

  final VoidCallback releaseRequest;
  ImageStreamCompleter? _codecCompleter;
  ImageStreamListener? _codecListener;
  int _listenerCount = 0;
  bool _codecListenerAttached = false;
  bool _nativeReleaseBound = false;

  Future<void> _load(
    Future<Map> result,
    ImageDecoderCallback decode,
    FutureOr<ImageInfo> Function(Map map) createNativeImageInfo,
  ) async {
    try {
      final Map map = await result;
      if (_isFlutterCodecResult(map)) {
        _codecCompleter = MultiFrameImageStreamCompleter(
          codec: _createCodec(map, decode),
          scale: 1.0,
          debugLabel: 'power_image_flutter_codec',
        );
        _codecListener = ImageStreamListener(
          (ImageInfo image, bool synchronousCall) {
            setImage(image.clone());
          },
          onChunk: reportImageChunkEvent,
          onError: (Object exception, StackTrace? stackTrace) {
            reportError(
              context: ErrorDescription('decoding a PowerImage encoded image'),
              exception: exception,
              stack: stackTrace,
              silent: true,
            );
          },
        );
        _attachCodecListener();
        return;
      }

      _bindNativeRelease();
      setImage(await createNativeImageInfo(map));
    } catch (exception, stackTrace) {
      releaseRequest();
      reportError(
        context: ErrorDescription('loading a PowerImage texture'),
        exception: exception,
        stack: stackTrace,
        silent: true,
      );
    }
  }

  void _bindNativeRelease() {
    if (_nativeReleaseBound) {
      return;
    }
    _nativeReleaseBound = true;
    if (!hasListeners) {
      scheduleMicrotask(_releaseWhenUnused);
      return;
    }
    addOnLastListenerRemovedCallback(releaseRequest);
  }

  void _releaseWhenUnused() {
    if (hasListeners) {
      addOnLastListenerRemovedCallback(releaseRequest);
    } else {
      releaseRequest();
    }
  }

  static bool _isFlutterCodecResult(Map map) {
    if (map['renderingBackend'] != 'flutterCodec') {
      return false;
    }
    final Object? data = map['encodedData'];
    final Object? filePath = map['encodedFilePath'];
    return (data is Uint8List && data.isNotEmpty) ||
        (filePath is String && filePath.isNotEmpty);
  }

  static Future<ui.Codec> _createCodec(
    Map map,
    ImageDecoderCallback decode,
  ) async {
    final Object? data = map['encodedData'];
    final ui.ImmutableBuffer buffer;
    if (data is Uint8List && data.isNotEmpty) {
      buffer = await ui.ImmutableBuffer.fromUint8List(data);
    } else {
      buffer = await ui.ImmutableBuffer.fromFilePath(
        map['encodedFilePath'] as String,
      );
    }

    final int? targetWidth = _validDimension(map['targetWidth']);
    final int? targetHeight = _validDimension(map['targetHeight']);
    return decode(
      buffer,
      getTargetSize: targetWidth == null && targetHeight == null
          ? null
          : (int intrinsicWidth, int intrinsicHeight) => ui.TargetImageSize(
                width: targetWidth,
                height: targetHeight,
              ),
    );
  }

  static int? _validDimension(Object? value) {
    return value is int && value > 0 ? value : null;
  }

  @override
  void addListener(ImageStreamListener listener) {
    _listenerCount += 1;
    super.addListener(listener);
    _attachCodecListener();
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (_listenerCount > 0) {
      _listenerCount -= 1;
    }
    if (_listenerCount == 0) {
      _detachCodecListener();
    }
  }

  void _attachCodecListener() {
    final ImageStreamCompleter? codecCompleter = _codecCompleter;
    final ImageStreamListener? codecListener = _codecListener;
    if (_listenerCount == 0 ||
        _codecListenerAttached ||
        codecCompleter == null ||
        codecListener == null) {
      return;
    }
    codecCompleter.addListener(codecListener);
    _codecListenerAttached = true;
  }

  void _detachCodecListener() {
    if (!_codecListenerAttached) {
      return;
    }
    _codecCompleter!.removeListener(_codecListener!);
    _codecListenerAttached = false;
  }
}
