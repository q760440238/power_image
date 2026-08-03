import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:power_image/power_image.dart';
import 'package:power_image/src/network/power_image_task_scheduler.dart';

void main() {
  test('visible work runs before queued background work', () async {
    final PowerImageTaskScheduler scheduler =
        PowerImageTaskScheduler(maxConcurrentTasks: 1);
    final Completer<void> releaseRunningTask = Completer<void>();
    final List<String> order = <String>[];

    final PowerImageScheduledTask<void> running = scheduler.schedule<void>(
      () async {
        order.add('running');
        await releaseRunningTask.future;
      },
      priority: PowerImageNetworkPriority.background,
    );
    final PowerImageScheduledTask<void> background = scheduler.schedule<void>(
      () async {
        order.add('background');
      },
      priority: PowerImageNetworkPriority.background,
    );
    final PowerImageScheduledTask<void> visible = scheduler.schedule<void>(
      () async {
        order.add('visible');
      },
      priority: PowerImageNetworkPriority.visible,
    );

    releaseRunningTask.complete();
    await Future.wait<void>(
      <Future<void>>[running.future, background.future, visible.future],
    );

    expect(order, <String>['running', 'visible', 'background']);
  });

  test('queued background work can be promoted', () async {
    final PowerImageTaskScheduler scheduler =
        PowerImageTaskScheduler(maxConcurrentTasks: 1);
    final Completer<void> releaseRunningTask = Completer<void>();
    final List<String> order = <String>[];

    final PowerImageScheduledTask<void> running = scheduler.schedule<void>(
      () => releaseRunningTask.future,
      priority: PowerImageNetworkPriority.background,
    );
    final PowerImageScheduledTask<void> promoted = scheduler.schedule<void>(
      () async {
        order.add('promoted');
      },
      priority: PowerImageNetworkPriority.background,
    );
    final PowerImageScheduledTask<void> background = scheduler.schedule<void>(
      () async {
        order.add('background');
      },
      priority: PowerImageNetworkPriority.background,
    );
    promoted.promote();

    releaseRunningTask.complete();
    await Future.wait<void>(
      <Future<void>>[running.future, promoted.future, background.future],
    );

    expect(order, <String>['promoted', 'background']);
  });

  test('only the first codec frame is scheduled', () async {
    final PowerImageTaskScheduler scheduler =
        PowerImageTaskScheduler(maxConcurrentTasks: 1);
    final Completer<void> blocker = Completer<void>();
    final PowerImageScheduledTask<void> running = scheduler.schedule<void>(
      () => blocker.future,
      priority: PowerImageNetworkPriority.visible,
    );
    final _FailingCodec codec = _FailingCodec();
    final PowerImageFirstFrameCodec scheduledCodec = PowerImageFirstFrameCodec(
      codec: codec,
      scheduler: scheduler,
      priority: () => PowerImageNetworkPriority.visible,
      onTaskScheduled: (_) {},
    );

    final Future<ui.FrameInfo> firstFrame = scheduledCodec.getNextFrame();
    expect(codec.requests, 0);
    blocker.complete();
    await running.future;
    await expectLater(firstFrame, throwsStateError);
    expect(codec.requests, 1);

    final Future<ui.FrameInfo> secondFrame = scheduledCodec.getNextFrame();
    expect(codec.requests, 2);
    await expectLater(secondFrame, throwsStateError);
  });
}

class _FailingCodec implements ui.Codec {
  int requests = 0;

  @override
  int get frameCount => 2;

  @override
  int get repetitionCount => 0;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    requests += 1;
    return Future<ui.FrameInfo>.error(StateError('test frame'));
  }

  @override
  void dispose() {}
}
