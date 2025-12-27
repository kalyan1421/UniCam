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
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00E5FF)),
            onPressed: () {
              context.read<CameraProvider>().startDiscovery();
            },
            tooltip: 'Rescan Network',
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
                const SliverFillRemaining(
                  child: EmptyState(),
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

  void _showCredentialsDialog(BuildContext context, CameraDevice camera) {
    showDialog(
      context: context,
      builder: (context) => CredentialsDialog(
        camera: camera,
        onSave: (username, password) {
          context.read<CameraProvider>().addDiscoveredCamera(
            camera,
            username: username,
            password: password,
          );
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

