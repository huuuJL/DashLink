package com.playport.server

import com.shilapi.xcertplay.airplay.AirPlayInfoPlist
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class CarPlayBluetoothIdentityTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun desktopAnnouncementMatchesNativeBluetoothHost() {
        val address = "02:00:00:00:00:01"
        val config = ServerConfig(
            stateDir = folder.newFolder("state").toPath(),
            identityDir = folder.newFolder("identity").toPath(),
            bindAddress = "127.0.0.1",
            nativeBluetoothAddress = address,
        )
        CarPlayServer(config).use { server ->
            assertEquals(address, server.airPlayConfig.btMac)
            assertEquals(listOf(address), AirPlayInfoPlist.build(server.airPlayConfig)["bluetoothIDs"])
        }
    }

    @Test fun standaloneConfigurationRetainsItsFallback() {
        val config = ServerConfig(
            stateDir = folder.newFolder("state").toPath(),
            identityDir = folder.newFolder("identity").toPath(),
            bindAddress = "127.0.0.1",
        )
        CarPlayServer(config).use { server ->
            assertEquals(server.deviceId, server.airPlayConfig.btMac)
        }
    }
}
