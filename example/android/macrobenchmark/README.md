# Android animated texture Macrobenchmark

This benchmark compares PowerImage, CachedNetworkImage and ExtendedImage with
the same 20-item grid, dimensions, animated WebP files and scroll gestures.
All 20 files are distinct 512x512 animated animals from Google's Animated Noto
Emoji collection. Every library requests the same density-aware 160x160 logical
target, so the test also exercises target-size decoding. The fixture is served by an in-process
loopback HTTP server, so no external network is involved. It records peak and
end-of-measurement memory for all three libraries and the count/average duration of
`PowerImage#renderAnimatedFrames` for PowerImage.

`FrameTimingMetric` is intentionally not used here. Flutter external textures
can update without producing a Flutter RenderThread slice for every texture
frame, and Android emulators may report no such slices at all. Comparing that
metric would therefore be incomplete rather than a useful animation benchmark.

Run `flutter test` from `example` first. The fixture tests verify that all 20
encoded files and visible first frames are unique, every file is animated,
successive frames differ, all 20 animal names are unique, and the HTTP server
maps every item and animal name to a different response body.

The fixtures are Animated Noto Emoji by Google, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Their source URLs
and pinned SHA-256 hashes are recorded in
`example/tool/generate_benchmark_webp.ps1`.

Run it from `example/android`:

```shell
./gradlew :macrobenchmark:connectedBenchmarkAndroidTest
```

Use a physical Android 14+ device for performance numbers. Emulator execution
is enabled only as a functional check and must not be treated as a performance
baseline.
