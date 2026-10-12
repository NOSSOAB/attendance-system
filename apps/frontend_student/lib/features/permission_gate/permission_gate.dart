import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum PermissionGateState {
  checking,
  bluetoothPermissionRequired,
  locationPermissionRequired,
  bluetoothDisabled,
  locationServiceDisabled,
  ready,
  error,
}

class PermissionGateSnapshot {
  final PermissionGateState state;
  final bool permanentlyDenied;
  final String? message;

  const PermissionGateSnapshot(
    this.state, {
    this.permanentlyDenied = false,
    this.message,
  });
}

abstract class PermissionGateController {
  Future<PermissionGateSnapshot> check();

  Future<void> requestPermissions();

  Future<void> requestBluetoothOn();

  Future<bool> openSettings();
}

class DevicePermissionGateController implements PermissionGateController {
  final bool requireBluetooth;

  const DevicePermissionGateController({this.requireBluetooth = true});

  @override
  Future<PermissionGateSnapshot> check() async {
    final platform = defaultTargetPlatform;
    if (kIsWeb ||
        (platform != TargetPlatform.android &&
            platform != TargetPlatform.iOS)) {
      return const PermissionGateSnapshot(PermissionGateState.ready);
    }

    if (requireBluetooth) {
      final bluetoothPermissions = platform == TargetPlatform.android
          ? [Permission.bluetoothScan, Permission.bluetoothConnect]
          : [Permission.bluetooth];
      final bluetoothStatuses = await Future.wait(
        bluetoothPermissions.map((permission) => permission.status),
      );
      if (bluetoothStatuses.any((status) => !status.isGranted)) {
        return PermissionGateSnapshot(
          PermissionGateState.bluetoothPermissionRequired,
          permanentlyDenied: bluetoothStatuses.any(
            (status) => status.isPermanentlyDenied,
          ),
        );
      }
    }

    final locationStatus = await Permission.locationWhenInUse.status;
    if (!locationStatus.isGranted) {
      return PermissionGateSnapshot(
        PermissionGateState.locationPermissionRequired,
        permanentlyDenied: locationStatus.isPermanentlyDenied,
      );
    }

    if (requireBluetooth) {
      final adapterState = await FlutterBluePlus.adapterState.first.timeout(
        const Duration(seconds: 4),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      if (adapterState != BluetoothAdapterState.on) {
        return const PermissionGateSnapshot(
          PermissionGateState.bluetoothDisabled,
        );
      }
    }

    final locationService = await Permission.locationWhenInUse.serviceStatus;
    if (!locationService.isEnabled) {
      return const PermissionGateSnapshot(
        PermissionGateState.locationServiceDisabled,
      );
    }

    return const PermissionGateSnapshot(PermissionGateState.ready);
  }

  @override
  Future<void> requestPermissions() async {
    final permissions = requireBluetooth
        ? defaultTargetPlatform == TargetPlatform.android
              ? [
                  Permission.bluetoothScan,
                  Permission.bluetoothConnect,
                  Permission.locationWhenInUse,
                ]
              : [Permission.bluetooth, Permission.locationWhenInUse]
        : [Permission.locationWhenInUse];
    await permissions.request();
  }

  @override
  Future<void> requestBluetoothOn() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterBluePlus.turnOn();
        return;
      } catch (_) {
        // Fall back to application settings below.
      }
    }
    await openAppSettings();
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}

class PermissionGate extends StatefulWidget {
  final Widget child;
  final PermissionGateController? controller;
  final bool requireBluetooth;

  const PermissionGate({
    super.key,
    required this.child,
    this.controller,
    this.requireBluetooth = true,
  });

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate>
    with WidgetsBindingObserver {
  late final PermissionGateController _controller;
  PermissionGateSnapshot _snapshot = const PermissionGateSnapshot(
    PermissionGateState.checking,
  );
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller =
        widget.controller ??
        DevicePermissionGateController(
          requireBluetooth: widget.requireBluetooth,
        );
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_isWorking) return;
    setState(() {
      _isWorking = true;
      _snapshot = const PermissionGateSnapshot(PermissionGateState.checking);
    });

    try {
      final next = await _controller.check();
      if (mounted) {
        setState(() => _snapshot = next);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _snapshot = PermissionGateSnapshot(
            PermissionGateState.error,
            message: error.toString(),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_isWorking) return;
    setState(() => _isWorking = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isWorking = false);
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_snapshot.state == PermissionGateState.ready) {
      return widget.child;
    }

    final content = _contentFor(_snapshot.state);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(content.icon, size: 64, color: const Color(0xFF165DFF)),
                  const SizedBox(height: 20),
                  Text(
                    content.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _snapshot.message ?? content.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      height: 1.5,
                      color: Color(0xFF667085),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_snapshot.state != PermissionGateState.checking)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isWorking
                            ? null
                            : () => _run(content.primaryAction),
                        child: Text(content.primaryLabel),
                      ),
                    ),
                  if (_snapshot.state != PermissionGateState.checking) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _isWorking ? null : _refresh,
                      child: const Text('Kiểm tra lại'),
                    ),
                  ] else
                    const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _GateContent _contentFor(PermissionGateState state) {
    switch (state) {
      case PermissionGateState.bluetoothPermissionRequired:
        return _GateContent(
          icon: Icons.bluetooth_searching_rounded,
          title: 'Cho phép sử dụng Bluetooth',
          description:
              'Ứng dụng cần quyền Bluetooth để tìm thiết bị BLE của phòng học.',
          primaryLabel: _snapshot.permanentlyDenied
              ? 'Mở cài đặt'
              : 'Cấp quyền Bluetooth',
          primaryAction: _snapshot.permanentlyDenied
              ? () async => _controller.openSettings()
              : _controller.requestPermissions,
        );
      case PermissionGateState.locationPermissionRequired:
        return _GateContent(
          icon: Icons.location_on_outlined,
          title: 'Cho phép sử dụng vị trí',
          description: widget.requireBluetooth
              ? 'Quyền vị trí được yêu cầu trước khi ứng dụng thực hiện quét BLE.'
              : 'Ứng dụng cần quyền vị trí để kiểm tra điều kiện điểm danh.',
          primaryLabel: _snapshot.permanentlyDenied
              ? 'Mở cài đặt'
              : 'Cấp quyền vị trí',
          primaryAction: _snapshot.permanentlyDenied
              ? () async => _controller.openSettings()
              : _controller.requestPermissions,
        );
      case PermissionGateState.bluetoothDisabled:
        return _GateContent(
          icon: Icons.bluetooth_disabled_rounded,
          title: 'Bluetooth đang tắt',
          description: 'Hãy bật Bluetooth để tiếp tục sử dụng ứng dụng.',
          primaryLabel: 'Bật Bluetooth',
          primaryAction: _controller.requestBluetoothOn,
        );
      case PermissionGateState.locationServiceDisabled:
        return _GateContent(
          icon: Icons.location_disabled_rounded,
          title: 'Dịch vụ vị trí đang tắt',
          description: 'Hãy bật dịch vụ vị trí trong cài đặt rồi kiểm tra lại.',
          primaryLabel: 'Mở cài đặt',
          primaryAction: () async => _controller.openSettings(),
        );
      case PermissionGateState.error:
        return _GateContent(
          icon: Icons.error_outline_rounded,
          title: 'Không kiểm tra được quyền',
          description: widget.requireBluetooth
              ? 'Đã có lỗi khi kiểm tra Bluetooth và vị trí.'
              : 'Đã có lỗi khi kiểm tra vị trí.',
          primaryLabel: 'Thử lại',
          primaryAction: _refresh,
        );
      default:
        return _GateContent(
          icon: Icons.security_rounded,
          title: 'Đang kiểm tra quyền',
          description: 'Vui lòng chờ trong giây lát.',
          primaryLabel: 'Kiểm tra lại',
          primaryAction: _refresh,
        );
    }
  }
}

class _GateContent {
  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final Future<void> Function() primaryAction;

  const _GateContent({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.primaryAction,
  });
}
