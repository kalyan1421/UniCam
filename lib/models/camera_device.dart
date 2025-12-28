import 'dart:convert';

/// Model class representing a camera device
class CameraDevice {
  final String id;
  String name;
  String ipAddress;       // Local IP (e.g., 192.168.1.50)
  int port;               // Local Port (e.g., 554)
  String? publicIpAddress; // Public IP or DDNS (e.g., myhome.ddns.net)
  int? publicPort;         // Public Port (e.g., 8554)
  String username;
  String password;
  String rtspPath;
  final bool isManuallyAdded;
  String? serviceUrl; // ONVIF device service URL for fetching stream info

  CameraDevice({
    required this.id,
    required this.name,
    required this.ipAddress,
    this.port = 554,
    this.publicIpAddress,
    this.publicPort,
    this.username = '',
    this.password = '',
    this.rtspPath = '/stream1',
    this.isManuallyAdded = false,
    this.serviceUrl,
  });

  /// Constructs the full RTSP URL with credentials (URL encoded)
  /// Properly encodes special characters in username/password to prevent URL parsing issues
  String get rtspUrl {
    return getRtspUrl(usePublic: false);
  }

  /// Helper to get the correct RTSP URL based on connection mode
  /// [usePublic] - If true, uses publicIpAddress and publicPort when available
  String getRtspUrl({bool usePublic = false}) {
    // Determine which IP and Port to use
    final targetIp = (usePublic && publicIpAddress != null && publicIpAddress!.isNotEmpty) 
        ? publicIpAddress! 
        : ipAddress;
        
    final targetPort = (usePublic && publicPort != null) 
        ? publicPort! 
        : port;

    if (username.isNotEmpty && password.isNotEmpty) {
      final encodedUser = Uri.encodeComponent(username);
      final encodedPass = Uri.encodeComponent(password);
      return 'rtsp://$encodedUser:$encodedPass@$targetIp:$targetPort$rtspPath';
    }
    return 'rtsp://$targetIp:$targetPort$rtspPath';
  }

  /// Constructs RTSP URL without credentials (for display purposes)
  String get rtspUrlDisplay {
    return 'rtsp://$ipAddress:$port$rtspPath';
  }

  /// Check if camera has credentials configured
  bool get hasCredentials => username.isNotEmpty && password.isNotEmpty;
  
  /// Check if this camera has ONVIF service URL for advanced features
  bool get hasServiceUrl => serviceUrl != null && serviceUrl!.isNotEmpty;
  
  /// Check if camera has remote access configured
  bool get hasRemoteAccess => publicIpAddress != null && publicIpAddress!.isNotEmpty;

  /// Create a copy with updated fields
  CameraDevice copyWith({
    String? id,
    String? name,
    String? ipAddress,
    int? port,
    String? publicIpAddress,
    int? publicPort,
    String? username,
    String? password,
    String? rtspPath,
    bool? isManuallyAdded,
    String? serviceUrl,
  }) {
    return CameraDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      publicIpAddress: publicIpAddress ?? this.publicIpAddress,
      publicPort: publicPort ?? this.publicPort,
      username: username ?? this.username,
      password: password ?? this.password,
      rtspPath: rtspPath ?? this.rtspPath,
      isManuallyAdded: isManuallyAdded ?? this.isManuallyAdded,
      serviceUrl: serviceUrl ?? this.serviceUrl,
    );
  }

  /// Convert to JSON map for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ipAddress': ipAddress,
      'port': port,
      'publicIpAddress': publicIpAddress,
      'publicPort': publicPort,
      'username': username,
      'password': password,
      'rtspPath': rtspPath,
      'isManuallyAdded': isManuallyAdded,
      'serviceUrl': serviceUrl,
    };
  }

  /// Create from JSON map
  factory CameraDevice.fromJson(Map<String, dynamic> json) {
    return CameraDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      ipAddress: json['ipAddress'] as String,
      port: json['port'] as int? ?? 554,
      publicIpAddress: json['publicIpAddress'] as String?,
      publicPort: json['publicPort'] as int?,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      rtspPath: json['rtspPath'] as String? ?? '/stream1',
      isManuallyAdded: json['isManuallyAdded'] as bool? ?? false,
      serviceUrl: json['serviceUrl'] as String?,
    );
  }

  /// Serialize to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON string
  factory CameraDevice.fromJsonString(String jsonString) {
    return CameraDevice.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  @override
  String toString() {
    return 'CameraDevice(id: $id, name: $name, ip: $ipAddress:$port, manual: $isManuallyAdded)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CameraDevice && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
