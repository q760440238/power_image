## Unreleased
- Route HTTP(S) network images through a single Flutter codec provider by default.
- Keep an explicit native network backend for Drawable/Texture/Surface rendering.
- Remove placeholder codec metadata, nested image providers, URL-suffix format routing,
  and completed encoded-handoff requests retained by Android.
- Split Flutter-codec and native Drawable/Surface animated WebP benchmarks.
- Add an injectable encoded-byte disk-cache boundary before direct codec decode,
  without introducing a file-backed or nested image provider.
- Add a lightweight file implementation with an in-memory index, byte-capacity
  LRU, same-key single-flight, atomic writes and background cleanup.
- Add direct-network headers, cache keys, per-attempt timeouts, transient retries
  and cancellation.
- Coalesce equal raw-byte network misses and prioritize visible transfer/decode
  work over queued prefetches.
- Batch raw-cache writes and LRU touches after the first displayed frame.
- Keep ordinary PNG, GIF and WebP on Flutter's codec by default; reserve the
  native backend for explicit Drawable and private-decoder integrations.
- Submit normal Surface frames asynchronously and wait for presentation only at
  teardown; scope release serialization to a TextureRegistry generation.
- Remove the runtime dependency on global `PowerImageBinding`/`ImageCacheExt`;
  native requests now follow the stream completer's last listener.
- Add cold-load, raw-byte disk-hit, Flutter ImageCache-hit and 100-Surface
  release/rebuild macrobenchmarks.

## 0.1.0-pre.2
- pre publish in github and flutter pub

## 0.1.0-pre.1
- publish in github and flutter pub
