package com.taobao.power_image_example.power_image_loader;

import android.content.Context;
import android.util.Base64;

import com.bumptech.glide.Glide;
import com.bumptech.glide.RequestManager;
import com.taobao.power_image.loader.PowerImageLoaderProtocol;
import com.taobao.power_image.request.PowerImageRequestConfig;

/**
 * Provides a deterministic in-memory animated WebP for the Macrobenchmark.
 */
public class PowerImageBenchmarkLoader implements PowerImageLoaderProtocol {
    public static final String IMAGE_TYPE = "benchmarkAnimatedWebp";

    private static final byte[] ANIMATED_WEBP = Base64.decode(
            "UklGRrICAABXRUJQVlA4WAoAAAASAAAAPwAAPwAAQU5JTQYAAAAAAAAAAABBTk1G"
                    + "UAAAAAAAAAAAAD8AAD8AAFAAAAJWUDhMOAAAAC8/wA8AD3AUqFOsH4p4/gMPZt"
                    + "q28Vf+TMugDLY3ov8TAQAAAAAAAAAAAAAAAAAAAAAA0OU/tzwDQU5NRkoAAAAC"
                    + "AAAJAAAVAAAcAABQAAAAVlA4TDEAAAAvFQAHEBcgEEhxOOMsEEiC2F9wCYFAEu"
                    + "LQg81/QPUHMgEL937R9JFHWHdE/yNWx00AAEFOTUZIAAAABQAACQAAFgAAHAAA"
                    + "UAAAAFZQOEwvAAAALxYABxAXIBBIcTjjLBBIgthfcAmBQBLi0IPNf0D1BzIBi"
                    + "+VZHkoK647of6QwbwoAQU5NRkoAAAAJAAAJAAAVAAAcAABQAAAAVlA4TDEAAAA"
                    + "vFQAHEBcgEEhxOOMsEEiC2F9wCYFAEuLQg81/QPUHMgEL937R9JFHWHdE/yNW"
                    + "x00AAEFOTUZIAAAADAAACQAAFgAAHAAAUAAAAFZQOEwvAAAALxYABxAXIBBIcT"
                    + "jjLBBIgthfcAmBQBLi0IPNf0D1BzIBi+VZHkoK647of6QwbwoAQU5NRkoAAAAQ"
                    + "AAAJAAAVAAAcAABQAAAAVlA4TDEAAAAvFQAHEBcgEEhxOOMsEEiC2F9wCYFAEu"
                    + "LQg81/QPUHMgEL937R9JFHWHdE/yNWx00AAEFOTUZIAAAAEwAACQAAFgAAHAAA"
                    + "UAAAAFZQOEwvAAAALxYABxAXIBBIcTjjLBBIgthfcAmBQBLi0IPNf0D1BzIBi"
                    + "+VZHkoK647of6QwbwoAQU5NRkgAAAAXAAAJAAARAAAcAABQAAAAVlA4TDAAAAA"
                    + "vEQAHEBcgEEhxOOMsEEiC2F9wCYFAEuLQg81/QPUHIgESMt1p/vF/MEf0Pxrm"
                    + "FQE=",
            Base64.DEFAULT);

    private final Context context;

    public PowerImageBenchmarkLoader(Context context) {
        this.context = context;
    }

    @Override
    public void handleRequest(
            PowerImageRequestConfig request, PowerImageResponse response) {
        RequestManager requestManager = Glide.with(context);
        PowerImageGlideResult.submit(
                requestManager,
                requestManager.asDrawable().load(ANIMATED_WEBP.clone()),
                request,
                response);
    }
}
