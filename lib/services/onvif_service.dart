import 'dart:async';
import 'dart:io';
import 'package:xml/xml.dart';
import 'package:uuid/uuid.dart';
import '../models/camera_device.dart';

/// Service for discovering ONVIF-compatible cameras via WS-Discovery
class OnvifDiscoveryService {
  static const String _multicastAddress = '239.255.255.250';
  static const int _multicastPort = 3702;
  static const Duration _discoveryTimeout = Duration(seconds: 5);
  
  final Uuid _uuid = const Uuid();

  /// WS-Discovery probe message template for ONVIF devices
  String _buildProbeMessage() {
    final messageId = _uuid.v4();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope 
  xmlns:soap="http://www.w3.org/2003/05/soap-envelope" 
  xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing" 
  xmlns:wsd="http://schemas.xmlsoap.org/ws/2005/04/discovery" 
  xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
  <soap:Header>
    <wsa:MessageID>uuid:$messageId</wsa:MessageID>
    <wsa:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</wsa:To>
    <wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</wsa:Action>
  </soap:Header>
  <soap:Body>
    <wsd:Probe>
      <wsd:Types>dn:NetworkVideoTransmitter</wsd:Types>
    </wsd:Probe>
  </soap:Body>
</soap:Envelope>''';
  }

  /// Discover ONVIF cameras on the local network
  /// Returns a list of CameraDevice objects found via UDP multicast
  Future<List<CameraDevice>> discoverCameras({
    void Function(String)? onStatusUpdate,
  }) async {
    final List<CameraDevice> discoveredCameras = [];
    final Set<String> discoveredIps = {};
    RawDatagramSocket? socket;

    try {
      onStatusUpdate?.call('Initializing network discovery...');
      
      // Create UDP socket bound to any available port
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;

      onStatusUpdate?.call('Sending discovery probe...');

      // Build and send the probe message
      final probeMessage = _buildProbeMessage();
      final probeBytes = probeMessage.codeUnits;
      
      // Send to multicast address
      socket.send(
        probeBytes,
        InternetAddress(_multicastAddress),
        _multicastPort,
      );

      onStatusUpdate?.call('Listening for ONVIF responses...');

      // Listen for responses with timeout
      final completer = Completer<void>();
      
      final subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            try {
              final response = String.fromCharCodes(datagram.data);
              final camera = _parseProbeResponse(response, datagram.address.address);
              
              if (camera != null && !discoveredIps.contains(camera.ipAddress)) {
                discoveredIps.add(camera.ipAddress);
                discoveredCameras.add(camera);
                onStatusUpdate?.call('Found camera at ${camera.ipAddress}');
              }
            } catch (e) {
              // Ignore malformed responses
              print('Error parsing response: $e');
            }
          }
        }
      });

      // Wait for timeout
      await Future.delayed(_discoveryTimeout);
      
      await subscription.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }

      onStatusUpdate?.call('Discovery complete. Found ${discoveredCameras.length} camera(s).');
      
    } catch (e) {
      onStatusUpdate?.call('Discovery error: $e');
      print('ONVIF Discovery Error: $e');
    } finally {
      socket?.close();
    }

    return discoveredCameras;
  }

  /// Parse the WS-Discovery probe response to extract device information
  CameraDevice? _parseProbeResponse(String xmlResponse, String senderIp) {
    try {
      final document = XmlDocument.parse(xmlResponse);
      
      // Try to find XAddrs which contains the device service URL
      String? deviceAddress;
      String? deviceName;
      
      // Look for XAddrs element (contains device service address)
      final xAddrsElements = document.findAllElements('XAddrs');
      for (final element in xAddrsElements) {
        final addresses = element.innerText.trim().split(' ');
        for (final addr in addresses) {
          if (addr.startsWith('http://') || addr.startsWith('https://')) {
            deviceAddress = addr;
            break;
          }
        }
        if (deviceAddress != null) break;
      }
      
      // Also check for d:XAddrs (namespaced)
      if (deviceAddress == null) {
        final dXAddrsElements = document.findAllElements('d:XAddrs');
        for (final element in dXAddrsElements) {
          final addresses = element.innerText.trim().split(' ');
          for (final addr in addresses) {
            if (addr.startsWith('http://') || addr.startsWith('https://')) {
              deviceAddress = addr;
              break;
            }
          }
          if (deviceAddress != null) break;
        }
      }
      
      // Extract IP from device address or use sender IP
      String extractedIp = senderIp;
      int port = 554; // Default RTSP port
      
      if (deviceAddress != null) {
        // Parse IP from URL like http://192.168.1.100:8080/onvif/device_service
        final uri = Uri.tryParse(deviceAddress);
        if (uri != null) {
          extractedIp = uri.host;
          // Try to find Scopes for device name
          final scopesElements = document.findAllElements('Scopes');
          for (final element in scopesElements) {
            final scopes = element.innerText.trim();
            // Look for hardware scope like onvif://www.onvif.org/hardware/IPCamera
            final hardwareMatch = RegExp(r'hardware/([^\s]+)').firstMatch(scopes);
            if (hardwareMatch != null) {
              deviceName = hardwareMatch.group(1)?.replaceAll('_', ' ');
            }
            // Look for name scope
            final nameMatch = RegExp(r'name/([^\s]+)').firstMatch(scopes);
            if (nameMatch != null) {
              deviceName = Uri.decodeComponent(nameMatch.group(1) ?? '').replaceAll('_', ' ');
            }
          }
        }
      }

      // Generate camera name
      final name = deviceName ?? 'Camera [$extractedIp]';
      
      return CameraDevice(
        id: const Uuid().v4(),
        name: name,
        ipAddress: extractedIp,
        port: port,
        username: '',
        password: '',
        rtspPath: '/stream1',
        isManuallyAdded: false,
      );
    } catch (e) {
      print('Error parsing probe response: $e');
      // If parsing fails, create a basic camera entry with sender IP
      return CameraDevice(
        id: const Uuid().v4(),
        name: 'Camera [$senderIp]',
        ipAddress: senderIp,
        port: 554,
        username: '',
        password: '',
        rtspPath: '/stream1',
        isManuallyAdded: false,
      );
    }
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
      print('Connection test failed for $ipAddress:$port - $e');
      return false;
    }
  }
}

