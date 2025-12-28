import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/camera_device.dart';
import '../providers/camera_provider.dart';
import '../services/onvif_service.dart';

/// Screen for viewing RTSP camera stream
class StreamViewScreen extends StatefulWidget {
  final CameraDevice camera;

  const StreamViewScreen({super.key, required this.camera});

  @override
  State<StreamViewScreen> createState() => _StreamViewScreenState();
}

class _StreamViewScreenState extends State<StreamViewScreen> {
  late final Player _player;
  late final VideoController _controller;
  late CameraDevice _currentCamera;
  
  bool _showControls = true;
  bool _isBuffering = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isPlaying = false;
  int _connectionAttempts = 0;
  String _currentRtspPath = '';
  bool _isUsingPublicConnection = false;

  @override
  void initState() {
    super.initState();
    _currentCamera = widget.camera;
    _currentRtspPath = widget.camera.rtspPath;
    
    // Set landscape orientation for video viewing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    
    // Enable wakelock to keep screen on during streaming
    WakelockPlus.enable();
    
    // Initialize media_kit player
    _player = Player();
    
    // FIX: Configure VideoController for software rendering compatibility
    // This fixes "Format allocation info not found" errors on some devices
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false, // Disable hardware acceleration for stability
        androidAttachSurfaceAfterVideoParameters: true, // Fix for some Android rendering issues
      ),
    );
    
    // Listen to player state
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });
    
    _player.stream.buffering.listen((buffering) {
      if (mounted) {
        setState(() => _isBuffering = buffering);
      }
    });
    
    _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        print('[Stream] Error: $error');
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
      }
    });
    
    // Start playing the stream
    _initializeStream();
  }

  Future<void> _initializeStream() async {
    _connectionAttempts++;
    bool usePublic = false;
    
    setState(() {
      _hasError = false;
      _isBuffering = true;
      _errorMessage = '';
    });

    try {
      // 1. Try Local Connection First (Fast check using HTTP HEAD request)
      // This is more reliable than raw socket for apps like IP Webcam
      print('[Stream] Testing Local Connection: ${_currentCamera.ipAddress}:${_currentCamera.port}');
      bool localReachable = false;
      try {
        final httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        final request = await httpClient.headUrl(
          Uri.parse('http://${_currentCamera.ipAddress}:${_currentCamera.port}/'),
        ).timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(const Duration(seconds: 3));
        await response.drain();
        httpClient.close();
        localReachable = true;
        print('✅ Local Connection Available (HTTP response: ${response.statusCode})');
      } catch (httpError) {
        // HTTP failed, try raw socket as fallback
        print('⚠️ HTTP check failed, trying socket: $httpError');
        try {
          await Socket.connect(
            _currentCamera.ipAddress, 
            _currentCamera.port, 
            timeout: const Duration(seconds: 2),
          ).then((socket) => socket.destroy());
          localReachable = true;
          print('✅ Local Connection Available (Socket)');
        } catch (socketError) {
          print('⚠️ Socket check also failed: $socketError');
        }
      }
      
      if (!localReachable) {
        // 2. Local failed? Check if we have Public IP Configured
        if (_currentCamera.hasRemoteAccess) {
          print('⚠️ Switching to Public IP: ${_currentCamera.publicIpAddress}');
          usePublic = true;
        } else {
          // No public IP configured, try local anyway (RTSP might still work)
          print('ℹ️ No public IP configured, attempting RTSP stream anyway');
        }
      }

      // Update connection state
      setState(() {
        _isUsingPublicConnection = usePublic;
      });

      // 3. Generate URL based on the result using the model's helper method
      final rtspUrl = _buildRtspUrl(_currentRtspPath, usePublic: usePublic);
      
      print('[Stream] Attempt #$_connectionAttempts - Opening: $rtspUrl');
      
      await _player.open(
        Media(rtspUrl),
        play: true,
      );
      
      // Show connection type notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              Icon(
                usePublic ? Icons.public_rounded : Icons.wifi_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(usePublic ? 'Connected via Internet (Remote)' : 'Connected via Wi-Fi (Local)'),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: usePublic ? Colors.orange.shade700 : Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ));
      }

    } catch (e) {
      print('[Stream] Exception: $e');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  String _buildRtspUrl(String path, {bool usePublic = false}) {
    final camera = _currentCamera;
    
    // Determine which IP and Port to use
    final targetIp = (usePublic && camera.publicIpAddress != null && camera.publicIpAddress!.isNotEmpty) 
        ? camera.publicIpAddress! 
        : camera.ipAddress;
        
    final targetPort = (usePublic && camera.publicPort != null) 
        ? camera.publicPort! 
        : camera.port;
    
    if (camera.username.isNotEmpty && camera.password.isNotEmpty) {
      final encodedUser = Uri.encodeComponent(camera.username);
      final encodedPass = Uri.encodeComponent(camera.password);
      return 'rtsp://$encodedUser:$encodedPass@$targetIp:$targetPort$path';
    }
    return 'rtsp://$targetIp:$targetPort$path';
  }

  Future<void> _tryPath(String newPath) async {
    setState(() {
      _currentRtspPath = newPath;
      _hasError = false;
      _isBuffering = true;
    });
    
    // Update camera with new path
    _currentCamera = _currentCamera.copyWith(rtspPath: newPath);
    
    await _player.stop();
    await _initializeStream();
  }

  void _showPathSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141A22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PathSelectorSheet(
        currentPath: _currentRtspPath,
        onPathSelected: (path) {
          Navigator.pop(context);
          _tryPath(path);
        },
        onCustomPath: () {
          Navigator.pop(context);
          _showCustomPathDialog();
        },
      ),
    );
  }

  void _showCustomPathDialog() {
    final controller = TextEditingController(text: _currentRtspPath);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Custom RTSP Path', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the RTSP path for your camera:',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: '/stream1',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: const Icon(Icons.link, color: Color(0xFF00E5FF)),
                filled: true,
                fillColor: const Color(0xFF0A0E14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Full URL: rtsp://${_currentCamera.ipAddress}:${_currentCamera.port}${controller.text}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final path = controller.text.isEmpty ? '/stream1' : controller.text;
              _tryPath(path.startsWith('/') ? path : '/$path');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
            ),
            child: const Text('Try Path'),
          ),
        ],
      ),
    );
  }

  void _saveCurrentPath() {
    final provider = context.read<CameraProvider>();
    provider.updateCamera(_currentCamera);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved path: $_currentRtspPath'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    // Disable wakelock when leaving stream view
    WakelockPlus.disable();
    
    // Reset orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    
    _player.dispose();
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  void _togglePlayPause() {
    _player.playOrPause();
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _isBuffering = true;
    });
    await _initializeStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video player
            Center(
              child: _hasError
                  ? _buildErrorState()
                  : Video(
                      controller: _controller,
                      fit: BoxFit.contain,
                    ),
            ),
            
            // Buffering indicator
            if (_isBuffering && !_hasError)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF00E5FF),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Connecting...',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentRtspPath,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Controls overlay
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _buildControlsOverlay(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
            ),
            child: const Icon(
              Icons.videocam_off_rounded,
              size: 64,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Stream Unavailable',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The RTSP path "$_currentRtspPath" might be incorrect for this camera.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          
          // Current URL display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isUsingPublicConnection ? Icons.public_rounded : Icons.wifi_rounded,
                      color: _isUsingPublicConnection ? Colors.orange : Colors.white.withOpacity(0.5),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isUsingPublicConnection ? 'Tried URL (Remote):' : 'Tried URL (Local):',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _buildRtspUrl(_currentRtspPath, usePublic: _isUsingPublicConnection).replaceAll(RegExp(r':[^:@]+@'), ':****@'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          
          // Show remote access tip if not configured
          if (!_currentCamera.hasRemoteAccess) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tips_and_updates_rounded, color: Color(0xFF00E5FF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tip: Configure Remote Access in camera settings to view from anywhere',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red.withOpacity(0.8),
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 24),
          
          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _retry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Retry'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _showPathSelector,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.route_rounded, size: 20),
                label: const Text('Try Different Path'),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Back button
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Go Back'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.7),
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Back button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Camera name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentCamera.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(
                              _isUsingPublicConnection ? Icons.public_rounded : Icons.wifi_rounded,
                              color: _isUsingPublicConnection ? Colors.orange : Colors.white.withOpacity(0.6),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isUsingPublicConnection 
                                  ? '${_currentCamera.publicIpAddress}' 
                                  : _currentCamera.ipAddress,
                              style: TextStyle(
                                color: _isUsingPublicConnection ? Colors.orange : Colors.white.withOpacity(0.6),
                                fontSize: 13,
                              ),
                            ),
                            if (_isUsingPublicConnection) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'REMOTE',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Settings button
                  IconButton(
                    onPressed: _showPathSelector,
                    icon: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white70,
                      size: 24,
                    ),
                    tooltip: 'Change RTSP Path',
                  ),
                  const SizedBox(width: 8),
                  // Live badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isPlaying && !_isBuffering
                          ? Colors.red
                          : Colors.grey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: _isPlaying && !_isBuffering
                                ? [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const Spacer(),
            
            // Bottom controls
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Play/Pause button
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Stream info
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: GestureDetector(
                onTap: _showPathSelector,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.link_rounded,
                        color: Colors.white.withOpacity(0.6),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _currentRtspPath,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.edit_rounded,
                        color: Colors.white.withOpacity(0.4),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for selecting RTSP path
class _PathSelectorSheet extends StatelessWidget {
  final String currentPath;
  final Function(String) onPathSelected;
  final VoidCallback onCustomPath;

  const _PathSelectorSheet({
    required this.currentPath,
    required this.onPathSelected,
    required this.onCustomPath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Title
          const Text(
            'Select RTSP Path',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Different camera brands use different stream paths. Try these common options:',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          
          // Path options
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _PathOption(
                    path: '/stream1',
                    description: 'Generic / Default',
                    isSelected: currentPath == '/stream1',
                    onTap: () => onPathSelected('/stream1'),
                  ),
                  _PathOption(
                    path: '/h264_ulaw.sdp',
                    description: 'Android IP Webcam App',
                    isSelected: currentPath == '/h264_ulaw.sdp',
                    onTap: () => onPathSelected('/h264_ulaw.sdp'),
                  ),
                  _PathOption(
                    path: '/Streaming/Channels/101',
                    description: 'Hikvision Main Stream',
                    isSelected: currentPath == '/Streaming/Channels/101',
                    onTap: () => onPathSelected('/Streaming/Channels/101'),
                  ),
                  _PathOption(
                    path: '/Streaming/Channels/102',
                    description: 'Hikvision Sub Stream',
                    isSelected: currentPath == '/Streaming/Channels/102',
                    onTap: () => onPathSelected('/Streaming/Channels/102'),
                  ),
                  _PathOption(
                    path: '/cam/realmonitor?channel=1&subtype=0',
                    description: 'Dahua Main Stream',
                    isSelected: currentPath == '/cam/realmonitor?channel=1&subtype=0',
                    onTap: () => onPathSelected('/cam/realmonitor?channel=1&subtype=0'),
                  ),
                  _PathOption(
                    path: '/live/ch0',
                    description: 'Generic Live',
                    isSelected: currentPath == '/live/ch0',
                    onTap: () => onPathSelected('/live/ch0'),
                  ),
                  _PathOption(
                    path: '/h264',
                    description: 'H.264 Stream',
                    isSelected: currentPath == '/h264',
                    onTap: () => onPathSelected('/h264'),
                  ),
                  _PathOption(
                    path: '/axis-media/media.amp',
                    description: 'Axis Cameras',
                    isSelected: currentPath == '/axis-media/media.amp',
                    onTap: () => onPathSelected('/axis-media/media.amp'),
                  ),
                  _PathOption(
                    path: '/onvif1',
                    description: 'ONVIF Stream 1',
                    isSelected: currentPath == '/onvif1',
                    onTap: () => onPathSelected('/onvif1'),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Custom path button
          OutlinedButton.icon(
            onPressed: onCustomPath,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
              side: const BorderSide(color: Color(0xFF00E5FF)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Enter Custom Path'),
          ),
        ],
      ),
    );
  }
}

class _PathOption extends StatelessWidget {
  final String path;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _PathOption({
    required this.path,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected 
            ? const Color(0xFF00E5FF).withOpacity(0.15)
            : const Color(0xFF0A0E14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected 
                    ? const Color(0xFF00E5FF)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        path,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF00E5FF) : Colors.white,
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF00E5FF),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
