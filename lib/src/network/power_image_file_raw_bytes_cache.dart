import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'power_image_network_controls.dart';

/// A capacity-bounded file cache for immutable encoded image bytes.
///
/// The caller owns the dedicated directory and should create only one cache
/// instance for it. Use versioned cache keys whenever the bytes at a URL can
/// change. Files are never exposed as image providers.
class PowerImageFileRawBytesCache
    implements
        PowerImageRawBytesCache,
        PowerImageRawBytesBufferCache,
        PowerImageRawBytesCacheBatch {
  PowerImageFileRawBytesCache({
    required this.directory,
    required this.maxSizeBytes,
  }) : assert(maxSizeBytes > 0, 'maxSizeBytes must be greater than zero.') {
    if (maxSizeBytes <= 0) {
      throw ArgumentError.value(
        maxSizeBytes,
        'maxSizeBytes',
        'must be greater than zero',
      );
    }
    _ready = _initialize();
    unawaited(_ready.catchError((Object _) {}));
  }

  static const String _cacheSuffix = '.pi-cache';
  static const String _temporaryPrefix = '.pi-tmp-';
  static const Duration _persistentTouchInterval = Duration(minutes: 30);

  final Directory directory;
  final int maxSizeBytes;

  late final Future<void> _ready;
  final Map<String, _FileCacheEntry> _entries = <String, _FileCacheEntry>{};
  final Map<String, Future<Uint8List?>> _reads = <String, Future<Uint8List?>>{};
  final Map<String, Set<Future<ui.ImmutableBuffer?>>> _bufferReads =
      <String, Set<Future<ui.ImmutableBuffer?>>>{};
  final Map<String, Future<void>> _writes = <String, Future<void>>{};
  final Map<String, Future<void>> _deletions = <String, Future<void>>{};
  final Map<String, Future<void>> _touches = <String, Future<void>>{};
  final List<Future<void>> _writeTails = List<Future<void>>.generate(
    16,
    (_) => Future<void>.value(),
  );
  int _nextWriteLane = 0;
  Future<void>? _cleanup;
  bool _cleanupRequested = false;
  int _totalSizeBytes = 0;
  int _accessOrder = 0;
  int _temporaryId = 0;

  int _debugDiskReadCount = 0;

  int _debugDiskWriteCount = 0;

  @visibleForTesting
  int get debugDiskReadCount => _debugDiskReadCount;

  @visibleForTesting
  int get debugDiskWriteCount => _debugDiskWriteCount;

  /// Starts directory scanning early so the first image does not pay for it.
  Future<void> warmUp() => _ready;

  /// Waits for background file touches and cache mutations to finish.
  /// No persistent file handle is kept after this future completes.
  Future<void> close() async {
    await _ready;
    while (_reads.isNotEmpty ||
        _bufferReads.isNotEmpty ||
        _writes.isNotEmpty ||
        _deletions.isNotEmpty ||
        _touches.isNotEmpty ||
        _cleanup != null) {
      final List<Future<void>> pending = <Future<void>>[
        ..._reads.values.map((Future<Uint8List?> future) async {
          await future;
        }),
        ..._bufferReads.values.expand(
          (Set<Future<ui.ImmutableBuffer?>> reads) =>
              reads.map((Future<ui.ImmutableBuffer?> future) async {
            await future;
          }),
        ),
        ..._writes.values,
        ..._deletions.values,
        ..._touches.values,
        if (_cleanup != null) _cleanup!,
      ];
      if (pending.isEmpty) {
        break;
      }
      await Future.wait<void>(pending);
    }
  }

  @override
  Future<ui.ImmutableBuffer?> readBuffer(String key) async {
    await _ready;
    final String fileName = _fileName(key);
    await _waitForMutation(fileName);

    if (!_entries.containsKey(fileName)) {
      return null;
    }
    final Future<ui.ImmutableBuffer?> read = _readBufferFile(fileName);
    _bufferReads
        .putIfAbsent(fileName, () => <Future<ui.ImmutableBuffer?>>{})
        .add(read);
    try {
      return await read;
    } finally {
      final Set<Future<ui.ImmutableBuffer?>>? reads = _bufferReads[fileName];
      reads?.remove(read);
      if (reads != null && reads.isEmpty) {
        _bufferReads.remove(fileName);
      }
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    await _ready;
    final String fileName = _fileName(key);
    await _waitForMutation(fileName);

    if (!_entries.containsKey(fileName)) {
      return null;
    }
    final Future<Uint8List?>? pendingRead = _reads[fileName];
    if (pendingRead != null) {
      return pendingRead;
    }

    final Future<Uint8List?> read = _readFile(fileName);
    _reads[fileName] = read;
    try {
      return await read;
    } finally {
      if (identical(_reads[fileName], read)) {
        _reads.remove(fileName);
      }
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (await _writeEntry(key, bytes)) {
      await compact();
    }
  }

  @override
  Future<void> writeAll(Map<String, Uint8List> entries) async {
    final List<bool> completed = await Future.wait<bool>(
      entries.entries.map((MapEntry<String, Uint8List> entry) {
        return _writeEntry(entry.key, entry.value);
      }),
    );
    if (completed.any((bool value) => value)) {
      await compact();
    }
  }

  Future<bool> _writeEntry(String key, Uint8List bytes) async {
    await _ready;
    final String fileName = _fileName(key);
    final Future<void>? pendingDeletion = _deletions[fileName];
    if (pendingDeletion != null) {
      await pendingDeletion;
    }
    final Future<void>? pendingWrite = _writes[fileName];
    if (pendingWrite != null) {
      await pendingWrite;
      return false;
    }

    final int writeLane = _nextWriteLane;
    _nextWriteLane = (_nextWriteLane + 1) % _writeTails.length;
    final Future<void> previousWrite = _writeTails[writeLane];
    final Future<void> write = () async {
      try {
        await previousWrite;
      } on Object {
        // A failed write must not stop later independent cache entries.
      }
      await _writeFile(fileName, bytes);
    }();
    _writeTails[writeLane] = write;
    _writes[fileName] = write;
    bool completed = false;
    try {
      await write;
      completed = true;
    } finally {
      if (identical(_writes[fileName], write)) {
        _writes.remove(fileName);
      }
    }
    return completed;
  }

  Future<void> touch(String key) => touchAll(<String>[key]);

  @override
  Future<void> touchAll(Iterable<String> keys) async {
    await _ready;
    final Set<String> fileNames = keys.map(_fileName).toSet();
    await Future.wait<void>(fileNames.map(_touchFile));
  }

  @override
  Future<void> evict(String key) async {
    await _ready;
    final String fileName = _fileName(key);
    final Future<void>? pendingWrite = _writes[fileName];
    if (pendingWrite != null) {
      await pendingWrite;
    }
    await _deleteEntry(fileName);
  }

  /// Runs capacity cleanup immediately. Normal writes already trigger this in
  /// their background future, so applications rarely need to call it.
  Future<void> compact() async {
    await _ready;
    final Future<void>? running = _cleanup;
    if (running != null) {
      _cleanupRequested = true;
      return running;
    }
    final Future<void> cleanup = _runCleanup();
    _cleanup = cleanup;
    return cleanup;
  }

  Future<void> _runCleanup() async {
    try {
      do {
        _cleanupRequested = false;
        await _trimToCapacity();
      } while (_cleanupRequested);
    } finally {
      // There is no await between the final loop check and this assignment,
      // so a concurrent compact either joins this worker or starts the next.
      _cleanup = null;
    }
  }

  Future<void> _initialize() async {
    await directory.create(recursive: true);
    final List<_ScannedFile> scanned = <_ScannedFile>[];
    await for (final FileSystemEntity entity in directory.list()) {
      final String name = _baseName(entity.path);
      if (name.startsWith(_temporaryPrefix)) {
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          // A stale temporary file can be retried during a future warm-up.
        }
        continue;
      }
      if (entity is! File || !name.endsWith(_cacheSuffix)) {
        continue;
      }
      try {
        final FileStat stat = await entity.stat();
        if (stat.size <= 0) {
          await entity.delete();
          continue;
        }
        scanned.add(_ScannedFile(name, stat.size, stat.modified));
      } on FileSystemException {
        // A file may disappear while the cache is being initialized.
      }
    }
    scanned.sort((_ScannedFile left, _ScannedFile right) {
      final int timeOrder = left.modified.compareTo(right.modified);
      return timeOrder != 0 ? timeOrder : left.name.compareTo(right.name);
    });
    for (final _ScannedFile file in scanned) {
      _entries[file.name] = _FileCacheEntry(
        size: file.size,
        accessOrder: ++_accessOrder,
        lastPersistedAccess: file.modified,
      );
      _totalSizeBytes += file.size;
    }
    await _trimToCapacity();
  }

  Future<Uint8List?> _readFile(String fileName) async {
    final File file = File(_join(directory.path, fileName));
    try {
      _debugDiskReadCount += 1;
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        // This method is itself registered in `_reads`. Going through
        // `_deleteEntry` here would wait for this same read to complete.
        try {
          await file.delete();
        } on FileSystemException {
          // Treat a concurrently removed empty file as a cache miss.
        }
        _removeIndexEntry(fileName);
        return null;
      }
      final _FileCacheEntry? existing = _entries[fileName];
      if (existing == null) {
        _entries[fileName] = _FileCacheEntry(
          size: bytes.lengthInBytes,
          accessOrder: ++_accessOrder,
          lastPersistedAccess: DateTime.now(),
        );
        _totalSizeBytes += bytes.lengthInBytes;
      } else if (existing.size != bytes.lengthInBytes) {
        _totalSizeBytes -= existing.size;
        existing.size = bytes.lengthInBytes;
        _totalSizeBytes += existing.size;
      }
      return bytes;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2 || !await file.exists()) {
        _removeIndexEntry(fileName);
        return null;
      }
      rethrow;
    }
  }

  Future<ui.ImmutableBuffer?> _readBufferFile(String fileName) async {
    final File file = File(_join(directory.path, fileName));
    try {
      _debugDiskReadCount += 1;
      final ui.ImmutableBuffer buffer =
          await ui.ImmutableBuffer.fromFilePath(file.path);
      if (buffer.length == 0) {
        buffer.dispose();
        try {
          await file.delete();
        } on FileSystemException {
          // Treat a concurrently removed empty file as a cache miss.
        }
        _removeIndexEntry(fileName);
        return null;
      }
      final _FileCacheEntry? existing = _entries[fileName];
      if (existing == null) {
        _entries[fileName] = _FileCacheEntry(
          size: buffer.length,
          accessOrder: ++_accessOrder,
          lastPersistedAccess: DateTime.now(),
        );
        _totalSizeBytes += buffer.length;
      } else if (existing.size != buffer.length) {
        _totalSizeBytes -= existing.size;
        existing.size = buffer.length;
        _totalSizeBytes += existing.size;
      }
      return buffer;
    } on Exception {
      if (!await file.exists()) {
        _removeIndexEntry(fileName);
        return null;
      }
      rethrow;
    }
  }

  Future<void> _waitForMutation(String fileName) async {
    while (true) {
      final Future<void>? pendingWrite = _writes[fileName];
      if (pendingWrite != null) {
        await pendingWrite;
        continue;
      }
      final Future<void>? pendingDeletion = _deletions[fileName];
      if (pendingDeletion != null) {
        await pendingDeletion;
        continue;
      }
      return;
    }
  }

  Future<void> _writeFile(String fileName, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.lengthInBytes > maxSizeBytes) {
      await _deleteEntry(fileName);
      return;
    }

    final Future<Uint8List?>? pendingRead = _reads[fileName];
    if (pendingRead != null) {
      try {
        await pendingRead;
      } on Object {
        // A failed old read must not prevent a complete replacement.
      }
    }
    final Set<Future<ui.ImmutableBuffer?>>? pendingBufferReads =
        _bufferReads[fileName];
    if (pendingBufferReads != null) {
      await Future.wait<ui.ImmutableBuffer?>(pendingBufferReads);
    }

    final File target = File(_join(directory.path, fileName));
    final String temporaryName =
        '$_temporaryPrefix$fileName-${++_temporaryId}.tmp';
    final File temporary = File(_join(directory.path, temporaryName));
    try {
      _debugDiskWriteCount += 1;
      await temporary.writeAsBytes(bytes);
      await _replaceAtomically(temporary, target);
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // Initialization removes abandoned temporary files next launch.
        }
      }
    }

    final _FileCacheEntry? previous = _entries[fileName];
    if (previous != null) {
      _totalSizeBytes -= previous.size;
    }
    _entries[fileName] = _FileCacheEntry(
      size: bytes.lengthInBytes,
      accessOrder: ++_accessOrder,
      lastPersistedAccess: DateTime.now(),
    );
    _totalSizeBytes += bytes.lengthInBytes;
  }

  Future<void> _replaceAtomically(File temporary, File target) async {
    try {
      await temporary.rename(target.path);
      return;
    } on FileSystemException {
      // Windows cannot replace an existing file with rename. Public reads wait
      // for the in-flight write, so this fallback still never exposes a partial
      // file through this cache.
    }

    final File backup = File(
      _join(
        directory.path,
        '$_temporaryPrefix${_baseName(target.path)}-${++_temporaryId}.bak',
      ),
    );
    bool movedOldFile = false;
    if (await target.exists()) {
      await target.rename(backup.path);
      movedOldFile = true;
    }
    try {
      await temporary.rename(target.path);
    } catch (_) {
      if (movedOldFile && !await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
    if (movedOldFile && await backup.exists()) {
      try {
        await backup.delete();
      } on FileSystemException {
        // The new file is already complete. Initialization can remove this
        // abandoned backup without turning a successful write into a miss.
      }
    }
  }

  Future<void> _trimToCapacity() async {
    if (_totalSizeBytes <= maxSizeBytes) {
      return;
    }
    final List<MapEntry<String, _FileCacheEntry>> oldest = _entries.entries
        .toList()
      ..sort((MapEntry<String, _FileCacheEntry> left,
              MapEntry<String, _FileCacheEntry> right) =>
          left.value.accessOrder.compareTo(right.value.accessOrder));
    for (final MapEntry<String, _FileCacheEntry> entry in oldest) {
      if (_totalSizeBytes <= maxSizeBytes) {
        break;
      }
      if (_reads.containsKey(entry.key) ||
          _bufferReads.containsKey(entry.key) ||
          _writes.containsKey(entry.key)) {
        continue;
      }
      await _deleteEntry(entry.key);
    }
  }

  Future<void> _deleteEntry(String fileName) async {
    final Future<void>? pendingDeletion = _deletions[fileName];
    if (pendingDeletion != null) {
      return pendingDeletion;
    }
    final Future<void> deletion = _deleteFile(fileName);
    _deletions[fileName] = deletion;
    try {
      await deletion;
    } finally {
      if (identical(_deletions[fileName], deletion)) {
        _deletions.remove(fileName);
      }
    }
  }

  Future<void> _deleteFile(String fileName) async {
    final Future<Uint8List?>? pendingRead = _reads[fileName];
    if (pendingRead != null) {
      try {
        await pendingRead;
      } on Object {
        // Deletion should still remove a file that failed to read.
      }
    }
    final Set<Future<ui.ImmutableBuffer?>>? pendingBufferReads =
        _bufferReads[fileName];
    if (pendingBufferReads != null) {
      try {
        await Future.wait<ui.ImmutableBuffer?>(pendingBufferReads);
      } on Object {
        // Deletion should still remove a file that failed to create a buffer.
      }
    }
    final File file = File(_join(directory.path, fileName));
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      rethrow;
    } finally {
      if (!await file.exists()) {
        _removeIndexEntry(fileName);
      }
    }
  }

  void _removeIndexEntry(String fileName) {
    final _FileCacheEntry? removed = _entries.remove(fileName);
    if (removed != null) {
      _totalSizeBytes -= removed.size;
    }
  }

  Future<void> _touchFile(String fileName) async {
    final _FileCacheEntry? entry = _entries[fileName];
    if (entry == null) {
      return;
    }
    entry.accessOrder = ++_accessOrder;
    final DateTime now = DateTime.now();
    if (now.difference(entry.lastPersistedAccess) < _persistentTouchInterval) {
      return;
    }
    entry.lastPersistedAccess = now;
    final Future<void>? pendingTouch = _touches[fileName];
    if (pendingTouch != null) {
      await pendingTouch;
      return;
    }
    final File file = File(_join(directory.path, fileName));
    final Future<void> touch =
        file.setLastModified(now).then<void>((_) {}).catchError((Object _) {});
    _touches[fileName] = touch;
    try {
      await touch;
    } finally {
      if (identical(_touches[fileName], touch)) {
        _touches.remove(fileName);
      }
    }
  }

  static String _fileName(String key) {
    return '${sha256.convert(utf8.encode(key))}$_cacheSuffix';
  }

  static String _join(String directory, String name) {
    final String separator = Platform.pathSeparator;
    return directory.endsWith(separator)
        ? '$directory$name'
        : '$directory$separator$name';
  }

  static String _baseName(String path) {
    final int separator = path.lastIndexOf(Platform.pathSeparator);
    return separator == -1 ? path : path.substring(separator + 1);
  }
}

class _FileCacheEntry {
  _FileCacheEntry({
    required this.size,
    required this.accessOrder,
    required this.lastPersistedAccess,
  });

  int size;
  int accessOrder;
  DateTime lastPersistedAccess;
}

class _ScannedFile {
  const _ScannedFile(this.name, this.size, this.modified);

  final String name;
  final int size;
  final DateTime modified;
}
