import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_student/features/permission_gate/permission_gate.dart';

class _FakePermissionController implements PermissionGateController {
  PermissionGateSnapshot snapshot;
  int permissionRequests = 0;

  _FakePermissionController(this.snapshot);

  @override
  Future<PermissionGateSnapshot> check() async => snapshot;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<void> requestBluetoothOn() async {
    snapshot = const PermissionGateSnapshot(PermissionGateState.ready);
  }

  @override
  Future<void> requestPermissions() async {
    permissionRequests += 1;
    snapshot = const PermissionGateSnapshot(PermissionGateState.ready);
  }
}

void main() {
  testWidgets('blocks the app until permissions are ready', (tester) async {
    final controller = _FakePermissionController(
      const PermissionGateSnapshot(
        PermissionGateState.locationPermissionRequired,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PermissionGate(
          controller: controller,
          child: const Text('APP_READY'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cho phép sử dụng vị trí'), findsOneWidget);
    expect(find.text('APP_READY'), findsNothing);

    await tester.tap(find.text('Cấp quyền vị trí'));
    await tester.pumpAndSettle();

    expect(controller.permissionRequests, 1);
    expect(find.text('APP_READY'), findsOneWidget);
  });
}
