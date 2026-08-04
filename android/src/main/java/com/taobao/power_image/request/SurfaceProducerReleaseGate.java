package com.taobao.power_image.request;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/** Serializes predecessor teardown for one request within an engine generation. */
final class SurfaceProducerReleaseGate {
    interface Release {
        void complete();
    }

    private final Map<String, Integer> pendingReleases = new HashMap<>();
    private final Map<String, List<Runnable>> waiters = new HashMap<>();

    Release beginRelease(final String requestId) {
        synchronized (this) {
            Integer pending = pendingReleases.get(requestId);
            pendingReleases.put(requestId, pending == null ? 1 : pending + 1);
        }
        final AtomicBoolean completed = new AtomicBoolean(false);
        return new Release() {
            @Override
            public void complete() {
                if (!completed.compareAndSet(false, true)) {
                    return;
                }
                finishRelease(requestId);
            }
        };
    }

    void runWhenIdle(String requestId, Runnable runnable) {
        boolean runNow;
        synchronized (this) {
            runNow = !pendingReleases.containsKey(requestId);
            if (!runNow) {
                List<Runnable> requestWaiters = waiters.get(requestId);
                if (requestWaiters == null) {
                    requestWaiters = new ArrayList<>();
                    waiters.put(requestId, requestWaiters);
                }
                requestWaiters.add(runnable);
            }
        }
        if (runNow) {
            runnable.run();
        }
    }

    private void finishRelease(String requestId) {
        final List<Runnable> ready;
        synchronized (this) {
            Integer pending = pendingReleases.get(requestId);
            if (pending == null) {
                return;
            }
            if (pending > 1) {
                pendingReleases.put(requestId, pending - 1);
                return;
            }
            pendingReleases.remove(requestId);
            List<Runnable> requestWaiters = waiters.remove(requestId);
            ready = requestWaiters == null
                    ? new ArrayList<Runnable>()
                    : new ArrayList<>(requestWaiters);
        }
        for (Runnable runnable : ready) {
            runnable.run();
        }
    }
}
