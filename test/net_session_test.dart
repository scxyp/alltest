import 'package:debug_assistant/features/network/domain/net_config.dart';
import 'package:debug_assistant/features/network/domain/net_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 等待接收合并（静默 30ms 判帧）冲刷完成。
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  // 固定高端口，降低与系统占用冲突的概率。
  const tcpPort = 19091;
  const udpPortA = 19092;
  const udpPortB = 19093;

  group('TCP 回环', () {
    test('客户端与服务端双向收发、客户端来源标记', () async {
      final server = NetSession(
        const NetConfig(mode: NetMode.tcpServer, localPort: tcpPort),
        id: 'srv',
      );
      await server.connect();

      final client = NetSession(
        const NetConfig(
          mode: NetMode.tcpClient,
          remoteHost: '127.0.0.1',
          remotePort: tcpPort,
        ),
        id: 'cli',
      );
      await client.connect();
      await _settle();

      // 服务端应收到客户端接入事件。
      expect(server.isConnected, isTrue);
      expect(client.isConnected, isTrue);
      expect(server.peers.length, 1);

      // 客户端 → 服务端（默认追加 CRLF，共 7 字节）。
      client.sendContent('hello', asHex: false);
      await _settle();
      expect(server.rxBytes, 7);
      expect(server.logs.any((e) => e.source != null), isTrue);

      // 服务端 → 客户端（"ok\r\n"，4 字节）。
      server.sendContent('ok', asHex: false);
      await _settle();
      expect(client.rxBytes, 4);

      // 服务端断开时资源能正常释放。
      await client.disconnect();
      await server.disconnect();
      client.dispose();
      server.dispose();
    });
  });

  group('UDP 回环', () {
    test('双向收发且接收日志带对端地址', () async {
      final a = NetSession(
        const NetConfig(
          mode: NetMode.udp,
          bindAddress: '127.0.0.1',
          localPort: udpPortA,
          remoteHost: '127.0.0.1',
          remotePort: udpPortB,
        ),
        id: 'udpA',
      );
      final b = NetSession(
        const NetConfig(
          mode: NetMode.udp,
          bindAddress: '127.0.0.1',
          localPort: udpPortB,
          remoteHost: '127.0.0.1',
          remotePort: udpPortA,
        ),
        id: 'udpB',
      );
      await a.connect();
      await b.connect();

      a.sendContent('ping', asHex: false); // ping\r\n = 6 字节
      await _settle();
      expect(b.rxBytes, 6);
      final rx = b.logs.where((e) => e.source != null).last;
      expect(rx.source, contains('127.0.0.1:$udpPortA'));

      b.sendContent('pong', asHex: false); // pong\r\n = 6 字节
      await _settle();
      expect(a.rxBytes, 6);

      await a.disconnect();
      await b.disconnect();
      a.dispose();
      b.dispose();
    });

    test('参数缺失时抛出 FormatException', () async {
      final session = NetSession(
        const NetConfig(mode: NetMode.tcpClient, remoteHost: ''),
        id: 'bad',
      );
      await expectLater(
        session.connect(),
        throwsA(isA<FormatException>()),
      );
      session.dispose();
    });
  });
}
