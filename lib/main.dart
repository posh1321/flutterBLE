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

  // Dugmad (stanje svakog LED-a)
  List<bool> _turnOnStates = [false, false, false, false];

  // Temperatura
  double? _temperature;
  Timer? _tempTimer;

  late StreamSubscription<ConnectionStateUpdate> _connection;
  StreamSubscription<List<int>>? _tempNotifySub;

  // UUIDs
  final Uuid serviceUuid = Uuid.parse("12345678-1234-1234-1234-1234567890ab");
  final Uuid charUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");

  Future<bool> _requestBlePermissions() async {
    if (Platform.isAndroid) {
      final permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ];

      final statuses = await permissions.request();
      return statuses.values.every((status) => status.isGranted);
    }
    return true; // iOS
  }

  void _scanDevices() async {
    if (_device != null) return;

    final granted = await _requestBlePermissions();
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bluetooth permissions not granted')),
      );
      return;
    }

    List<DiscoveredDevice> devices = [];
    final subscription = _ble.scanForDevices(withServices: []).listen((device) {
      if (!devices.any((d) => d.id == device.id)) devices.add(device);
    });

    await Future.delayed(Duration(seconds: 5));
    await subscription.cancel();

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
        _device = selected;
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
      connectionTimeout: Duration(seconds: 5),
    ).listen((event) {
      if (event.connectionState == DeviceConnectionState.connected) {
        setState(() => _connected = true);
        _subscribeToTempNotify();
        _startTempTimer();
      } else if (event.connectionState == DeviceConnectionState.disconnected) {
        setState(() {
          _connected = false;
          _device = null;
          _turnOnStates = [false, false, false, false];
          _tempTimer?.cancel();
          _tempNotifySub?.cancel();
        });
      }
    });
  }

  void _disconnect() async {
    await _connection.cancel();
    _tempTimer?.cancel();
    _tempNotifySub?.cancel();
    setState(() {
      _connected = false;
      _device = null;
      _turnOnStates = [false, false, false, false];
    });
  }

  void _sendCommand(int index) async {
    if (!_connected || _device == null) return;

    // Odredi komandu prema trenutnom stanju dugmeta
    String cmd;
    if (_turnOnStates[index]) {
      cmd = "OFF${index == 0 ? '' : index + 1}";
    } else {
      cmd = "ON${index == 0 ? '' : index + 1}";
    }

    try {
      await _ble.writeCharacteristicWithResponse(
        QualifiedCharacteristic(
          characteristicId: charUuid,
          serviceId: serviceUuid,
          deviceId: _device!.id,
        ),
        value: utf8.encode(cmd),
      );

      // samo update UI ako komanda prođe
      setState(() {
        _turnOnStates[index] = !_turnOnStates[index];
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Write failed: $e')),
      );
    }
  }

  void _subscribeToTempNotify() {
    _tempNotifySub?.cancel();
    if (_device == null) return;

    _tempNotifySub = _ble.subscribeToCharacteristic(
      QualifiedCharacteristic(
        characteristicId: charUuid,
        serviceId: serviceUuid,
        deviceId: _device!.id,
      ),
    ).listen((data) {
      final val = utf8.decode(data);
      if (val.startsWith("TEMP:")) {
        final tStr = val.substring(5);
        double? t = tStr == "None" ? null : double.tryParse(tStr);
        setState(() => _temperature = t);
      }
    });
  }

  void _startTempTimer() {
    _tempTimer?.cancel();
    _tempTimer = Timer.periodic(Duration(seconds: 10), (_) async {
      if (!_connected || _device == null) return;

      try {
        await _ble.writeCharacteristicWithResponse(
          QualifiedCharacteristic(
            characteristicId: charUuid,
            serviceId: serviceUuid,
            deviceId: _device!.id,
          ),
          value: utf8.encode("TEMP?"),
        );
      } catch (e) {
        print("TEMP read failed: $e");
      }
    });
  }

  @override
  void dispose() {
    _tempTimer?.cancel();
    _tempNotifySub?.cancel();
    if (_connected) _connection.cancel();
    super.dispose();
  }

  Widget _buildTempCard() {
    return Container(
      width: 260,
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.thermostat_rounded, size: 40, color: Colors.redAccent),
            const SizedBox(width: 10),
            Text(
              _temperature != null
                  ? "${_temperature!.toStringAsFixed(1)} °C"
                  : "--.- °C",
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text("SmartHome"),
            Text("ver 1.1"),
          ],
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // SCAN / DISCONNECT dugme veće
              SizedBox(
                width: 300,
                height: 65,
                child: ElevatedButton(
                  onPressed: _connected ? _disconnect : _scanDevices,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _connected ? Colors.red : Colors.blue,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(_connected ? 'Disconnect' : 'Scan Devices'),
                ),
              ),

              // temperatura card
              _buildTempCard(),

              const SizedBox(height: 10),

              // 4 dugmeta Turn On/Off
              for (int i = 0; i < 4; i++) ...[
                SizedBox(
                  width: 260,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _connected ? () => _sendCommand(i) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      _turnOnStates[i] ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(_turnOnStates[i] ? 'Turn Off' : 'Turn On'),
                  ),
                ),
                const SizedBox(height: 15),
              ],

              if (_device != null)
                Text(
                  'Device: ${_device!.name.isEmpty ? "Unknown" : _device!.name}',
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
