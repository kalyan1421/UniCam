import 'dart:async';
import 'dart:io';
import 'package:easy_onvif/onvif.dart' as onvif;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';
import '../models/camera_device.dart';

/// Service for discovering ONVIF-compatible cameras and fetching stream URIs
class OnvifDiscoveryService {
  static const String _multicastAddress = '239.255.255.250';
  static const int _multicastPort = 3702;
  static const Duration _discoveryTimeout = Duration(seconds: 5);
  
  final Uuid _uuid = const Uuid();
  final NetworkInfo _networkInfo = NetworkInfo();

  /// Connects to the camera using easy_onvif and fetches the REAL RTSP Stream URI
  /// This replaces naive path guessing like "/stream1"
  Future<CameraDevice> enrichCameraDetails(CameraDevice camera) async {
    if (camera.username.isEmpty || camera.password.isEmpty) {
      _log('Skipping ONVIF enrichment - no credentials provided');
      return camera;
    }

    try {
      _log('Connecting to camera via ONVIF: ${camera.ipAddress}');
      
      // Connect to the device using ONVIF
      final device = await onvif.Onvif.connect(
        host: camera.ipAddress,
        username: camera.username,
        password: camera.password,
      );

      _log('Connected! Fetching media profiles...');
      
      // Get Media Profiles (High Res, Low Res, etc.)
      final profiles = await device.media.getProfiles();
      
      if (profiles.isEmpty) {
        _log('No media profiles found');
        return camera;
      }

      _log('Found ${profiles.length} profile(s). Using main profile.');
      
      // Usually the first profile is the "Main Stream" (High Quality)
      final mainProfile = profiles.first;

      // Ask the camera for the RTSP Stream URI for this profile
      final streamUri = await device.media.getStreamUri(mainProfile.token);
      
      _log('Got stream URI: $streamUri');
      
      // Parse the URI to extract path and port
      final uri = Uri.parse(streamUri);
      final rtspPath = uri.path + (uri.query.isNotEmpty ? '?${uri.query}' : '');
      final rtspPort = uri.port > 0 ? uri.port : 554;
      
      _log('Extracted RTSP path: $rtspPath, port: $rtspPort');
      
      return camera.copyWith(
        rtspPath: rtspPath,
        port: rtspPort,
      );
      
    } catch (e) {
      _log('Failed to fetch Stream URI via ONVIF: $e');
      // Fallback: Return original camera if ONVIF fails
      return camera;
    }
  }

  /// Discover ONVIF cameras on the local network using WS-Discovery
  /// Returns a list of discovered camera IPs with basic info
  Future<List<CameraDevice>> discoverCameras({
    void Function(String)? onStatusUpdate,
  }) async {
    final List<CameraDevice> discoveredCameras = [];
    final Set<String> discoveredIps = {};
    RawDatagramSocket? socket;

    try {
      onStatusUpdate?.call('Getting WiFi interface...');
      
      // Get local WiFi IP to bind specifically to it
      // This prevents the OS from sending probes via Cellular Data
      String? wifiIP;
      try {
        wifiIP = await _networkInfo.getWifiIP();
        _log('WiFi IP: $wifiIP');
      } catch (e) {
        _log('Could not get WiFi IP: $e');
      }
      
      final bindAddress = wifiIP != null 
          ? InternetAddress(wifiIP)
          : InternetAddress.anyIPv4;
      
      onStatusUpdate?.call('Initializing network discovery...');
      
      // Create UDP socket bound to the appropriate interface
      socket = await RawDatagramSocket.bind(bindAddress, 0);
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;
      
      // Try to join multicast group
      try {
        socket.joinMulticast(InternetAddress(_multicastAddress));
      } catch (e) {
        _log('Could not join multicast group: $e');
      }

      onStatusUpdate?.call('Sending discovery probe...');

      // Build and send the probe message
      final probeMessage = _buildProbeMessage();
      
      // Send probe multiple times for reliability
      for (int i = 0; i < 3; i++) {
        socket.send(
          probeMessage.codeUnits,
          InternetAddress(_multicastAddress),
          _multicastPort,
        );
        await Future.delayed(const Duration(milliseconds: 100));
      }

      onStatusUpdate?.call('Listening for ONVIF responses...');

      // Listen for responses
      final subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final ip = datagram.address.address;
            if (!discoveredIps.contains(ip)) {
              discoveredIps.add(ip);
              
              // Parse response to get device name
              final response = String.fromCharCodes(datagram.data);
              final deviceName = _extractDeviceName(response) ?? 'Camera [$ip]';
              final serviceUrl = _extractServiceUrl(response);
              
              final camera = CameraDevice(
                id: _uuid.v4(),
                name: deviceName,
                ipAddress: ip,
                port: 554,
                username: '',
                password: '',
                rtspPath: '/stream1', // Will be replaced by enrichCameraDetails
                isManuallyAdded: false,
                serviceUrl: serviceUrl,
              );
              
              discoveredCameras.add(camera);
              onStatusUpdate?.call('Found camera at $ip');
            }
          }
        }
      });

      // Wait for responses
      await Future.delayed(_discoveryTimeout);
      await subscription.cancel();

      onStatusUpdate?.call('Discovery complete. Found ${discoveredCameras.length} camera(s).');
      
    } catch (e) {
      onStatusUpdate?.call('Discovery error: $e');
      _log('ONVIF Discovery Error: $e');
    } finally {
      socket?.close();
    }

    return discoveredCameras;
  }

  /// Scan network and return just IPs (lightweight discovery)
  Future<List<String>> scanForCameraIps() async {
    final Set<String> discoveredIps = {};
    RawDatagramSocket? socket;
    
    try {
      // Get local WiFi IP to bind specifically to it
      final wifiIp = await _networkInfo.getWifiIP();
      final bindAddress = wifiIp != null 
          ? InternetAddress(wifiIp) 
          : InternetAddress.anyIPv4;

      socket = await RawDatagramSocket.bind(bindAddress, 0);
      socket.broadcastEnabled = true;
      
      // Send ONVIF Probe
      final message = _buildProbeMessage();
      socket.send(
        message.codeUnits,
        InternetAddress(_multicastAddress),
        _multicastPort,
      );

      // Listen for 3 seconds
      final subscription = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            discoveredIps.add(datagram.address.address);
          }
        }
      });
      
      await Future.delayed(const Duration(seconds: 3));
      await subscription.cancel();
      
    } catch (e) {
      _log("Discovery Error: $e");
    } finally {
      socket?.close();
    }
    
    return discoveredIps.toList();
  }

  /// Build WS-Discovery probe message for ONVIF devices
  String _buildProbeMessage() {
    final messageId = _uuid.v4();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
            xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
            xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
            xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <e:Header>
    <w:MessageID>uuid:$messageId</w:MessageID>
    <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
    <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
  </e:Header>
  <e:Body>
    <d:Probe>
      <d:Types>dn:NetworkVideoTransmitter</d:Types>
    </d:Probe>
  </e:Body>
</e:Envelope>''';
  }

  /// Extract device name from WS-Discovery response
  String? _extractDeviceName(String xmlResponse) {
    try {
      // Look for name in Scopes
      final nameMatch = RegExp(r'onvif://www\.onvif\.org/name/([^\s<]+)')
          .firstMatch(xmlResponse);
      if (nameMatch != null) {
        return Uri.decodeComponent(nameMatch.group(1) ?? '').replaceAll('_', ' ');
      }
      
      // Look for hardware type as fallback
      final hardwareMatch = RegExp(r'onvif://www\.onvif\.org/hardware/([^\s<]+)')
          .firstMatch(xmlResponse);
      if (hardwareMatch != null) {
        return Uri.decodeComponent(hardwareMatch.group(1) ?? '').replaceAll('_', ' ');
      }
    } catch (e) {
      _log('Error extracting device name: $e');
    }
    return null;
  }

  /// Extract service URL from WS-Discovery response
  String? _extractServiceUrl(String xmlResponse) {
    try {
      final xAddrsMatch = RegExp(r'<[^:]*:?XAddrs>([^<]+)</[^:]*:?XAddrs>')
          .firstMatch(xmlResponse);
      if (xAddrsMatch != null) {
        final addresses = xAddrsMatch.group(1)?.split(RegExp(r'\s+')) ?? [];
        for (final addr in addresses) {
          if (addr.startsWith('http://') || addr.startsWith('https://')) {
            return addr.trim();
          }
        }
      }
    } catch (e) {
      _log('Error extracting service URL: $e');
    }
    return null;
  }

  /// Test if a camera endpoint is reachable via socket connection
  Future<bool> testConnection(String ipAddress, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(
        ipAddress,
        port,
        timeout: timeout,
      );
      await socket.close();
      return true;
    } catch (e) {
      _log('Connection test failed for $ipAddress:$port - $e');
      return false;
    }
  }
  
  /// Common RTSP paths for different camera manufacturers
  /// Used as fallback when ONVIF enrichment fails
  static const List<String> commonRtspPaths = [
    '/stream1',
    '/Streaming/Channels/101',  // Hikvision main stream
    '/Streaming/Channels/102',  // Hikvision sub stream  
    '/cam/realmonitor?channel=1&subtype=0', // Dahua main
    '/cam/realmonitor?channel=1&subtype=1', // Dahua sub
    '/live/ch0',
    '/live/ch00_0',
    '/h264',
    '/video1',
    '/MediaInput/h264',
    '/axis-media/media.amp', // Axis
    '/videoMain',
    '/live.sdp',
    '/onvif1',
    '/1',
  ];

  void _log(String message) {
    // ignore: avoid_print
    print('[ONVIF] $message');
  }
}
