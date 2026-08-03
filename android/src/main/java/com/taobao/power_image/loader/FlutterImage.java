package com.taobao.power_image.loader;

import android.graphics.Canvas;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.os.Build;
import android.view.Surface;

import com.taobao.power_image.PowerImageDiagnostics;

import java.nio.ByteBuffer;

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
    private FencedSurfaceRenderer fencedRenderer;

    public interface SurfaceProvider {
        Surface getSurface();
    }
    
    public FlutterImage(Drawable drawable) {
        this(drawable, false);
    }

    /** Constructor for encoded-only images that never allocate a Drawable. */
    protected FlutterImage() {
        drawable = null;
        needRecycle = false;
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
        releaseSurfaceRenderer();
        resetCanvasMode();
    }

    /**
     * Pauses or resumes animated images. Single-frame images ignore this state.
     */
    public void setAnimationActive(boolean active) {
    }

    /** Returns the original compressed image when it is cheaply available. */
    public byte[] getEncodedData() {
        return null;
    }

    /** Returns a readable compressed image file when one is already cached. */
    public String getEncodedFilePath() {
        return null;
    }

    /** Copies a decoder-owned buffer without changing its position. */
    protected static byte[] copyEncodedBuffer(ByteBuffer source) {
        if (source == null) {
            return null;
        }
        ByteBuffer copy = source.asReadOnlyBuffer();
        copy.rewind();
        if (!copy.hasRemaining()) {
            return null;
        }
        byte[] bytes = new byte[copy.remaining()];
        copy.get(bytes);
        return bytes;
    }

    public final void setDiagnosticRequestId(String requestId) {
        diagnosticRequestId = requestId;
    }

    protected final String diagnosticRequestId() {
        return diagnosticRequestId;
    }

    protected final Canvas lockSurfaceCanvas(Surface surface, int width, int height) {
        if (surface == null || !surface.isValid()) {
            throw new IllegalStateException("Surface is unavailable");
        }
        if (needsFencedHwuiRenderer()) {
            if (fencedRenderer == null) {
                fencedRenderer = new FencedSurfaceRenderer();
            }
            canvasMode = CANVAS_MODE_HARDWARE;
            return fencedRenderer.lock(surface, width, height);
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

    protected final void unlockSurfaceCanvasAndPost(Surface surface, Canvas canvas) {
        if (fencedRenderer != null && fencedRenderer.owns(canvas)) {
            fencedRenderer.unlockAndPost();
            return;
        }
        surface.unlockCanvasAndPost(canvas);
    }

    protected final void releaseSurfaceRenderer() {
        FencedSurfaceRenderer renderer = fencedRenderer;
        if (renderer == null) {
            return;
        }
        fencedRenderer = null;
        renderer.release();
    }

    static boolean needsFencedHwuiRenderer(int sdkInt) {
        return sdkInt >= Build.VERSION_CODES.Q;
    }

    private static boolean needsFencedHwuiRenderer() {
        return needsFencedHwuiRenderer(Build.VERSION.SDK_INT);
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
