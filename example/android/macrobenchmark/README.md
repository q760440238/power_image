# Android animated WebP Macrobenchmarks

There are four deliberately separate areas covered by the suites:

- `FlutterCodecAnimatedWebpBenchmark` compares PowerImage,
  CachedNetworkImage and ExtendedImage through the same Flutter codec path.
- `NativeDrawableSurfaceBenchmark` measures PowerImage's explicit native
  Glide/Drawable/Surface path and additionally records
  `PowerImage#renderAnimatedFrames`.
- `FirstFrameDisplayBenchmark` compares the cold first displayed frame of
  PowerImage, CachedNetworkImage and ExtendedImage through a common Flutter
  `Image` widget.
- `CacheLifecycleBenchmark` records PowerImage cold load, encoded-byte disk hit,
  Flutter `ImageCache` hit, and release/rebuild of 100 native image Surfaces.

The suites use the same 100-item grid, dimensions and scroll gestures. Every
item is a different 512x512 Noto animal. Static WebP, 12-frame animated WebP
and 12-frame GIF fixtures are generated from the same pinned source images and
motion, so format comparisons do not change visual complexity. Every library
requests the same density-aware 160x160 logical target, so the test also
exercises target-size decoding. The fixture is served by an in-process loopback
HTTP server, so no external network is involved.

It records the same Flutter UI-frame callback timing, raster `queueBuffer`
timing and peak-memory metrics for all three libraries. AndroidX
`FrameTimingMetric` is intentionally not used: Flutter/Impeller renders its
SurfaceView outside Android HWUI's RenderThread, so that metric sees Android
window transitions rather than the animated Flutter frames. The cross-library
suite excludes PowerImage's native trace because it never enters that backend;
the native suite includes it. Android 10 traces do not contain Flutter's
`CALLBACK_ANIMATION` section, so those devices report raster `queueBuffer` and
memory only.

For the scrolling suites, app startup, fixture creation, page navigation and
initial decoding run outside the measured block, including a three-second
decode-settling interval shared by all libraries. The measured block alternates
scrolling through the 100 items toward the end and then back to the start,
ensuring lazy GridView creation covers the full data set. `startupMode` is
deliberately unset because this is a steady-state interaction benchmark, not an
app-startup benchmark.

The first-frame suite uses the first 512x512 fixture at a 160x160 logical
target. Its native async trace starts immediately before constructing the
provider and ends in the post-frame callback after the first real `ImageInfo`
has participated in paint. Every iteration uses a unique URL and a killed app
process, so neither Flutter memory cache nor package disk-cache hits are counted.
The loopback server removes internet variance while retaining HTTP transfer,
cache-layer work, WebP decoding, scheduling and first paint. This suite requires
Android 10 (API 29) or newer for async trace sections.

The cache/lifecycle suite separates the four cache states instead of mixing
them in one average. Cold load uses a unique URL with no preparation. Raw-byte
disk hit preloads the encoded cache and explicitly evicts the provider from
Flutter's memory cache. Flutter ImageCache hit retains the preloaded provider.
The Surface lifecycle case displays 100 explicit native-backend images, removes
all of them for one frame, then rebuilds all 100 and waits for their first real
frames. Cache cases run 10 measured iterations; the 100-Surface case runs 5.

Run `flutter test` from `example` first. The fixture tests verify that all 100
encoded files and visible first frames are unique, animated files have
successive frame changes, all animal identifiers are unique, and the HTTP
server maps every item to a different response body in each format.

The source images are Noto Emoji by Google, licensed under Apache 2.0. The
generator pins the upstream Git revision and writes source/output SHA-256
hashes to `assets/benchmark/manifest.json`.

Run it from `example/android`:

```shell
./gradlew :macrobenchmark:connectedBenchmarkAndroidTest
```

Run only one execution path with an instrumentation class filter:

```shell
./gradlew :macrobenchmark:connectedBenchmarkAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.taobao.power_image_example.macrobenchmark.FlutterCodecAnimatedWebpBenchmark
./gradlew :macrobenchmark:connectedBenchmarkAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.taobao.power_image_example.macrobenchmark.NativeDrawableSurfaceBenchmark
./gradlew :macrobenchmark:connectedBenchmarkAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.taobao.power_image_example.macrobenchmark.FirstFrameDisplayBenchmark
./gradlew :macrobenchmark:connectedBenchmarkAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.taobao.power_image_example.macrobenchmark.CacheLifecycleBenchmark
```

Use a physical Android device for performance numbers. Emulator execution is
enabled only as a functional check and must not be treated as a performance
baseline.

Keep the physical device unlocked and its display on while invoking AndroidX
Macrobenchmark. The library itself calls `UiDevice.wakeUp()` before setup; MIUI
builds with USB debugging security disabled reject that call even though these
benchmark scenarios use intent commands instead of injected taps.

Checked-in physical-device result sets:

- Xiaomi 22041216C / Android 14: `results/2026-08-03-22041216C`
- Huawei VOG-AL10 / Android 10: `results/2026-08-03-VOG-AL10`
