package com.taobao.power_image.loader;

import android.graphics.Canvas;
import android.graphics.HardwareRenderer;
import android.graphics.RecordingCanvas;
import android.graphics.RenderNode;
import android.view.Surface;

import androidx.annotation.RequiresApi;

/** API 29 renderer with asynchronous frames and one present fence at teardown. */
@RequiresApi(29)
final class FencedSurfaceRenderer {
    private final RenderNode renderNode = new RenderNode("PowerImageSurface");
    private final HardwareRenderer renderer = new HardwareRenderer();
    private RecordingCanvas canvas;
    private Surface surface;
    private boolean submittedFrame;

    FencedSurfaceRenderer() {
        renderer.setContentRoot(renderNode);
        renderer.setOpaque(false);
    }

    Canvas lock(Surface target, int width, int height) {
        if (surface != target) {
            renderer.setSurface(target);
            surface = target;
        }
        renderNode.setPosition(0, 0, width, height);
        canvas = renderNode.beginRecording(width, height);
        return canvas;
    }

    boolean owns(Canvas candidate) {
        return canvas == candidate;
    }

    void unlockAndPost() {
        renderNode.endRecording();
        canvas = null;
        int result = renderer.createRenderRequest()
                .setVsyncTime(System.nanoTime())
                .setWaitForPresent(waitForPresent(false))
                .syncAndDraw();
        submittedFrame = true;
        if ((result & HardwareRenderer.SYNC_LOST_SURFACE_REWARD_IF_FOUND) != 0) {
            throw new IllegalStateException("Surface was lost while rendering");
        }
    }

    void release() {
        try {
            if (submittedFrame && surface != null && surface.isValid()) {
                // The normal frame path only waits for command submission. This
                // final request is the teardown fence that prevents HWUI from
                // retaining the ImageReader surface after producer release.
                renderer.createRenderRequest()
                        .setVsyncTime(System.nanoTime())
                        .setWaitForPresent(waitForPresent(true))
                        .syncAndDraw();
            }
        } catch (RuntimeException ignored) {
            // A surface may be reported invalid concurrently with teardown.
        } finally {
            canvas = null;
            surface = null;
            submittedFrame = false;
            renderer.setSurface(null);
            renderer.destroy();
        }
    }

    static boolean waitForPresent(boolean tearingDown) {
        return tearingDown;
    }
}
