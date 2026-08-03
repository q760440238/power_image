import 'package:flutter/foundation.dart';
import 'package:power_image/src/tools/power_num_safe.dart';

import '../network/power_image_network_controls.dart';
import 'power_image_request_options_src.dart';

const String renderingTypeExternal = "external";
const String renderingTypeTexture = "texture";
const String defaultGlobalRenderType = renderingTypeTexture;

const String imageTypeNetwork = "network";
const String imageTypeNativeAsset = "nativeAsset";
const String imageTypeAsset = "asset";
const String imageTypeFile = "file";

/// Selects who downloads and decodes a network image.
enum PowerImageNetworkBackend {
  /// HTTP(S) uses Flutter's codec; non-HTTP sources keep their native loader.
  auto,

  /// Require direct HTTP(S) download and content-based Flutter codec decoding.
  flutterCodec,

  /// Require the registered native loader and native rendering path.
  native,
}

class PowerImageRequestOptions {
  PowerImageRequestOptions(
      {required this.src,
      required this.imageType,
      required this.renderingType,
      this.networkBackend = PowerImageNetworkBackend.auto,
      Map<String, String>? headers,
      this.cacheKey,
      this.timeout,
      this.retryCount = 0,
      this.retryDelay = Duration.zero,
      this.cancellationToken,
      this.cacheRawBytes = true,
      this.networkPriority = PowerImageNetworkPriority.visible,
      double? imageWidth,
      double? imageHeight})
      : assert(timeout == null || timeout.inMicroseconds > 0,
            'timeout must be greater than zero.'),
        assert(retryCount >= 0, 'retryCount must not be negative.'),
        assert(!retryDelay.isNegative, 'retryDelay must not be negative.'),
        headers =
            headers == null ? null : Map<String, String>.unmodifiable(headers),
        assert(isNumValid(imageWidth), 'imageWidth is a Invalid value!'),
        _imageWidth = makeNumValid(imageWidth, null),
        assert(isNumValid(imageHeight), 'imageHeight is a Invalid value!'),
        _imageHeight = makeNumValid(imageHeight, null);

  PowerImageRequestOptions.network(String src,
      {required this.renderingType,
      this.networkBackend = PowerImageNetworkBackend.auto,
      Map<String, String>? headers,
      this.cacheKey,
      this.timeout,
      this.retryCount = 0,
      this.retryDelay = Duration.zero,
      this.cancellationToken,
      this.cacheRawBytes = true,
      this.networkPriority = PowerImageNetworkPriority.visible,
      double? imageWidth,
      double? imageHeight})
      : src = PowerImageRequestOptionsSrcNormal(src: src),
        imageType = imageTypeNetwork,
        assert(timeout == null || timeout.inMicroseconds > 0,
            'timeout must be greater than zero.'),
        assert(retryCount >= 0, 'retryCount must not be negative.'),
        assert(!retryDelay.isNegative, 'retryDelay must not be negative.'),
        headers =
            headers == null ? null : Map<String, String>.unmodifiable(headers),
        assert(isNumValid(imageWidth), 'imageWidth is a Invalid value!'),
        _imageWidth = makeNumValid(imageWidth, null),
        assert(isNumValid(imageHeight), 'imageHeight is a Invalid value!'),
        _imageHeight = makeNumValid(imageHeight, null);

  PowerImageRequestOptions.nativeAsset(String src,
      {required this.renderingType, double? imageWidth, double? imageHeight})
      : src = PowerImageRequestOptionsSrcNormal(src: src),
        imageType = imageTypeNativeAsset,
        networkBackend = PowerImageNetworkBackend.auto,
        headers = null,
        cacheKey = null,
        timeout = null,
        retryCount = 0,
        retryDelay = Duration.zero,
        cancellationToken = null,
        cacheRawBytes = true,
        networkPriority = PowerImageNetworkPriority.visible,
        assert(isNumValid(imageWidth), 'imageWidth is a Invalid value!'),
        _imageWidth = makeNumValid(imageWidth, null),
        assert(isNumValid(imageHeight), 'imageHeight is a Invalid value!'),
        _imageHeight = makeNumValid(imageHeight, null);

  PowerImageRequestOptions.asset(String src,
      {String? package,
      required this.renderingType,
      double? imageWidth,
      double? imageHeight})
      : src = PowerImageRequestOptionsSrcAsset(src: src, package: package),
        imageType = imageTypeAsset,
        networkBackend = PowerImageNetworkBackend.auto,
        headers = null,
        cacheKey = null,
        timeout = null,
        retryCount = 0,
        retryDelay = Duration.zero,
        cancellationToken = null,
        cacheRawBytes = true,
        networkPriority = PowerImageNetworkPriority.visible,
        assert(isNumValid(imageWidth), 'imageWidth is a Invalid value!'),
        _imageWidth = makeNumValid(imageWidth, null),
        assert(isNumValid(imageHeight), 'imageHeight is a Invalid value!'),
        _imageHeight = makeNumValid(imageHeight, null);

  PowerImageRequestOptions.file(String src,
      {required this.renderingType, double? imageWidth, double? imageHeight})
      : src = PowerImageRequestOptionsSrcNormal(src: src),
        imageType = imageTypeFile,
        networkBackend = PowerImageNetworkBackend.auto,
        headers = null,
        cacheKey = null,
        timeout = null,
        retryCount = 0,
        retryDelay = Duration.zero,
        cancellationToken = null,
        cacheRawBytes = true,
        networkPriority = PowerImageNetworkPriority.visible,
        assert(isNumValid(imageWidth), 'imageWidth is a Invalid value!'),
        _imageWidth = makeNumValid(imageWidth, null),
        assert(isNumValid(imageHeight), 'imageHeight is a Invalid value!'),
        _imageHeight = makeNumValid(imageHeight, null);

  final PowerImageRequestOptionsSrc src;
  final String imageType;
  final String? renderingType;
  final PowerImageNetworkBackend networkBackend;

  /// HTTP headers used by the direct Flutter network codec backend.
  final Map<String, String>? headers;

  /// Overrides the encoded-byte cache key. It does not alter the request URL.
  final String? cacheKey;

  /// Per-attempt timeout for opening, receiving and reading the response.
  final Duration? timeout;

  /// Number of additional attempts after the initial request.
  final int retryCount;

  /// Delay before each retry.
  final Duration retryDelay;

  /// Optional cancellation signal for this request.
  final PowerImageCancellationToken? cancellationToken;

  /// Whether the configured encoded-byte cache may be read and written.
  final bool cacheRawBytes;

  /// Queue priority for direct Flutter-codec transfer and decode work.
  /// This does not participate in image identity, so a visible resolve can
  /// promote an equal in-flight background prefetch.
  final PowerImageNetworkPriority networkPriority;

  double? get imageWidth => _imageWidth;
  final double? _imageWidth;

  double? get imageHeight => _imageHeight;
  final double? _imageHeight;

  @override
  String toString() {
    return 'src: $src, imageType: $imageType, renderingType: $renderingType, '
        'networkBackend: $networkBackend, headerNames: ${headers?.keys}, '
        'cacheKey: $cacheKey, timeout: $timeout, retryCount: $retryCount, '
        'retryDelay: $retryDelay, cacheRawBytes: $cacheRawBytes, '
        'networkPriority: $networkPriority';
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }

    return other is PowerImageRequestOptions &&
        other.src == src &&
        other.imageType == imageType &&
        other.renderingType == renderingType &&
        other.networkBackend == networkBackend &&
        mapEquals(other.headers, headers) &&
        other.cacheKey == cacheKey &&
        other.timeout == timeout &&
        other.retryCount == retryCount &&
        other.retryDelay == retryDelay &&
        identical(other.cancellationToken, cancellationToken) &&
        other.cacheRawBytes == cacheRawBytes &&
        other.imageWidth == imageWidth &&
        other.imageHeight == imageHeight;
  }

  @override
  //todo hashValues(src, imageType) will make different hashCode
  int get hashCode => Object.hash(
        src,
        imageType,
        renderingType,
        networkBackend,
        _headersHash,
        cacheKey,
        timeout,
        retryCount,
        retryDelay,
        cancellationToken,
        cacheRawBytes,
        imageWidth,
        imageHeight,
      );

  int get _headersHash {
    final List<MapEntry<String, String>> entries =
        headers?.entries.toList() ?? <MapEntry<String, String>>[];
    entries
        .sort((MapEntry<String, String> left, MapEntry<String, String> right) {
      final int nameOrder = left.key.compareTo(right.key);
      return nameOrder != 0 ? nameOrder : left.value.compareTo(right.value);
    });
    return Object.hashAll(entries.map(
      (MapEntry<String, String> entry) => Object.hash(entry.key, entry.value),
    ));
  }
}
