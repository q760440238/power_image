import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:power_image/src/common/power_image_provider.dart';
import 'package:power_image/src/options/power_image_request_options.dart';
import 'package:power_image_ext/image_info_ext.dart';
import '../../power_image.dart';

class PowerTextureImageProvider extends PowerImageProvider {
  PowerTextureImageProvider(PowerImageRequestOptions options) : super(options);

  @override
  FutureOr<ImageInfo> createImageInfo(Map map) {
    final int? textureId = map['textureId'];
    final int? width = map['width'];
    final int? height = map['height'];
    final Object? encodedData = map['encodedData'];
    final Object? encodedFilePath = map['encodedFilePath'];
    if (map['renderingBackend'] == 'flutterCodec' &&
        ((encodedData is Uint8List && encodedData.isNotEmpty) ||
            (encodedFilePath is String && encodedFilePath.isNotEmpty))) {
      return PowerFlutterCodecImageInfo.create(
        encodedData: encodedData is Uint8List ? encodedData : null,
        encodedFilePath: encodedFilePath is String ? encodedFilePath : null,
        width: width,
        height: height,
        targetWidth: map['targetWidth'],
        targetHeight: map['targetHeight'],
      );
    }
    return PowerTextureImageInfo.create(
      textureId: textureId,
      width: width,
      height: height,
    );
  }

  @override
  void dispose() {
    PowerImageLoader.instance.releaseImageRequest(options);
    super.dispose();
  }
}

/// Metadata used when Android delegates animated decoding to Flutter instead
/// of allocating one SurfaceProducer/ImageReader per image.
class PowerFlutterCodecImageInfo extends PowerTextureImageInfo {
  PowerFlutterCodecImageInfo({
    this.encodedData,
    this.encodedFilePath,
    required super.image,
    super.width,
    super.height,
    this.targetWidth,
    this.targetHeight,
    super.scale,
    super.debugLabel,
  }) : assert(encodedData != null || encodedFilePath != null);

  final Uint8List? encodedData;
  final String? encodedFilePath;
  final int? targetWidth;
  final int? targetHeight;

  @override
  int get sizeBytes => encodedData?.lengthInBytes ?? 0;

  @override
  ImageInfo clone() {
    return PowerFlutterCodecImageInfo(
      encodedData: encodedData,
      encodedFilePath: encodedFilePath,
      image: image.clone(),
      width: width,
      height: height,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      scale: scale,
      debugLabel: debugLabel,
    );
  }

  static FutureOr<PowerFlutterCodecImageInfo> create({
    Uint8List? encodedData,
    String? encodedFilePath,
    int? width,
    int? height,
    int? targetWidth,
    int? targetHeight,
  }) async {
    assert(encodedData != null || encodedFilePath != null);
    final PowerTextureImageInfo placeholder =
        await PowerTextureImageInfo.create(
      textureId: null,
      width: width,
      height: height,
    );
    return PowerFlutterCodecImageInfo(
      encodedData: encodedData,
      encodedFilePath: encodedFilePath,
      image: placeholder.image,
      width: width,
      height: height,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      debugLabel: 'power_image_flutter_codec',
    );
  }
}
