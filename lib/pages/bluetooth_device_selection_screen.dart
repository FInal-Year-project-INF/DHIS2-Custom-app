import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/bluetooth_provider.dart';
import '../constants/app_constants.dart';

class BluetoothDeviceSelectionScreen extends StatefulWidget {
  const BluetoothDeviceSelectionScreen({Key? key}) : super(key: key);

  @override
  State<BluetoothDeviceSelectionScreen> createState() =>
      _BluetoothDeviceSelectionScreenState();
}

class _BluetoothDeviceSelectionScreenState
    extends State<BluetoothDeviceSelectionScreen> {
  // State to track if a connection is in progress
  bool _isConnecting = false;

  // Status message displayed to the user
  String _statusMessage = "Looking for ESP32-Thermo device...";

  @override
  void initState() {
    super.initState();
    // Attempt to connect to the ESP32 device when screen loads
    _connectToESP32();
  }

  // Attempts to connect to the ESP32 Bluetooth device
  Future<void> _connectToESP32() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = "Looking for ESP32-Thermo device...";
    });

    final bluetoothProvider = Provider.of<BluetoothProvider>(
      context,
      listen: false,
    );

    try {
      bool success = await bluetoothProvider.findAndConnectToESP32();

      if (!mounted) return;

      if (success) {
        // Close the screen on successful connection
        Navigator.of(context).pop();
      } else {
        // Show failure message
        setState(() {
          _isConnecting = false;
          _statusMessage =
              "Failed to connect to ESP32-Thermo device. Tap to retry.";
        });
      }
    } catch (e) {
      // Handle error during connection
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
        _statusMessage = "Error: $e. Tap to retry.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Thermometer'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<BluetoothProvider>(
        builder: (context, bluetoothProvider, child) {
          // Determine the status message to show
          String displayStatus = _statusMessage;

          if (bluetoothProvider.isProcessingBluetoothAction &&
              bluetoothProvider.bluetoothActionStatus.isNotEmpty) {
            displayStatus = bluetoothProvider.bluetoothActionStatus;
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Thermometer icon
                _buildDeviceIcon(),

                const SizedBox(height: 24),

                // Device name
                _buildTitle(),

                const SizedBox(height: 16),

                // Current connection status message
                _buildStatusMessage(displayStatus),

                const SizedBox(height: 32),

                // Show loading spinner or retry button
                _buildActionButton(bluetoothProvider),
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget for displaying the thermometer icon
  Widget _buildDeviceIcon() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(50),
      ),
      child: const Icon(
        Icons.thermostat_rounded,
        color: Colors.blue,
        size: 60,
      ),
    );
  }

  // Widget for the title text
  Widget _buildTitle() {
    return const Text(
      'ESP32-Thermo Device',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Colors.blue,
      ),
    );
  }

  // Widget for showing the connection status message
  Widget _buildStatusMessage(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
      ),
    );
  }

  // Widget for the action button or loading indicator
  Widget _buildActionButton(BluetoothProvider bluetoothProvider) {
    if (_isConnecting || bluetoothProvider.isConnecting) {
      // Show loading spinner while connecting
      return const CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
      );
    }

    // Retry button if not connecting
    return ElevatedButton.icon(
      onPressed: _connectToESP32,
      icon: const Icon(Icons.refresh),
      label: const Text('Try Again'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
      ),
    );
  }
}
