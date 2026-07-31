package com.taobao.power_image.loader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class MultiFrameRenderStateTest {
    @Test
    public void coalescesInvalidationsAndKeepsOnlyLatestPendingFrame() {
        MultiFrameRenderState state = new MultiFrameRenderState();

        assertTrue(state.markDirty());
        assertFalse(state.markDirty());
        assertTrue(state.tryStartRender());
        assertTrue(state.markDirty());
        assertFalse(state.markDirty());

        assertEquals(
                MultiFrameRenderState.Completion.RENDER_AGAIN,
                state.finishRender(2_000_000, true, false));
        assertTrue(state.tryStartRender());
        assertEquals(
                MultiFrameRenderState.Completion.NONE,
                state.finishRender(1_000_000, true, false));

        MultiFrameRenderState.Snapshot stats = state.snapshot();
        assertEquals(4, stats.invalidations);
        assertEquals(2, stats.coalescedFrames);
        assertEquals(2, stats.renderedFrames);
        assertEquals(1_500_000, stats.averageRenderNanos());
        assertEquals(2_000_000, stats.maxRenderNanos);
    }

    @Test
    public void releaseWaitsForInFlightRenderBeforeCleanup() {
        MultiFrameRenderState state = new MultiFrameRenderState();
        state.markDirty();
        assertTrue(state.tryStartRender());

        assertFalse(state.release());
        assertFalse(state.tryScheduleCleanup());
        assertEquals(
                MultiFrameRenderState.Completion.CLEANUP,
                state.finishRender(500_000, true, false));
        assertTrue(state.tryScheduleCleanup());
        assertFalse(state.tryScheduleCleanup());

        state.markCleanupFinished();
        assertTrue(state.isCleanupFinished());
    }

    @Test
    public void pauseDropsPendingFrameAndResumeRequestsFreshFrame() {
        MultiFrameRenderState state = new MultiFrameRenderState();
        state.markDirty();

        assertTrue(state.setActive(false));
        assertFalse(state.tryStartRender());
        assertFalse(state.markDirty());
        assertTrue(state.setActive(true));
        assertTrue(state.tryStartRender());
        assertEquals(
                MultiFrameRenderState.Completion.NONE,
                state.finishRender(100, true, false));
    }

    @Test
    public void rejectedExecutionRestoresDirtyFrame() {
        MultiFrameRenderState state = new MultiFrameRenderState();
        state.markDirty();
        assertTrue(state.tryStartRender());

        assertEquals(
                MultiFrameRenderState.Completion.RENDER_AGAIN,
                state.abortRender());
        assertTrue(state.tryStartRender());
    }

    @Test
    public void recordsSkippedAndFailedRenders() {
        MultiFrameRenderState state = new MultiFrameRenderState();
        state.markDirty();
        state.tryStartRender();
        state.finishRender(0, false, true);

        MultiFrameRenderState.Snapshot stats = state.snapshot();
        assertEquals(0, stats.renderedFrames);
        assertEquals(1, stats.skippedFrames);
        assertEquals(1, stats.failedFrames);
    }
}
