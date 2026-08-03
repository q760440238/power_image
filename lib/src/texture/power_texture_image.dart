import 'package:flutter/widgets.dart';

import 'package:power_image_ext/image_ext.dart';
import 'package:power_image_ext/image_info_ext.dart';
import '../common/power_image_loader.dart';
import 'power_texture_image_provider.dart';

class PowerTextureImage extends StatefulWidget {
  const PowerTextureImage({
    Key? key,
    required this.provider,
    this.frameBuilder,
    this.errorBuilder,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.semanticLabel,
    this.excludeFromSemantics = false,
  }) : super(key: key);

  final PowerTextureImageProvider provider;
  final ImageFrameBuilder? frameBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;

  /// same as [Image]
  ///
  /// A Semantic description of the image.
  ///
  /// Used to provide a description of the image to TalkBack on Android, and
  /// VoiceOver on iOS.
  final String? semanticLabel;

  /// Whether to exclude this image from semantics.
  ///
  /// Useful for images which do not contribute meaningful information to an
  /// application.
  final bool excludeFromSemantics;

  @override
  PowerTextureState createState() {
    return PowerTextureState();
  }
}

class PowerTextureState extends State<PowerTextureImage>
    with WidgetsBindingObserver {
  final Object _visibilityOwner = Object();
  bool _tickerActive = true;
  bool _applicationActive = true;
  bool _usesNativeTexture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    _applicationActive = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerActive = TickerMode.of(context);
    if (_usesNativeTexture) {
      _updateAnimationState();
    }
  }

  @override
  void didUpdateWidget(covariant PowerTextureImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider.options != widget.provider.options &&
        _usesNativeTexture) {
      PowerImageLoader.instance.removeTextureVisibility(
          oldWidget.provider.options, _visibilityOwner);
      _usesNativeTexture = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool applicationActive = state == AppLifecycleState.resumed;
    if (_applicationActive != applicationActive) {
      _applicationActive = applicationActive;
      if (_usesNativeTexture) {
        _updateAnimationState();
      }
    }
  }

  void _updateAnimationState() {
    if (_usesNativeTexture) {
      PowerImageLoader.instance.updateTextureVisibility(
        widget.provider.options,
        _visibilityOwner,
        _tickerActive && _applicationActive,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_usesNativeTexture) {
      PowerImageLoader.instance.removeTextureVisibility(
        widget.provider.options,
        _visibilityOwner,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ImageExt(
      image: widget.provider,
      frameBuilder: widget.frameBuilder,
      errorBuilder: widget.errorBuilder,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      imageBuilder: buildImage,
      semanticLabel: widget.semanticLabel,
      excludeFromSemantics: widget.excludeFromSemantics,
    );
  }

  Widget buildImage(BuildContext context, ImageInfo? imageInfo) {
    if (imageInfo == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    if (imageInfo is! PowerTextureImageInfo) {
      _setUsesNativeTexture(false);
      return RawImage(
        image: imageInfo.image,
        scale: imageInfo.scale,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
      );
    }

    final PowerTextureImageInfo textureImageInfo = imageInfo;
    _setUsesNativeTexture(true);
    final int? textureId = textureImageInfo.textureId;
    if (textureId == null) {
      return SizedBox(width: widget.width, height: widget.height);
    }
    return ClipRect(
      child: SizedBox(
        child: FittedBox(
          fit: widget.fit ?? BoxFit.contain,
          alignment: widget.alignment,
          child: SizedBox(
            width: textureImageInfo.width?.toDouble() ?? widget.width,
            height: textureImageInfo.height?.toDouble() ?? widget.height,
            child: Texture(textureId: textureId),
          ),
        ),
        width: widget.width,
        height: widget.height,
      ),
    );
  }

  void _setUsesNativeTexture(bool value) {
    if (_usesNativeTexture == value) {
      return;
    }
    final bool wasNative = _usesNativeTexture;
    _usesNativeTexture = value;
    if (wasNative && !_usesNativeTexture) {
      PowerImageLoader.instance.removeTextureVisibility(
        widget.provider.options,
        _visibilityOwner,
      );
    } else if (_usesNativeTexture) {
      _updateAnimationState();
    }
  }
}
