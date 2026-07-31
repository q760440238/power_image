package com.taobao.power_image_example;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.drawable.Drawable;

import com.bumptech.glide.integration.webp.decoder.WebpDrawable;
import com.taobao.power_image.loader.FlutterMultiFrameImage;

/**
 * Adapts Glide's animated WebP drawable to power_image's texture renderer.
 */
public class GlideWebpMultiFrameImage extends FlutterMultiFrameImage {

    private final Bitmap currentFrame;
    private final Canvas frameCanvas;
    private final boolean recycleDrawable;

    public GlideWebpMultiFrameImage(WebpDrawable drawable, boolean needRecycle) {
        super(drawable, needRecycle);
        recycleDrawable = needRecycle;
        currentFrame = Bitmap.createBitmap(getWidth(), getHeight(), Bitmap.Config.ARGB_8888);
        frameCanvas = new Canvas(currentFrame);
        drawable.setBounds(0, 0, getWidth(), getHeight());
    }

    @Override
    public Bitmap getCurrentFrame(Drawable who) {
        currentFrame.eraseColor(Color.TRANSPARENT);
        who.draw(frameCanvas);
        return currentFrame;
    }

    @Override
    protected void onStart(Drawable who) {
        ((WebpDrawable) who).start();
    }

    @Override
    protected void onRelease(Drawable who) {
        WebpDrawable webpDrawable = (WebpDrawable) who;
        webpDrawable.stop();
        if (recycleDrawable) {
            webpDrawable.recycle();
        }
        if (!currentFrame.isRecycled()) {
            currentFrame.recycle();
        }
    }

    @Override
    public int getFrameCount() {
        return ((WebpDrawable) drawable).getFrameCount();
    }
}
