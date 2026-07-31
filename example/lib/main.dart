import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:power_image_example/animated_webp_fixture.dart';
import 'package:power_image_example/examples/example_gallery_preview.dart';
import 'examples/drag_overlay.dart';
import 'examples/example_decoration_image_page.dart';
import 'examples/example_page.dart';
import 'package:power_image/power_image.dart';
import 'examples/example_prefetch_page.dart';
import 'examples/image_cache_status.dart';

void main() {
  runZonedGuarded(() async {
    PowerImageBinding();
    PowerImageLoader.instance.setup(PowerImageSetupOptions(renderingTypeTexture,
        debugLogging: kDebugMode,
        errorCallbackSamplingRate: null,
        errorCallback: (PowerImageLoadException exception) {}));
    final AnimatedWebpFixture fixture = await AnimatedWebpFixture.start();
    runApp(MyApp(animatedWebpUrl: fixture.url));
  }, (Object error, StackTrace stackTrace) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      context: ErrorDescription('starting the power_image example'),
    ));
  });
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key, required this.animatedWebpUrl}) : super(key: key);

  final String animatedWebpUrl;

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
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
      home: MyHomePage(animatedWebpUrl: animatedWebpUrl),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.animatedWebpUrl}) : super(key: key);

  final String animatedWebpUrl;

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
          title: const Text('benchmark_power_image'),
          onTap: () {
            DragOverlay.remove();
            Navigator.push(context, MaterialPageRoute(builder: (context) {
              return AnimatedBenchmarkPage(
                library: BenchmarkLibrary.powerImage,
                animatedWebpUrl: widget.animatedWebpUrl,
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
                animatedWebpUrl: widget.animatedWebpUrl,
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
                animatedWebpUrl: widget.animatedWebpUrl,
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

enum BenchmarkLibrary {
  powerImage,
  cachedNetworkImage,
  extendedImage,
}

String benchmarkName(BenchmarkLibrary library) {
  switch (library) {
    case BenchmarkLibrary.powerImage:
      return 'power_image';
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
    required this.animatedWebpUrl,
  }) : super(key: key);

  final BenchmarkLibrary library;
  final String animatedWebpUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('benchmark_${benchmarkName(library)}_page')),
      body: Semantics(
        label: 'benchmark_${benchmarkName(library)}_grid',
        child: GridView.builder(
          cacheExtent: 0,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
          ),
          itemCount: benchmarkAnimatedWebpCount,
          itemBuilder: (BuildContext context, int index) {
            final String url = '$animatedWebpUrl?library='
                '${benchmarkName(library)}&item=$index';
            return Semantics(
              label: 'benchmark_${benchmarkName(library)}_item_${index}_'
                  '${benchmarkAnimatedWebpAnimalNames[index]}',
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
