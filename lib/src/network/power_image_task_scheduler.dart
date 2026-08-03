import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'power_image_network_controls.dart';

/// A bounded two-level scheduler used by network transfer and codec creation.
///
/// Visible work always drains before queued prefetch work. Running work is not
/// preempted, which keeps cancellation and resource ownership straightforward.
class PowerImageTaskScheduler {
  PowerImageTaskScheduler({required this.maxConcurrentTasks})
      : assert(maxConcurrentTasks > 0);

  final int maxConcurrentTasks;
  final Queue<_ScheduledTask<dynamic>> _visibleTasks =
      Queue<_ScheduledTask<dynamic>>();
  final Queue<_ScheduledTask<dynamic>> _backgroundTasks =
      Queue<_ScheduledTask<dynamic>>();
  int _runningTasks = 0;

  PowerImageScheduledTask<T> schedule<T>(
    Future<T> Function() operation, {
    required PowerImageNetworkPriority priority,
  }) {
    final _ScheduledTask<T> task = _ScheduledTask<T>(
      owner: this,
      operation: operation,
      priority: priority,
    );
    _queueFor(priority).add(task);
    _drain();
    return PowerImageScheduledTask<T>._(task);
  }

  Queue<_ScheduledTask<dynamic>> _queueFor(
    PowerImageNetworkPriority priority,
  ) {
    return priority == PowerImageNetworkPriority.visible
        ? _visibleTasks
        : _backgroundTasks;
  }

  void _promote(_ScheduledTask<dynamic> task) {
    if (task.started ||
        task.priority == PowerImageNetworkPriority.visible ||
        !_backgroundTasks.remove(task)) {
      return;
    }
    task.priority = PowerImageNetworkPriority.visible;
    _visibleTasks.add(task);
    _drain();
  }

  void _drain() {
    while (_runningTasks < maxConcurrentTasks &&
        (_visibleTasks.isNotEmpty || _backgroundTasks.isNotEmpty)) {
      final _ScheduledTask<dynamic> task = _visibleTasks.isNotEmpty
          ? _visibleTasks.removeFirst()
          : _backgroundTasks.removeFirst();
      task.started = true;
      _runningTasks += 1;
      Future<dynamic>.sync(task.operation)
          .then<void>(
        task.complete,
        onError: task.completeError,
      )
          .then<void>((_) {
        _runningTasks -= 1;
        _drain();
      });
    }
  }
}

class PowerImageScheduledTask<T> {
  PowerImageScheduledTask._(this._task);

  final _ScheduledTask<T> _task;

  Future<T> get future => _task.completer.future;

  void promote() => _task.owner._promote(_task);
}

/// Routes only the first frame request through the visibility-aware decode
/// scheduler. Animated frames continue directly through Flutter's codec.
class PowerImageFirstFrameCodec implements ui.Codec {
  PowerImageFirstFrameCodec({
    required ui.Codec codec,
    required PowerImageTaskScheduler scheduler,
    required PowerImageNetworkPriority Function() priority,
    required void Function(PowerImageScheduledTask<ui.FrameInfo> task)
        onTaskScheduled,
  })  : _codec = codec,
        _scheduler = scheduler,
        _priority = priority,
        _onTaskScheduled = onTaskScheduled;

  final ui.Codec _codec;
  final PowerImageTaskScheduler _scheduler;
  final PowerImageNetworkPriority Function() _priority;
  final void Function(PowerImageScheduledTask<ui.FrameInfo> task)
      _onTaskScheduled;
  bool _firstFrameRequested = false;

  @override
  int get frameCount => _codec.frameCount;

  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    if (_firstFrameRequested) {
      return _codec.getNextFrame();
    }
    _firstFrameRequested = true;
    final PowerImageScheduledTask<ui.FrameInfo> task = _scheduler.schedule(
      _codec.getNextFrame,
      priority: _priority(),
    );
    _onTaskScheduled(task);
    return task.future;
  }

  @override
  void dispose() => _codec.dispose();
}

class _ScheduledTask<T> {
  _ScheduledTask({
    required this.owner,
    required this.operation,
    required this.priority,
  });

  final PowerImageTaskScheduler owner;
  final Future<T> Function() operation;
  final Completer<T> completer = Completer<T>.sync();
  PowerImageNetworkPriority priority;
  bool started = false;

  void complete(dynamic value) {
    if (!completer.isCompleted) {
      completer.complete(value as T);
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
}
