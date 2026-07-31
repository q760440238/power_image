package com.taobao.power_image.request;

import android.graphics.Rect;
import android.view.Surface;

import com.taobao.power_image.PowerImageEngineContext;
import com.taobao.power_image.PowerImageDiagnostics;
import com.taobao.power_image.dispatcher.PowerImageDispatcher;
import com.taobao.power_image.loader.FlutterEncodedImage;
import com.taobao.power_image.loader.FlutterImage;
import com.taobao.power_image.loader.PowerImageResult;

import java.lang.ref.WeakReference;
import java.lang.reflect.Method;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import io.flutter.view.TextureRegistry;

/**
 * created by Muke on 2021/7/27
 */
public class PowerImageTextureRequest extends PowerImageBaseRequest
        implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "PowerImageTextureRequest";

    public static final int MAX_RESIZE_HEIGHT = 1920;
    public static final int MAX_RESIZE_WIDTH = 1920;
    private static final int ESTIMATED_SURFACE_BUFFER_COUNT = 3;
    private static final AtomicInteger ACTIVE_SURFACE_PRODUCERS = new AtomicInteger();
    private static final AtomicLong ESTIMATED_SURFACE_BYTES = new AtomicLong();

    private final WeakReference<TextureRegistry> textureRegistryWrf;
    private final AtomicBoolean loadSuccessSent = new AtomicBoolean(false);
    private final AtomicBoolean surfaceProducerTracked = new AtomicBoolean(false);
    private final int requestedWidth;
    private final int requestedHeight;
    private volatile boolean stopped;
    private volatile boolean surfaceAvailable;
    private volatile boolean animationActive = true;
    private volatile TextureRegistry.SurfaceProducer textureEntry;
    private volatile byte[] flutterCodecData;
    private volatile String flutterCodecFilePath;
    private volatile boolean flutterCodecBackend;
    private volatile int imageTextureWidth;
    private volatile int imageTextureHeight;
    private int bitmapWidth;
    private int bitmapHeight;
    private long estimatedProducerBytes;

    public PowerImageTextureRequest(PowerImageEngineContext context, Map<String, Object> arguments, TextureRegistry textureRegistry) {
        super(context, arguments);
        textureRegistryWrf = new WeakReference<>(textureRegistry);
        PowerImageRequestConfig config = getImageRequestConfig();
        requestedWidth = config != null ? config.width : 0;
        requestedHeight = config != null ? config.height : 0;
        stopped = false;
    }

    @Override
    void onLoadResult(final PowerImageResult result) {
        if (stopped || isRequestReleased()) {
            if (result != null && result.image != null) {
                result.image.release();
            }
            return;
        }
        super.onLoadResult(result);
        if (result == null) {
            onLoadFailed(TAG + ":onLoadResult(PowerImageResult result) result is null");
            return;
        }
        if (!result.success) {
            onLoadFailed(result.errMsg);
            return;
        }
        if (stopped) {
            if (result.image != null) {
                result.image.release();
            }
            return;
        }
        if (result.image == null || !result.image.isValid()) {
            onLoadFailed(TAG + ":onLoadResult FlutterImage/bitmap is null or bitmap has recycled");
            return;
        }
        result.image.setDiagnosticRequestId(requestId);
        realResult = result;
        bitmapWidth = result.image.getWidth();
        bitmapHeight = result.image.getHeight();
        checkImageTextureSize(result.image);

        if (useFlutterCodec(result.image)) {
            return;
        }

        PowerImageDispatcher.getInstance().runOnMainThread(new Runnable() {
            @Override
            public void run() {
                TextureRegistry textureRegistry = textureRegistryWrf.get();
                if (textureEntry == null && textureRegistry != null) {
                    // 纹理创建，需要运行在有Looper的线程
                    textureEntry = createSurfaceProducer(textureRegistry);
                    surfaceAvailable = true;
                    textureEntry.setCallback(PowerImageTextureRequest.this);
                    trackSurfaceProducer(result.image.getFrameCount());
                }
                if (textureEntry == null) {
                    onLoadFailed(TAG + ":onLoadResult SurfaceTextureEntry create failed");
                    return;
                }
                if (stopped) {
                    return;
                }
                // 切到子线程进行图片加载和纹理绘制
                performDraw(result.image);
            }
        });

    }

    @Override
    public boolean stopTask() {
        return stopTask(false);
    }

    @Override
    public boolean stopTaskForEngineDetach() {
        return stopTask(true);
    }

    private boolean stopTask(final boolean engineDetaching) {
        stopped = true;
        surfaceAvailable = false;
        flutterCodecData = null;
        flutterCodecFilePath = null;
        if (!markRequestReleased()) {
            return true;
        }
        imageTaskState = REQUEST_STATE_RELEASE_SUCCEED;
        textureRegistryWrf.clear();

        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                final TextureRegistry.SurfaceProducer entry = textureEntry;
                if (entry != null) {
                    synchronized (entry) {
                        try {
                            if (textureEntry == entry) {
                                textureEntry = null;
                                entry.setCallback(null);
                            }
                        } catch (Exception error) {
                            PowerImageDiagnostics.error(
                                    "surface_callback_clear_failed",
                                    requestId,
                                    null,
                                    error);
                        }
                    }
                }
                final Runnable finishRelease = new Runnable() {
                    @Override
                    public void run() {
                        PowerImageDispatcher.getInstance().runOnMainThread(new Runnable() {
                            @Override
                            public void run() {
                                if (!engineDetaching) {
                                    releaseSurfaceProducer(entry);
                                }
                                releaseLoadHandle();
                                PowerImageDiagnostics.debug(
                                        "texture_request_released", requestId, null);
                            }
                        });
                    }
                };
                if (engineDetaching) {
                    // onSurfaceCleanup waits for an in-flight multi-frame draw's
                    // surface lock and prevents future draws from using entry.
                    if (realResult != null && realResult.image != null) {
                        realResult.image.onSurfaceCleanup();
                    }
                    releaseSurfaceProducer(entry);
                }
                if (realResult != null && realResult.image != null) {
                    realResult.image.release(finishRelease);
                } else {
                    finishRelease.run();
                }
            }
        };

        PowerImageDispatcher.getInstance().runOnMainThread(runnable);
        return true;
    }

    private void releaseSurfaceProducer(TextureRegistry.SurfaceProducer entry) {
        if (entry == null) {
            return;
        }
        try {
            entry.release();
        } catch (Exception error) {
            PowerImageDiagnostics.error(
                    "surface_producer_release_failed", requestId, null, error);
        } finally {
            untrackSurfaceProducer();
        }
    }

    @Override
    public Map<String, Object> encode() {
        Map<String, Object> encodedRequest = super.encode();
        encodedRequest.put("width", bitmapWidth);
        encodedRequest.put("height", bitmapHeight);
        TextureRegistry.SurfaceProducer entry = textureEntry;
        if (entry != null) {
            encodedRequest.put("textureId", entry.id());
        }
        byte[] encodedData = flutterCodecData;
        String encodedFilePath = flutterCodecFilePath;
        if (flutterCodecBackend && (encodedData != null || encodedFilePath != null)) {
            encodedRequest.put("renderingBackend", "flutterCodec");
            if (encodedData != null) {
                encodedRequest.put("encodedData", encodedData);
            }
            if (encodedFilePath != null) {
                encodedRequest.put("encodedFilePath", encodedFilePath);
            }
            encodedRequest.put("targetWidth", imageTextureWidth);
            encodedRequest.put("targetHeight", imageTextureHeight);
        }
        return encodedRequest;
    }

    private boolean useFlutterCodec(final FlutterImage image) {
        if (!(image instanceof FlutterEncodedImage) || image.getFrameCount() <= 1) {
            return false;
        }

        final byte[] encodedData;
        final String encodedFilePath;
        try {
            encodedData = image.getEncodedData();
            encodedFilePath = image.getEncodedFilePath();
        } catch (RuntimeException error) {
            PowerImageDiagnostics.error(
                    "flutter_codec_data_failed", requestId, null, error);
            return false;
        }
        boolean hasData = encodedData != null && encodedData.length > 0;
        boolean hasFile = encodedFilePath != null && !encodedFilePath.isEmpty();
        if (!hasData && !hasFile) {
            onLoadFailed(TAG + ": encoded image has no data");
            return true;
        }

        flutterCodecData = hasData ? encodedData : null;
        flutterCodecFilePath = hasFile ? encodedFilePath : null;
        flutterCodecBackend = true;
        loadSuccessSent.set(true);
        PowerImageDiagnostics.debug(
                "flutter_codec_backend",
                requestId,
                "bytes=" + (hasData ? encodedData.length : 0)
                        + " file=" + hasFile
                        + " source=" + bitmapWidth + "x" + bitmapHeight
                        + " target=" + imageTextureWidth + "x" + imageTextureHeight);
        image.release(new Runnable() {
            @Override
            public void run() {
                PowerImageDispatcher.getInstance().runOnMainThread(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            releaseLoadHandle();
                            if (!stopped && !isRequestReleased()) {
                                onLoadSuccess();
                            }
                        } finally {
                            flutterCodecData = null;
                            flutterCodecFilePath = null;
                            realResult = null;
                        }
                    }
                });
            }
        });
        return true;
    }

    @Override
    public void onSurfaceCreated() {
        onSurfaceAvailable();
    }

    // No @Override: this callback was added after Flutter 3.24.
    public void onSurfaceAvailable() {
        if (stopped) {
            return;
        }
        surfaceAvailable = true;
        PowerImageDiagnostics.debug("surface_available", requestId, null);
        PowerImageResult result = realResult;
        if (!stopped && result != null && result.image != null && result.image.isValid()) {
            result.image.setAnimationActive(animationActive);
            performDraw(result.image);
        }
    }

    @Override
    public void onSurfaceDestroyed() {
        onSurfaceCleanup();
    }

    // No @Override: this callback was added after Flutter 3.24.
    public void onSurfaceCleanup() {
        surfaceAvailable = false;
        PowerImageDiagnostics.debug("surface_cleanup", requestId, null);
        PowerImageResult result = realResult;
        if (result != null && result.image != null) {
            result.image.onSurfaceCleanup();
        }
    }

    @Override
    public void setAnimationActive(boolean active) {
        animationActive = active;
        PowerImageDiagnostics.verbose(
                "animation_visibility", requestId, "active=" + active);
        PowerImageResult result = realResult;
        if (result != null && result.image != null) {
            result.image.setAnimationActive(active && surfaceAvailable);
        }
    }

    // 独立线程中完成纹理绘制工作
    void performDraw(final FlutterImage image) {
        PowerImageDispatcher.getInstance().runOnWorkThread(new Runnable() {
            @Override
            public void run() {
                final TextureRegistry.SurfaceProducer entry = textureEntry;
                if (entry == null || stopped || !surfaceAvailable || image == null) {
                    return;
                }
                synchronized (entry) {
                    if (textureEntry != entry || stopped || !surfaceAvailable) {
                        return;
                    }

                    try {
                        // 显示纹理
                        checkImageTextureSize(image);
                        if (imageTextureWidth <= 0 || imageTextureHeight <= 0) {
                            throw new IllegalArgumentException(
                                    "Drawable has invalid intrinsic dimensions");
                        }
                        entry.setSize(imageTextureWidth, imageTextureHeight);
                        image.setAnimationActive(animationActive);
                        Surface surface = entry.getSurface();
                        if (surface != null && surface.isValid()) {
                            Rect destRect = new Rect(0, 0, imageTextureWidth, imageTextureHeight);
                            image.draw(new FlutterImage.SurfaceProvider() {
                                @Override
                                public Surface getSurface() {
                                    if (textureEntry != entry || stopped || !surfaceAvailable) {
                                        return null;
                                    }
                                    return entry.getSurface();
                                }
                            }, destRect);
                            if (loadSuccessSent.compareAndSet(false, true)) {
                                onLoadSuccess();
                            }
                        }
                    } catch (Exception e) {
                        PowerImageDiagnostics.error(
                                "texture_draw_failed", requestId, null, e);
                        if (!loadSuccessSent.get()) {
                            onLoadFailed(TAG + ":performDraw drawBitmap " + e.getMessage());
                        }
                    }
                }
            }
        });
    }

    private static TextureRegistry.SurfaceProducer createSurfaceProducer(
            TextureRegistry textureRegistry) {
        try {
            Class<?> lifecycleClass =
                    Class.forName("io.flutter.view.TextureRegistry$SurfaceLifecycle");
            Object lifecycle = lifecycleClass.getField("resetInBackground").get(null);
            Method method = TextureRegistry.class.getMethod(
                    "createSurfaceProducer", lifecycleClass);
            return (TextureRegistry.SurfaceProducer) method.invoke(textureRegistry, lifecycle);
        } catch (ReflectiveOperationException | LinkageError | SecurityException ignored) {
            // Flutter 3.24 exposes SurfaceProducer through the no-argument API.
            return textureRegistry.createSurfaceProducer();
        }
    }

    //  确保图片的大小不超过系统的纹理大小的限制
    void checkImageTextureSize(FlutterImage imageBitmap) {
        if (imageBitmap == null) {
            return;
        }
        int originWidth = imageBitmap.getWidth();
        int originHeight = imageBitmap.getHeight();


        int[] size = fitTextureSize(
                originWidth,
                originHeight,
                requestedWidth,
                requestedHeight);
        imageTextureWidth = size[0];
        imageTextureHeight = size[1];
    }

    static int[] fitTextureSize(
            int originWidth,
            int originHeight,
            int requestedWidth,
            int requestedHeight) {
        if (originWidth <= 0 || originHeight <= 0) {
            return new int[]{0, 0};
        }

        double scale = Math.min(
                1d,
                Math.min(
                        MAX_RESIZE_WIDTH / (double) originWidth,
                        MAX_RESIZE_HEIGHT / (double) originHeight));
        if (requestedWidth > 0) {
            scale = Math.min(scale, requestedWidth / (double) originWidth);
        }
        if (requestedHeight > 0) {
            scale = Math.min(scale, requestedHeight / (double) originHeight);
        }

        return new int[]{
                Math.max(1, (int) Math.round(originWidth * scale)),
                Math.max(1, (int) Math.round(originHeight * scale))};
    }

    static long estimateSurfaceBufferBytes(int width, int height) {
        if (width <= 0 || height <= 0) {
            return 0L;
        }
        return (long) width * height * 4L * ESTIMATED_SURFACE_BUFFER_COUNT;
    }

    private void trackSurfaceProducer(int frameCount) {
        if (!surfaceProducerTracked.compareAndSet(false, true)) {
            return;
        }
        estimatedProducerBytes = estimateSurfaceBufferBytes(
                imageTextureWidth, imageTextureHeight);
        int active = ACTIVE_SURFACE_PRODUCERS.incrementAndGet();
        long estimatedTotal = ESTIMATED_SURFACE_BYTES.addAndGet(estimatedProducerBytes);
        if (PowerImageDiagnostics.isDebugEnabled()) {
            PowerImageDiagnostics.debug(
                    "surface_producer_created",
                    requestId,
                    "source=" + bitmapWidth + "x" + bitmapHeight
                            + " target=" + imageTextureWidth + "x" + imageTextureHeight
                            + " frames=" + frameCount
                            + " active=" + active
                            + " estimatedTripleBufferBytes=" + estimatedProducerBytes
                            + " estimatedTotalBufferBytes=" + estimatedTotal
                            + " " + PowerImageDiagnostics.memorySummary());
        }
    }

    private void untrackSurfaceProducer() {
        if (!surfaceProducerTracked.compareAndSet(true, false)) {
            return;
        }
        int active = ACTIVE_SURFACE_PRODUCERS.decrementAndGet();
        long estimatedTotal = ESTIMATED_SURFACE_BYTES.addAndGet(-estimatedProducerBytes);
        if (PowerImageDiagnostics.isDebugEnabled()) {
            PowerImageDiagnostics.debug(
                    "surface_producer_released",
                    requestId,
                    "active=" + active
                            + " estimatedTotalBufferBytes=" + estimatedTotal
                            + " " + PowerImageDiagnostics.memorySummary());
        }
        estimatedProducerBytes = 0L;
    }
}
