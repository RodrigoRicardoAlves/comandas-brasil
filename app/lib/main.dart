import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'telas/entrada.dart';
import 'telas/inicio.dart';
import 'telas/pin.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await App.i.iniciar();
  WakelockPlus.enable().catchError((_) {}); // tela não apaga durante o atendimento
  // o app continua rodando quando a tela fecha (líder); ao voltar, religa a tela acesa e sincroniza
  ouvinteCiclo = AppLifecycleListener(onResume: () {
    WakelockPlus.enable().catchError((_) {});
    App.i.ciclo();
    App.i.rede.sincronizarJa();
  });
  runApp(const ComandasApp());
}

/// Guardado para o ouvinte não ser descartado.
AppLifecycleListener? ouvinteCiclo;

class ComandasApp extends StatelessWidget {
  const ComandasApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ambar = Color(0xFFFFB020);
    final esquema = ColorScheme.fromSeed(seedColor: ambar, brightness: Brightness.dark, primary: ambar);
    return MaterialApp(
      title: 'Comandas',
      debugShowCheckedModeBanner: false,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: esquema,
        scaffoldBackgroundColor: const Color(0xFF15161A),
        cardTheme: const CardThemeData(color: Color(0xFF22242B), margin: EdgeInsets.zero),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1C1D22), centerTitle: false),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(64, 52),
            textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52), textStyle: const TextStyle(fontSize: 16)),
        ),
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const Raiz(),
    );
  }
}

/// Decide a primeira tela conforme a sessão.
class Raiz extends StatelessWidget {
  const Raiz({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: App.i,
      builder: (context, _) {
        final a = App.i;
        if (a.boot == null) return const TelaEntrada();
        if (a.usuario == null) return const TelaPin();
        return const TelaInicio();
      },
    );
  }
}
