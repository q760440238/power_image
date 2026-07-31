# Android animated texture Macrobenchmark

This benchmark compares PowerImage, CachedNetworkImage and ExtendedImage with
the same 20-item grid, dimensions, animated WebP files and scroll gestures.
All 20 files are distinct 512x512 animated animals from Google's Animated Noto
Emoji collection. Every library requests the same density-aware 160x160 logical
target, so the test also exercises target-size decoding. The fixture is served
by an in-process loopback HTTP server, so no external network is involved.

It records the same Flutter UI-frame callback timing, raster `queueBuffer`
timing and peak-memory metrics for all three libraries. AndroidX
`FrameTimingMetric` is intentionally not used: Flutter/Impeller renders its
SurfaceView outside Android HWUI's RenderThread, so that metric sees Android
window transitions rather than the animated Flutter frames. PowerImage's native
`PowerImage#renderAnimatedFrames` trace is also excluded because network animated
WebP uses Flutter's codec path; native Drawable tracing belongs in a separate
benchmark for that execution path. Android 10 traces do not contain Flutter's
`CALLBACK_ANIMATION` section, so those devices report raster `queueBuffer` and
memory only.

App startup, fixture creation, page navigation and initial decoding run outside
the measured block, including a three-second decode-settling interval shared by
all libraries. The measured block alternates scrolling toward the end and start
of the grid, ensuring every gesture moves content instead of repeatedly swiping
against an edge. `startupMode` is deliberately unset because this is a
steady-state interaction benchmark, not an app-startup benchmark.

Run `flutter test` from `example` first. The fixture tests verify that all 20
encoded files and visible first frames are unique, every file is animated,
successive frames differ, all animal names are unique, and the HTTP server maps
every item and animal name to a different response body.

The fixtures are Animated Noto Emoji by Google, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Their source URLs
and pinned SHA-256 hashes are recorded in
`example/tool/generate_benchmark_webp.ps1`.

Run it from `example/android`:

```shell
./gradlew :macrobenchmark:connectedBenchmarkAndroidTest
```

Use a physical Android device for performance numbers. Emulator execution is
enabled only as a functional check and must not be treated as a performance
baseline.
