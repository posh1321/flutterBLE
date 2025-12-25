import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ble = FlutterReactiveBle();
  DiscoveredDevice? _device;
  bool _connected = false;
  bool _turnOn = false;
  late StreamSubscription<ConnectionStateUpdate> _connection;
  bool _scanning = false;

  // UUID of the service and characteristic to write ON/OFF
  final Uuid serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
  final Uuid charUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");

  Future<bool> _requestBlePermissions() async {
    if (Platform.isAndroid) {
      // Android 12+ (SDK 31+)
      final permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];

      final statuses = await permissions.request();

      return statuses.values.every((status) => status.isGranted);
    } else if (Platform.isIOS) {
        return true;
    }
    return false;
  }

  void _scanDevices() async {
    if (_scanning) return;

    final granted = await _requestBlePermissions();
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth permissions not granted')),
      );
      return;
    }

    setState(() => _scanning = true);

    List<DiscoveredDevice> devices = [];

    final subscription = _ble.scanForDevices(withServices: []).listen((device) {
      if (!devices.any((d) => d.id == device.id)) {
        devices.add(device);
      }
    });

    // Scan 5 sekundi
    await Future.delayed(Duration(seconds: 5));
    await subscription.cancel();

    setState(() => _scanning = false);

    if (devices.isNotEmpty) {
      DiscoveredDevice? selected = await showDialog(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Select device'),
          children: devices.map((d) => SimpleDialogOption(
            onPressed: () => Navigator.pop(context, d),
            child: Text('${d.name.isEmpty ? "Unknown" : d.name} (${d.id})'),
          )).toList(),
        ),
      );

      if (selected != null) {
        setState(() => _device = selected);
        _connect();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No devices found')),
      );
    }
  }

  void _connect() {
    if (_device == null) return;

    _connection = _ble.connectToDevice(
      id: _device!.id,
      connectionTimeout: const Duration(seconds: 5),
    ).listen((event) {
      if (event.connectionState == DeviceConnectionState.connected) {
        setState(() {
          _connected = true;
        });
      } else if (event.connectionState == DeviceConnectionState.disconnected) {
        setState(() {
          _connected = false;
          _turnOn = false;
          _device = null;
        });
      }
    });
  }

  void _disconnect() async {
    await _connection.cancel();
    setState(() {
      _connected = false;
      _turnOn = false;
      _device = null;
    });
  }

  void _toggle() async {
    if (!_connected || _device == null) return;

    final value = utf8.encode(_turnOn ? "OFF" : "ON");

    try {
      await _ble.writeCharacteristicWithoutResponse(
        QualifiedCharacteristic(
          characteristicId: charUuid,
          serviceId: serviceUuid,
          deviceId: _device!.id,
        ),
        value: value,
      );

      setState(() {
        _turnOn = !_turnOn;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Write failed: $e')),
      );
    }
  }

  @override
  void dispose() {
    if (_connected) _connection.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text(
          'Smart Home',
          style: TextStyle(color: Colors.white),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: Text(
                'ver 1.0',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 40),

            // SCAN / DISCONNECT DUGME
            SizedBox(
              width: 260,
              height: 55,
              child: ElevatedButton(
                onPressed: _connected ? _disconnect : _scanDevices,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _connected ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_connected ? 'Disconnect' : 'Scan Devices'),
              ),
            ),

            const SizedBox(height: 200),

            // TURN ON / OFF DUGME
            SizedBox(
              width: 260,
              height: 55,
              child: ElevatedButton(
                onPressed: _connected ? _toggle : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _turnOn ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(fontSize: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_turnOn ? 'Turn Off' : 'Turn On'),
              ),
            ),

            const SizedBox(height: 30),

            if (_device != null)
              Text(
                'Device: ${_device!.name.isEmpty ? "Unknown" : _device!.name}',
                textAlign: TextAlign.center,
              ),

            if (_connected)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Connected!',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
