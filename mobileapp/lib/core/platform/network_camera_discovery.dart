import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

class DiscoveredCameraService {
  const DiscoveredCameraService({
    required this.url,
    required this.source,
    this.description,
  });

  final String url;
  final String source;
  final String? description;
}

class NetworkCameraDiscovery {
  NetworkCameraDiscovery._();

  static const List<String> _knownMdnsServices = [
    '_http._tcp.local',
    '_https._tcp.local',
    '_device-info._tcp.local',
    '_ptp._tcp.local',
    '_companion-link._tcp.local',
  ];

  static const List<String> _cameraHints = [
    'camera',
    'canon',
    'nikon',
    'sony',
    'fuji',
    'fujifilm',
    'lumix',
    'panasonic',
    'pentax',
    'ricoh',
    'imaging',
    'ptp',
    'alpha',
    'eos',
    'snapbridge',
  ];

  static Future<List<DiscoveredCameraService>> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final results = <DiscoveredCameraService>[];

    final discovered = await Future.wait([
      _discoverMdns(timeout: timeout),
      _discoverSsdp(timeout: timeout),
    ]);

    for (final group in discovered) {
      for (final item in group) {
        if (results.any((current) => current.url == item.url)) continue;
        results.add(item);
      }
    }

    return results;
  }

  static Future<List<DiscoveredCameraService>> _discoverMdns({
    required Duration timeout,
  }) async {
    final client = MDnsClient();
    final results = <DiscoveredCameraService>[];

    try {
      await client.start();
      final serviceTypes = <String>{..._knownMdnsServices};

      try {
        await for (final PtrResourceRecord ptr in client
            .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer('_services._dns-sd._udp.local'),
              timeout: timeout,
            )
            ) {
          serviceTypes.add(ptr.domainName);
        }
      } catch (_) {}

      final filteredTypes = serviceTypes.where((type) {
        final lower = type.toLowerCase();
        return lower.contains('_http') ||
            lower.contains('camera') ||
            lower.contains('canon') ||
            lower.contains('nikon') ||
            lower.contains('sony') ||
            lower.contains('fuji') ||
            lower.contains('lumix') ||
            lower.contains('panasonic') ||
            lower.contains('pentax') ||
            lower.contains('ricoh') ||
            lower.contains('ptp') ||
            lower.contains('device');
      }).toList(growable: false);

      for (final serviceType in filteredTypes) {
        final instances = <PtrResourceRecord>[];
        try {
          await for (final PtrResourceRecord ptr in client
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer(serviceType),
                timeout: timeout,
              )
              ) {
            instances.add(ptr);
          }
        } catch (_) {}

        for (final ptr in instances) {
          final lowerName = ptr.domainName.toLowerCase();
          if (!_cameraHints.any(lowerName.contains) &&
              !serviceType.toLowerCase().contains('_http')) {
            continue;
          }

          try {
            await for (final SrvResourceRecord srv in client
                .lookup<SrvResourceRecord>(
                  ResourceRecordQuery.service(ptr.domainName),
                  timeout: timeout,
                )
                ) {
              final addresses = <String>{};

              try {
                await for (final IPAddressResourceRecord record in client
                    .lookup<IPAddressResourceRecord>(
                      ResourceRecordQuery.addressIPv4(srv.target),
                      timeout: timeout,
                    )
                    ) {
                  addresses.add(record.address.address);
                }
              } catch (_) {}

              try {
                await for (final IPAddressResourceRecord record in client
                    .lookup<IPAddressResourceRecord>(
                      ResourceRecordQuery.addressIPv6(srv.target),
                      timeout: timeout,
                    )
                    ) {
                  addresses.add(record.address.address);
                }
              } catch (_) {}

              for (final address in addresses) {
                final scheme =
                    serviceType.toLowerCase().contains('_https') ? 'https' : 'http';
                final host = address.contains(':') ? '[$address]' : address;
                results.add(
                  DiscoveredCameraService(
                    url: '$scheme://$host:${srv.port}/',
                    source: 'mdns',
                    description: '${ptr.domainName} via $serviceType',
                  ),
                );
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {
      return const [];
    } finally {
      client.stop();
    }

    return results;
  }

  static Future<List<DiscoveredCameraService>> _discoverSsdp({
    required Duration timeout,
  }) async {
    RawDatagramSocket? socket;
    final results = <DiscoveredCameraService>[];

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: false,
      );
      socket.broadcastEnabled = true;

      final completer = Completer<void>();
      final search = [
        'M-SEARCH * HTTP/1.1',
        'HOST: 239.255.255.250:1900',
        'MAN: "ssdp:discover"',
        'MX: 2',
        'ST: ssdp:all',
        '',
        '',
      ].join('\r\n');

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;

        final body = utf8.decode(datagram.data, allowMalformed: true);
        final lower = body.toLowerCase();
        final useful = _cameraHints.any(lower.contains) ||
            lower.contains('upnp') ||
            lower.contains('dlna');
        if (!useful) return;

        final locationMatch = RegExp(
          r'^location:\s*(.+)$',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(body);
        final location = locationMatch?.group(1)?.trim();
        if (location == null || location.isEmpty) return;

        final uri = Uri.tryParse(location);
        if (uri == null || !uri.hasScheme || uri.host.isEmpty) return;

        results.add(
          DiscoveredCameraService(
            url: uri.replace(path: uri.path.isEmpty ? '/' : uri.path).toString(),
            source: 'ssdp',
            description: '${datagram.address.address}:${datagram.port}',
          ),
        );
      });

      socket.send(
        utf8.encode(search),
        InternetAddress('239.255.255.250'),
        1900,
      );

      Future<void>.delayed(timeout).then((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await completer.future;
    } catch (_) {
      return const [];
    } finally {
      socket?.close();
    }

    return results;
  }
}
