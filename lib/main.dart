import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/env.dart';
import 'core/services/supabase_service.dart';
import 'app.dart';

/// Global error state — set by FlutterError.onError and
/// PlatformDispatcher.instance.onError, read by the
/// ValueListenableBuilder wrapper in [main].
final ValueNotifier<String?> globalCrashError = ValueNotifier<String?>(null);
String? globalCrashStack;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error capture (diagnostic scaffolding) ──────────────
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    globalCrashError.value = details.exceptionAsString();
    globalCrashStack = details.stack.toString();
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    globalCrashError.value = error.toString();
    globalCrashStack = stack.toString();
    return true;
  };
  // ── End global error capture ───────────────────────────────────

  Object? startupError;
  StackTrace? startupStack;
  try {
    await SupabaseService.init().timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException(
        'Supabase.initialize() did not complete within 10 seconds — '
        'check SUPABASE_URL and SUPABASE_ANON_KEY dart-define values.',
      ),
    );
  } catch (e, st) {
    startupError = e;
    startupStack = st;
  }

  runApp(
    ProviderScope(
      child: ValueListenableBuilder<String?>(
        valueListenable: globalCrashError,
        builder: (context, crashError, _) {
          // ── Crash overlay ──
          if (crashError != null) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'App Error Detected',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          crashError,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Stack trace:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Text(
                              globalCrashStack ?? '(no stack trace)',
                              style: const TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          // ── Normal app ──
          if (startupError != null) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Startup failed',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(startupError.toString()),
                        const SizedBox(height: 12),
                        Text(
                          startupStack.toString(),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return const Birr5App();
        },
      ),
    ),
  );
}
