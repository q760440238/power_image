package com.taobao.power_image.loader;

/**
 * Thread-safe state for one animated image renderer.
 *
 * <p>The state keeps at most one dirty frame and one in-flight render. New
 * invalidations replace an older dirty frame instead of creating queue work.
 */
final class MultiFrameRenderState {
    enum Completion {
        NONE,
        RENDER_AGAIN,
        CLEANUP
    }

    static final class Snapshot {
        final long invalidations;
        final long coalescedFrames;
        final long renderedFrames;
        final long skippedFrames;
        final long failedFrames;
        final long totalRenderNanos;
        final long maxRenderNanos;

        Snapshot(
                long invalidations,
                long coalescedFrames,
                long renderedFrames,
                long skippedFrames,
                long failedFrames,
                long totalRenderNanos,
                long maxRenderNanos) {
            this.invalidations = invalidations;
            this.coalescedFrames = coalescedFrames;
            this.renderedFrames = renderedFrames;
            this.skippedFrames = skippedFrames;
            this.failedFrames = failedFrames;
            this.totalRenderNanos = totalRenderNanos;
            this.maxRenderNanos = maxRenderNanos;
        }

        long averageRenderNanos() {
            return renderedFrames == 0 ? 0 : totalRenderNanos / renderedFrames;
        }
    }

    private boolean dirty;
    private boolean renderInFlight;
    private boolean released;
    private boolean active = true;
    private boolean cleanupScheduled;
    private boolean cleanupFinished;

    private long invalidations;
    private long coalescedFrames;
    private long renderedFrames;
    private long skippedFrames;
    private long failedFrames;
    private long totalRenderNanos;
    private long maxRenderNanos;

    synchronized boolean markDirty() {
        if (released || !active) {
            return false;
        }
        invalidations++;
        final boolean newlyDirty = !dirty;
        if (!newlyDirty) {
            coalescedFrames++;
        }
        dirty = true;
        return newlyDirty;
    }

    synchronized boolean tryStartRender() {
        if (released || !active || !dirty || renderInFlight) {
            return false;
        }
        dirty = false;
        renderInFlight = true;
        return true;
    }

    synchronized Completion finishRender(
            long renderNanos, boolean rendered, boolean failed) {
        if (!renderInFlight) {
            throw new IllegalStateException("No render is in flight");
        }
        renderInFlight = false;
        if (rendered) {
            renderedFrames++;
            totalRenderNanos += Math.max(0, renderNanos);
            maxRenderNanos = Math.max(maxRenderNanos, Math.max(0, renderNanos));
        } else {
            skippedFrames++;
        }
        if (failed) {
            failedFrames++;
        }
        return nextAction();
    }

    synchronized Completion abortRender() {
        if (!renderInFlight) {
            return nextAction();
        }
        renderInFlight = false;
        if (!released && active) {
            dirty = true;
        }
        return nextAction();
    }

    synchronized boolean setActive(boolean active) {
        if (released || this.active == active) {
            return false;
        }
        this.active = active;
        dirty = active;
        return true;
    }

    synchronized void clearDirty() {
        dirty = false;
    }

    synchronized boolean release() {
        released = true;
        dirty = false;
        return !renderInFlight;
    }

    synchronized boolean tryScheduleCleanup() {
        if (!released || renderInFlight || cleanupScheduled || cleanupFinished) {
            return false;
        }
        cleanupScheduled = true;
        return true;
    }

    synchronized void markCleanupFinished() {
        cleanupFinished = true;
    }

    synchronized boolean isReleased() {
        return released;
    }

    synchronized boolean isActive() {
        return active;
    }

    synchronized boolean isCleanupFinished() {
        return cleanupFinished;
    }

    synchronized Snapshot snapshot() {
        return new Snapshot(
                invalidations,
                coalescedFrames,
                renderedFrames,
                skippedFrames,
                failedFrames,
                totalRenderNanos,
                maxRenderNanos);
    }

    private Completion nextAction() {
        if (released) {
            return Completion.CLEANUP;
        }
        if (active && dirty) {
            return Completion.RENDER_AGAIN;
        }
        return Completion.NONE;
    }
}
