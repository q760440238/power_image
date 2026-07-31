package com.taobao.power_image.loader;

import android.os.Handler;
import android.os.Looper;
import android.os.Trace;
import android.view.Choreographer;

import java.util.ArrayList;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Set;

/**
 * Coalesces all animated image invalidations into one render batch per display frame.
 */
final class MultiFrameRenderCoordinator {
    private final Object lock = new Object();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Handler renderHandler;
    private final Set<FlutterMultiFrameImage> dirtyImages =
            Collections.newSetFromMap(new IdentityHashMap<FlutterMultiFrameImage, Boolean>());

    private boolean frameCallbackPending;
    private boolean renderBatchInFlight;

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
                        if (dirtyImages.isEmpty()) {
                            return;
                        }
                        batch = new ArrayList<>(dirtyImages);
                        dirtyImages.clear();
                        renderBatchInFlight = true;
                    }
                    renderHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            Trace.beginSection("PowerImage#renderAnimatedFrames");
                            try {
                                for (FlutterMultiFrameImage image : batch) {
                                    image.renderPendingFrame();
                                }
                            } finally {
                                Trace.endSection();
                                onRenderBatchComplete();
                            }
                        }
                    });
                }
            };

    MultiFrameRenderCoordinator(Handler renderHandler) {
        this.renderHandler = renderHandler;
    }

    void requestRender(FlutterMultiFrameImage image) {
        boolean scheduleFrame = false;
        synchronized (lock) {
            dirtyImages.add(image);
            if (!frameCallbackPending && !renderBatchInFlight) {
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

    private void onRenderBatchComplete() {
        boolean scheduleFrame = false;
        synchronized (lock) {
            renderBatchInFlight = false;
            if (!dirtyImages.isEmpty() && !frameCallbackPending) {
                frameCallbackPending = true;
                scheduleFrame = true;
            }
        }
        if (scheduleFrame) {
            mainHandler.post(postFrameCallback);
        }
    }
}
