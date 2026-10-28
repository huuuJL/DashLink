package com.playport.server

import com.shilapi.xcertplay.airplay.AirPlayInfoPlist
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class CarPlayAudioCapabilitiesTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun receiverOffersDuplexVoiceAndOutputOnlyMusic() {
        val config = ServerConfig(
            stateDir = folder.newFolder("state").toPath(),
            identityDir = folder.newFolder("identity").toPath(),
            bindAddress = "127.0.0.1",
        )
        CarPlayServer(config).use { server ->
            val formats = (AirPlayInfoPlist.build(server.airPlayConfig)["audioFormats"] as List<*>)
                .map { it as Map<*, *> }
            for (kind in listOf("default", "telephony", "speechRecognition")) {
                val voice = formats.single { it["type"] == 100 && it["audioType"] == kind }
                assertTrue("$kind must support input", (voice["audioInputFormats"] as Number).toLong() != 0L)
                assertTrue("$kind must support output", (voice["audioOutputFormats"] as Number).toLong() != 0L)
            }
            val music = formats.filter { it["audioType"] == "media" }
            assertTrue(music.isNotEmpty())
            music.forEach {
                assertFalse("Music must not request microphone capture", it.containsKey("audioInputFormats"))
                assertTrue((it["audioOutputFormats"] as Number).toLong() != 0L)
            }
        }
    }
}
