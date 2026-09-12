import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/env.dart';
import 'core/services/supabase_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      child: startupError != null
          ? MaterialApp(
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
            )
          : const Birr5App(),
    ),
  );
}
