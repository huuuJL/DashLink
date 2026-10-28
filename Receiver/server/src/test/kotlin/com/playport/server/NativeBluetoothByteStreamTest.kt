package com.playport.server

import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class NativeBluetoothByteStreamTest {
    @Test fun authenticationDoesNotConsumeBinaryPayloadAndSmallReadsPreserveOrder() {
        ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { server ->
            val pool = Executors.newSingleThreadExecutor()
            val payload = ByteArray(20000) { (it % 251).toByte() }
            val task = pool.submit {
                server.accept().use { peer ->
                    val greeting = StringBuilder()
                    while (true) {
                        val byte = peer.getInputStream().read()
                        if (byte == 10) break
                        check(byte >= 0); greeting.append(byte.toChar())
                    }
                    assertEquals("session-secret", greeting.toString())
                    peer.getOutputStream().write("OK\n".toByteArray() + payload)
                    peer.getOutputStream().flush()
                    assertEquals(42, peer.getInputStream().read())
                }
            }
            try {
                NativeBluetoothByteStream.connect(server.localPort, "session-secret").use { stream ->
                    val received = ArrayList<Byte>()
                    while (received.size < payload.size) {
                        val next = stream.recv(3, 5_000)
                        assertNotNull(next); assertTrue(next!!.isNotEmpty())
                        received.addAll(next.toList())
                    }
                    assertArrayEquals(payload, received.toByteArray())
                    stream.send(byteArrayOf(42))
                    assertArrayEquals(ByteArray(0), stream.recv(4, 5_000))
                    assertArrayEquals(ByteArray(0), stream.recv(4, 10))
                }
                task.get(5, TimeUnit.SECONDS)
            } finally { pool.shutdownNow() }
        }
    }

    @Test fun rejectedAuthenticationNeverStartsAStream() {
        ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { server ->
            val pool = Executors.newSingleThreadExecutor()
            val task = pool.submit { server.accept().use { it.getOutputStream().write("NO\n".toByteArray()) } }
            try {
                assertThrows(IllegalStateException::class.java) {
                    NativeBluetoothByteStream.connect(server.localPort, "bad-token")
                }
                task.get(5, TimeUnit.SECONDS)
            } finally { pool.shutdownNow() }
        }
    }
}
