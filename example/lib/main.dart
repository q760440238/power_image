import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:power_image/power_image.dart';
import 'package:power_image_example/animated_webp_fixture.dart';
import 'package:power_image_example/examples/example_gallery_preview.dart';

import 'examples/drag_overlay.dart';
import 'examples/example_decoration_image_page.dart';
import 'examples/example_page.dart';
import 'examples/example_prefetch_page.dart';
import 'examples/image_cache_status.dart';

late PowerImageFileRawBytesCache benchmarkRawBytesCache;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    BenchmarkTrace.initialize();
    final Directory temporaryDirectory = await getTemporaryDirectory();
    final PowerImageFileRawBytesCache rawBytesCache =
        PowerImageFileRawBytesCache(
      directory: Directory(
        '${temporaryDirectory.path}${Platform.pathSeparator}'
        'power_image_raw_bytes',
      ),
      maxSizeBytes: 200 * 1024 * 1024,
    );
    await rawBytesCache.warmUp();
    benchmarkRawBytesCache = rawBytesCache;
    PowerImageLoader.instance.setup(
      PowerImageSetupOptions(
        renderingTypeTexture,
        debugLogging: kDebugMode,
        errorCallbackSamplingRate: null,
        errorCallback: (PowerImageLoadException exception) {},
        rawBytesCache: rawBytesCache,
      ),
    );
    final String initialRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final AnimatedWebpFixture fixture = initialRoute.startsWith(
      '/benchmark/steady20/',
    )
        ? await AnimatedWebpFixture.startGiphyOnly()
        : await AnimatedWebpFixture.start();
    runApp(MyApp(
      animatedWebpUrl: fixture.url,
      benchmarkWebpUrl: fixture.giphyWebpUrl,
      comparisonImageUrls: ComparisonImageUrls(
        png: fixture.pngUrl,
        gif: fixture.gifUrl,
        staticWebp: fixture.staticWebpUrl,
        animatedWebp: fixture.url,
      ),
    ));
  }, (Object error, StackTrace stackTrace) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      context: ErrorDescription('starting the power_image example'),
    ));
  });
}

class MyApp extends StatelessWidget {
  const MyApp({
    Key? key,
    required this.animatedWebpUrl,
    required this.benchmarkWebpUrl,
    required this.comparisonImageUrls,
  }) : super(key: key);

  final String animatedWebpUrl;
  final String benchmarkWebpUrl;
  final ComparisonImageUrls comparisonImageUrls;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final String initialRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    return MaterialApp(
      title: 'power_image',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: _initialPage(initialRoute),
    );
  }

  Widget _initialPage(String route) {
    switch (route) {
      case '/benchmark/cache/cold':
        return CacheLifecycleBenchmarkPage(
          mode: CacheBenchmarkMode.cold,
          animatedWebpUrl: animatedWebpUrl,
        );
      case '/benchmark/cache/raw_bytes_disk':
        return CacheLifecycleBenchmarkPage(
          mode: CacheBenchmarkMode.rawBytesDisk,
          animatedWebpUrl: animatedWebpUrl,
        );
      case '/benchmark/cache/flutter_image_cache':
        return CacheLifecycleBenchmarkPage(
          mode: CacheBenchmarkMode.flutterImageCache,
          animatedWebpUrl: animatedWebpUrl,
        );
      case '/benchmark/surface_rebuild':
        return SurfaceRebuildBenchmarkPage(
          animatedWebpUrl: animatedWebpUrl,
        );
      case '/benchmark/cache_write_100':
        return CacheWriteBenchmarkPage(
          imageUrl: comparisonImageUrls.staticWebp,
        );
      case '/benchmark/steady20/power_flutter':
        return Steady20BenchmarkPage(
          library: BenchmarkLibrary.powerImage,
          imageUrl: benchmarkWebpUrl,
        );
      case '/benchmark/steady20/native_glide':
        return Steady20BenchmarkPage(
          library: BenchmarkLibrary.powerImageNativeSurface,
          imageUrl: benchmarkWebpUrl,
        );
      case '/benchmark/steady20/extended':
        return Steady20BenchmarkPage(
          library: BenchmarkLibrary.extendedImage,
          imageUrl: benchmarkWebpUrl,
        );
      default:
        return MyHomePage(
          animatedWebpUrl: animatedWebpUrl,
          comparisonImageUrls: comparisonImageUrls,
        );
    }
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    Key? key,
    required this.animatedWebpUrl,
    required this.comparisonImageUrls,
  }) : super(key: key);

  final String animatedWebpUrl;
  final ComparisonImageUrls comparisonImageUrls;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DragOverlay.show(context: context, view: const ImageCacheStatusWidget());
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('power_image example app'),
      ),
      body: ListView(children: <Widget>[
        ListTile(
          title: const Text('三库四格式体验对比'),
          subtitle: const Text('PNG / GIF / 静态 WebP / 动态 WebP'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return FormatComparisonPage(urls: widget.comparisonImageUrls);
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_first_frame'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return FirstFrameBenchmarkMenu(
                animatedWebpUrl: widget.animatedWebpUrl,
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_cache_lifecycle'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return CacheLifecycleBenchmarkMenu(
                animatedWebpUrl: widget.animatedWebpUrl,
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_surface_rebuild'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return SurfaceRebuildBenchmarkPage(
                animatedWebpUrl: widget.animatedWebpUrl,
              );
            }));
          },
        ),
        ListTile(
          title: const Text('prefetch_image'),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return const ExamplePrefetchPage();
            }));
          },
        ),
        ListTile(
          title: const Text('external_image'),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return const ExamplePage(renderingTypeExternal);
            }));
          },
        ),
        ListTile(
          title: const Text('texture_image'),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return const ExamplePage(renderingTypeTexture);
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_static_power_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.powerImage,
                imageUrl: widget.comparisonImageUrls.staticWebp,
                benchmarkId: 'benchmark_static_power_image',
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_static_cached_network_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.cachedNetworkImage,
                imageUrl: widget.comparisonImageUrls.staticWebp,
                benchmarkId: 'benchmark_static_cached_network_image',
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_static_extended_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.extendedImage,
                imageUrl: widget.comparisonImageUrls.staticWebp,
                benchmarkId: 'benchmark_static_extended_image',
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_power_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.powerImage,
                imageUrl: widget.animatedWebpUrl,
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_power_image_native_surface'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.powerImageNativeSurface,
                imageUrl: widget.animatedWebpUrl,
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_cached_network_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.cachedNetworkImage,
                imageUrl: widget.animatedWebpUrl,
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_extended_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.extendedImage,
                imageUrl: widget.animatedWebpUrl,
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_gif_power_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.powerImage,
                imageUrl: widget.comparisonImageUrls.gif,
                benchmarkId: 'benchmark_gif_power_image',
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_gif_cached_network_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.cachedNetworkImage,
                imageUrl: widget.comparisonImageUrls.gif,
                benchmarkId: 'benchmark_gif_cached_network_image',
              );
            }));
          },
        ),
        ListTile(
          title: const Text('benchmark_gif_extended_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.extendedImage,
                imageUrl: widget.comparisonImageUrls.gif,
                benchmarkId: 'benchmark_gif_extended_image',
              );
            }));
          },
        ),
        ListTile(
          title: const Text('decoration_image'),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return const ExampleDecorationImagePage();
            }));
          },
        ),
        ListTile(
            title: const Text('gallery'),
            onTap: () async {
              ImagePicker picker = ImagePicker();
              var image = await picker.pickImage(source: ImageSource.gallery);
              if (image != null) {
                Navigator.push(context, MaterialPageRoute(builder: (context) {
                  return ExampleGalleryPrev(
                    path: image.path,
                  );
                }));
              }
            })
      ]),
    );
  }
}

enum ComparisonImageFormat {
  png,
  gif,
  staticWebp,
  animatedWebp,
}

String comparisonFormatName(ComparisonImageFormat format) {
  switch (format) {
    case ComparisonImageFormat.png:
      return 'PNG';
    case ComparisonImageFormat.gif:
      return 'GIF';
    case ComparisonImageFormat.staticWebp:
      return '静态 WebP';
    case ComparisonImageFormat.animatedWebp:
      return '动态 WebP';
  }
}

class ComparisonImageUrls {
  const ComparisonImageUrls({
    required this.png,
    required this.gif,
    required this.staticWebp,
    required this.animatedWebp,
  });

  final String png;
  final String gif;
  final String staticWebp;
  final String animatedWebp;

  String forFormat(ComparisonImageFormat format) {
    switch (format) {
      case ComparisonImageFormat.png:
        return png;
      case ComparisonImageFormat.gif:
        return gif;
      case ComparisonImageFormat.staticWebp:
        return staticWebp;
      case ComparisonImageFormat.animatedWebp:
        return animatedWebp;
    }
  }
}

class FormatComparisonPage extends StatefulWidget {
  const FormatComparisonPage({Key? key, required this.urls}) : super(key: key);

  final ComparisonImageUrls urls;

  @override
  State<FormatComparisonPage> createState() => _FormatComparisonPageState();
}

class _FormatComparisonPageState extends State<FormatComparisonPage> {
  ComparisonImageFormat _format = ComparisonImageFormat.png;
  int _requestGeneration = 0;
  final int _session = DateTime.now().microsecondsSinceEpoch;

  String _urlFor(BenchmarkLibrary library) {
    final Uri uri = Uri.parse(widget.urls.forFormat(_format));
    return uri.replace(queryParameters: <String, String>{
      ...uri.queryParameters,
      if (_format != ComparisonImageFormat.png) 'item': '0',
      'library': benchmarkName(library),
      'session': _session.toString(),
      'run': _requestGeneration.toString(),
    }).toString();
  }

  @override
  Widget build(BuildContext context) {
    const List<BenchmarkLibrary> libraries = <BenchmarkLibrary>[
      BenchmarkLibrary.powerImage,
      BenchmarkLibrary.cachedNetworkImage,
      BenchmarkLibrary.extendedImage,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('三库四格式体验对比')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Wrap(
            spacing: 8,
            children: ComparisonImageFormat.values
                .map((ComparisonImageFormat format) => ChoiceChip(
                      label: Text(comparisonFormatName(format)),
                      selected: _format == format,
                      onSelected: (_) => setState(() {
                        _format = format;
                        _requestGeneration++;
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '同一素材、同一尺寸；数字为 Widget 创建到首帧显示。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _requestGeneration++),
                icon: const Icon(Icons.refresh),
                label: const Text('新 Key 重载'),
              ),
            ],
          ),
          ...libraries.map((BenchmarkLibrary library) {
            final String url = _urlFor(library);
            return ComparisonImageCard(
              key: ValueKey<String>('${benchmarkName(library)}:$url'),
              library: library,
              url: url,
            );
          }),
        ],
      ),
    );
  }
}

class ComparisonImageCard extends StatefulWidget {
  const ComparisonImageCard({
    Key? key,
    required this.library,
    required this.url,
  }) : super(key: key);

  final BenchmarkLibrary library;
  final String url;

  @override
  State<ComparisonImageCard> createState() => _ComparisonImageCardState();
}

class _ComparisonImageCardState extends State<ComparisonImageCard> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  double? _firstFrameMilliseconds;
  bool _frameUpdateScheduled = false;

  ImageProvider _provider(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final double displayWidth = mediaQuery.size.width - 24;
    final int decodeWidth =
        (displayWidth * mediaQuery.devicePixelRatio).round();
    final int decodeHeight = (140 * mediaQuery.devicePixelRatio).round();
    switch (widget.library) {
      case BenchmarkLibrary.powerImage:
        return PowerImageProvider.options(PowerImageRequestOptions.network(
          widget.url,
          renderingType: renderingTypeTexture,
          networkBackend: PowerImageNetworkBackend.flutterCodec,
          imageWidth: displayWidth,
          imageHeight: 140,
        ));
      case BenchmarkLibrary.cachedNetworkImage:
        return CachedNetworkImageProvider(
          widget.url,
          maxWidth: decodeWidth,
          maxHeight: decodeHeight,
        );
      case BenchmarkLibrary.extendedImage:
        return ResizeImage.resizeIfNeeded(
          decodeWidth,
          decodeHeight,
          ExtendedNetworkImageProvider(widget.url, cache: true),
        );
      case BenchmarkLibrary.powerImageNativeSurface:
        throw StateError('Native Surface is not part of this comparison.');
    }
  }

  Widget _onFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (frame != null &&
        _firstFrameMilliseconds == null &&
        !_frameUpdateScheduled) {
      _frameUpdateScheduled = true;
      final double elapsed = _stopwatch.elapsedMicroseconds / 1000;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          setState(() => _firstFrameMilliseconds = elapsed);
        }
      });
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final String? elapsed = _firstFrameMilliseconds?.toStringAsFixed(1);
    return Card(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(benchmarkName(widget.library))),
                Text(elapsed == null ? '加载中' : '首帧 $elapsed ms'),
              ],
            ),
          ),
          Image(
            image: _provider(context),
            height: 140,
            fit: BoxFit.cover,
            frameBuilder: _onFrame,
            errorBuilder: (BuildContext context, Object error, StackTrace? _) {
              return SizedBox(
                height: 140,
                child: Center(child: Text('加载失败：$error')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class FirstFrameBenchmarkMenu extends StatelessWidget {
  const FirstFrameBenchmarkMenu({
    Key? key,
    required this.animatedWebpUrl,
  }) : super(key: key);

  final String animatedWebpUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('benchmark_first_frame_menu')),
      body: Semantics(
        label: 'benchmark_first_frame_menu',
        child: ListView(
          children: <Widget>[
            for (final BenchmarkLibrary library in <BenchmarkLibrary>[
              BenchmarkLibrary.powerImage,
              BenchmarkLibrary.cachedNetworkImage,
              BenchmarkLibrary.extendedImage,
            ])
              ListTile(
                title: Text('first_frame_${benchmarkName(library)}'),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) {
                    return FirstFrameBenchmarkPage(
                      library: library,
                      animatedWebpUrl: animatedWebpUrl,
                    );
                  }));
                },
              ),
            ListTile(
              title: const Text('first_frame_power_image_widget'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) {
                  return FirstFrameBenchmarkPage(
                    library: BenchmarkLibrary.powerImage,
                    animatedWebpUrl: animatedWebpUrl,
                    usePowerImageWidget: true,
                  );
                }));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class FirstFrameBenchmarkPage extends StatefulWidget {
  const FirstFrameBenchmarkPage({
    Key? key,
    required this.library,
    required this.animatedWebpUrl,
    this.usePowerImageWidget = false,
  }) : super(key: key);

  final BenchmarkLibrary library;
  final String animatedWebpUrl;
  final bool usePowerImageWidget;

  @override
  State<FirstFrameBenchmarkPage> createState() =>
      _FirstFrameBenchmarkPageState();
}

class _FirstFrameBenchmarkPageState extends State<FirstFrameBenchmarkPage> {
  static const MethodChannel _benchmarkChannel = MethodChannel(
    'com.taobao.power_image_example/first_frame_benchmark',
  );

  ImageProvider? _provider;
  String? _url;
  bool _initializationStarted = false;
  bool _nativeTraceStarted = false;
  bool _finishScheduled = false;
  bool _displayed = false;

  String get _libraryName => widget.usePowerImageWidget
      ? 'power_image_widget'
      : benchmarkName(widget.library);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializationStarted) {
      return;
    }
    _initializationStarted = true;

    final int decodePixels =
        (160 * MediaQuery.of(context).devicePixelRatio).round();
    final String url = '${widget.animatedWebpUrl}?library=$_libraryName'
        '&item=0&run=${DateTime.now().microsecondsSinceEpoch}';
    _initialize(url, decodePixels);
  }

  Future<void> _initialize(String url, int decodePixels) async {
    try {
      await _benchmarkChannel.invokeMethod<void>('begin');
      _nativeTraceStarted = true;
    } on MissingPluginException {
      // The first-frame benchmark channel is Android-only.
    }
    if (!mounted) {
      _finishNativeTrace();
      return;
    }
    setState(() {
      _url = url;
      if (!widget.usePowerImageWidget) {
        _provider = _createProvider(url, decodePixels);
      }
    });
  }

  ImageProvider _createProvider(String url, int decodePixels) {
    switch (widget.library) {
      case BenchmarkLibrary.powerImage:
        return PowerImageProvider.options(PowerImageRequestOptions.network(
          url,
          renderingType: renderingTypeTexture,
          networkBackend: PowerImageNetworkBackend.flutterCodec,
          imageWidth: 160,
          imageHeight: 160,
        ));
      case BenchmarkLibrary.cachedNetworkImage:
        return CachedNetworkImageProvider(
          url,
          maxWidth: decodePixels,
          maxHeight: decodePixels,
        );
      case BenchmarkLibrary.extendedImage:
        return ResizeImage.resizeIfNeeded(
          decodePixels,
          decodePixels,
          ExtendedNetworkImageProvider(url, cache: true),
        );
      case BenchmarkLibrary.powerImageNativeSurface:
        throw StateError('Native Surface is not part of this comparison.');
    }
  }

  Widget _onFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (frame != null && !_finishScheduled) {
      _finishScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
        await _finishNativeTrace();
        if (mounted) {
          setState(() {
            _displayed = true;
          });
        }
      });
    }
    return child;
  }

  Future<void> _finishNativeTrace() async {
    if (!_nativeTraceStarted) {
      return;
    }
    _nativeTraceStarted = false;
    await _benchmarkChannel.invokeMethod<void>('end');
  }

  @override
  void dispose() {
    _finishNativeTrace();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'first_frame_${_libraryName}_page',
      child: Scaffold(
        appBar: AppBar(title: Text('first_frame_$_libraryName')),
        body: Center(
          child: Semantics(
            label: _displayed
                ? 'first_frame_${_libraryName}_displayed'
                : 'first_frame_${_libraryName}_loading',
            child: _url == null
                ? const SizedBox(width: 160, height: 160)
                : widget.usePowerImageWidget
                    ? PowerImage.network(
                        _url!,
                        networkBackend: PowerImageNetworkBackend.flutterCodec,
                        renderingType: renderingTypeTexture,
                        width: 160,
                        height: 160,
                        imageWidth: 160,
                        imageHeight: 160,
                        fit: BoxFit.cover,
                        frameBuilder: _onFrame,
                      )
                    : Image(
                        image: _provider!,
                        width: 160,
                        height: 160,
                        fit: BoxFit.cover,
                        frameBuilder: _onFrame,
                      ),
          ),
        ),
      ),
    );
  }
}

enum BenchmarkLibrary {
  powerImage,
  powerImageNativeSurface,
  cachedNetworkImage,
  extendedImage,
}

String benchmarkName(BenchmarkLibrary library) {
  switch (library) {
    case BenchmarkLibrary.powerImage:
      return 'power_image';
    case BenchmarkLibrary.powerImageNativeSurface:
      return 'power_image_native_surface';
    case BenchmarkLibrary.cachedNetworkImage:
      return 'cached_network_image';
    case BenchmarkLibrary.extendedImage:
      return 'extended_image';
  }
}

class AnimatedBenchmarkPage extends StatelessWidget {
  const AnimatedBenchmarkPage({
    Key? key,
    required this.library,
    required this.imageUrl,
    this.benchmarkId,
  }) : super(key: key);

  final BenchmarkLibrary library;
  final String imageUrl;
  final String? benchmarkId;

  @override
  Widget build(BuildContext context) {
    final String pageId = benchmarkId ?? 'benchmark_${benchmarkName(library)}';
    return Scaffold(
      appBar: AppBar(title: Text('${pageId}_page')),
      body: Semantics(
        label: '${pageId}_grid',
        child: GridView.builder(
          cacheExtent: 0,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
          ),
          itemCount: benchmarkAnimalCount,
          itemBuilder: (BuildContext context, int index) {
            final String url = '$imageUrl?library='
                '${benchmarkName(library)}&item=$index';
            return Semantics(
              label: 'benchmark_${benchmarkName(library)}_item_${index}_'
                  '${benchmarkAnimalNames[index]}',
              image: true,
              child: _benchmarkImage(context, url),
            );
          },
        ),
      ),
    );
  }

  Widget _benchmarkImage(BuildContext context, String url) {
    final int decodePixels =
        (160 * MediaQuery.of(context).devicePixelRatio).round();
    switch (library) {
      case BenchmarkLibrary.powerImage:
        return PowerImage.network(
          url,
          networkBackend: PowerImageNetworkBackend.flutterCodec,
          renderingType: renderingTypeTexture,
          width: 160,
          height: 160,
          imageWidth: 160,
          imageHeight: 160,
          fit: BoxFit.cover,
        );
      case BenchmarkLibrary.powerImageNativeSurface:
        return PowerImage.network(
          url,
          networkBackend: PowerImageNetworkBackend.native,
          renderingType: renderingTypeTexture,
          width: 160,
          height: 160,
          imageWidth: 160,
          imageHeight: 160,
          fit: BoxFit.cover,
        );
      case BenchmarkLibrary.cachedNetworkImage:
        return CachedNetworkImage(
          imageUrl: url,
          width: 160,
          height: 160,
          memCacheWidth: decodePixels,
          memCacheHeight: decodePixels,
          fit: BoxFit.cover,
        );
      case BenchmarkLibrary.extendedImage:
        return ExtendedImage.network(
          url,
          width: 160,
          height: 160,
          cacheWidth: decodePixels,
          cacheHeight: decodePixels,
          fit: BoxFit.cover,
          cache: true,
        );
    }
  }
}

/// Keeps the same 20 high-complexity animated WebPs visible at once so an
/// external profiler can sample steady-state CPU, GPU frequency and memory.
class Steady20BenchmarkPage extends StatelessWidget {
  const Steady20BenchmarkPage({
    Key? key,
    required this.library,
    required this.imageUrl,
  }) : super(key: key);

  final BenchmarkLibrary library;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final String baseName = benchmarkName(library);
    final String name = baseName;
    return Scaffold(
      body: Semantics(
        label: 'steady20_${name}_page',
        child: SingleChildScrollView(
          child: Wrap(
            children: List<Widget>.generate(
              benchmarkGiphyAnimatedWebpAssets.length,
              (int position) {
                final int index = benchmarkGiphyShortestLoopFirst[position];
                final String url = '$imageUrl?library=$name'
                    '&item=$index&steady20=1';
                switch (library) {
                  case BenchmarkLibrary.powerImage:
                    return PowerImage.network(
                      url,
                      networkBackend: PowerImageNetworkBackend.flutterCodec,
                    );
                  case BenchmarkLibrary.powerImageNativeSurface:
                    return PowerImage.network(
                      url,
                      networkBackend: PowerImageNetworkBackend.native,
                      renderingType: renderingTypeTexture,
                    );
                  case BenchmarkLibrary.extendedImage:
                    return ExtendedImage.network(
                      url,
                      cache: true,
                    );
                  case BenchmarkLibrary.cachedNetworkImage:
                    throw StateError(
                        'CNI is not part of the steady20 comparison.');
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

enum CacheBenchmarkMode { cold, rawBytesDisk, flutterImageCache }

extension CacheBenchmarkModeName on CacheBenchmarkMode {
  String get id {
    switch (this) {
      case CacheBenchmarkMode.cold:
        return 'cold';
      case CacheBenchmarkMode.rawBytesDisk:
        return 'raw_bytes_disk';
      case CacheBenchmarkMode.flutterImageCache:
        return 'flutter_image_cache';
    }
  }

  String get traceName => 'PowerImageBenchmark#$id';
}

class CacheLifecycleBenchmarkMenu extends StatelessWidget {
  const CacheLifecycleBenchmarkMenu({
    Key? key,
    required this.animatedWebpUrl,
  }) : super(key: key);

  final String animatedWebpUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('cache_lifecycle_benchmark_menu')),
      body: Semantics(
        label: 'cache_lifecycle_benchmark_menu',
        child: ListView(
          children: CacheBenchmarkMode.values.map((CacheBenchmarkMode mode) {
            return ListTile(
              title: Text('cache_benchmark_${mode.id}'),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) {
                  return CacheLifecycleBenchmarkPage(
                    mode: mode,
                    animatedWebpUrl: animatedWebpUrl,
                  );
                }));
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class CacheLifecycleBenchmarkPage extends StatefulWidget {
  const CacheLifecycleBenchmarkPage({
    Key? key,
    required this.mode,
    required this.animatedWebpUrl,
  }) : super(key: key);

  final CacheBenchmarkMode mode;
  final String animatedWebpUrl;

  @override
  State<CacheLifecycleBenchmarkPage> createState() =>
      _CacheLifecycleBenchmarkPageState();
}

class _CacheLifecycleBenchmarkPageState
    extends State<CacheLifecycleBenchmarkPage> {
  late final StreamSubscription<String> _commandSubscription;
  ImageProvider? _preparedProvider;
  ImageProvider? _displayedProvider;
  bool _preparing = true;
  bool _preparationStarted = false;
  bool _running = false;
  bool _displayed = false;
  bool _finishScheduled = false;

  @override
  void initState() {
    super.initState();
    _commandSubscription = BenchmarkTrace.commands.listen((String command) {
      if (command == 'cache:${widget.mode.id}:run') {
        _run();
      }
    });
  }

  @override
  void dispose() {
    _commandSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_preparationStarted) {
      _preparationStarted = true;
      _prepare();
    }
  }

  Future<void> _prepare() async {
    final String url = '${widget.animatedWebpUrl}?library=power_image&item=0'
        '&cache_mode=${widget.mode.id}'
        '&run=${DateTime.now().microsecondsSinceEpoch}';
    final PowerImageProvider provider = PowerImageProvider.options(
      PowerImageRequestOptions.network(
        url,
        renderingType: renderingTypeTexture,
        networkBackend: PowerImageNetworkBackend.flutterCodec,
        imageWidth: 160,
        imageHeight: 160,
      ),
    );

    if (widget.mode != CacheBenchmarkMode.cold) {
      await precacheImage(provider, context);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(Duration.zero);
      if (widget.mode == CacheBenchmarkMode.rawBytesDisk) {
        await benchmarkRawBytesCache.close();
        await provider.evict(
          configuration: createLocalImageConfiguration(context),
        );
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _preparedProvider = provider;
      _preparing = false;
    });
  }

  Future<void> _run() async {
    final ImageProvider? provider = _preparedProvider;
    if (provider == null || _running) {
      return;
    }
    _running = true;
    await BenchmarkTrace.begin(widget.mode.traceName);
    if (!mounted) {
      await BenchmarkTrace.end();
      return;
    }
    setState(() {
      _displayed = false;
      _displayedProvider = provider;
    });
  }

  Widget _onFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (frame != null && _running && !_finishScheduled) {
      _finishScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
        await BenchmarkTrace.end();
        if (mounted) {
          setState(() {
            _running = false;
            _displayed = true;
          });
        }
      });
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final String state = _displayed
        ? 'displayed'
        : _preparing
            ? 'preparing'
            : 'ready';
    return Semantics(
      label: 'cache_benchmark_${widget.mode.id}_$state',
      child: Scaffold(
        appBar: AppBar(title: Text('cache_benchmark_${widget.mode.id}')),
        body: Center(
          child: _displayedProvider == null
              ? Semantics(
                  label: 'cache_benchmark_${widget.mode.id}_run',
                  button: true,
                  child: ElevatedButton(
                    onPressed: _preparing ? null : _run,
                    child: Text(_preparing ? 'preparing' : 'run'),
                  ),
                )
              : Image(
                  image: _displayedProvider!,
                  width: 160,
                  height: 160,
                  fit: BoxFit.cover,
                  frameBuilder: _onFrame,
                ),
        ),
      ),
    );
  }
}

class SurfaceRebuildBenchmarkPage extends StatefulWidget {
  const SurfaceRebuildBenchmarkPage({
    Key? key,
    required this.animatedWebpUrl,
  }) : super(key: key);

  final String animatedWebpUrl;

  @override
  State<SurfaceRebuildBenchmarkPage> createState() =>
      _SurfaceRebuildBenchmarkPageState();
}

class _SurfaceRebuildBenchmarkPageState
    extends State<SurfaceRebuildBenchmarkPage> {
  static const int _imageCount = 100;

  final Set<int> _displayedImages = <int>{};
  int _generation = 0;
  bool _showImages = true;
  bool _ready = false;
  bool _running = false;
  bool _finishScheduled = false;

  late final StreamSubscription<String> _commandSubscription;

  @override
  void initState() {
    super.initState();
    _commandSubscription = BenchmarkTrace.commands.listen((String command) {
      if (command == 'surface_rebuild:run') {
        _rebuild();
      }
    });
  }

  @override
  void dispose() {
    _commandSubscription.cancel();
    super.dispose();
  }

  Future<void> _rebuild() async {
    if (!_ready || _running) {
      return;
    }
    _running = true;
    _ready = false;
    await BenchmarkTrace.begin('PowerImageBenchmark#surfaceRebuild100');
    if (!mounted) {
      await BenchmarkTrace.end();
      return;
    }
    setState(() {
      _showImages = false;
      _displayedImages.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) {
        return;
      }
      setState(() {
        _generation += 1;
        _showImages = true;
      });
    });
  }

  Widget _frameBuilder(
    int index,
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (frame != null && _displayedImages.add(index)) {
      if (_displayedImages.length == _imageCount && !_finishScheduled) {
        _finishScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
          if (_running) {
            await BenchmarkTrace.end();
          }
          if (mounted) {
            setState(() {
              _ready = true;
              _running = false;
              _finishScheduled = false;
            });
          }
        });
      }
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final String state = _ready
        ? (_generation == 0 ? 'ready_0' : 'complete_$_generation')
        : 'loading_$_generation';
    return Semantics(
      label: 'surface_rebuild_$state',
      child: Scaffold(
        appBar: AppBar(title: const Text('benchmark_surface_rebuild')),
        body: Column(
          children: <Widget>[
            Semantics(
              label: 'surface_rebuild_run',
              button: true,
              child: ElevatedButton(
                onPressed: _ready ? _rebuild : null,
                child: const Text('release and rebuild 100'),
              ),
            ),
            Expanded(
              child: _showImages
                  ? Wrap(
                      children: List<Widget>.generate(_imageCount, (int index) {
                        final String url = '${widget.animatedWebpUrl}'
                            '?library=power_image_native&item=$index'
                            '&generation=$_generation';
                        return PowerImage.network(
                          url,
                          key: ValueKey<String>('$_generation:$index'),
                          networkBackend: PowerImageNetworkBackend.native,
                          renderingType: renderingTypeTexture,
                          width: 28,
                          height: 28,
                          imageWidth: 28,
                          imageHeight: 28,
                          frameBuilder: (
                            BuildContext context,
                            Widget child,
                            int? frame,
                            bool sync,
                          ) =>
                              _frameBuilder(index, context, child, frame, sync),
                        );
                      }),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class CacheWriteBenchmarkPage extends StatefulWidget {
  const CacheWriteBenchmarkPage({
    Key? key,
    required this.imageUrl,
  }) : super(key: key);

  final String imageUrl;

  @override
  State<CacheWriteBenchmarkPage> createState() =>
      _CacheWriteBenchmarkPageState();
}

class _CacheWriteBenchmarkPageState extends State<CacheWriteBenchmarkPage> {
  static const int _imageCount = 100;

  final Set<int> _displayedImages = <int>{};
  late final StreamSubscription<String> _commandSubscription;
  bool _running = false;
  bool _complete = false;
  int _runId = 0;

  @override
  void initState() {
    super.initState();
    _commandSubscription = BenchmarkTrace.commands.listen((String command) {
      if (command == 'cache_write_100:run') {
        _run();
      }
    });
  }

  @override
  void dispose() {
    _commandSubscription.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) {
      return;
    }
    _running = true;
    _complete = false;
    _displayedImages.clear();
    _runId = DateTime.now().microsecondsSinceEpoch;
    await BenchmarkTrace.begin('PowerImageBenchmark#cacheWrite100');
    if (!mounted) {
      await BenchmarkTrace.end();
      return;
    }
    setState(() {});
  }

  Widget _frameBuilder(
    int index,
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (frame != null && _displayedImages.add(index)) {
      if (_displayedImages.length == _imageCount) {
        WidgetsBinding.instance.addPostFrameCallback((Duration _) async {
          await benchmarkRawBytesCache.close();
          await BenchmarkTrace.end();
          if (mounted) {
            setState(() {
              _running = false;
              _complete = true;
            });
          }
        });
      }
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final String state = _complete
        ? 'complete'
        : _running
            ? 'running'
            : 'ready';
    return Semantics(
      label: 'cache_write_100_$state',
      child: Scaffold(
        appBar: AppBar(title: const Text('cache_write_100')),
        body: _running
            ? Wrap(
                children: List<Widget>.generate(_imageCount, (int index) {
                  final String url = '${widget.imageUrl}'
                      '?library=power_image&item=$index&run=$_runId';
                  return PowerImage.network(
                    url,
                    key: ValueKey<int>(index),
                    width: 28,
                    height: 28,
                    imageWidth: 28,
                    imageHeight: 28,
                    frameBuilder: (
                      BuildContext context,
                      Widget child,
                      int? frame,
                      bool sync,
                    ) =>
                        _frameBuilder(index, context, child, frame, sync),
                  );
                }),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class BenchmarkTrace {
  static const MethodChannel _channel = MethodChannel(
    'com.taobao.power_image_example/first_frame_benchmark',
  );
  static final StreamController<String> _commands =
      StreamController<String>.broadcast(sync: true);

  static Stream<String> get commands => _commands.stream;

  static void initialize() {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'command' && call.arguments is String) {
        _commands.add(call.arguments as String);
      }
    });
  }

  static Future<void> begin(String name) async {
    try {
      await _channel.invokeMethod<void>('begin', name);
    } on MissingPluginException {
      // Android-only benchmark trace.
    }
  }

  static Future<void> end() async {
    try {
      await _channel.invokeMethod<void>('end');
    } on MissingPluginException {
      // Android-only benchmark trace.
    }
  }
}
