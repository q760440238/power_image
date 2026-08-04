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

  test('background work leaves capacity for a newly visible task', () async {
    final PowerImageTaskScheduler scheduler = PowerImageTaskScheduler(
      maxConcurrentTasks: 6,
      maxBackgroundTasks: 4,
    );
    final Completer<void> release = Completer<void>();
    int backgroundStarted = 0;
    bool visibleStarted = false;
    final List<PowerImageScheduledTask<void>> background =
        List<PowerImageScheduledTask<void>>.generate(6, (_) {
      return scheduler.schedule<void>(
        () async {
          backgroundStarted += 1;
          await release.future;
        },
        priority: PowerImageNetworkPriority.background,
      );
    });

    await Future<void>.delayed(Duration.zero);
    expect(backgroundStarted, 4);
    final PowerImageScheduledTask<void> visible = scheduler.schedule<void>(
      () async {
        visibleStarted = true;
      },
      priority: PowerImageNetworkPriority.visible,
    );
    await visible.future;
    expect(visibleStarted, isTrue);
    expect(backgroundStarted, 4);

    release.complete();
    await Future.wait<void>(background.map((task) => task.future));
  });

  test('task costs bound concurrent expensive work', () async {
    final PowerImageTaskScheduler scheduler = PowerImageTaskScheduler(
      maxConcurrentTasks: 4,
      maxConcurrentCost: 4,
    );
    final Completer<void> release = Completer<void>();
    bool secondStarted = false;
    final PowerImageScheduledTask<void> first = scheduler.schedule<void>(
      () => release.future,
      priority: PowerImageNetworkPriority.visible,
      cost: 3,
    );
    final PowerImageScheduledTask<void> second = scheduler.schedule<void>(
      () async {
        secondStarted = true;
      },
      priority: PowerImageNetworkPriority.visible,
      cost: 2,
    );

    await Future<void>.delayed(Duration.zero);
    expect(secondStarted, isFalse);
    release.complete();
    await Future.wait<void>(<Future<void>>[first.future, second.future]);
    expect(secondStarted, isTrue);
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
