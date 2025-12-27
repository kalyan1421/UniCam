import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for handling runtime permissions
class PermissionService {
  
  /// Request all permissions needed for camera discovery
  /// Returns true if all critical permissions are granted
  static Future<bool> requestPermissions(BuildContext context) async {
    if (Platform.isAndroid) {
      return await _requestAndroidPermissions(context);
    } else if (Platform.isIOS) {
      return await _requestIOSPermissions(context);
    }
    return true;
  }

  /// Request Android-specific permissions
  static Future<bool> _requestAndroidPermissions(BuildContext context) async {
    // Check Android version for appropriate permissions
    final androidInfo = await _getAndroidSdkVersion();
    
    List<Permission> permissionsToRequest = [];
    
    if (androidInfo >= 33) {
      // Android 13+ uses NEARBY_WIFI_DEVICES instead of location
      permissionsToRequest.add(Permission.nearbyWifiDevices);
    } else {
      // Older Android versions need location for WiFi scanning
      permissionsToRequest.add(Permission.locationWhenInUse);
    }
    
    // Request permissions
    Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();
    
    // Check results
    bool allGranted = true;
    for (var entry in statuses.entries) {
      if (!entry.value.isGranted) {
        allGranted = false;
        debugPrint('Permission ${entry.key} not granted: ${entry.value}');
      }
    }
    
    // If permission denied, show explanation dialog
    if (!allGranted && context.mounted) {
      await _showPermissionDeniedDialog(context, 'network discovery');
    }
    
    return allGranted;
  }

  /// Request iOS-specific permissions
  static Future<bool> _requestIOSPermissions(BuildContext context) async {
    // On iOS, local network permission is requested automatically
    // when the app tries to access the network. 
    // However, we may need location for WiFi info.
    
    final locationStatus = await Permission.locationWhenInUse.request();
    
    if (!locationStatus.isGranted && context.mounted) {
      // Location is optional on iOS for basic functionality
      debugPrint('Location permission not granted on iOS - WiFi info may be limited');
    }
    
    // Local network permission will be triggered automatically on first network access
    return true;
  }

  /// Get Android SDK version
  static Future<int> _getAndroidSdkVersion() async {
    try {
      // Using device_info_plus would be better, but we'll use a simple approach
      // Android 13 = API 33
      final version = int.tryParse(Platform.operatingSystemVersion.split(' ').first) ?? 0;
      return version;
    } catch (e) {
      return 30; // Default to Android 11 behavior
    }
  }

  /// Show dialog explaining why permission is needed
  static Future<void> _showPermissionDeniedDialog(BuildContext context, String feature) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade400),
            const SizedBox(width: 12),
            const Text(
              'Permission Required',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Text(
          'CCTV Open needs permission to access $feature to find cameras on your network.\n\n'
          'Without this permission, automatic camera discovery will not work. '
          'You can still add cameras manually.',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Anyway'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Check if all required permissions are granted
  static Future<bool> hasRequiredPermissions() async {
    if (Platform.isAndroid) {
      final androidVersion = await _getAndroidSdkVersion();
      if (androidVersion >= 33) {
        return await Permission.nearbyWifiDevices.isGranted;
      } else {
        return await Permission.locationWhenInUse.isGranted;
      }
    }
    // iOS handles permissions differently
    return true;
  }
}

