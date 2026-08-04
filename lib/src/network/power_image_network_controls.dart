import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// Scheduling priority for direct Flutter-codec network work.
///
/// Widget loads should keep the default [visible] priority. Prefetch callers
/// use [background], allowing newly visible images to move ahead of queued
/// network transfers and codec creation.
enum PowerImageNetworkPriority { background, visible }

/// Controls how a requested decode box is applied to the source dimensions.
enum PowerImageDecodeFit { contain, cover, exact }

/// Stores encoded network image bytes without exposing a file-backed
/// [ImageProvider]. Implementations may persist the bytes on disk.
abstract class PowerImageRawBytesCache {
  Future<Uint8List?> read(String key);

  Future<void> write(String key, Uint8List bytes);

  Future<void> evict(String key);
}

/// Optional fast path for caches that can construct Flutter's encoded buffer
/// directly from their backing store without first materializing Dart bytes.
abstract class PowerImageRawBytesBufferCache {
  Future<ui.ImmutableBuffer?> readBuffer(String key);
}

/// Optional batched maintenance implemented by caches with persistent LRU.
abstract class PowerImageRawBytesCacheBatch {
  Future<void> writeAll(Map<String, Uint8List> entries);

  Future<void> touchAll(Iterable<String> keys);
}

/// Cancels an in-flight Flutter-codec network request.
class PowerImageCancellationToken {
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Object? get reason => _reason;
  Object? _reason;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel([Object? reason]) {
    if (isCancelled) {
      return;
    }
    _reason = reason;
    _cancelled.complete();
    final List<VoidCallback> listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final VoidCallback listener in listeners) {
      listener();
    }
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw PowerImageRequestCancelledException(reason);
    }
  }

  void addListener(VoidCallback listener) {
    if (isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}

class PowerImageRequestCancelledException implements Exception {
  const PowerImageRequestCancelledException([this.reason]);

  final Object? reason;

  @override
  String toString() {
    return reason == null
        ? 'PowerImage network request cancelled.'
        : 'PowerImage network request cancelled: $reason';
  }
}
