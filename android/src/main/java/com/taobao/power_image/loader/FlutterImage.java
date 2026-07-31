package com.taobao.power_image.loader;

import android.graphics.Canvas;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.view.Surface;

import com.taobao.power_image.PowerImageDiagnostics;

/**
 */
public abstract class FlutterImage {
    private static final int CANVAS_MODE_UNKNOWN = 0;
    private static final int CANVAS_MODE_HARDWARE = 1;
    private static final int CANVAS_MODE_SOFTWARE = 2;

    protected Drawable drawable;
    protected boolean needRecycle;
    private volatile int canvasMode = CANVAS_MODE_UNKNOWN;
    private volatile String diagnosticRequestId;

    public interface SurfaceProvider {
        Surface getSurface();
    }
    
    public FlutterImage(Drawable drawable) {
        this(drawable, false);
    }

    /**
     *
     * @param drawable actual drawable to render
     * @param needRecycle if true,  when power_image stopTask, we will invoke Bitmap.recycle/GifDrawable.stop
     */
    public FlutterImage(Drawable drawable, boolean needRecycle) {
        if (drawable == null) {
            throw new IllegalArgumentException("Empty input drawable!");
        }

        this.drawable = drawable;
        this.needRecycle = needRecycle;
    }


    /**
     * SingleFrame return 1、 MultiFrame should return actual frameCount
     * @return
     */
    public abstract int getFrameCount();

    /**
     * release some object for memory consideration
     */
    public abstract void release();

    /**
     * Releases the image and runs {@code onReleased} after no renderer can use
     * the backing drawable anymore. Single-frame images release synchronously;
     * animated images may wait for an in-flight surface draw to finish.
     */
    public void release(Runnable onReleased) {
        release();
        if (onReleased != null) {
            onReleased.run();
        }
    }

    /**
     * draw the actual bitmap to the surface with specific destRect
     * @param surface
     * @param destRect
     */
    public abstract void draw(Surface surface, Rect destRect);

    /**
     * Draw using a Flutter-managed surface that may change during its lifetime.
     */
    public void draw(SurfaceProvider surfaceProvider, Rect destRect) {
        if (surfaceProvider == null) {
            return;
        }
        draw(surfaceProvider.getSurface(), destRect);
    }

    /**
     * Called when Flutter temporarily destroys the backing surface.
     */
    public void onSurfaceCleanup() {
        resetCanvasMode();
    }

    /**
     * Pauses or resumes animated images. Single-frame images ignore this state.
     */
    public void setAnimationActive(boolean active) {
    }

    public final void setDiagnosticRequestId(String requestId) {
        diagnosticRequestId = requestId;
    }

    protected final String diagnosticRequestId() {
        return diagnosticRequestId;
    }

    protected final Canvas lockSurfaceCanvas(Surface surface) {
        if (surface == null || !surface.isValid()) {
            throw new IllegalStateException("Surface is unavailable");
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                && canvasMode != CANVAS_MODE_SOFTWARE) {
            try {
                Canvas canvas = surface.lockHardwareCanvas();
                canvasMode = CANVAS_MODE_HARDWARE;
                return canvas;
            } catch (RuntimeException ignored) {
                // Some Surface implementations do not support hardware canvases.
                canvasMode = CANVAS_MODE_SOFTWARE;
                PowerImageDiagnostics.debug(
                        "canvas_fallback",
                        diagnosticRequestId,
                        "reason=" + ignored.getClass().getSimpleName());
            }
        }
        Canvas canvas = surface.lockCanvas(null);
        canvasMode = CANVAS_MODE_SOFTWARE;
        return canvas;
    }

    protected final void resetCanvasMode() {
        canvasMode = CANVAS_MODE_UNKNOWN;
    }

    /**
     * Returns the drawable's intrinsic width.
     * @return
     */
    public int getWidth() {
        return drawable.getIntrinsicWidth();
    }

    /**
     * Returns the drawable's intrinsic height.
     * @return
     */
    public int getHeight() {
        return drawable.getIntrinsicHeight();
    }

    /**
     * Returns the actual drawable(BitmapDrawable、GifDrawable)
     * @return
     */
    public Drawable getDrawable(){
        return drawable;
    }
    
    public boolean isValid(){
        return drawable != null;
    }

}
