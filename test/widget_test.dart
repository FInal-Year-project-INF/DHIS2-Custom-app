import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hsasmartapp/pages/login_screen.dart';
import 'package:provider/provider.dart';

// Import your providers and the widget that contains the counter
import 'package:hsasmartapp/providers/auth_provider.dart';
import 'package:hsasmartapp/providers/bluetooth_provider.dart';

// Import the widget that contains the counter functionality
// Replace with the actual path and widget name
//import 'package:hsasmartapp/pages/counter_screen.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // Build the widget tree with providers and MaterialApp
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => BluetoothProvider()),
        ],
        child: MaterialApp(
          home: const LoginScreen(), // Replace with your actual counter widget
        ),
      ),
    );

    // Verify the counter starts at 0.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    // Verify the '+' icon exists.
    expect(find.byIcon(Icons.add), findsOneWidget);

    // Tap the '+' icon and rebuild the widget.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    // Verify the counter increments.
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
