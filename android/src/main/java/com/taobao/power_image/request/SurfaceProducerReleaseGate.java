package com.taobao.power_image.request;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

/** Serializes producer teardown within one engine/TextureRegistry generation. */
final class SurfaceProducerReleaseGate {
    interface Release {
        void complete();
    }

    private int pendingReleases;
    private final List<Runnable> waiters = new ArrayList<>();

    Release beginRelease() {
        synchronized (this) {
            pendingReleases++;
        }
        final AtomicBoolean completed = new AtomicBoolean(false);
        return new Release() {
            @Override
            public void complete() {
                if (!completed.compareAndSet(false, true)) {
                    return;
                }
                finishRelease();
            }
        };
    }

    void runWhenIdle(Runnable runnable) {
        boolean runNow;
        synchronized (this) {
            runNow = pendingReleases == 0;
            if (!runNow) {
                waiters.add(runnable);
            }
        }
        if (runNow) {
            runnable.run();
        }
    }

    private void finishRelease() {
        final List<Runnable> ready;
        synchronized (this) {
            pendingReleases--;
            if (pendingReleases != 0) {
                return;
            }
            ready = new ArrayList<>(waiters);
            waiters.clear();
        }
        for (Runnable runnable : ready) {
            runnable.run();
        }
    }
}
