package com.taobao.power_image.loader;

import android.os.Handler;
import android.os.Looper;
import android.view.Choreographer;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.Executor;

/**
 * Coalesces invalidations to VSync and keeps executor work bounded.
 *
 * <p>At most {@code maxConcurrentRenders} images are submitted at once. Other
 * dirty images remain in insertion order, so a slow surface cannot create an
 * unbounded executor queue or permanently starve later images.
 */
final class MultiFrameRenderCoordinator {
    private final Object lock = new Object();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Executor renderExecutor;
    private final int maxConcurrentRenders;
    private final Set<FlutterMultiFrameImage> dirtyImages = new LinkedHashSet<>();

    private boolean frameCallbackPending;
    private int rendersInFlight;

    private final Runnable renderFinished = new Runnable() {
        @Override
        public void run() {
            onRenderFinished();
        }
    };

    private final Runnable postFrameCallback = new Runnable() {
        @Override
        public void run() {
            Choreographer.getInstance().postFrameCallback(frameCallback);
        }
    };

    private final Choreographer.FrameCallback frameCallback =
            new Choreographer.FrameCallback() {
                @Override
                public void doFrame(long frameTimeNanos) {
                    final List<FlutterMultiFrameImage> batch;
                    synchronized (lock) {
                        frameCallbackPending = false;
                        final int availableSlots =
                                maxConcurrentRenders - rendersInFlight;
                        if (dirtyImages.isEmpty() || availableSlots <= 0) {
                            return;
                        }
                        batch = new ArrayList<>(
                                Math.min(availableSlots, dirtyImages.size()));
                        java.util.Iterator<FlutterMultiFrameImage> iterator =
                                dirtyImages.iterator();
                        while (iterator.hasNext()
                                && batch.size() < availableSlots) {
                            batch.add(iterator.next());
                            iterator.remove();
                        }
                        rendersInFlight += batch.size();
                    }
                    for (FlutterMultiFrameImage image : batch) {
                        if (!image.dispatchPendingFrame(
                                renderExecutor, renderFinished)) {
                            onRenderFinished();
                        }
                    }
                }
            };

    MultiFrameRenderCoordinator(
            Executor renderExecutor, int maxConcurrentRenders) {
        this.renderExecutor = renderExecutor;
        if (maxConcurrentRenders <= 0) {
            throw new IllegalArgumentException(
                    "maxConcurrentRenders must be positive");
        }
        this.maxConcurrentRenders = maxConcurrentRenders;
    }

    void requestRender(FlutterMultiFrameImage image) {
        boolean scheduleFrame = false;
        synchronized (lock) {
            dirtyImages.add(image);
            if (!frameCallbackPending
                    && rendersInFlight < maxConcurrentRenders) {
                frameCallbackPending = true;
                scheduleFrame = true;
            }
        }
        if (scheduleFrame) {
            mainHandler.post(postFrameCallback);
        }
    }

    void remove(FlutterMultiFrameImage image) {
        synchronized (lock) {
            dirtyImages.remove(image);
        }
    }

    private void onRenderFinished() {
        boolean scheduleFrame = false;
        synchronized (lock) {
            if (rendersInFlight <= 0) {
                throw new IllegalStateException("No render is in flight");
            }
            rendersInFlight--;
            if (!dirtyImages.isEmpty()
                    && !frameCallbackPending
                    && rendersInFlight < maxConcurrentRenders) {
                frameCallbackPending = true;
                scheduleFrame = true;
            }
        }
        if (scheduleFrame) {
            mainHandler.post(postFrameCallback);
        }
    }
}
