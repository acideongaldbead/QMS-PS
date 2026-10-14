package com.nexperia.qms.common.storage;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.io.BufferedOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * ClamAV adapter speaking the clamd INSTREAM command.
 *
 * Protocol: send "zINSTREAM\0", then length-prefixed chunks, then a zero-length
 * chunk, and read back a NUL-terminated verdict ("stream: OK" or
 * "stream: <Signature> FOUND").
 *
 * Selected with qms.antivirus.provider=clamav. If the daemon is unreachable the
 * scan is reported as failed, and the upload is rejected: silently accepting an
 * unscanned file would defeat the requirement.
 */
@Component
@ConditionalOnProperty(name = "qms.antivirus.provider", havingValue = "clamav")
public class ClamAvScanner implements AntivirusScanner {

    private static final Logger log = LoggerFactory.getLogger(ClamAvScanner.class);

    private static final String PREFIX = "zINSTREAM\0";
    private static final int CHUNK_SIZE = 8192;

    private final String host;
    private final int port;
    private final int timeoutMs;

    public ClamAvScanner(
            @Value("${qms.antivirus.clamav.host}") String host,
            @Value("${qms.antivirus.clamav.port}") int port,
            @Value("${qms.antivirus.clamav.timeout-ms:30000}") int timeoutMs) {
        this.host = host;
        this.port = port;
        this.timeoutMs = timeoutMs;
    }

    @Override
    public String name() {
        return "clamav";
    }

    @Override
    public ScanResult scan(Path file) {
        long size;
        try {
            size = Files.size(file);
        } catch (IOException e) {
            return ScanResult.infected("无法读取待扫描文件：" + e.getMessage());
        }

        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), timeoutMs);
            socket.setSoTimeout(timeoutMs);

            OutputStream rawOut = socket.getOutputStream();
            DataOutputStream out = new DataOutputStream(new BufferedOutputStream(rawOut));
            out.write(PREFIX.getBytes(StandardCharsets.US_ASCII));

            try (InputStream in = Files.newInputStream(file)) {
                byte[] buffer = new byte[CHUNK_SIZE];
                int read;
                while ((read = in.read(buffer)) > 0) {
                    out.writeInt(read);
                    out.write(buffer, 0, read);
                }
            }
            out.writeInt(0);
            out.flush();

            String reply = readReply(socket.getInputStream());
            log.debug("clamd replied '{}' for a {} byte upload", reply, size);
            return interpret(reply);
        } catch (IOException e) {
            log.error("clamd scan failed for a {} byte upload", size, e);
            return ScanResult.infected("杀毒服务不可用，已拒绝保存：" + e.getMessage());
        }
    }

    /** clamd terminates its verdict with a NUL byte. */
    private static String readReply(InputStream in) throws IOException {
        StringBuilder sb = new StringBuilder();
        int b;
        while ((b = in.read()) > 0) {
            sb.append((char) b);
        }
        return sb.toString().trim();
    }

    private static ScanResult interpret(String reply) {
        if (reply == null || reply.isEmpty()) {
            return ScanResult.infected("杀毒服务返回空响应");
        }
        if (reply.endsWith("FOUND")) {
            return ScanResult.infected("检出威胁：" + reply);
        }
        if (reply.endsWith("OK")) {
            return ScanResult.clean("已扫描：" + reply);
        }
        return ScanResult.infected("杀毒服务返回异常结果：" + reply);
    }
}
