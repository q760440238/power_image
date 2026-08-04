# 2026-08-04 VOG-AL10 optimization results

Device: HUAWEI VOG-AL10, Android 10 / API 29, 8 CPU cores. The tests use a
release/benchmark build and AndroidX Macrobenchmark async trace sections.

## Retained changes

- HTTP(S) PNG/GIF/WebP stays on Flutter's codec by default. Native remains an
  explicit path for custom Drawable or private decoders.
- `decodeFit` now has consistent contain/cover/exact geometry, with a default
  16-physical-pixel decode-size bucket.
- Network and first-frame decode scheduling reserves visible capacity and
  limits concurrent work by requested pixel/byte cost.
- A deterministic encoded-byte cache key can be read before the startup
  directory scan finishes. Deferred writes have a 32 MiB pending-byte budget;
  one oversized entry uses an exclusive temporary-file/atomic-rename path.
- Surface teardown serialization is request-scoped, so a released request no
  longer blocks unrelated Surface generations.

## 20 animated WebPs, natural-size Wrap

Each Flutter implementation uses the same 20 files, the same shortest-loop
first order, no fixed display size, no fixed decode size, 12 s warm-up and 20 s
sampling. Values aggregate 60 one-second CPU samples across three runs.

| Implementation | CPU P50 | CPU P95 | Total PSS P50 | Graphics PSS P50 | FPS P50 |
| --- | ---: | ---: | ---: | ---: | ---: |
| PowerImage Flutter codec | 132.824% | 135.731% | 158,923 KB | 53,272 KB | 60.140 |
| ExtendedImage 10.1.0 | 134.780% | 136.548% | 160,596 KB | 45,812 KB | 60.182 |
| Android Glide 4.16.0 | 81.431% | 83.517% | 55,144 KB | 7,580 KB | 60.202 |

PowerImage is 1.45% lower in CPU and 1.04% lower in total PSS than
ExtendedImage, but uses 16.28% more Graphics PSS. This is parity, not an 8%+
steady-state win. Glide is a platform reference rather than a fully equivalent
plugin comparison: native Drawable visibility/invalidations can suppress
off-screen work differently from Flutter ImageStreams in a scrollable Wrap.
The production kernel does not expose GPU utilization, so GPU frequency is
recorded only as a DVFS proxy in the raw JSON.

Raw data: `isolated-power-3x.json`, `isolated-extended-3x.json`,
`isolated-glide-3x.json`, and `steady20-wrap-original-size-summary-3x.json`.

## Rejected short-loop frame-cache prototype

The bounded decoded-frame prototype was tested directly, then removed from the
product API and codec path. In the smoke A/B it changed CPU P50 from 125.670%
to 137.177% (+9.16%, worse), total PSS from 170,066 KB to 186,907 KB, and
Graphics PSS from 56,680 KB to 75,252 KB. It did not meet the requested 8% CPU
reduction and imposed a clear memory cost.

Raw data: `steady20-wrap-frame-cache-smoke.json`.

## Cold first displayed frame, 10 iterations

All providers use the same 512x512 WebP, 160x160 logical target, killed app
process and the same post-paint async trace boundary.

| Implementation | P50 | P95 | Max | Heap peak P50 |
| --- | ---: | ---: | ---: | ---: |
| PowerImage provider | 44.021 ms | 45.142 ms | 45.470 ms | 1,811.5 KB |
| PowerImage.network widget | 44.568 ms | 60.989 ms | 62.169 ms | 1,812.0 KB |
| ExtendedImage 10.1.0 | 50.956 ms | 61.050 ms | 61.429 ms | 1,812.0 KB |
| CachedNetworkImage 3.4.1 | 67.603 ms | 79.928 ms | 81.060 ms | 1,894.5 KB |

The provider-level comparison puts PowerImage 13.6% ahead of ExtendedImage and
34.9% ahead of CachedNetworkImage at P50. The complete PowerImage widget path
is 12.5% and 34.1% ahead respectively.

Raw data: `first-frame-display-4libs-10x.json`.

## Cache and Surface lifecycle A/B

The before values are the checked-in 2026-08-03 formal medians. The after
values come from one complete 40-iteration `CacheLifecycleBenchmark` run.

| Scenario | Before P50 | After P50 | Delta | After max |
| --- | ---: | ---: | ---: | ---: |
| Cold load | 41.967 ms | 43.539 ms | +3.75% | 45.111 ms |
| Encoded-byte disk hit | 27.936 ms | 22.723 ms | -18.66% | 48.419 ms |
| Flutter ImageCache hit | 15.878 ms | 11.572 ms | -27.12% | 22.316 ms |
| Write 100 encoded entries | 230.714 ms | 238.050 ms | +3.18% | 260.814 ms |
| Release/rebuild 100 native Surfaces | 962.568 ms | 446.408 ms | -53.62% | 457.058 ms |

Surface rebuilding passed 5/5 iterations. Its anonymous RSS peak median moved
from 322,820 KB to 321,772 KB (-0.32%); heap peak median moved from 30,432 KB
to 25,005 KB (-17.8%). The write-100 and cold-load regressions are retained in
the report and are not claimed as wins.

Raw data: `cache-lifecycle-optimized-5tests.json` and
`surface-request-generation-ab-5x.json`.

## Verification

- `flutter test`: 90/90 passed.
- AndroidX `CacheLifecycleBenchmark`: 5/5 test methods passed, 40 formal
  iterations total.
- AndroidX `FirstFrameDisplayBenchmark`: 4/4 test methods passed, 40 formal
  iterations total.
- Android 10 request-generation Surface stress: 5/5 passed. No Android 14
  device was connected for this final run.
