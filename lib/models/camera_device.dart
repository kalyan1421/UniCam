import 'dart:convert';

/// Model class representing a camera device
class CameraDevice {
  final String id;
  String name;
  String ipAddress;
  int port;
  String username;
  String password;
  String rtspPath;
  final bool isManuallyAdded;

  CameraDevice({
    required this.id,
    required this.name,
    required this.ipAddress,
    this.port = 554,
    this.username = '',
    this.password = '',
    this.rtspPath = '/stream1',
    this.isManuallyAdded = false,
  });

  /// Constructs the full RTSP URL with credentials
  String get rtspUrl {
    final credentials = username.isNotEmpty ? '$username:$password@' : '';
    return 'rtsp://$credentials$ipAddress:$port$rtspPath';
  }

  /// Constructs RTSP URL without credentials (for display purposes)
  String get rtspUrlDisplay {
    return 'rtsp://$ipAddress:$port$rtspPath';
  }

  /// Check if camera has credentials configured
  bool get hasCredentials => username.isNotEmpty && password.isNotEmpty;

  /// Create a copy with updated fields
  CameraDevice copyWith({
    String? id,
    String? name,
    String? ipAddress,
    int? port,
    String? username,
    String? password,
    String? rtspPath,
    bool? isManuallyAdded,
  }) {
    return CameraDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      rtspPath: rtspPath ?? this.rtspPath,
      isManuallyAdded: isManuallyAdded ?? this.isManuallyAdded,
    );
  }

  /// Convert to JSON map for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ipAddress': ipAddress,
      'port': port,
      'username': username,
      'password': password,
      'rtspPath': rtspPath,
      'isManuallyAdded': isManuallyAdded,
    };
  }

  /// Create from JSON map
  factory CameraDevice.fromJson(Map<String, dynamic> json) {
    return CameraDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      ipAddress: json['ipAddress'] as String,
      port: json['port'] as int? ?? 554,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      rtspPath: json['rtspPath'] as String? ?? '/stream1',
      isManuallyAdded: json['isManuallyAdded'] as bool? ?? false,
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

