package com.playport.server

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioPlaybackStatsTest {
    @Test fun playbackMetricsDecodeWithoutMediaContent() {
        val message = Json.decodeFromString<ClientMessage>(
            """{"type":"audioStats","audioStats":{"scheduled":234,"underruns":0,"dropped":0,"maxQueuedMs":984,"maxArrivalGapMs":417}}""",
        )
        assertEquals("audioStats", message.type)
        assertTrue(message.audioStats!!.valid())
        assertEquals(417, message.audioStats!!.maxArrivalGapMs)
    }

    @Test fun invalidMetricValuesAreRejected() {
        assertFalse(AudioPlaybackStats(dropped = -1).valid())
        assertFalse(AudioPlaybackStats(maxQueuedMs = Int.MAX_VALUE).valid())
        assertTrue(AudioPlaybackStats().valid())
    }
}
