import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';

class BluetoothDeviceWrapper {
  final BluetoothDevice device;
  int rssi;
  String? _cachedName;
  bool _isConnectable = true;

  BluetoothDeviceWrapper({
    required this.device,
    required this.rssi,
    String? name,
  }) {
    if (name != null && name.isNotEmpty) {
      _cachedName = name;
    }
  }

  String get id => device.remoteId.str;

  String get name {
    if (_cachedName != null && _cachedName!.isNotEmpty) {
      return _cachedName!;
    }
    if (device.platformName.isNotEmpty) {
      _cachedName = device.platformName;
      return device.platformName;
    }
    final shortId = device.remoteId.str.substring(
      max(0, device.remoteId.str.length - 5),
    );
    return 'Device $shortId';
  }

  set name(String newName) => _cachedName = newName.isNotEmpty ? newName : _cachedName;
  bool get isESP32Thermo => name.toLowerCase().contains('esp32') || name.toLowerCase().contains('thermo');
  bool get isConnectable => _isConnectable;
  set isConnectable(bool value) => _isConnectable = value;

  @override
  String toString() => 'Device: $name (${device.remoteId.str}), RSSI: $rssi';
}

class BluetoothProvider with ChangeNotifier {
  BluetoothDeviceWrapper? selectedDevice;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _characteristicSubscription;
  bool isConnected = false;
  String temperatureValue = "No reading";
  bool _isReading = false;
  bool get isReading => _isReading;
  bool _isConnecting = false;

  static const String esp32DeviceName = BluetoothConstants.deviceName;
  static const String temperatureServiceUuid = BluetoothConstants.serviceUuid;
  static const String temperatureCharacteristicUuid = BluetoothConstants.characteristicUuid;
  
  bool _isProcessingBluetoothAction = false;
  String _bluetoothActionStatus = "";
  Timer? _stateResetTimer;
  Timer? _updateTimer;

  bool get isProcessingBluetoothAction => _isProcessingBluetoothAction;
  String get bluetoothActionStatus => _bluetoothActionStatus;
  bool get isConnecting => _isConnecting;

  // State management
  void resetConnectionState() {
    if (kDebugMode) print("Resetting Bluetooth connection state flags");
    _isProcessingBluetoothAction = false;
    _bluetoothActionStatus = "";
    _isConnecting = false;
    _stateResetTimer?.cancel();
    _stateResetTimer = null;
    notifyListeners();
  }

  void _safeUpdateState(Function() updateFunction) {
    updateFunction();
    _updateTimer?.cancel();
    _updateTimer = Timer(Duration.zero, notifyListeners);
  }

  // Bluetooth operations
  Future<bool> isBluetoothEnabled() async {
    try {
      return await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
    } catch (e) {
      if (kDebugMode) print("Error checking Bluetooth state: $e");
      return false;
    }
  }

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    
    bool allGranted = true;
    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
        if (kDebugMode) print("$permission not granted. Status: $status");
      }
    });
    return allGranted;
  }

  Future<bool> findAndConnectToESP32() async {
    _safeUpdateState(() {
      _isProcessingBluetoothAction = true;
      _bluetoothActionStatus = "Looking for ESP32-Thermo device...";
      _isConnecting = true;
    });

    try {
      if (!await isBluetoothEnabled()) {
        _safeUpdateState(() {
          _bluetoothActionStatus = "Bluetooth is turned off. Please turn it on.";
          _isProcessingBluetoothAction = false;
          _isConnecting = false;
        });
        return false;
      }

      if (!await requestPermissions()) {
        _safeUpdateState(() {
          _bluetoothActionStatus = "Bluetooth permissions not granted.";
          _isProcessingBluetoothAction = false;
          _isConnecting = false;
        });
        return false;
      }

      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();

      _safeUpdateState(() => _bluetoothActionStatus = "Scanning for ESP32-Thermo device...");

      final completer = Completer<bool>();
      final timeoutTimer = Timer(const Duration(seconds: 30), () => completer.complete(false));
      
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: false);

      final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          final deviceName = result.device.platformName.toLowerCase();
          if (deviceName.contains(esp32DeviceName.toLowerCase()) || 
              (deviceName.contains('esp32') && deviceName.contains('thermo'))) {
            
            if (kDebugMode) print("Found ESP32-Thermo: ${result.device.platformName}");
            
            FlutterBluePlus.stopScan();
            completer.complete(true);
            
            selectedDevice = BluetoothDeviceWrapper(
              device: result.device,
              rssi: result.rssi,
              name: result.device.platformName,
            );
            break;
          }
        }
      }, onError: (e) {
        if (kDebugMode) print("Scan error: $e");
        _safeUpdateState(() {
          _bluetoothActionStatus = "Error during scan: $e";
          _isProcessingBluetoothAction = false;
          _isConnecting = false;
        });
        completer.complete(false);
      });

      final deviceFound = await completer.future;
      timeoutTimer.cancel();
      scanSubscription.cancel();

      if (!deviceFound || selectedDevice == null) {
        _safeUpdateState(() {
          _bluetoothActionStatus = "ESP32-Thermo not found. Ensure it's powered on and nearby.";
          _isProcessingBluetoothAction = false;
          _isConnecting = false;
        });
        return false;
      }

      _safeUpdateState(() => _bluetoothActionStatus = "Connecting to ESP32-Thermo...");
      return await connectToDevice(selectedDevice!);
    } catch (e) {
      if (kDebugMode) print("Error finding/connecting to ESP32-Thermo: $e");
      _safeUpdateState(() {
        _bluetoothActionStatus = "Error: $e";
        _isProcessingBluetoothAction = false;
        _isConnecting = false;
      });
      return false;
    }
  }

  Future<bool> connectToDevice(BluetoothDeviceWrapper device) async {
    _safeUpdateState(() {
      _isConnecting = true;
      _isProcessingBluetoothAction = true;
      _bluetoothActionStatus = "Connecting to ${device.name}...";
    });

    try {
      _stateResetTimer = Timer(const Duration(seconds: 30), () {
        if (_isConnecting) {
          if (kDebugMode) print("Connection attempt timed out");
          resetConnectionState();
        }
      });

      if (device.device.isConnected) {
        await device.device.disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (kDebugMode) print("Attempting to connect to ${device.name}");
      await device.device.connect(autoConnect: false);
      await Future.delayed(const Duration(milliseconds: 500));

_connectionSubscription = device.device.connectionState.listen((state) async {
  if (state == BluetoothConnectionState.connected) {
    if (kDebugMode) {
      print("[BLE] Connected to ${device.name}");
      print("[BLE] Connection state: $state");
    }
    
    await device.device.discoverServices();
    isConnected = true;
    selectedDevice = device;

    _safeUpdateState(() {
      _bluetoothActionStatus = "Connected to ${device.name}";
      _isConnecting = false;
      _isProcessingBluetoothAction = false;
    });

    await _startTemperatureMonitoring();
  } else if (state == BluetoothConnectionState.disconnected) {
    if (kDebugMode) {
      print("[BLE] Disconnected from ${device.name}");
      print("[BLE] Connection state: $state");
    }
    isConnected = false;
    _safeUpdateState(() {
      _bluetoothActionStatus = "Disconnected from ${device.name}";
      _isProcessingBluetoothAction = false;
      _isConnecting = false;
    });
  }
});
      _stateResetTimer?.cancel();
      _stateResetTimer = null;
      return true;
    } catch (e) {
      if (kDebugMode) print("Error connecting to device: $e");
      _safeUpdateState(() {
        _bluetoothActionStatus = "Connection failed: $e";
        _isProcessingBluetoothAction = false;
        _isConnecting = false;
      });
      return false;
    }
  }
Future<void> _startTemperatureMonitoring() async {
  if (selectedDevice == null || !isConnected) {
    if (kDebugMode) print("[BLE] ❌ Cannot start monitoring - no connected device");
    return;
  }

  try {
    if (kDebugMode) print("[BLE] 🔄 Starting temperature monitoring...");
    _safeUpdateState(() => _isReading = true);
    
    // Cancel any existing subscription first
    if (_characteristicSubscription != null) {
      if (kDebugMode) print("[BLE] 🔄 Cancelling existing characteristic subscription");
      await _characteristicSubscription?.cancel();
      _characteristicSubscription = null;
    }

    if (kDebugMode) print("[BLE] 🔍 Discovering services...");
    final services = await selectedDevice!.device.discoverServices();
    if (kDebugMode) print("[BLE] ✅ Found ${services.length} services");

    // Log all services and characteristics for debugging
    if (kDebugMode) {
      for (var service in services) {
        print("[BLE] 🔧 Service UUID: ${service.uuid}");
        for (var char in service.characteristics) {
          print("[BLE]   🔹 Characteristic: ${char.uuid} (Properties: ${char.properties})");
        }
      }
    }

    BluetoothService? tempService;
    try {
      tempService = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == temperatureServiceUuid.toLowerCase(),
      );
      if (kDebugMode) print("[BLE] ✅ Found temperature service: ${tempService.uuid}");
    } catch (e) {
      if (kDebugMode) print("[BLE] ❌ Temperature service not found: $e");
      throw Exception("Temperature service not found");
    }

    BluetoothCharacteristic? tempCharacteristic;
    try {
      tempCharacteristic = tempService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == temperatureCharacteristicUuid.toLowerCase(),
      );
      if (kDebugMode) {
        print("[BLE] ✅ Found temperature characteristic: ${tempCharacteristic.uuid}");
        print("[BLE] 🔹 Characteristic properties: ${tempCharacteristic.properties}");
      }
    } catch (e) {
      if (kDebugMode) print("[BLE] ❌ Temperature characteristic not found: $e");
      throw Exception("Temperature characteristic not found");
    }

    // Verify characteristic supports notifications
    if (!tempCharacteristic.properties.notify) {
      if (kDebugMode) print("[BLE] ❌ Characteristic does not support notifications");
      throw Exception("Characteristic does not support notifications");
    }

    // Create a completer to manage the monitoring session
    final completer = Completer<void>();
    int readingCount = 0;
    const maxReadings = 10;

    if (kDebugMode) print("[BLE] 🔔 Setting up notifications...");
    await tempCharacteristic.setNotifyValue(true);
    if (kDebugMode) print("[BLE] ✅ Notifications enabled successfully");
    
    _characteristicSubscription = tempCharacteristic.onValueReceived.listen(
      (data) {
        readingCount++;
        if (kDebugMode) {
          print("\n[BLE] 📡 Received data packet #$readingCount");
          print("[BLE] 📦 Raw data bytes: ${data.join(', ')}");
          print("[BLE] 📦 Data length: ${data.length} bytes");
        }
        
        _processTemperatureData(data);
        
        if (readingCount >= maxReadings) {
          if (!completer.isCompleted) {
            if (kDebugMode) print("[BLE] 🔚 Reached max readings of $maxReadings");
            completer.complete();
          }
        }
      },
      onError: (error) {
        if (kDebugMode) print("[BLE] ❌ Notification error: $error");
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (kDebugMode) print("[BLE] 🔚 Notification stream closed by remote device");
      },
      cancelOnError: true,
    );

    // Set timeout for safety
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        if (kDebugMode) print("[BLE] ⏰ Monitoring timeout reached (30s)");
        completer.complete();
      }
    });

    if (kDebugMode) print("[BLE] 👂 Listening for temperature readings...");
    await completer.future;
    if (kDebugMode) print("[BLE] ✅ Monitoring session completed");

    // Clean up
    if (kDebugMode) print("[BLE] 🧹 Cleaning up resources...");
    await tempCharacteristic.setNotifyValue(false);
    await _characteristicSubscription?.cancel();
    _characteristicSubscription = null;
    if (kDebugMode) print("[BLE] ✅ Resources cleaned up");

    _safeUpdateState(() => _isReading = false);

  } catch (e) {
    if (kDebugMode) print("[BLE] ❌ Error in temperature monitoring: $e");
    _safeUpdateState(() {
      temperatureValue = "Error: ${e.toString()}";
      _isReading = false;
    });
    
    // Ensure resources are cleaned up even on error
    await _characteristicSubscription?.cancel();
    _characteristicSubscription = null;
    if (kDebugMode) print("[BLE] 🧹 Cleaned up resources after error");
  }
}

void _processTemperatureData(List<int> data) {
  try {
    if (kDebugMode) print("[DATA] 🔄 Processing received data...");
    
    // First try UTF-8 decoding
    String tempString;
    try {
      tempString = utf8.decode(data).trim();
      if (kDebugMode) print("[DATA] 🔤 UTF-8 decoded: $tempString");
    } catch (_) {
      // Fallback to ASCII decoding if UTF-8 fails
      tempString = String.fromCharCodes(data).trim();
      if (kDebugMode) print("[DATA] 🔤 ASCII decoded: $tempString");
    }

    // Clean the string
    tempString = tempString
        .replaceAll('°C', '')
        .replaceAll('°', '')
        .replaceAll('C', '')
        .trim();

    if (kDebugMode) print("[DATA] ✨ Cleaned string: $tempString");

    // Try to parse as double
    final tempValue = double.tryParse(tempString);
    
    if (tempValue != null) {
      if (kDebugMode) print("[DATA] ✅ Parsed temperature: $tempValue°C");
      _safeUpdateState(() {
        temperatureValue = '${tempValue.toStringAsFixed(1)}°C';
        _isReading = true;
      });
    } else {
      if (kDebugMode) print("[DATA] ❌ Failed to parse temperature from: $tempString");
      _safeUpdateState(() {
        temperatureValue = 'Raw: ${data.join(', ')}';
        _isReading = false;
      });
    }
  } catch (e) {
    if (kDebugMode) print("[DATA] ❌ Processing error: $e");
    _safeUpdateState(() {
      temperatureValue = "Invalid data";
      _isReading = false;
    });
  }
}

 

  double? getTemperatureAsDouble() {
    if (temperatureValue == "No reading" ||
        temperatureValue.startsWith("Error") ||
        temperatureValue.startsWith("Invalid") ||
        temperatureValue.startsWith("Service") ||
        temperatureValue.startsWith("Characteristic")) {
      return null;
    }

    try {
      final sanitized = temperatureValue
          .replaceAll('°C', '')
          .replaceAll('°', '')
          .replaceAll('C', '')
          .trim();
      return double.parse(sanitized);
    } catch (e) {
      if (kDebugMode) print("Error parsing temperature value: $e");
      return null;
    }
  }

  Future<void> startTemperatureReading() async {
    if (!isConnected || selectedDevice == null) return;

    _safeUpdateState(() {
      _isReading = true;
      _bluetoothActionStatus = "Reading temperature...";
    });

    try {
      await _startTemperatureMonitoring();
    } catch (e) {
      if (kDebugMode) print("Error starting temperature reading: $e");
      _safeUpdateState(() {
        _isReading = false;
        temperatureValue = "Error reading temperature";
      });
    }
  }

  Future<void> disconnect() async {
    _safeUpdateState(() {
      _isProcessingBluetoothAction = true;
      _bluetoothActionStatus = "Disconnecting...";
    });

    try {
      _connectionSubscription?.cancel();
      _connectionSubscription = null;
      _characteristicSubscription?.cancel();
      _characteristicSubscription = null;

      if (selectedDevice != null && selectedDevice!.device.isConnected) {
        await selectedDevice!.device.disconnect();
      }

      _safeUpdateState(() {
        isConnected = false;
        _isReading = false;
        temperatureValue = "No reading";
        _bluetoothActionStatus = "Disconnected";
        _isProcessingBluetoothAction = false;
      });
    } catch (e) {
      if (kDebugMode) print("Error disconnecting: $e");
      _safeUpdateState(() {
        _bluetoothActionStatus = "Error disconnecting: $e";
        _isProcessingBluetoothAction = false;
      });
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _stateResetTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }
}