import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';
import '../models/camera_device.dart';
import '../widgets/camera_list_tile.dart';
import '../widgets/scanning_indicator.dart';
import '../widgets/empty_state.dart';
import 'add_camera_screen.dart';
import 'stream_view_screen.dart';
import 'credentials_dialog.dart';

/// Home screen with camera discovery and saved cameras list
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141A22),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Color(0xFF00E5FF),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'CCTV Open',
              style: TextStyle(
                fontFamily: 'SpaceMono',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          // Scan options menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.wifi_find_rounded, color: Color(0xFF00E5FF)),
            tooltip: 'Scan Options',
            color: const Color(0xFF141A22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              final provider = context.read<CameraProvider>();
              switch (value) {
                case 'full':
                  provider.startDiscovery();
                  break;
                case 'onvif':
                  provider.startOnvifDiscovery();
                  break;
                case 'generic':
                  provider.startGenericScan();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'full',
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 20),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Full Scan',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'ONVIF + Generic cameras',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'onvif',
                child: Row(
                  children: [
                    const Icon(Icons.wifi_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ONVIF Only',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Professional IP cameras',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'generic',
                child: Row(
                  children: [
                    const Icon(Icons.phone_android_rounded, color: Colors.orange, size: 20),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generic Scan',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'IP Webcam, Phone cameras',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<CameraProvider>(
        builder: (context, provider, child) {
          return CustomScrollView(
            slivers: [
              // Scanning indicator or scan button
              SliverToBoxAdapter(
                child: _buildScanSection(context, provider),
              ),
              
              // Discovered cameras section
              if (provider.hasDiscoveredCameras) ...[
                const SliverToBoxAdapter(
                  child: _SectionHeader(title: 'Discovered Cameras'),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final camera = provider.discoveredCameras[index];
                      final isSaved = provider.isCameraSaved(camera);
                      return DiscoveredCameraTile(
                        camera: camera,
                        isSaved: isSaved,
                        onAdd: () => _showCredentialsDialog(context, camera),
                      );
                    },
                    childCount: provider.discoveredCameras.length,
                  ),
                ),
              ],
              
              // Saved cameras section
              if (provider.hasSavedCameras) ...[
                const SliverToBoxAdapter(
                  child: _SectionHeader(title: 'My Cameras'),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final camera = provider.savedCameras[index];
                      return SavedCameraTile(
                        camera: camera,
                        onTap: () => _openStream(context, camera),
                        onDelete: () => _confirmDelete(context, camera),
                      );
                    },
                    childCount: provider.savedCameras.length,
                  ),
                ),
              ],
              
              // Empty state
              if (!provider.isScanning && 
                  !provider.hasDiscoveredCameras && 
                  !provider.hasSavedCameras)
                SliverFillRemaining(
                  child: _buildEmptyState(context),
                ),
              
              // Bottom padding
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddCamera(context),
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: const Color(0xFF0A0E14),
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Camera',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildScanSection(BuildContext context, CameraProvider provider) {
    if (provider.isScanning) {
      return ScanningIndicator(status: provider.scanStatus);
    }
    
    if (!provider.hasSavedCameras && !provider.hasDiscoveredCameras) {
      return const SizedBox.shrink(); // Empty state handles this
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF141A22),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF00E5FF).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.videocam_off_rounded,
                size: 80,
                color: Colors.white.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Cameras Added',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Scan your network or add cameras manually',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            
            // Scan options
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _QuickScanButton(
                  icon: Icons.search_rounded,
                  label: 'Full Scan',
                  color: const Color(0xFF00E5FF),
                  onTap: () => context.read<CameraProvider>().startDiscovery(),
                ),
                _QuickScanButton(
                  icon: Icons.phone_android_rounded,
                  label: 'IP Webcam',
                  color: Colors.orange,
                  onTap: () => context.read<CameraProvider>().startGenericScan(),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Or divider
            Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Manual add button
            OutlinedButton.icon(
              onPressed: () => _navigateToAddCamera(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Add Manually'),
            ),
            
            const SizedBox(height: 32),
            
            // Tips
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.blue.shade300, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tips',
                        style: TextStyle(
                          color: Colors.blue.shade300,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Use "IP Webcam" scan for phone cameras\n'
                    '• Use "Full Scan" for professional ONVIF cameras\n'
                    '• Make sure cameras are on the same WiFi network',
                    style: TextStyle(
                      color: Colors.blue.shade200,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCredentialsDialog(BuildContext context, CameraDevice camera) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => CredentialsDialog(
        camera: camera,
        onSave: (username, password) async {
          // Show loading indicator
          showDialog(
            context: dialogContext,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: Card(
                color: Color(0xFF141A22),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF00E5FF)),
                      SizedBox(height: 16),
                      Text(
                        'Fetching stream info...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          
          // Add camera (this now fetches RTSP URL via ONVIF if available)
          await context.read<CameraProvider>().addDiscoveredCamera(
            camera,
            username: username,
            password: password,
          );
          
          // Close loading dialog
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        },
      ),
    );
  }

  void _openStream(BuildContext context, CameraDevice camera) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StreamViewScreen(camera: camera),
      ),
    );
  }

  void _confirmDelete(BuildContext context, CameraDevice camera) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove Camera?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to remove "${camera.name}"?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<CameraProvider>().removeCamera(camera.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _navigateToAddCamera(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddCameraScreen()),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.6),
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickScanButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickScanButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}