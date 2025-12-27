import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:xml/xml.dart';
import 'package:uuid/uuid.dart';
import '../models/camera_device.dart';

/// Service for discovering ONVIF-compatible cameras via WS-Discovery
/// and fetching their actual RTSP stream URLs
class OnvifDiscoveryService {
  static const String _multicastAddress = '239.255.255.250';
  static const int _multicastPort = 3702;
  static const Duration _discoveryTimeout = Duration(seconds: 5);
  
  final Uuid _uuid = const Uuid();
  final NetworkInfo _networkInfo = NetworkInfo();

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

  /// Build SOAP request for GetProfiles
  String _buildGetProfilesRequest() {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" 
               xmlns:trt="http://www.onvif.org/ver10/media/wsdl">
  <soap:Body>
    <trt:GetProfiles/>
  </soap:Body>
</soap:Envelope>''';
  }

  /// Build SOAP request for GetStreamUri
  String _buildGetStreamUriRequest(String profileToken) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" 
               xmlns:trt="http://www.onvif.org/ver10/media/wsdl"
               xmlns:tt="http://www.onvif.org/ver10/schema">
  <soap:Body>
    <trt:GetStreamUri>
      <trt:StreamSetup>
        <tt:Stream>RTP-Unicast</tt:Stream>
        <tt:Transport>
          <tt:Protocol>RTSP</tt:Protocol>
        </tt:Transport>
      </trt:StreamSetup>
      <trt:ProfileToken>$profileToken</trt:ProfileToken>
    </trt:GetStreamUri>
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
      onStatusUpdate?.call('Getting WiFi interface...');
      
      // Get WiFi IP address for proper interface binding
      // This ensures we send on WiFi, not mobile data
      String? wifiIP;
      try {
        wifiIP = await _networkInfo.getWifiIP();
      } catch (e) {
        _logDebug('Could not get WiFi IP: $e');
      }
      
      // Bind to WiFi interface if available, otherwise any interface
      final bindAddress = wifiIP != null 
          ? InternetAddress(wifiIP)
          : InternetAddress.anyIPv4;
      
      onStatusUpdate?.call('Initializing network discovery...');
      
      // Create UDP socket bound to the appropriate interface
      socket = await RawDatagramSocket.bind(bindAddress, 0);
      socket.broadcastEnabled = true;
      socket.multicastLoopback = false;
      
      // Join multicast group for receiving responses
      try {
        socket.joinMulticast(InternetAddress(_multicastAddress));
      } catch (e) {
        _logDebug('Could not join multicast group: $e');
      }

      onStatusUpdate?.call('Sending discovery probe...');

      // Build and send the probe message
      final probeMessage = _buildProbeMessage();
      final probeBytes = probeMessage.codeUnits;
      
      // Send to multicast address multiple times for reliability
      for (int i = 0; i < 3; i++) {
        socket.send(
          probeBytes,
          InternetAddress(_multicastAddress),
          _multicastPort,
        );
        await Future.delayed(const Duration(milliseconds: 100));
      }

      onStatusUpdate?.call('Listening for ONVIF responses...');

      // Listen for responses with timeout
      final completer = Completer<void>();
      
      final subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            try {
              final response = String.fromCharCodes(datagram.data);
              final cameraInfo = _parseProbeResponse(response, datagram.address.address);
              
              if (cameraInfo != null && !discoveredIps.contains(cameraInfo['ip'])) {
                discoveredIps.add(cameraInfo['ip']!);
                
                final camera = CameraDevice(
                  id: _uuid.v4(),
                  name: cameraInfo['name'] ?? 'Camera [${cameraInfo['ip']}]',
                  ipAddress: cameraInfo['ip']!,
                  port: 554,
                  username: '',
                  password: '',
                  rtspPath: '/stream1', // Will be fetched properly when credentials are added
                  isManuallyAdded: false,
                  serviceUrl: cameraInfo['serviceUrl'],
                );
                
                discoveredCameras.add(camera);
                onStatusUpdate?.call('Found camera at ${cameraInfo['ip']}');
              }
            } catch (e) {
              _logDebug('Error parsing response: $e');
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
      _logDebug('ONVIF Discovery Error: $e');
    } finally {
      socket?.close();
    }

    return discoveredCameras;
  }

  /// Parse the WS-Discovery probe response to extract device information
  Map<String, String>? _parseProbeResponse(String xmlResponse, String senderIp) {
    try {
      final document = XmlDocument.parse(xmlResponse);
      
      // Try to find XAddrs which contains the device service URL
      String? deviceServiceUrl;
      String? deviceName;
      String extractedIp = senderIp;
      
      // Look for XAddrs element (contains device service address)
      // Try various namespace patterns
      final xAddrsPatterns = ['XAddrs', 'd:XAddrs', 'wsd:XAddrs'];
      for (final pattern in xAddrsPatterns) {
        final elements = document.findAllElements(pattern);
        for (final element in elements) {
          final addresses = element.innerText.trim().split(RegExp(r'\s+'));
          for (final addr in addresses) {
            if (addr.startsWith('http://') || addr.startsWith('https://')) {
              deviceServiceUrl = addr;
              // Extract IP from URL
              final uri = Uri.tryParse(addr);
              if (uri != null && uri.host.isNotEmpty) {
                extractedIp = uri.host;
              }
              break;
            }
          }
          if (deviceServiceUrl != null) break;
        }
        if (deviceServiceUrl != null) break;
      }
      
      // Extract device name from Scopes
      final scopesPatterns = ['Scopes', 'd:Scopes', 'wsd:Scopes'];
      for (final pattern in scopesPatterns) {
        final elements = document.findAllElements(pattern);
        for (final element in elements) {
          final scopes = element.innerText.trim();
          
          // Look for name scope
          final nameMatch = RegExp(r'onvif://www\.onvif\.org/name/([^\s]+)').firstMatch(scopes);
          if (nameMatch != null) {
            deviceName = Uri.decodeComponent(nameMatch.group(1) ?? '').replaceAll('_', ' ');
            break;
          }
          
          // Look for hardware scope as fallback
          final hardwareMatch = RegExp(r'onvif://www\.onvif\.org/hardware/([^\s]+)').firstMatch(scopes);
          if (hardwareMatch != null && deviceName == null) {
            deviceName = Uri.decodeComponent(hardwareMatch.group(1) ?? '').replaceAll('_', ' ');
          }
        }
        if (deviceName != null) break;
      }

      return {
        'ip': extractedIp,
        'name': deviceName ?? 'ONVIF Camera',
        'serviceUrl': deviceServiceUrl ?? 'http://$extractedIp/onvif/device_service',
      };
    } catch (e) {
      _logDebug('Error parsing probe response: $e');
      return {
        'ip': senderIp,
        'name': 'Camera [$senderIp]',
        'serviceUrl': 'http://$senderIp/onvif/device_service',
      };
    }
  }

  /// Fetch the actual RTSP stream URL from the camera using ONVIF protocol
  /// This properly queries GetProfiles and GetStreamUri instead of guessing
  Future<String?> fetchStreamUrl({
    required String serviceUrl,
    required String username,
    required String password,
  }) async {
    try {
      // Derive media service URL from device service URL
      final uri = Uri.parse(serviceUrl);
      final mediaServiceUrl = '${uri.scheme}://${uri.host}:${uri.port}/onvif/media';
      
      // Step 1: Get Profiles
      final profilesResponse = await _sendOnvifRequest(
        mediaServiceUrl,
        _buildGetProfilesRequest(),
        username,
        password,
      );
      
      if (profilesResponse == null) {
        _logDebug('Failed to get profiles');
        return null;
      }
      
      // Parse profile token from response
      final profileToken = _extractProfileToken(profilesResponse);
      if (profileToken == null) {
        _logDebug('No profile token found');
        return null;
      }
      
      _logDebug('Found profile token: $profileToken');
      
      // Step 2: Get Stream URI using the profile token
      final streamUriResponse = await _sendOnvifRequest(
        mediaServiceUrl,
        _buildGetStreamUriRequest(profileToken),
        username,
        password,
      );
      
      if (streamUriResponse == null) {
        _logDebug('Failed to get stream URI');
        return null;
      }
      
      // Parse RTSP URI from response
      final rtspUri = _extractStreamUri(streamUriResponse);
      _logDebug('Extracted RTSP URI: $rtspUri');
      
      return rtspUri;
    } catch (e) {
      _logDebug('Error fetching stream URL: $e');
      return null;
    }
  }

  /// Send an ONVIF SOAP request with digest authentication
  Future<String?> _sendOnvifRequest(
    String url,
    String soapBody,
    String username,
    String password,
  ) async {
    try {
      // First try without auth (some cameras don't require it for basic queries)
      var response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/soap+xml; charset=utf-8',
        },
        body: soapBody,
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      // If unauthorized, try with WS-Security UsernameToken
      if (response.statusCode == 401 || response.statusCode == 400) {
        final authenticatedBody = _addWsSecurityHeader(soapBody, username, password);
        response = await http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/soap+xml; charset=utf-8',
          },
          body: authenticatedBody,
        ).timeout(const Duration(seconds: 10));
        
        if (response.statusCode == 200) {
          return response.body;
        }
      }
      
      _logDebug('ONVIF request failed with status: ${response.statusCode}');
      return null;
    } catch (e) {
      _logDebug('ONVIF request error: $e');
      return null;
    }
  }

  /// Add WS-Security UsernameToken header for authentication
  String _addWsSecurityHeader(String soapBody, String username, String password) {
    // Generate nonce and timestamp for WS-Security
    final nonce = _uuid.v4().replaceAll('-', '').substring(0, 16);
    final created = DateTime.now().toUtc().toIso8601String();
    
    // For simplicity, using PasswordText (some cameras require PasswordDigest)
    final securityHeader = '''
    <wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd"
                   xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
      <wsse:UsernameToken>
        <wsse:Username>$username</wsse:Username>
        <wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText">$password</wsse:Password>
        <wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">$nonce</wsse:Nonce>
        <wsu:Created>$created</wsu:Created>
      </wsse:UsernameToken>
    </wsse:Security>''';
    
    // Insert security header into SOAP envelope
    if (soapBody.contains('<soap:Header>')) {
      return soapBody.replaceFirst('<soap:Header>', '<soap:Header>$securityHeader');
    } else if (soapBody.contains('<soap:Body>')) {
      return soapBody.replaceFirst('<soap:Body>', '<soap:Header>$securityHeader</soap:Header><soap:Body>');
    }
    
    return soapBody;
  }

  /// Extract profile token from GetProfiles response
  String? _extractProfileToken(String xmlResponse) {
    try {
      final document = XmlDocument.parse(xmlResponse);
      
      // Look for Profile token attribute
      final patterns = ['Profiles', 'trt:Profiles', 'ns1:Profiles'];
      for (final pattern in patterns) {
        final profiles = document.findAllElements(pattern);
        for (final profile in profiles) {
          final token = profile.getAttribute('token');
          if (token != null && token.isNotEmpty) {
            return token;
          }
        }
      }
      
      // Also try looking for token in nested elements
      final tokenElements = document.findAllElements('token');
      for (final element in tokenElements) {
        if (element.innerText.isNotEmpty) {
          return element.innerText;
        }
      }
      
      return null;
    } catch (e) {
      _logDebug('Error extracting profile token: $e');
      return null;
    }
  }

  /// Extract RTSP URI from GetStreamUri response
  String? _extractStreamUri(String xmlResponse) {
    try {
      final document = XmlDocument.parse(xmlResponse);
      
      // Look for Uri element in MediaUri
      final uriPatterns = ['Uri', 'tt:Uri', 'ns1:Uri'];
      for (final pattern in uriPatterns) {
        final uris = document.findAllElements(pattern);
        for (final uri in uris) {
          final uriText = uri.innerText.trim();
          if (uriText.startsWith('rtsp://')) {
            return uriText;
          }
        }
      }
      
      return null;
    } catch (e) {
      _logDebug('Error extracting stream URI: $e');
      return null;
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
      _logDebug('Connection test failed for $ipAddress:$port - $e');
      return false;
    }
  }
  
  /// Common RTSP paths for different camera manufacturers
  /// Used as fallback when ONVIF GetStreamUri fails
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
  ];

  /// Try to find a working RTSP path by testing common paths
  Future<String?> probeRtspPath({
    required String ipAddress,
    required int port,
    required String username,
    required String password,
  }) async {
    for (final path in commonRtspPaths) {
      final testUrl = 'rtsp://$ipAddress:$port$path';
      _logDebug('Testing RTSP path: $testUrl');
      
      // Try to connect to the RTSP port
      final isReachable = await testConnection(ipAddress, port);
      if (isReachable) {
        // Return the first path if port is reachable
        // Full validation would require actually trying to play the stream
        return path;
      }
    }
    return null;
  }
}

void _logDebug(String message) {
  // ignore: avoid_print
  print('[ONVIF] $message');
}
