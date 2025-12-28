import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/camera_device.dart';
import '../services/onvif_service.dart';

/// Provider for managing camera state across the app
class CameraProvider extends ChangeNotifier {
  final OnvifDiscoveryService _discoveryService = OnvifDiscoveryService();
  
  // Saved cameras (user's camera list)
  List<CameraDevice> _savedCameras = [];
  
  // Discovered cameras from ONVIF scan
  List<CameraDevice> _discoveredCameras = [];
  
  // State flags
  bool _isScanning = false;
  bool _isFetchingStreamUrl = false;
  String _scanStatus = '';
  String? _errorMessage;
  
  // Getters
  List<CameraDevice> get savedCameras => List.unmodifiable(_savedCameras);
  List<CameraDevice> get discoveredCameras => List.unmodifiable(_discoveredCameras);
  bool get isScanning => _isScanning;
  bool get isFetchingStreamUrl => _isFetchingStreamUrl;
  String get scanStatus => _scanStatus;
  String? get errorMessage => _errorMessage;
  bool get hasSavedCameras => _savedCameras.isNotEmpty;
  bool get hasDiscoveredCameras => _discoveredCameras.isNotEmpty;
  
  CameraProvider() {
    _loadSavedCameras();
  }

  /// Check if a discovered camera is already saved
  bool isCameraSaved(CameraDevice camera) {
    return _savedCameras.any((c) => c.ipAddress == camera.ipAddress);
  }

  /// Start comprehensive discovery scan (ONVIF + Generic)
  Future<void> startDiscovery() async {
    _isScanning = true;
    _scanStatus = 'Initializing...';
    _errorMessage = null;
    _discoveredCameras = [];
    notifyListeners();

    try {
      // Step 1: ONVIF Discovery
      _scanStatus = 'Scanning for ONVIF cameras...';
      notifyListeners();
      
      final onvifCameras = await _discoveryService.discoverCameras(
        onStatusUpdate: (status) {
          _scanStatus = status;
          notifyListeners();
        },
      );
      
      _discoveredCameras.addAll(onvifCameras);
      
      // Step 2: Generic HTTP/RTSP scan (for IP Webcam, etc.)
      _scanStatus = 'Scanning for generic cameras...';
      notifyListeners();
      
      final genericCameras = await _discoveryService.scanGenericCameras(
        onStatusUpdate: (status) {
          _scanStatus = status;
          notifyListeners();
        },
      );
      
      // Merge cameras, avoiding duplicates by IP
      final existingIps = _discoveredCameras.map((c) => c.ipAddress).toSet();
      for (final camera in genericCameras) {
        if (!existingIps.contains(camera.ipAddress)) {
          _discoveredCameras.add(camera);
        }
      }
      
      _scanStatus = _discoveredCameras.isEmpty 
          ? 'No cameras found. Try manual addition.'
          : 'Found ${_discoveredCameras.length} camera(s)';
          
    } catch (e) {
      _errorMessage = 'Discovery failed: $e';
      _scanStatus = 'Error during discovery';
      debugPrint('Discovery error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// ONVIF-only discovery (faster, for real ONVIF cameras)
  Future<void> startOnvifDiscovery() async {
    _isScanning = true;
    _scanStatus = 'Initializing...';
    _errorMessage = null;
    _discoveredCameras = [];
    notifyListeners();

    try {
      final cameras = await _discoveryService.discoverCameras(
        onStatusUpdate: (status) {
          _scanStatus = status;
          notifyListeners();
        },
      );
      
      _discoveredCameras = cameras;
      _scanStatus = cameras.isEmpty 
          ? 'No ONVIF cameras found.'
          : 'Found ${cameras.length} ONVIF camera(s)';
    } catch (e) {
      _errorMessage = 'Discovery failed: $e';
      _scanStatus = 'Error during discovery';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Generic camera scan (for IP Webcam and non-ONVIF cameras)
  Future<void> startGenericScan() async {
    _isScanning = true;
    _scanStatus = 'Scanning network...';
    _errorMessage = null;
    _discoveredCameras = [];
    notifyListeners();

    try {
      final cameras = await _discoveryService.scanGenericCameras(
        onStatusUpdate: (status) {
          _scanStatus = status;
          notifyListeners();
        },
      );
      
      _discoveredCameras = cameras;
      _scanStatus = cameras.isEmpty 
          ? 'No cameras found.'
          : 'Found ${cameras.length} camera(s)';
    } catch (e) {
      _errorMessage = 'Scan failed: $e';
      _scanStatus = 'Error during scan';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Add a discovered camera with credentials
  /// Uses ONVIF to fetch the REAL Stream URI instead of guessing (if ONVIF-capable)
  Future<void> addDiscoveredCamera(
    CameraDevice camera, {
    String? username,
    String? password,
  }) async {
    if (isCameraSaved(camera)) return;

    _isFetchingStreamUrl = true;
    notifyListeners();

    try {
      // 1. Update camera with credentials
      var cameraWithCreds = camera.copyWith(
        username: username ?? '',
        password: password ?? '',
      );
      
      // 2. If camera has ONVIF service URL, try to get real stream URI
      // Otherwise use the guessed path (good for IP Webcam)
      if (cameraWithCreds.hasServiceUrl && cameraWithCreds.hasCredentials) {
        debugPrint('Fetching real RTSP URL via ONVIF...');
        try {
          cameraWithCreds = await _discoveryService.enrichCameraDetails(cameraWithCreds);
          debugPrint('RTSP path: ${cameraWithCreds.rtspPath}');
        } catch (e) {
          debugPrint('ONVIF enrichment failed, using default path: $e');
          // Continue with guessed path
        }
      } else {
        debugPrint('Using default path (no ONVIF or no creds): ${cameraWithCreds.rtspPath}');
      }
      
      // 3. Save to list
      _savedCameras.add(cameraWithCreds);
      await _saveCamerasToStorage();
      
    } catch (e) {
      debugPrint('Error adding camera: $e');
      // Still add camera with default path if enrichment fails
      _savedCameras.add(camera.copyWith(
        username: username ?? '',
        password: password ?? '',
      ));
      await _saveCamerasToStorage();
    } finally {
      _isFetchingStreamUrl = false;
      notifyListeners();
    }
  }

  /// Add camera with credentials and fetch real stream URL
  /// Convenience method matching the user's expected API
  Future<void> addCameraWithCredentials(CameraDevice camera, String user, String pass) async {
    await addDiscoveredCamera(camera, username: user, password: pass);
  }

  /// Add a manually configured camera
  void addManualCamera(CameraDevice camera) {
    // Check for duplicate IP
    final existingIndex = _savedCameras.indexWhere(
      (c) => c.ipAddress == camera.ipAddress && c.port == camera.port,
    );
    
    if (existingIndex >= 0) {
      // Update existing camera
      _savedCameras[existingIndex] = camera;
    } else {
      _savedCameras.add(camera);
    }
    
    _saveCamerasToStorage();
    notifyListeners();
  }

  /// Update an existing camera's configuration
  void updateCamera(CameraDevice camera) {
    final index = _savedCameras.indexWhere((c) => c.id == camera.id);
    if (index >= 0) {
      _savedCameras[index] = camera;
      _saveCamerasToStorage();
      notifyListeners();
    }
  }

  /// Re-fetch stream URL for a saved camera (useful if URL changed)
  Future<void> refreshCameraStreamUrl(CameraDevice camera) async {
    if (!camera.hasCredentials) return;
    
    _isFetchingStreamUrl = true;
    notifyListeners();
    
    try {
      final enrichedCamera = await _discoveryService.enrichCameraDetails(camera);
      updateCamera(enrichedCamera);
    } finally {
      _isFetchingStreamUrl = false;
      notifyListeners();
    }
  }

  /// Remove a camera from saved list
  void removeCamera(String cameraId) {
    _savedCameras.removeWhere((c) => c.id == cameraId);
    _saveCamerasToStorage();
    notifyListeners();
  }

  /// Clear all discovered cameras
  void clearDiscoveredCameras() {
    _discoveredCameras = [];
    notifyListeners();
  }

  /// Test connection to a camera
  Future<bool> testCameraConnection(String ipAddress, int port) async {
    return _discoveryService.testConnection(ipAddress, port);
  }
  
  /// Get list of common RTSP paths to try
  List<String> get commonRtspPaths => OnvifDiscoveryService.commonRtspPaths;

  /// Load saved cameras from local storage
  Future<void> _loadSavedCameras() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final camerasJson = prefs.getStringList('saved_cameras') ?? [];
      
      _savedCameras = camerasJson
          .map((json) => CameraDevice.fromJson(jsonDecode(json)))
          .toList();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading saved cameras: $e');
      _savedCameras = [];
    }
  }

  /// Save cameras to local storage
  Future<void> _saveCamerasToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final camerasJson = _savedCameras
          .map((camera) => jsonEncode(camera.toJson()))
          .toList();
      
      await prefs.setStringList('saved_cameras', camerasJson);
    } catch (e) {
      debugPrint('Error saving cameras: $e');
    }
  }
}