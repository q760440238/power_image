package com.taobao.power_image.loader;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.PorterDuff;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.os.Trace;
import android.view.Surface;

import com.taobao.power_image.PowerImageDiagnostics;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;


/**
 * created by wayne.xie on 2021/7/22
 * A MultiFrame Object。 such as format: gif、webp、apng
 */
public abstract class FlutterMultiFrameImage extends FlutterImage implements Drawable.Callback {

    private static final String TAG = "FlutterMultiFrameImage";
    // schedule thread for multi-frame
    private static final Handler gAnimateScheduler;
    private static final ExecutorService gRenderExecutor;
    private static final MultiFrameRenderCoordinator gRenderCoordinator;

    static {
        final HandlerThread schedulerThead = new HandlerThread("multi-frame-image-scheduler");
        schedulerThead.start();

        gAnimateScheduler = new Handler(schedulerThead.getLooper());
        final int renderThreadCount = Math.min(
                4, Math.max(2, Runtime.getRuntime().availableProcessors() / 2));
        final AtomicInteger renderThreadId = new AtomicInteger();
        gRenderExecutor = Executors.newFixedThreadPool(
                renderThreadCount,
                new ThreadFactory() {
                    @Override
                    public Thread newThread(Runnable runnable) {
                        return new Thread(
                                runnable,
                                "power-image-render-" + renderThreadId.incrementAndGet());
                    }
                });
        gRenderCoordinator = new MultiFrameRenderCoordinator(
                gRenderExecutor, renderThreadCount);
        PowerImageDiagnostics.debug(
                "render_pool_created", null, "threads=" + renderThreadCount);
    }

    private volatile Surface fixedSurface;
    private volatile SurfaceProvider surfaceProvider;
    private volatile Rect destRect;

    private boolean started = false;

    private final MultiFrameRenderState renderState = new MultiFrameRenderState();
    private final Object surfaceLock = new Object();
    private final List<Runnable> releaseCallbacks = new ArrayList<>();
    private long lastLoggedFrameCount;

    public FlutterMultiFrameImage(Drawable drawable) {
        this(drawable,  false);
    }

    public FlutterMultiFrameImage(Drawable drawable, boolean needRecycle) {
        super(drawable,  needRecycle);
        drawable.setCallback(this);
    }

    @Override
    public final void invalidateDrawable(final Drawable who) {
        if (!renderState.markDirty()) {
            return;
        }
        gRenderCoordinator.requestRender(this);
    }

    /**
     * Returns a one-off snapshot for the external rendering path.
     * Texture animations draw the Drawable directly and never retain this Bitmap.
     */
    @Deprecated
    public Bitmap getCurrentFrame(Drawable who) {
        final int width = getWidth();
        final int height = getHeight();
        if (who == null || width <= 0 || height <= 0) {
            return null;
        }

        final Rect previousBounds = who.copyBounds();
        final Bitmap frame = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(frame);
        try {
            who.setBounds(0, 0, width, height);
            who.draw(canvas);
        } finally {
            who.setBounds(previousBounds);
        }
        return frame;
    }

    @Override
    public final void scheduleDrawable(Drawable who, Runnable what, long when) {
        if (renderState.isReleased()) {
            return;
        }

        gAnimateScheduler.postAtTime(what, this, when);
    }

    @Override
    public final void unscheduleDrawable(Drawable who, Runnable what) {
        gAnimateScheduler.removeCallbacks(what);
    }

    @Override
    public final void draw(Surface surface, Rect destRect) {
        if (renderState.isReleased()) {
            return;
        }
        synchronized (surfaceLock) {
            this.surfaceProvider = null;
            this.fixedSurface = surface;
        }
        attachSurface(destRect);
    }

    @Override
    public final void draw(SurfaceProvider surfaceProvider, Rect destRect) {
        if (renderState.isReleased()) {
            return;
        }
        synchronized (surfaceLock) {
            this.fixedSurface = null;
            this.surfaceProvider = surfaceProvider;
        }
        attachSurface(destRect);
    }

    private void attachSurface(Rect destRect) {
        this.destRect = new Rect(destRect);
        if (renderState.markDirty()) {
            gRenderCoordinator.requestRender(this);
        }
        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                if (renderState.isActive() && drawable != null && !started) {
                    startDrawable();
                }
            }
        }, false);
    }

    private boolean renderCurrentFrame() {
        final long frameStartedAt = SystemClock.elapsedRealtimeNanos();
        synchronized (surfaceLock) {
            final Drawable currentDrawable = drawable;
            final Rect currentDestRect = destRect;
            final SurfaceProvider currentProvider = surfaceProvider;
            final Surface surface = currentProvider != null
                    ? currentProvider.getSurface()
                    : fixedSurface;
            if (renderState.isReleased() || currentDrawable == null
                    || currentDestRect == null || surface == null || !surface.isValid()) {
                return false;
            }

            final long surfaceReadyAt = SystemClock.elapsedRealtimeNanos();
            final Canvas canvas = lockSurfaceCanvas(
                    surface, currentDestRect.width(), currentDestRect.height());
            final long canvasLockedAt = SystemClock.elapsedRealtimeNanos();
            long drawableDrawnAt;
            try {
                if (!coversOpaqueSurface(currentDrawable, currentDestRect, canvas)) {
                    canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR);
                }
                currentDrawable.setBounds(currentDestRect);
                currentDrawable.draw(canvas);
            } finally {
                drawableDrawnAt = SystemClock.elapsedRealtimeNanos();
                unlockSurfaceCanvasAndPost(surface, canvas);
            }
            final long framePostedAt = SystemClock.elapsedRealtimeNanos();
            if (PowerImageDiagnostics.isVerboseEnabled()
                    && framePostedAt - frameStartedAt > 32_000_000L) {
                PowerImageDiagnostics.verbose(
                        "frame_slow",
                        diagnosticRequestId(),
                        "surfaceUs=" + ((surfaceReadyAt - frameStartedAt) / 1_000L)
                                + " lockUs=" + ((canvasLockedAt - surfaceReadyAt) / 1_000L)
                                + " drawUs=" + ((drawableDrawnAt - canvasLockedAt) / 1_000L)
                                + " postUs=" + ((framePostedAt - drawableDrawnAt) / 1_000L)
                                + " hardware=" + canvas.isHardwareAccelerated());
            }
            return true;
        }
    }

    final boolean dispatchPendingFrame(Executor executor, final Runnable onTaskFinished) {
        if (!renderState.tryStartRender()) {
            return false;
        }

        final long queuedAtNanos = SystemClock.elapsedRealtimeNanos();
        try {
            executor.execute(new Runnable() {
                @Override
                public void run() {
                    Trace.beginSection("PowerImage#renderAnimatedFrames");
                    final long startedAt = SystemClock.elapsedRealtimeNanos();
                    boolean rendered = false;
                    boolean failed = false;
                    try {
                        rendered = renderCurrentFrame();
                    } catch (Throwable error) {
                        failed = true;
                        PowerImageDiagnostics.error(
                                "frame_render_failed",
                                diagnosticRequestId(),
                                null,
                                error);
                    } finally {
                        try {
                            Trace.endSection();
                            MultiFrameRenderState.Completion completion =
                                    renderState.finishRender(
                                    SystemClock.elapsedRealtimeNanos() - startedAt,
                                    rendered,
                                    failed);
                            long queueWaitNanos = startedAt - queuedAtNanos;
                            if (queueWaitNanos > 16_666_667L) {
                                PowerImageDiagnostics.verbose(
                                        "frame_queue_wait",
                                        diagnosticRequestId(),
                                        "waitUs=" + (queueWaitNanos / 1_000L));
                            }
                            logPeriodicFrameStats();
                            handleCompletion(completion);
                        } finally {
                            onTaskFinished.run();
                        }
                    }
                }
            });
        } catch (RuntimeException error) {
            handleCompletion(renderState.abortRender());
            onTaskFinished.run();
            PowerImageDiagnostics.error(
                    "frame_dispatch_failed",
                    diagnosticRequestId(),
                    null,
                    error);
        }
        return true;
    }

    private void handleCompletion(MultiFrameRenderState.Completion completion) {
        if (completion == MultiFrameRenderState.Completion.CLEANUP) {
            scheduleReleaseCleanup();
        } else if (completion == MultiFrameRenderState.Completion.RENDER_AGAIN) {
            gRenderCoordinator.requestRender(this);
        }
    }

    private void logPeriodicFrameStats() {
        if (!PowerImageDiagnostics.isVerboseEnabled()) {
            return;
        }
        MultiFrameRenderState.Snapshot stats = renderState.snapshot();
        if (stats.renderedFrames >= lastLoggedFrameCount + 120) {
            lastLoggedFrameCount = stats.renderedFrames;
            logFrameStats("frame_stats");
        }
    }

    private void logFrameStats(String event) {
        MultiFrameRenderState.Snapshot stats = renderState.snapshot();
        PowerImageDiagnostics.debug(
                event,
                diagnosticRequestId(),
                "invalidations=" + stats.invalidations
                        + " rendered=" + stats.renderedFrames
                        + " coalesced=" + stats.coalescedFrames
                        + " skipped=" + stats.skippedFrames
                        + " failed=" + stats.failedFrames
                        + " avgUs=" + (stats.averageRenderNanos() / 1_000L)
                        + " maxUs=" + (stats.maxRenderNanos / 1_000L));
    }

    private boolean coversOpaqueSurface(
            Drawable currentDrawable, Rect currentDestRect, Canvas canvas) {
        return isCurrentFrameOpaqueAndComplete(currentDrawable)
                && currentDestRect.left <= 0
                && currentDestRect.top <= 0
                && currentDestRect.right >= canvas.getWidth()
                && currentDestRect.bottom >= canvas.getHeight();
    }

    /**
     * Subclasses may opt into skipping the surface clear only when every
     * rendered frame is known to be both opaque and a complete image.
     * Drawable#getOpacity alone is not sufficient for partial GIF/WebP frames.
     */
    protected boolean isCurrentFrameOpaqueAndComplete(Drawable who) {
        return false;
    }

    /**
     * we should play the GifDrawable
     * @param who
     */
    protected abstract void onStart(Drawable who);

    protected void onStop(Drawable who) {
    }

    @Override
    public final void setAnimationActive(final boolean active) {
        if (!renderState.setActive(active)) {
            return;
        }
        if (active) {
            gRenderCoordinator.requestRender(this);
        } else {
            gRenderCoordinator.remove(this);
        }
        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                if (drawable == null) {
                    return;
                }
                if (active && hasSurface() && !started) {
                    startDrawable();
                } else if (!active && started) {
                    stopDrawable();
                }
            }
        }, false);
    }

    @Override
    public final void onSurfaceCleanup() {
        if (renderState.isReleased()) {
            return;
        }
        synchronized (surfaceLock) {
            surfaceProvider = null;
            releaseSurfaceRenderer();
            resetCanvasMode();
        }
        renderState.clearDirty();
        gRenderCoordinator.remove(this);
        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                if (!hasSurface() && drawable != null && started) {
                    stopDrawable();
                }
            }
        }, false);
    }

    /**
     * we should stop the gifDrawable and do some gc work
     */
    @Override
    public final void release() {
        release(null);
    }

    @Override
    public final void release(Runnable onReleased) {
        boolean runCallbackNow = false;
        boolean firstRelease = false;
        synchronized (renderState) {
            if (onReleased != null) {
                if (renderState.isCleanupFinished()) {
                    runCallbackNow = true;
                } else {
                    releaseCallbacks.add(onReleased);
                }
            }
            firstRelease = !renderState.isReleased();
            renderState.release();
        }

        if (runCallbackNow) {
            onReleased.run();
            return;
        }

        if (firstRelease) {
            gRenderCoordinator.remove(this);
            gAnimateScheduler.removeCallbacksAndMessages(this);
        }
        scheduleReleaseCleanup();
    }

    protected abstract void onRelease(Drawable who);

    private void startDrawable() {
        try {
            onStart(drawable);
            started = true;
            PowerImageDiagnostics.debug(
                    "animation_started", diagnosticRequestId(), null);
        } catch (Throwable error) {
            PowerImageDiagnostics.error(
                    "animation_start_failed", diagnosticRequestId(), null, error);
        }
    }

    private void stopDrawable() {
        try {
            onStop(drawable);
        } catch (Throwable error) {
            PowerImageDiagnostics.error(
                    "animation_stop_failed", diagnosticRequestId(), null, error);
        } finally {
            started = false;
            PowerImageDiagnostics.debug(
                    "animation_stopped", diagnosticRequestId(), null);
        }
    }

    private boolean hasSurface() {
        synchronized (surfaceLock) {
            return surfaceProvider != null || fixedSurface != null;
        }
    }

    private void scheduleReleaseCleanup() {
        if (!renderState.tryScheduleCleanup()) {
            return;
        }

        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                try {
                    synchronized (surfaceLock) {
                        if (drawable != null) {
                            Drawable releasedDrawable = drawable;
                            drawable = null;
                            releasedDrawable.setCallback(null);
                            try {
                                onRelease(releasedDrawable);
                            } catch (Throwable error) {
                                PowerImageDiagnostics.error(
                                        "drawable_release_failed",
                                        diagnosticRequestId(),
                                        null,
                                        error);
                            }
                        }

                        if (fixedSurface != null) {
                            Surface releasedSurface = fixedSurface;
                            fixedSurface = null;
                            try {
                                releasedSurface.release();
                            } catch (Throwable error) {
                                PowerImageDiagnostics.error(
                                        "surface_release_failed",
                                        diagnosticRequestId(),
                                        null,
                                        error);
                            }
                        }
                        surfaceProvider = null;
                        releaseSurfaceRenderer();
                    }
                } finally {
                    started = false;
                    logFrameStats("frame_stats_final");

                    final List<Runnable> callbacks;
                    synchronized (renderState) {
                        renderState.markCleanupFinished();
                        callbacks = new ArrayList<>(releaseCallbacks);
                        releaseCallbacks.clear();
                    }
                    for (Runnable callback : callbacks) {
                        try {
                            callback.run();
                        } catch (Throwable error) {
                            PowerImageDiagnostics.error(
                                    "release_callback_failed",
                                    diagnosticRequestId(),
                                    null,
                                    error);
                        }
                    }
                }
            }
        }, false);
    }

    private void runOnScheduler(Runnable task, boolean forceNextLoop) {
        if (Thread.currentThread() == gAnimateScheduler.getLooper().getThread() && !forceNextLoop) {
            task.run();
        } else {
            gAnimateScheduler.postAtTime(task, this, SystemClock.uptimeMillis());
        }
    }
}
