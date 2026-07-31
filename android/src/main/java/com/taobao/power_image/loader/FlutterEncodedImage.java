package com.taobao.power_image.loader;

import android.graphics.Rect;
import android.view.Surface;

/** Compressed image data intended for Flutter's codec instead of a native texture. */
public final class FlutterEncodedImage extends FlutterImage {
    private volatile byte[] encodedData;
    private volatile String encodedFilePath;
    private final int width;
    private final int height;
    private final int frameCount;

    public FlutterEncodedImage(byte[] encodedData, int width, int height, int frameCount) {
        super();
        if (encodedData == null || encodedData.length == 0) {
            throw new IllegalArgumentException("Empty encoded image data");
        }
        validateDimensions(width, height, frameCount);
        this.encodedData = encodedData;
        this.width = width;
        this.height = height;
        this.frameCount = frameCount;
    }

    public FlutterEncodedImage(String encodedFilePath, int width, int height, int frameCount) {
        super();
        if (encodedFilePath == null || encodedFilePath.isEmpty()) {
            throw new IllegalArgumentException("Empty encoded image file path");
        }
        validateDimensions(width, height, frameCount);
        this.encodedFilePath = encodedFilePath;
        this.width = width;
        this.height = height;
        this.frameCount = frameCount;
    }

    private static void validateDimensions(int width, int height, int frameCount) {
        if (width <= 0 || height <= 0) {
            throw new IllegalArgumentException("Invalid encoded image dimensions");
        }
        if (frameCount <= 0) {
            throw new IllegalArgumentException("Invalid frame count");
        }
    }

    @Override
    public int getFrameCount() {
        return frameCount;
    }

    @Override
    public byte[] getEncodedData() {
        return encodedData;
    }

    @Override
    public String getEncodedFilePath() {
        return encodedFilePath;
    }

    @Override
    public int getWidth() {
        return width;
    }

    @Override
    public int getHeight() {
        return height;
    }

    @Override
    public boolean isValid() {
        return encodedData != null || encodedFilePath != null;
    }

    @Override
    public void release() {
        encodedData = null;
        encodedFilePath = null;
    }

    @Override
    public void draw(Surface surface, Rect destRect) {
        throw new UnsupportedOperationException(
                "Encoded-only images require the Flutter codec backend");
    }
}
