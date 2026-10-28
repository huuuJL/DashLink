package com.playport.server

import com.shilapi.xcertplay.transport.BlockingDuplexByteStream
import java.io.Closeable
import java.io.EOFException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit

/** The native app owns Bluetooth. This stream can only connect to IPv4 loopback. */
class NativeBluetoothByteStream private constructor(private val socket: Socket) : BlockingDuplexByteStream, Closeable {
    private val inbound = LinkedBlockingDeque<ByteArray>(128)
    private val writeLock = Any()
    @Volatile private var ended = false
    private val reader = Thread({
        val buffer = ByteArray(8192)
        try {
            while (!ended) {
                val count = socket.getInputStream().read(buffer)
                if (count < 0) break
                if (count > 0) inbound.putLast(buffer.copyOf(count))
            }
        } catch (_: Exception) {
        } finally {
            ended = true
            // Preserve queued bytes. recv checks ended after draining the queue.
            inbound.offerLast(ByteArray(0))
        }
    }, "native-bluetooth-reader").apply { isDaemon = true; start() }
    private var remainder = ByteArray(0)

    override fun send(data: ByteArray) {
        synchronized(writeLock) {
            check(!ended) { "Native Bluetooth stream closed" }
            socket.getOutputStream().write(data)
            socket.getOutputStream().flush()
        }
    }

    @Synchronized override fun recv(maxBytes: Int, timeoutMillis: Long): ByteArray? {
        require(maxBytes > 0)
        val chunk = if (remainder.isNotEmpty()) remainder.also { remainder = ByteArray(0) }
        else {
            if (ended && inbound.isEmpty()) return ByteArray(0)
            if (timeoutMillis == Long.MAX_VALUE) inbound.takeFirst()
            else inbound.pollFirst(timeoutMillis, TimeUnit.MILLISECONDS) ?: return null
        }
        if (chunk.size <= maxBytes) return chunk
        remainder = chunk.copyOfRange(maxBytes, chunk.size)
        return chunk.copyOf(maxBytes)
    }

    override fun close() {
        ended = true
        runCatching { socket.close() }
        reader.interrupt()
        inbound.clear()
        inbound.offerLast(ByteArray(0))
    }

    companion object {
        fun connect(port: Int, token: String): NativeBluetoothByteStream {
            require(port in 1..65535)
            require(token.isNotBlank() && token.length <= 100 && '\n' !in token && '\r' !in token)
            val socket = Socket()
            try {
                socket.connect(InetSocketAddress(InetAddress.getByName("127.0.0.1"), port), 5_000)
                socket.tcpNoDelay = true
                socket.soTimeout = 45_000
                socket.getOutputStream().write((token + "\n").toByteArray(Charsets.UTF_8))
                socket.getOutputStream().flush()
                val response = StringBuilder()
                while (response.length <= 32) {
                    val value = socket.getInputStream().read()
                    if (value < 0) throw EOFException("Native Bluetooth connection was not accepted")
                    if (value == 10) break
                    response.append(value.toChar())
                }
                check(response.toString() == "OK") { "Native Bluetooth connection was not accepted" }
                socket.soTimeout = 0
                return NativeBluetoothByteStream(socket)
            } catch (error: Exception) {
                runCatching { socket.close() }
                throw error
            }
        }
    }
}
