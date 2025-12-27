import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'providers/camera_provider.dart';
import 'screens/home_screen.dart';
import 'services/permission_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize media_kit
  MediaKit.ensureInitialized();
  
  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0E14),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  
  runApp(const CCTVOpenApp());
}

class CCTVOpenApp extends StatelessWidget {
  const CCTVOpenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => CameraProvider(),
      child: MaterialApp(
        title: 'CCTV Open',
        debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0A0E14),
          primaryColor: const Color(0xFF00E5FF),
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFF00E5FF),
            secondary: const Color(0xFF00E5FF),
            surface: const Color(0xFF141A22),
            onPrimary: const Color(0xFF0A0E14),
            onSecondary: const Color(0xFF0A0E14),
            onSurface: Colors.white,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF141A22),
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
          ),
          cardTheme: CardThemeData(
            color: const Color(0xFF141A22),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: const Color(0xFF0A0E14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
              side: const BorderSide(color: Color(0xFF00E5FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF141A22),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E2832)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E2832)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF00E5FF)),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            backgroundColor: const Color(0xFF141A22),
            contentTextStyle: const TextStyle(color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            behavior: SnackBarBehavior.floating,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: const Color(0xFF141A22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF00E5FF),
            foregroundColor: Color(0xFF0A0E14),
          ),
        ),
        home: const PermissionWrapper(child: HomeScreen()),
      ),
    );
  }
}

/// Wrapper widget that handles permission requests on app startup
class PermissionWrapper extends StatefulWidget {
  final Widget child;
  
  const PermissionWrapper({super.key, required this.child});

  @override
  State<PermissionWrapper> createState() => _PermissionWrapperState();
}

class _PermissionWrapperState extends State<PermissionWrapper> {
  bool _permissionsChecked = false;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    // Request permissions after first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndRequestPermissions();
    });
  }

  Future<void> _checkAndRequestPermissions() async {
    // First check if permissions are already granted
    final hasPermissions = await PermissionService.hasRequiredPermissions();
    
    if (hasPermissions) {
      setState(() {
        _permissionsChecked = true;
        _permissionsGranted = true;
      });
      return;
    }

    // Show welcome dialog explaining why we need permissions
    if (mounted) {
      final shouldRequest = await _showWelcomeDialog();
      
      if (shouldRequest && mounted) {
        final granted = await PermissionService.requestPermissions(context);
        setState(() {
          _permissionsChecked = true;
          _permissionsGranted = granted;
        });
      } else {
        setState(() {
          _permissionsChecked = true;
          _permissionsGranted = false;
        });
      }
    }
  }

  Future<bool> _showWelcomeDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141A22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            // Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: Color(0xFF00E5FF),
                size: 48,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Welcome to CCTV Open',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'To automatically discover cameras on your network, '
              'we need permission to access your local network.\n\n'
              'This allows the app to find ONVIF-compatible IP cameras.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Permission icons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PermissionIcon(
                  icon: Icons.wifi_find_rounded,
                  label: 'Network\nDiscovery',
                ),
                const SizedBox(width: 24),
                _PermissionIcon(
                  icon: Icons.videocam_rounded,
                  label: 'Camera\nStreaming',
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Skip',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E5FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text(
              'Allow Access',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while checking permissions
    if (!_permissionsChecked) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E14),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF00E5FF)),
              SizedBox(height: 24),
            Text(
                'Setting up...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
            ),
          ],
        ),
      ),
      );
    }
    
    return widget.child;
  }
}

class _PermissionIcon extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PermissionIcon({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2832),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF00E5FF), size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
