package com.taobao.power_image.loader;

import com.taobao.power_image.request.PowerImageRequestConfig;

/**
 * created by Muke on 2021/7/22
 */
public interface PowerImageLoaderProtocol {

    interface PowerImageRequestHandle {
        void cancel();
    }

    interface PowerImageResponse {
        void onResult(PowerImageResult result);

        default void onRequestHandle(PowerImageRequestHandle handle) {
        }
    }

    void handleRequest(PowerImageRequestConfig request, PowerImageResponse response);

}
