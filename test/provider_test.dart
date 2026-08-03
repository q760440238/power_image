import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:power_image/power_image.dart';
import 'package:power_image/src/common/power_image_platform_channel.dart';
import 'package:power_image/src/common/power_image_provider.dart';
import 'package:power_image/src/common/power_image_request.dart';
import 'package:power_image/src/external/power_external_image_provider.dart';
import 'package:power_image/src/network/power_network_image_provider.dart';
import 'package:power_image/src/texture/power_texture_image_provider.dart';
import 'package:power_image_ext/power_image_ext.dart';

import 'test_utils.dart';

Uint8List get _onePixelPng => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );

void main() {
  PowerImagePlatformChannel? platformChannel =
      PowerImageLoader.instance.channel.impl as PowerImagePlatformChannel?;
  final Map<String, List<MethodCall>> calls = <String, List<MethodCall>>{};
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();

    platformChannel!.methodChannel.setMockMethodCallHandler((
      MethodCall methodCall,
    ) async {
      calls.putIfAbsent(methodCall.method, () {
        return <MethodCall>[];
      });

      calls[methodCall.method]!.add(methodCall);
      return [{}];
    });

    MethodChannel(platformChannel.eventChannel.name).setMockMethodCallHandler((
      MethodCall methodCall,
    ) async {
      switch (methodCall.method) {
        case 'listen':
        case 'cancel':
        default:
          return null;
      }
    });

    PowerImageLoader.instance.setup(
      PowerImageSetupOptions(renderingTypeTexture),
    );
  });

  group('options_test', () {
    setUp(() {});

    test('factory', () {
      // texture
      final PowerImageRequestOptions textureOptions = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );

      PowerImageProvider textureProvider = PowerImageProvider.options(
        textureOptions,
      );
      expect(textureProvider.runtimeType == PowerTextureImageProvider, true);

      // external
      final PowerImageRequestOptions externalOptions = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeExternal,
      );
      PowerImageProvider externalProvider = PowerImageProvider.options(
        externalOptions,
      );
      expect(externalProvider.runtimeType == PowerExternalImageProvider, true);

      // renderingType null
      final PowerImageRequestOptions renderingTypeNullOptions =
          PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: null,
      );
      PowerImageProvider renderingTypeNullProvider = PowerImageProvider.options(
        renderingTypeNullOptions,
      );
      expect(
        renderingTypeNullProvider.runtimeType == PowerTextureImageProvider,
        true,
      );

      final PowerImageProvider directNetworkProvider =
          PowerImageProvider.options(PowerImageRequestOptions.network(
        'https://example.test/image-without-extension?id=1',
        renderingType: renderingTypeTexture,
      ));
      expect(directNetworkProvider, isA<PowerNetworkImageProvider>());

      final PowerImageProvider nativeNetworkProvider =
          PowerImageProvider.options(PowerImageRequestOptions.network(
        'https://example.test/image.webp',
        renderingType: renderingTypeTexture,
        networkBackend: PowerImageNetworkBackend.native,
      ));
      expect(nativeNetworkProvider, isA<PowerTextureImageProvider>());

      // renderingType unknown
      final PowerImageRequestOptions testRenderingTypeOptions =
          PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: 'testRenderingType',
      );
      expect(() {
        PowerImageProvider.options(testRenderingTypeOptions);
      }, throwsA(isA<AssertionError>()));
    });

    test('auto network backend uses Flutter codec for HTTP on every platform',
        () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final PowerImageRequestOptions autoOptions =
            PowerImageRequestOptions.network(
          'https://example.test/image',
          renderingType: renderingTypeTexture,
        );
        expect(
          PowerImageProvider.options(autoOptions),
          isA<PowerNetworkImageProvider>(),
        );

        final PowerImageRequestOptions explicitFlutterOptions =
            PowerImageRequestOptions.network(
          'https://example.test/image',
          renderingType: renderingTypeTexture,
          networkBackend: PowerImageNetworkBackend.flutterCodec,
        );
        expect(
          PowerImageProvider.options(explicitFlutterOptions),
          isA<PowerNetworkImageProvider>(),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('==', () {
      // texture
      final PowerImageRequestOptions textureOptions1 = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );

      PowerImageProvider textureProvider1 = PowerImageProvider.options(
        textureOptions1,
      );

      final PowerImageRequestOptions textureOptions2 = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );

      PowerImageProvider textureProvider2 = PowerImageProvider.options(
        textureOptions2,
      );

      expect(textureProvider2 == textureProvider1, true);

      // external
      final PowerImageRequestOptions externalOptions1 =
          PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeExternal,
      );
      PowerImageProvider externalProvider1 = PowerImageProvider.options(
        externalOptions1,
      );

      final PowerImageRequestOptions externalOptions2 =
          PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeExternal,
      );
      PowerImageProvider externalProvider2 = PowerImageProvider.options(
        externalOptions2,
      );

      expect(externalProvider1 == externalProvider2, true);
    });

    test('!=', () {
      // texture
      final PowerImageRequestOptions textureOptions1 = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );

      PowerImageProvider textureProvider1 = PowerImageProvider.options(
        textureOptions1,
      );

      //same src different image size
      final PowerImageRequestOptions textureOptions2 = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 101.0,
        imageHeight: 100.0,
        renderingType: renderingTypeTexture,
      );

      PowerImageProvider textureProvider2 = PowerImageProvider.options(
        textureOptions2,
      );

      expect(textureProvider2 == textureProvider1, false);

      // external
      final PowerImageRequestOptions externalOptions1 =
          PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeExternal,
      );
      PowerImageProvider externalProvider1 = PowerImageProvider.options(
        externalOptions1,
      );

      final PowerImageRequestOptions externalOptions2 =
          PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 101.0,
        imageHeight: 101.0,
        renderingType: renderingTypeExternal,
      );
      PowerImageProvider externalProvider2 = PowerImageProvider.options(
        externalOptions2,
      );

      expect(externalProvider1 == externalProvider2, false);

      expect(externalProvider1 == textureProvider1, false);
    });

    test('load_success', () async {
      final PowerImageRequestOptions textureOptions1 = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );

      PowerImageProvider textureProvider1 = PowerImageProvider.options(
        textureOptions1,
      );

      final ImageStreamCompleter completer = textureProvider1.loadImage(
        textureProvider1,
        (_, {getTargetSize}) => throw UnimplementedError(),
      );
      expect(completer, isNot(isA<OneFrameImageStreamCompleter>()));

      const int textureId = 233;
      const int width = 1;
      const int height = 2;
      completer.addListener(
        ImageStreamListener((ImageInfo image, bool synchronousCall) {
          expect(image.runtimeType == PowerTextureImageInfo, true);
          PowerTextureImageInfo textureImageInfo =
              image as PowerTextureImageInfo;
          expect(textureImageInfo.image.width == 1, true);
          expect(textureImageInfo.image.height == 1, true);
          expect(textureImageInfo.textureId == textureId, true);
          expect(textureImageInfo.width == width, true);
          expect(textureImageInfo.height == height, true);
        }),
      );

      Map mockCompleteMap = {
        'eventName': 'onReceiveImageEvent',
        'uniqueKey': PowerImageLoader.completers.keys.toList()[0],
        'success': true,
        'textureId': textureId,
        'width': width,
        'height': height,
      };

      ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        platformChannel!.eventChannel.name,
        platformChannel.eventChannel.codec.encodeSuccessEnvelope(
          mockCompleteMap,
        ),
        (_) {},
      );
      await Future.delayed(const Duration(milliseconds: 500), () {});
    });

    test('load_multiFrame_success', () async {
      final PowerImageRequestOptions textureOptions1 = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );

      PowerImageProvider textureProvider1 = PowerImageProvider.options(
        textureOptions1,
      );

      final ImageStreamCompleter? completer = imageCache!.putIfAbsent(
        textureProvider1,
        () {
          return textureProvider1.loadImage(
            textureProvider1,
            (_, {getTargetSize}) => throw UnimplementedError(),
          );
        },
      );
      // final ImageStreamCompleter completer =
      // textureProvider1.load(textureProvider1, null);
      expect(completer, isNot(isA<OneFrameImageStreamCompleter>()));
      const int textureId = 233;
      const int width = 1;
      const int height = 2;

      ImageStreamListener listener = ImageStreamListener((
        ImageInfo image,
        bool synchronousCall,
      ) {
        expect(image.runtimeType == PowerTextureImageInfo, true);
        PowerTextureImageInfo textureImageInfo = image as PowerTextureImageInfo;
        expect(textureImageInfo.image.width == 1, true);
        expect(textureImageInfo.image.height == 1, true);
        expect(textureImageInfo.textureId == textureId, true);
        expect(textureImageInfo.width == width, true);
        expect(textureImageInfo.height == height, true);
      });

      completer?.addListener(listener);

      Map mockCompleteMap = {
        'eventName': 'onReceiveImageEvent',
        'uniqueKey': PowerImageLoader.completers.keys.toList()[0],
        'success': true,
        'textureId': textureId,
        '_multiFrame': true,
        'width': width,
        'height': height,
      };

      ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        platformChannel!.eventChannel.name,
        platformChannel.eventChannel.codec.encodeSuccessEnvelope(
          mockCompleteMap,
        ),
        (_) {},
      );

      await Future.delayed(const Duration(milliseconds: 500), () {
        completer?.removeListener(listener);
        expect(imageCache!.containsKey(textureProvider1) == true, true);
        Future.microtask(() {
          expect(imageCache!.containsKey(textureProvider1) == false, true);
        });
      });
    });

    test('load_flutterCodec_multiFrame_keeps_bounded_cache_entry', () async {
      final PowerImageRequestOptions options = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "animated.webp"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );
      final PowerImageProvider provider = PowerImageProvider.options(options);
      final ImageStreamCompleter completer = imageCache!.putIfAbsent(
        provider,
        () {
          return provider.loadImage(
            provider,
            (buffer, {getTargetSize}) =>
                PaintingBinding.instance.instantiateImageCodecWithSize(
              buffer,
              getTargetSize: getTargetSize,
            ),
          );
        },
      )!;
      final Completer<void> imageReceived = Completer<void>();
      final ImageStreamListener listener = ImageStreamListener((
        ImageInfo image,
        bool synchronousCall,
      ) {
        expect(image, isNot(isA<PowerTextureImageInfo>()));
        if (!imageReceived.isCompleted) {
          imageReceived.complete();
        }
      });
      completer.addListener(listener);

      final Map<String, dynamic> mockCompleteMap = <String, dynamic>{
        'eventName': 'onReceiveImageEvent',
        'uniqueKey': PowerImageLoader.completers.keys.toList()[0],
        'success': true,
        '_multiFrame': true,
        'renderingBackend': 'flutterCodec',
        'encodedData': _onePixelPng,
        'width': 100,
        'height': 101,
        'targetWidth': 100,
        'targetHeight': 101,
      };
      await ServicesBinding.instance!.defaultBinaryMessenger
          .handlePlatformMessage(
        platformChannel!.eventChannel.name,
        platformChannel.eventChannel.codec.encodeSuccessEnvelope(
          mockCompleteMap,
        ),
        (_) {},
      );
      await imageReceived.future;

      completer.removeListener(listener);
      await Future<void>.delayed(Duration.zero);
      expect(imageCache!.containsKey(provider), true);

      // The entry is still bounded by ImageCache and remains evictable.
      expect(imageCache!.evict(provider), true);
    });

    test('load_flutterCodec_file_emits_a_real_codec_frame', () async {
      final Directory temporaryDirectory =
          await Directory.systemTemp.createTemp('power_image_codec_test_');
      final File encodedFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}image-no-suffix',
      );
      await encodedFile.writeAsBytes(_onePixelPng, flush: true);
      try {
        final PowerImageProvider provider = PowerImageProvider.options(
          PowerImageRequestOptions(
            src: PowerImageRequestOptionsSrcNormal(src: 'encoded-file'),
            imageType: 'imageType',
            imageWidth: 1,
            imageHeight: 1,
            renderingType: renderingTypeTexture,
          ),
        );
        final ImageStreamCompleter completer = provider.loadImage(
          provider,
          (buffer, {getTargetSize}) =>
              PaintingBinding.instance.instantiateImageCodecWithSize(
            buffer,
            getTargetSize: getTargetSize,
          ),
        );
        final Completer<ImageInfo> received = Completer<ImageInfo>();
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (ImageInfo image, bool synchronousCall) {
            if (!received.isCompleted) {
              received.complete(image);
            }
          },
          onError: received.completeError,
        );
        completer.addListener(listener);

        await ServicesBinding.instance!.defaultBinaryMessenger
            .handlePlatformMessage(
          platformChannel!.eventChannel.name,
          platformChannel.eventChannel.codec.encodeSuccessEnvelope(
            <String, dynamic>{
              'eventName': 'onReceiveImageEvent',
              'uniqueKey': PowerImageLoader.completers.keys.single,
              'success': true,
              '_multiFrame': true,
              'renderingBackend': 'flutterCodec',
              'encodedFilePath': encodedFile.path,
              'width': 1,
              'height': 1,
              'targetWidth': 1,
              'targetHeight': 1,
            },
          ),
          (_) {},
        );
        final ImageInfo image = await received.future.timeout(
          const Duration(seconds: 5),
        );

        expect(image, isNot(isA<PowerTextureImageInfo>()));
        expect(image.image.width, 1);
        expect(image.image.height, 1);
        completer.removeListener(listener);
      } finally {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('load_error', () {
      final PowerImageRequestOptions textureOptions1 = PowerImageRequestOptions(
        src: PowerImageRequestOptionsSrcNormal(src: "srcValue"),
        imageType: 'imageType',
        imageWidth: 100.0,
        imageHeight: 101.0,
        renderingType: renderingTypeTexture,
      );

      FlutterError.onError = (FlutterErrorDetails details) {
        throw Error();
      };

      PowerImageProvider textureProvider1 = PowerImageProvider.options(
        textureOptions1,
      );

      final ImageStreamCompleter completer = textureProvider1.loadImage(
        textureProvider1,
        (_, {getTargetSize}) => throw UnimplementedError(),
      );
      expect(completer, isNot(isA<OneFrameImageStreamCompleter>()));

      final Map mockCompleteMap = {
        'eventName': 'onReceiveImageEvent',
        'uniqueKey': PowerImageLoader.completers.keys.toList()[0],
        'success': false,
        'textureId': 0,
      };

      completer.addListener(
        ImageStreamListener(
          (ImageInfo image, bool synchronousCall) {},
          onError: (dynamic exception, StackTrace? stackTrace) {
            expect(exception.runtimeType == PowerImageLoadException, true);
            PowerImageLoadException powerImageLoadException = exception;
            expect(
              mapEquals(powerImageLoadException.nativeResult, mockCompleteMap),
              true,
            );
          },
        ),
      );

      ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        platformChannel!.eventChannel.name,
        platformChannel.eventChannel.codec.encodeSuccessEnvelope(
          mockCompleteMap,
        ),
        (_) {},
      );
    });
  });

  test('PowerExternalImageProvider', () {
    PowerExternalImageProvider provider = PowerExternalImageProvider(
      testRequestOptions(),
    );

    expect(
      () => provider.createImageInfo({
        'handle': 0,
        'length': -1,
        'width': 0,
        'height': 0,
        'rowBytes': 0,
      }),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('PowerTextureImageProvider releases at its last listener', () async {
    final PowerTextureImageProvider provider = PowerTextureImageProvider(
      testRequestOptions(),
    );
    final ImageStreamCompleter completer = provider.loadImage(
      provider,
      (_, {getTargetSize}) => throw UnimplementedError(),
    );
    final Completer<void> imageReceived = Completer<void>();
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) {
        image.dispose();
        if (!imageReceived.isCompleted) {
          imageReceived.complete();
        }
      },
    );
    completer.addListener(listener);
    final String? uniqueKey = PowerImageLoader.completers.keys.single;
    final int releasesBefore = calls['releaseImageRequests']?.length ?? 0;

    await ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      platformChannel!.eventChannel.name,
      platformChannel.eventChannel.codec.encodeSuccessEnvelope(
        <String, dynamic>{
          'eventName': 'onReceiveImageEvent',
          'uniqueKey': uniqueKey,
          'success': true,
          'textureId': 7,
          'width': 1,
          'height': 1,
        },
      ),
      (_) {},
    );
    await imageReceived.future;

    expect(calls['releaseImageRequests']?.length ?? 0, releasesBefore);
    completer.removeListener(listener);
    await Future<void>.delayed(Duration.zero);

    expect(calls['releaseImageRequests']?.length, releasesBefore + 1);
  });

  test('PowerTextureImageProvider creates native texture metadata', () async {
    final PowerTextureImageProvider provider =
        PowerTextureImageProvider(testRequestOptions());
    final ImageInfo imageInfo = await Future<ImageInfo>.value(
      provider.createImageInfo(<String, dynamic>{
        'textureId': 42,
        'width': 512,
        'height': 256,
      }),
    );

    expect(imageInfo, isA<PowerTextureImageInfo>());
    final PowerTextureImageInfo textureInfo =
        imageInfo as PowerTextureImageInfo;
    expect(textureInfo.textureId, 42);
    expect(textureInfo.width, 512);
    expect(textureInfo.height, 256);
    textureInfo.dispose();
  });
}
