# CCTV Open

A Flutter app prototype for managing IP cameras with ONVIF discovery and RTSP streaming.

## Features

- **ONVIF Discovery**: Automatically discover IP cameras on your local network using WS-Discovery protocol
- **Manual Camera Addition**: Add cameras manually by entering IP, port, and credentials
- **RTSP Streaming**: Live video streaming from IP cameras
- **Camera Management**: Save, organize, and manage your cameras

## Tech Stack

- **Flutter** - Cross-platform mobile framework
- **Provider** - State management
- **media_kit** - Video player for RTSP streaming
- **xml** - ONVIF XML response parsing

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── camera_device.dart    # Camera data model
├── providers/
│   └── camera_provider.dart  # State management
├── services/
│   └── onvif_service.dart    # ONVIF discovery logic
├── screens/
│   ├── home_screen.dart      # Main screen with camera list
│   ├── add_camera_screen.dart # Manual camera addition
│   ├── stream_view_screen.dart # RTSP video player
│   └── credentials_dialog.dart # Credentials entry dialog
└── widgets/
    ├── camera_list_tile.dart   # Camera list items
    ├── scanning_indicator.dart # Scanning animation
    └── empty_state.dart        # Empty state view
```

## Getting Started

### Prerequisites

- Flutter SDK (3.8.0 or higher)
- Android Studio / Xcode for mobile development

### Installation

1. Clone the repository:
```bash
cd CCTVOPEN
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## How It Works

### 1. Discovery Flow
```
UDP Broadcast → Parse XML → List IPs
```
The app sends a WS-Discovery probe to the multicast address `239.255.255.250:3702` and parses ONVIF responses to discover cameras.

### 2. Camera Addition Flow
```
User selects IP → Prompts for User/Pass → Saves to List
```
Discovered cameras can be added with credentials, or cameras can be added manually with full configuration.

### 3. Streaming Flow
```
User taps saved camera → App builds RTSP URL → Video Player opens
```
RTSP URLs are constructed as: `rtsp://user:pass@ip:port/path`

## Permissions

### Android
- `INTERNET` - Network access
- `ACCESS_NETWORK_STATE` - Network state detection
- `ACCESS_WIFI_STATE` - WiFi state detection
- `CHANGE_WIFI_MULTICAST_STATE` - UDP multicast for ONVIF discovery

### iOS
- `NSLocalNetworkUsageDescription` - Local network access for camera discovery
- `NSAppTransportSecurity` - Allow cleartext traffic for RTSP

## Common RTSP Paths

Different camera manufacturers use different RTSP paths:
- `/stream1` - Generic
- `/live/ch0` - Hikvision
- `/h264` - Various
- `/Streaming/Channels/1` - Hikvision
- `/cam/realmonitor` - Dahua

## License

This project is for prototyping purposes.
