import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/calling.dart';
import 'core/realtime.dart';
import 'core/session.dart';
import 'ui/root.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await WhatomateApi.create();
  final session = SessionController(api);
  await session.bootstrap();
  final realtime = RealtimeService(api, session);
  final calls = CallingService(api, realtime);
  if (session.authenticated) await realtime.connect();
  runApp(WhatomateRoot(api: api, session: session, realtime: realtime, calls: calls));
}
