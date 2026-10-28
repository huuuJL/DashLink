import com.shilapi.xcertplay.network.TcpLiveness;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import kotlin.Unit;

/** Run with the packaged runtime and receiver classpath, not the build JDK. */
public final class NetworkRuntimeSmoke {
    public static void main(String[] args) throws Exception {
        Class.forName("jdk.net.ExtendedSocketOptions");
        Class.forName("jdk.jfr.Event");
        Class.forName("java.sql.Connection");
        var loopback = InetAddress.getByName("127.0.0.1");
        try (var listener = new ServerSocket(0, 1, loopback);
             var client = new Socket(loopback, listener.getLocalPort());
             var peer = listener.accept()) {
            TcpLiveness.INSTANCE.configure(peer, message -> {
                System.out.println(message);
                return Unit.INSTANCE;
            });
            if (!peer.getKeepAlive()) throw new AssertionError("TCP keepalive was not enabled");
        }
        System.out.println("Packaged runtime passed actual receiver TCP health setup.");
    }
}
