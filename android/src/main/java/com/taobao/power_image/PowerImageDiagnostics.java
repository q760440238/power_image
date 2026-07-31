package com.taobao.power_image;

import android.os.Debug;
import android.os.SystemClock;
import android.util.Log;

/** Structured, opt-in diagnostics for request and animated-frame performance. */
public final class PowerImageDiagnostics {
    public static final String TAG = "PowerImage";

    private static volatile boolean enabled;

    private PowerImageDiagnostics() {
    }

    /** Enables verbose diagnostics at runtime. Disabled by default. */
    public static void setEnabled(boolean value) {
        if (enabled == value) {
            return;
        }
        enabled = value;
        Log.i(TAG, "event=diagnostics enabled=" + value);
    }

    public static boolean isDebugEnabled() {
        return enabled || Log.isLoggable(TAG, Log.DEBUG);
    }

    public static boolean isVerboseEnabled() {
        return enabled || Log.isLoggable(TAG, Log.VERBOSE);
    }

    public static void debug(String event, String requestId, String details) {
        if (!isDebugEnabled()) {
            return;
        }
        Log.d(TAG, format(event, requestId, details));
    }

    public static void verbose(String event, String requestId, String details) {
        if (!isVerboseEnabled()) {
            return;
        }
        Log.v(TAG, format(event, requestId, details));
    }

    public static void error(
            String event, String requestId, String details, Throwable throwable) {
        String message = format(event, requestId, details);
        if (throwable == null) {
            Log.e(TAG, message);
        } else {
            Log.e(TAG, message, throwable);
        }
    }

    /** Avoids putting URLs and file paths from the request key into logcat. */
    public static String requestToken(String requestId) {
        return valueToken(requestId);
    }

    /** Returns a correlation token without exposing the original text. */
    public static String valueToken(String value) {
        return value == null ? "none" : Integer.toHexString(value.hashCode());
    }

    public static long elapsedMillis(long startedAtNanos) {
        return (SystemClock.elapsedRealtimeNanos() - startedAtNanos) / 1_000_000L;
    }

    /** Lightweight process memory counters suitable for lifecycle logs. */
    public static String memorySummary() {
        Runtime runtime = Runtime.getRuntime();
        long javaUsedBytes = runtime.totalMemory() - runtime.freeMemory();
        return "javaUsedBytes=" + Math.max(0L, javaUsedBytes)
                + " javaCommittedBytes=" + runtime.totalMemory()
                + " nativeHeapBytes=" + Debug.getNativeHeapAllocatedSize();
    }

    private static String format(String event, String requestId, String details) {
        StringBuilder message = new StringBuilder(96)
                .append("event=").append(event)
                .append(" request=").append(requestToken(requestId))
                .append(" thread=").append(Thread.currentThread().getName());
        if (details != null && !details.isEmpty()) {
            message.append(' ').append(details.replace('\n', ' '));
        }
        return message.toString();
    }
}
