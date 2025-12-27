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
  String _scanStatus = '';
  String? _errorMessage;
  
  // Getters
  List<CameraDevice> get savedCameras => List.unmodifiable(_savedCameras);
  List<CameraDevice> get discoveredCameras => List.unmodifiable(_discoveredCameras);
  bool get isScanning => _isScanning;
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

  /// Start ONVIF discovery scan
  Future<void> startDiscovery() async {
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
          ? 'No cameras found. Try manual addition.'
          : 'Found ${cameras.length} camera(s)';
    } catch (e) {
      _errorMessage = 'Discovery failed: $e';
      _scanStatus = 'Error during discovery';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Add a discovered camera to saved list
  void addDiscoveredCamera(CameraDevice camera, {String? username, String? password}) {
    if (!isCameraSaved(camera)) {
      final updatedCamera = camera.copyWith(
        username: username ?? '',
        password: password ?? '',
      );
      _savedCameras.add(updatedCamera);
      _saveCamerasToStorage();
      notifyListeners();
    }
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
      print('Error loading saved cameras: $e');
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
      print('Error saving cameras: $e');
    }
  }
}

