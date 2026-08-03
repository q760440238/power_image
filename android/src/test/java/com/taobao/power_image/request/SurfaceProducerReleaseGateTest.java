package com.taobao.power_image.request;

import static org.junit.Assert.assertEquals;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.junit.Test;

public class SurfaceProducerReleaseGateTest {
    @Test
    public void waitsForEveryPendingReleaseBeforeStartingNewSurfaceWork() {
        SurfaceProducerReleaseGate gate = new SurfaceProducerReleaseGate();
        SurfaceProducerReleaseGate.Release first = gate.beginRelease();
        SurfaceProducerReleaseGate.Release second = gate.beginRelease();
        List<Integer> events = new ArrayList<>();

        gate.runWhenIdle(() -> events.add(3));
        first.complete();
        assertEquals(0, events.size());

        second.complete();
        assertEquals(Arrays.asList(3), events);
    }

    @Test
    public void completionIsIdempotentAndIdleWorkRunsImmediately() {
        SurfaceProducerReleaseGate gate = new SurfaceProducerReleaseGate();
        SurfaceProducerReleaseGate.Release release = gate.beginRelease();
        List<Integer> events = new ArrayList<>();

        release.complete();
        release.complete();
        gate.runWhenIdle(() -> events.add(1));

        assertEquals(Arrays.asList(1), events);
    }
}
