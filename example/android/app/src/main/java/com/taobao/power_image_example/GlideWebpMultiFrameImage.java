package com.taobao.power_image_example;

import android.graphics.drawable.Drawable;

import com.bumptech.glide.integration.webp.decoder.WebpDrawable;
import com.taobao.power_image.loader.FlutterMultiFrameImage;

/**
 * Adapts Glide's animated WebP drawable to power_image's texture renderer.
 */
public class GlideWebpMultiFrameImage extends FlutterMultiFrameImage {

    private final boolean recycleDrawable;

    public GlideWebpMultiFrameImage(WebpDrawable drawable, boolean needRecycle) {
        super(drawable, needRecycle);
        recycleDrawable = needRecycle;
    }

    @Override
    protected void onStart(Drawable who) {
        ((WebpDrawable) who).start();
    }

    @Override
    protected void onStop(Drawable who) {
        ((WebpDrawable) who).stop();
    }

    @Override
    protected void onRelease(Drawable who) {
        WebpDrawable webpDrawable = (WebpDrawable) who;
        webpDrawable.stop();
        if (recycleDrawable) {
            webpDrawable.recycle();
        }
    }

    @Override
    public int getFrameCount() {
        return ((WebpDrawable) drawable).getFrameCount();
    }
}
