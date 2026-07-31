package com.taobao.power_image.request;

import android.graphics.Rect;
import android.view.Surface;

import com.taobao.power_image.PowerImageEngineContext;
import com.taobao.power_image.dispatcher.PowerImageDispatcher;
import com.taobao.power_image.loader.FlutterImage;
import com.taobao.power_image.loader.PowerImageResult;

import java.lang.ref.WeakReference;
import java.lang.reflect.Method;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.view.TextureRegistry;

/**
 * created by Muke on 2021/7/27
 */
public class PowerImageTextureRequest extends PowerImageBaseRequest
        implements TextureRegistry.SurfaceProducer.Callback {
    private static final String TAG = "PowerImageTextureRequest";

    public static final int MAX_RESIZE_HEIGHT = 1920;
    public static final int MAX_RESIZE_WIDTH = 1920;

    private final WeakReference<TextureRegistry> textureRegistryWrf;
    private final AtomicBoolean loadSuccessSent = new AtomicBoolean(false);
    private volatile boolean stopped;
    private volatile boolean surfaceAvailable;
    private volatile boolean animationActive = true;
    private volatile TextureRegistry.SurfaceProducer textureEntry;
    private volatile int imageTextureWidth;
    private volatile int imageTextureHeight;
    private int bitmapWidth;
    private int bitmapHeight;

    public PowerImageTextureRequest(PowerImageEngineContext context, Map<String, Object> arguments, TextureRegistry textureRegistry) {
        super(context, arguments);
        textureRegistryWrf = new WeakReference<>(textureRegistry);
        stopped = false;
    }

    @Override
    void onLoadResult(final PowerImageResult result) {
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
            onLoadFailed(TAG + ":onLoadResult isStopped");
            return;
        }
        if (result.image == null || !result.image.isValid()) {
            onLoadFailed(TAG + ":onLoadResult FlutterImage/bitmap is null or bitmap has recycled");
            return;
        }
        realResult = result;
        bitmapWidth = result.image.getWidth();
        bitmapHeight = result.image.getHeight();

        PowerImageDispatcher.getInstance().runOnMainThread(new Runnable() {
            @Override
            public void run() {
                TextureRegistry textureRegistry = textureRegistryWrf.get();
                if (textureEntry == null && textureRegistry != null) {
                    // 纹理创建，需要运行在有Looper的线程
                    textureEntry = createSurfaceProducer(textureRegistry);
                    surfaceAvailable = true;
                    textureEntry.setCallback(PowerImageTextureRequest.this);
                }
                if (textureEntry == null) {
                    onLoadFailed(TAG + ":onLoadResult SurfaceTextureEntry create failed");
                    return;
                }
                if (stopped) {
                    onLoadFailed(TAG + ":onLoadResult isStopped 2");
                    return;
                }
                // 切到子线程进行图片加载和纹理绘制
                performDraw(result.image);
            }
        });

    }

    @Override
    public boolean stopTask() {
        stopped = true;
        surfaceAvailable = false;
        imageTaskState = REQUEST_STATE_RELEASE_SUCCEED;
        textureRegistryWrf.clear();

        Runnable runnable = new Runnable() {
            @Override
            public void run() {
                TextureRegistry.SurfaceProducer entry = textureEntry;
                if (entry != null) {
                    synchronized (entry) {
                        try {
                            if (textureEntry == entry) {
                                textureEntry = null;
                                entry.setCallback(null);
                                entry.release();
                            }
                        } catch (Exception e) {
                        }
                    }
                }
                if (realResult != null && realResult.image != null) {
                    realResult.image.release();
                }
                releaseLoadHandle();
            }
        };

        PowerImageDispatcher.getInstance().runOnMainThread(runnable);
        return true;
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
        return encodedRequest;
    }

    @Override
    public void onSurfaceCreated() {
        onSurfaceAvailable();
    }

    // No @Override: this callback was added after Flutter 3.24.
    public void onSurfaceAvailable() {
        surfaceAvailable = true;
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
        PowerImageResult result = realResult;
        if (result != null && result.image != null) {
            result.image.onSurfaceCleanup();
        }
    }

    @Override
    public void setAnimationActive(boolean active) {
        animationActive = active;
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

                    // 显示纹理
                    checkImageTextureSize(image);
                    entry.setSize(imageTextureWidth, imageTextureHeight);
                    image.setAnimationActive(animationActive);
                    Surface surface = entry.getSurface();
                    if (surface != null && surface.isValid()) {
                        try {
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
                        } catch (Exception e) {
                            e.printStackTrace();
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


        double widthRatio = originWidth / (double) MAX_RESIZE_WIDTH;
        double heightRatio = originHeight / (double) MAX_RESIZE_HEIGHT;

        if (widthRatio <= 1 && heightRatio <= 1) {
            imageTextureWidth = originWidth;
            imageTextureHeight = originHeight;
            return;
        }

        double ratio = Math.max(widthRatio, heightRatio);
        imageTextureWidth = (int) (originWidth / ratio);
        imageTextureHeight = (int) (originHeight / ratio);
    }
}
