package com.taobao.power_image.request;

import android.os.SystemClock;

import com.taobao.power_image.PowerImageEngineContext;
import com.taobao.power_image.PowerImageDiagnostics;
import com.taobao.power_image.dispatcher.PowerImageDispatcher;
import com.taobao.power_image.loader.FlutterMultiFrameImage;
import com.taobao.power_image.loader.FlutterEncodedImage;
import com.taobao.power_image.loader.PowerImageLoader;
import com.taobao.power_image.loader.PowerImageLoaderProtocol;
import com.taobao.power_image.loader.PowerImageResult;

import java.util.HashMap;
import java.util.Map;

/**
 * created by Muke on 2021/7/21
 */
public abstract class PowerImageBaseRequest {
    protected static final String REQUEST_STATE_INITIALIZE_SUCCEED = "initializeSucceed";
    protected static final String REQUEST_STATE_INITIALIZE_FAILED = "initializeFailed";
    protected static final String REQUEST_STATE_LOAD_SUCCEED = "loadSucceed";
    protected static final String REQUEST_STATE_LOAD_FAILED = "loadFailed";
    protected static final String REQUEST_STATE_RELEASE_SUCCEED = "releaseSucceed";
    protected static final String REQUEST_STATE_RELEASE_FAILED = "releaseFailed";

    public static final String RENDER_TYPE_EXTERNAL = "external";
    public static final String RENDER_TYPE_TEXTURE = "texture";

    private final PowerImageEngineContext engineContext;
    private final Object loadHandleLock = new Object();
    private final long createdAtNanos = SystemClock.elapsedRealtimeNanos();
    private PowerImageRequestConfig imageRequestConfig;
    private PowerImageLoaderProtocol.PowerImageRequestHandle loadHandle;
    private boolean loadHandleReleased;
    private volatile boolean requestReleased;
    String requestId;
    protected String imageTaskState;
    protected PowerImageResult realResult;

    public PowerImageBaseRequest(PowerImageEngineContext context, Map<String, Object> arguments) {
        engineContext = context;
        Object requestIdValue = arguments.get("uniqueKey");
        requestId = requestIdValue instanceof String
                ? (String) requestIdValue : null;
        imageRequestConfig = PowerImageRequestConfig.requestConfigWithArguments(arguments);
        PowerImageDiagnostics.debug(
                "request_created",
                requestId,
                "type=" + imageRequestConfig.imageType
                        + " render=" + imageRequestConfig.renderingType
                        + " target=" + imageRequestConfig.width + "x"
                        + imageRequestConfig.height);
    }

    public boolean configTask() {
        boolean inited = imageRequestConfig != null;
        imageTaskState = inited ? REQUEST_STATE_INITIALIZE_SUCCEED
                : REQUEST_STATE_INITIALIZE_FAILED;
        PowerImageDiagnostics.debug(
                "request_configured", requestId, "success=" + inited);
        return inited;
    }

    public boolean startLoading() {
        if (!REQUEST_STATE_INITIALIZE_SUCCEED.equals(imageTaskState)
                && !REQUEST_STATE_LOAD_FAILED.equals(imageTaskState)) {
            // 只有初始化好 或者 加载失败的情况可以重新加载
            return false;
        }
        if (imageRequestConfig == null) {
            return false;
        }
        PowerImageDiagnostics.debug("load_started", requestId, null);
        performLoadImage();
        return true;
    }

    private void performLoadImage() {
        try {
            PowerImageLoader.getInstance().handleRequest(
                    imageRequestConfig,
                    new PowerImageLoaderProtocol.PowerImageResponse() {
                        @Override
                        public void onResult(PowerImageResult result) {
                            PowerImageBaseRequest.this.onLoadResult(result);
                        }

                        @Override
                        public void onRequestHandle(
                                PowerImageLoaderProtocol.PowerImageRequestHandle handle) {
                            PowerImageBaseRequest.this.setLoadHandle(handle);
                        }
                    }
            );
        } catch (RuntimeException error) {
            PowerImageDiagnostics.error(
                    "load_dispatch_failed", requestId, null, error);
            onLoadFailed(error.getMessage());
        }
    }

    private void setLoadHandle(PowerImageLoaderProtocol.PowerImageRequestHandle handle) {
        boolean cancelImmediately;
        synchronized (loadHandleLock) {
            cancelImmediately = loadHandleReleased;
            if (!cancelImmediately) {
                loadHandle = handle;
            }
        }
        if (cancelImmediately && handle != null) {
            handle.cancel();
        }
        PowerImageDiagnostics.verbose(
                "load_handle",
                requestId,
                "cancelImmediately=" + cancelImmediately + " present=" + (handle != null));
    }

    protected final void releaseLoadHandle() {
        PowerImageLoaderProtocol.PowerImageRequestHandle handle;
        synchronized (loadHandleLock) {
            loadHandleReleased = true;
            handle = loadHandle;
            loadHandle = null;
        }
        if (handle != null) {
            handle.cancel();
        }
        PowerImageDiagnostics.debug("load_handle_released", requestId, null);
    }

    void onLoadResult(PowerImageResult result) {
        this.realResult = result;
    }

    public void onLoadSuccess() {
        PowerImageDispatcher.getInstance().runOnMainThread(new Runnable() {
            @Override
            public void run() {
                if (requestReleased) {
                    return;
                }
                PowerImageBaseRequest.this.imageTaskState = REQUEST_STATE_LOAD_SUCCEED;
                PowerImageDiagnostics.debug(
                        "load_succeeded",
                        requestId,
                        "elapsedMs=" + PowerImageDiagnostics.elapsedMillis(createdAtNanos));
                engineContext.sendImageStateEvent(PowerImageBaseRequest.this.encode(), true);
            }
        });
    }

    public void onLoadFailed(final String errMsg) {
        PowerImageDispatcher.getInstance().runOnMainThread(new Runnable() {
            @Override
            public void run() {
                if (requestReleased) {
                    return;
                }
                PowerImageBaseRequest.this.imageTaskState = REQUEST_STATE_LOAD_FAILED;
                Map<String, Object> event = PowerImageBaseRequest.this.encode();
                event.put("errMsg", errMsg != null ? errMsg : "failed!");
                PowerImageDiagnostics.error(
                        "load_failed",
                        requestId,
                        "elapsedMs=" + PowerImageDiagnostics.elapsedMillis(createdAtNanos)
                                + " reasonToken="
                                + PowerImageDiagnostics.valueToken(errMsg)
                                + " reasonLength="
                                + (errMsg != null ? errMsg.length() : 0),
                        null);
                engineContext.sendImageStateEvent(event, false);
            }
        });
    }

    public boolean stopTask() {
        return false;
    }

    protected final synchronized boolean markRequestReleased() {
        if (requestReleased) {
            return false;
        }
        requestReleased = true;
        PowerImageDiagnostics.debug(
                "request_releasing",
                requestId,
                "elapsedMs=" + PowerImageDiagnostics.elapsedMillis(createdAtNanos));
        return true;
    }

    protected final boolean isRequestReleased() {
        return requestReleased;
    }

    protected final PowerImageRequestConfig getImageRequestConfig() {
        return imageRequestConfig;
    }

    protected final boolean isEngineAttached() {
        return engineContext.isAttached();
    }

    public void setAnimationActive(boolean active) {
    }

    public Map<String, Object> encode() {
        Map<String, Object> encodedTask = new HashMap<>();
        encodedTask.put("uniqueKey", requestId);
        encodedTask.put("state", imageTaskState);
        if (realResult != null
                && realResult.success
                && (realResult.image instanceof FlutterMultiFrameImage
                        || realResult.image instanceof FlutterEncodedImage)) {
            encodedTask.put("_multiFrame", true);
        }
        return encodedTask;
    }

}
