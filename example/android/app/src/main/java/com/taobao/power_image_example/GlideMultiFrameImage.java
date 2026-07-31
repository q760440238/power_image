package com.taobao.power_image_example;

import android.graphics.drawable.Drawable;

import com.bumptech.glide.load.resource.gif.GifDrawable;
import com.taobao.power_image.loader.FlutterMultiFrameImage;

/**
 */
public class GlideMultiFrameImage extends FlutterMultiFrameImage {

    public GlideMultiFrameImage(GifDrawable drawable, boolean needRecycle) {
        super(drawable,  needRecycle);
    }

    @Override
    protected void onStart(Drawable who) {
        ((GifDrawable) who).start();
    }

    @Override
    protected void onStop(Drawable who) {
        ((GifDrawable) who).stop();
    }

    @Override
    protected void onRelease(Drawable who) {
        ((GifDrawable) who).stop();
    }

    @Override
    public int getFrameCount() {
        return ((GifDrawable)drawable).getFrameCount();
    }

    @Override
    public byte[] getEncodedData() {
        return copyEncodedBuffer(((GifDrawable) drawable).getBuffer());
    }

}
