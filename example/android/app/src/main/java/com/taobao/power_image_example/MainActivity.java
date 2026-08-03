package com.taobao.power_image_example;

import android.content.Intent;
import android.os.Bundle;
import android.os.Build;
import android.os.Trace;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.taobao.power_image.loader.PowerImageLoader;
import com.taobao.power_image_example.power_image_loader.PowerImageFileLoader;
import com.taobao.power_image_example.power_image_loader.PowerImageFlutterAssetLoader;
import com.taobao.power_image_example.power_image_loader.PowerImageNativeAssetLoader;
import com.taobao.power_image_example.power_image_loader.PowerImageNetworkLoader;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String BENCHMARK_CHANNEL =
            "com.taobao.power_image_example/first_frame_benchmark";
    private static final String BENCHMARK_ROUTE_EXTRA =
            "power_image_benchmark_route";
    private static final String BENCHMARK_COMMAND_EXTRA =
            "power_image_benchmark_command";
    private static final String FIRST_FRAME_TRACE =
            "PowerImageBenchmark#firstFrameDisplayed";
    private static final int FIRST_FRAME_TRACE_COOKIE = 1;
    private String activeBenchmarkTrace;
    private MethodChannel benchmarkChannel;

    @Nullable
    @Override
    public String getInitialRoute() {
        String benchmarkRoute = getIntent().getStringExtra(BENCHMARK_ROUTE_EXTRA);
        return benchmarkRoute != null ? benchmarkRoute : super.getInitialRoute();
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        PowerImageLoader.getInstance().registerImageLoader(
                new PowerImageNetworkLoader(this.getApplicationContext()), "network");
        PowerImageLoader.getInstance().registerImageLoader(
                new PowerImageNativeAssetLoader(this.getApplicationContext()), "nativeAsset");
        PowerImageLoader.getInstance().registerImageLoader(
                new PowerImageFlutterAssetLoader(this.getApplicationContext()), "asset");
        PowerImageLoader.getInstance().registerImageLoader(
                new PowerImageFileLoader(this.getApplicationContext()), "file");
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        benchmarkChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                BENCHMARK_CHANNEL);
        benchmarkChannel.setMethodCallHandler((call, result) -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        if ("begin".equals(call.method)) {
                            String requestedTrace = call.arguments instanceof String
                                    ? (String) call.arguments : FIRST_FRAME_TRACE;
                            activeBenchmarkTrace = requestedTrace;
                            Trace.beginAsyncSection(
                                    requestedTrace,
                                    FIRST_FRAME_TRACE_COOKIE);
                        } else if ("end".equals(call.method)) {
                            if (activeBenchmarkTrace != null) {
                                Trace.endAsyncSection(
                                        activeBenchmarkTrace,
                                        FIRST_FRAME_TRACE_COOKIE);
                                activeBenchmarkTrace = null;
                            }
                        } else {
                            result.notImplemented();
                            return;
                        }
                    }
                    result.success(null);
                });
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        String command = intent.getStringExtra(BENCHMARK_COMMAND_EXTRA);
        if (command != null && benchmarkChannel != null) {
            benchmarkChannel.invokeMethod("command", command);
        }
    }
}
