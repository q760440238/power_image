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
import android.view.Surface;

import java.util.concurrent.atomic.AtomicBoolean;


/**
 * created by wayne.xie on 2021/7/22
 * A MultiFrame Object。 such as format: gif、webp、apng
 */
public abstract class FlutterMultiFrameImage extends FlutterImage implements Drawable.Callback {

    private static final String TAG = "FlutterMultiFrameImage";
    // schedule thread for multi-frame
    private static final Handler gAnimateScheduler;
    private static final MultiFrameRenderCoordinator gRenderCoordinator;

    static {
        final HandlerThread schedulerThead = new HandlerThread("multi-frame-image-scheduler");
        schedulerThead.start();

        gAnimateScheduler = new Handler(schedulerThead.getLooper());
        gRenderCoordinator = new MultiFrameRenderCoordinator(gAnimateScheduler);
    }

    private volatile Surface fixedSurface;
    private volatile SurfaceProvider surfaceProvider;
    private volatile Rect destRect;

    private volatile boolean released = false;
    private volatile boolean animationActive = true;
    private boolean started = false;

    private final AtomicBoolean frameDirty = new AtomicBoolean(false);

    public FlutterMultiFrameImage(Drawable drawable) {
        this(drawable,  false);
    }

    public FlutterMultiFrameImage(Drawable drawable, boolean needRecycle) {
        super(drawable,  needRecycle);
        drawable.setCallback(this);
    }

    @Override
    public final void invalidateDrawable(final Drawable who) {
        if (released || !animationActive) {
            return;
        }

        frameDirty.set(true);
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
        if (released) {
            return;
        }

        final long delay = when - SystemClock.uptimeMillis();
        gAnimateScheduler.postDelayed(what, delay);
    }

    @Override
    public final void unscheduleDrawable(Drawable who, Runnable what) {
        gAnimateScheduler.removeCallbacks(what);
    }

    @Override
    public final void draw(Surface surface, Rect destRect) {
        if (released) {
            return;
        }

        this.surfaceProvider = null;
        this.fixedSurface = surface;
        attachSurface(destRect);
    }

    @Override
    public final void draw(SurfaceProvider surfaceProvider, Rect destRect) {
        if (released) {
            return;
        }

        this.fixedSurface = null;
        this.surfaceProvider = surfaceProvider;
        attachSurface(destRect);
    }

    private void attachSurface(Rect destRect) {
        this.destRect = new Rect(destRect);
        frameDirty.set(true);
        gRenderCoordinator.requestRender(this);
        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                if (animationActive && drawable != null && !started) {
                    started = true;
                    onStart(drawable);
                }
            }
        }, false);
    }

    private void renderCurrentFrame() {
        final Drawable currentDrawable = drawable;
        final Rect currentDestRect = destRect;
        final SurfaceProvider currentProvider = surfaceProvider;
        final Surface surface = currentProvider != null
                ? currentProvider.getSurface()
                : fixedSurface;
        if (released || currentDrawable == null || currentDestRect == null
                || surface == null || !surface.isValid()) {
            return;
        }

        final Canvas canvas = lockSurfaceCanvas(surface);
        try {
            if (!coversOpaqueSurface(currentDrawable, currentDestRect, canvas)) {
                canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR);
            }
            currentDrawable.setBounds(currentDestRect);
            currentDrawable.draw(canvas);
        } finally {
            surface.unlockCanvasAndPost(canvas);
        }
    }

    final void renderPendingFrame() {
        if (released || !frameDirty.getAndSet(false)) {
            return;
        }
        try {
            renderCurrentFrame();
        } catch (Throwable t) {
            t.printStackTrace();
        }
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
        if (released || animationActive == active) {
            return;
        }
        animationActive = active;
        if (active) {
            frameDirty.set(true);
            gRenderCoordinator.requestRender(this);
        } else {
            frameDirty.set(false);
            gRenderCoordinator.remove(this);
        }
        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                if (drawable == null) {
                    return;
                }
                if (active && hasSurface() && !started) {
                    started = true;
                    onStart(drawable);
                } else if (!active && started) {
                    onStop(drawable);
                    started = false;
                }
            }
        }, false);
    }

    @Override
    public final void onSurfaceCleanup() {
        if (released) {
            return;
        }
        surfaceProvider = null;
        frameDirty.set(false);
        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                if (surfaceProvider == null && drawable != null && started) {
                    onStop(drawable);
                    started = false;
                }
            }
        }, false);
    }

    /**
     * we should stop the gifDrawable and do some gc work
     */
    @Override
    public final void release() {
        released = true;
        frameDirty.set(false);
        gRenderCoordinator.remove(this);

        runOnScheduler(new Runnable() {
            @Override
            public void run() {
                if (drawable != null) {
                    drawable.setCallback(null);
                    onRelease(drawable);
                    drawable = null;
                }

                if (fixedSurface != null) {
                    fixedSurface.release();
                    fixedSurface = null;
                }
                surfaceProvider = null;
                started = false;
            }
        }, false);
    }

    protected abstract void onRelease(Drawable who);

    private boolean hasSurface() {
        return surfaceProvider != null || fixedSurface != null;
    }

    private void runOnScheduler(Runnable task, boolean forceNextLoop) {
        if (Thread.currentThread() == gAnimateScheduler.getLooper().getThread() && !forceNextLoop) {
            task.run();
        } else {
            gAnimateScheduler.post(task);
        }
    }
}
