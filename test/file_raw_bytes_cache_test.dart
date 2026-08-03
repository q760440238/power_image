import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:power_image/power_image.dart';

void main() {
  late Directory directory;
  late List<PowerImageFileRawBytesCache> caches;

  PowerImageFileRawBytesCache createCache({required int maxSizeBytes}) {
    final PowerImageFileRawBytesCache cache = PowerImageFileRawBytesCache(
      directory: directory,
      maxSizeBytes: maxSizeBytes,
    );
    caches.add(cache);
    return cache;
  }

  setUp(() async {
    caches = <PowerImageFileRawBytesCache>[];
    directory = await Directory.systemTemp.createTemp(
      'power_image_raw_cache_test_',
    );
  });

  tearDown(() async {
    for (final PowerImageFileRawBytesCache cache in caches) {
      await cache.close();
    }
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('persists encoded bytes without exposing the cache key', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);

    await cache.write('https://cdn.test/avatar.webp?v=3', bytes);

    expect(
      await cache.read('https://cdn.test/avatar.webp?v=3'),
      orderedEquals(bytes),
    );
    final List<FileSystemEntity> files = await directory.list().toList();
    expect(files, hasLength(1));
    expect(files.single.path, isNot(contains('avatar')));
    expect(files.single.path, endsWith('.pi-cache'));
  });

  test('rebuilds the in-memory index after restart', () async {
    final Uint8List bytes = Uint8List.fromList(<int>[8, 6, 7, 5, 3, 0, 9]);
    final PowerImageFileRawBytesCache first = createCache(maxSizeBytes: 1024);
    await first.write('immutable-v1', bytes);

    final PowerImageFileRawBytesCache restarted =
        createCache(maxSizeBytes: 1024);
    await restarted.warmUp();

    expect(await restarted.read('immutable-v1'), orderedEquals(bytes));
  });

  test('the in-memory index avoids disk I/O for known misses', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    await cache.warmUp();

    expect(await cache.read('not-cached'), isNull);
    expect(cache.debugDiskReadCount, 0);
  });

  test('concurrent reads share one physical file read', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    final Uint8List bytes = Uint8List.fromList(List<int>.generate(64, (int i) {
      return i;
    }));
    await cache.write('same-key', bytes);
    final int readsBefore = cache.debugDiskReadCount;

    final List<Uint8List?> results = await Future.wait<Uint8List?>(
      List<Future<Uint8List?>>.generate(32, (_) => cache.read('same-key')),
    );

    expect(cache.debugDiskReadCount - readsBefore, 1);
    for (final Uint8List? result in results) {
      expect(result, orderedEquals(bytes));
    }
  });

  test('creates an immutable buffer directly from the cached file', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
    await cache.write('buffer-key', bytes);
    final int readsBefore = cache.debugDiskReadCount;

    final ui.ImmutableBuffer? buffer = await cache.readBuffer('buffer-key');

    expect(buffer, isNotNull);
    expect(buffer!.length, bytes.lengthInBytes);
    expect(cache.debugDiskReadCount - readsBefore, 1);
    buffer.dispose();
  });

  test('concurrent immutable writes share one atomic replacement', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    await cache.warmUp();
    final Uint8List bytes = Uint8List.fromList(List<int>.filled(128, 7));

    await Future.wait<void>(
      List<Future<void>>.generate(32, (_) => cache.write('same-key', bytes)),
    );

    expect(cache.debugDiskWriteCount, 1);
    expect(await cache.read('same-key'), orderedEquals(bytes));
    final List<String> names = await directory
        .list()
        .map((FileSystemEntity entity) => entity.path)
        .toList();
    expect(names.where((String name) => name.contains('.pi-tmp-')), isEmpty);
    expect(
        names.where((String name) => name.endsWith('.pi-cache')), hasLength(1));
  });

  test('capacity cleanup evicts least recently used bytes', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 8);
    final Uint8List first = Uint8List.fromList(<int>[1, 1, 1, 1]);
    final Uint8List second = Uint8List.fromList(<int>[2, 2, 2, 2]);
    final Uint8List third = Uint8List.fromList(<int>[3, 3, 3, 3]);
    await cache.write('first', first);
    await cache.write('second', second);

    // Make the first entry newer than the second one.
    expect(await cache.read('first'), orderedEquals(first));
    await cache.touch('first');
    await cache.write('third', third);

    expect(await cache.read('first'), orderedEquals(first));
    expect(await cache.read('second'), isNull);
    expect(await cache.read('third'), orderedEquals(third));
  });

  test('persistent LRU touches are coalesced within the coarse interval',
      () async {
    final PowerImageFileRawBytesCache first = createCache(maxSizeBytes: 1024);
    await first.write('touch-key', Uint8List.fromList(<int>[1, 2, 3]));
    final File cacheFile = (await directory
        .list()
        .where((FileSystemEntity entity) => entity.path.endsWith('.pi-cache'))
        .single) as File;
    final DateTime old = DateTime.now().subtract(const Duration(hours: 1));
    await cacheFile.setLastModified(old);

    final PowerImageFileRawBytesCache restarted =
        createCache(maxSizeBytes: 1024);
    await restarted.warmUp();
    await restarted.touch('touch-key');
    final DateTime firstTouch = (await cacheFile.stat()).modified;
    await restarted.touch('touch-key');
    final DateTime secondTouch = (await cacheFile.stat()).modified;

    expect(firstTouch.isAfter(old), isTrue);
    expect(secondTouch, firstTouch);
  });

  test('concurrent writes still finish within byte capacity', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 128);

    await Future.wait<void>(List<Future<void>>.generate(24, (int index) {
      return cache.write(
        'concurrent-$index',
        Uint8List.fromList(List<int>.filled(32, index)),
      );
    }));
    await cache.compact();

    final List<File> files = await directory
        .list()
        .where((FileSystemEntity entity) => entity.path.endsWith('.pi-cache'))
        .cast<File>()
        .toList();
    final List<int> sizes = await Future.wait<int>(
      files.map((File file) async => (await file.stat()).size),
    );
    expect(sizes.fold<int>(0, (int total, int size) => total + size),
        lessThanOrEqualTo(128));
    expect(
      await directory
          .list()
          .where((FileSystemEntity entity) => entity.path.contains('.pi-tmp-'))
          .isEmpty,
      isTrue,
    );
  });

  test('an entry larger than total capacity is not persisted', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 4);
    await cache.write('large', Uint8List.fromList(<int>[1, 2, 3, 4, 5]));

    expect(await cache.read('large'), isNull);
    expect(
      await directory
          .list()
          .where((FileSystemEntity entity) => entity.path.endsWith('.pi-cache'))
          .isEmpty,
      isTrue,
    );
  });

  test('a truncated cache file is removed without deadlocking', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    await cache.write('truncated', Uint8List.fromList(<int>[1, 2, 3]));
    final File cacheFile = (await directory
        .list()
        .where((FileSystemEntity entity) => entity.path.endsWith('.pi-cache'))
        .single) as File;
    await cacheFile.writeAsBytes(<int>[], flush: true);

    expect(
      await cache.read('truncated').timeout(const Duration(seconds: 2)),
      isNull,
    );
    expect(await cacheFile.exists(), isFalse);
  });

  test('warm-up removes abandoned temporary files', () async {
    final File abandoned = File(
      '${directory.path}${Platform.pathSeparator}.pi-tmp-abandoned.tmp',
    );
    await abandoned.writeAsBytes(<int>[1, 2, 3]);

    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    await cache.warmUp();

    expect(await abandoned.exists(), isFalse);
  });

  test('evict removes bytes and the index entry', () async {
    final PowerImageFileRawBytesCache cache = createCache(maxSizeBytes: 1024);
    await cache.write('remove-me', Uint8List.fromList(<int>[1, 2, 3]));

    await cache.evict('remove-me');

    expect(await cache.read('remove-me'), isNull);
  });
}
