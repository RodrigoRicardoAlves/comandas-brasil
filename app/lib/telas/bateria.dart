import 'package:flutter/material.dart';

import '../app.dart';
import '../sistema.dart';
import 'comum.dart';

/// Guia para o Android não "matar" o app no meio do expediente.
/// Importa principalmente para o celular líder (o que imprime), mas vale para todos.
class TelaBateria extends StatefulWidget {
  const TelaBateria({super.key});
  @override
  State<TelaBateria> createState() => _TelaBateriaState();
}

class _TelaBateriaState extends State<TelaBateria> with WidgetsBindingObserver {
  Map<String, dynamic> _estado = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _atualizar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // voltou das configurações do Android: confere de novo
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _atualizar();
  }

  Future<void> _atualizar() async {
    final e = await Sistema.estado();
    if (mounted) setState(() => _estado = e);
  }

  @override
  Widget build(BuildContext context) {
    final f = App.i.fabricante;
    final xiaomi = f.contains('xiaomi') || f.contains('redmi') || f.contains('poco');
    final samsung = f.contains('samsung');
    final motorola = f.contains('motorola') || f.contains('lenovo');
    final outros = !xiaomi && !samsung && !motorola;
    final semOtimizacao = _estado['otimizado'] == false;
    final notificacao = _estado['notificacao'] == true;

    Widget passo(int n, String titulo, String texto, {bool? feito, String? botao, VoidCallback? acao}) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: feito == true ? corVerde : corAmbar,
                  child: feito == true
                      ? const Icon(Icons.check, size: 18, color: Colors.black)
                      : Text('$n', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              ]),
              const SizedBox(height: 8),
              Text(texto, style: const TextStyle(fontSize: 15, color: Colors.white70)),
              if (botao != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: feito == true
                      ? OutlinedButton(onPressed: acao, child: Text(botao))
                      : FilledButton(onPressed: acao, child: Text(botao)),
                ),
              ],
            ]),
          ),
        );

    var n = 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Bateria e segundo plano')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Text(
          'O Android desliga apps "parados" para economizar bateria. Se isso acontecer com o celular que está '
          'imprimindo, os pedidos param de sair. Faça estes passos uma vez em cada celular (leva 1 minuto).',
          style: TextStyle(fontSize: 15),
        ),
        const SizedBox(height: 14),
        passo(++n, 'Deixar o app rodar em segundo plano',
            semOtimizacao ? 'Pronto: o Android não vai mais pausar o app.' : 'Toque no botão e escolha "Permitir".',
            feito: semOtimizacao, botao: semOtimizacao ? 'Ver de novo' : 'Permitir', acao: () => Sistema.pedirSemOtimizacao()),
        passo(++n, 'Permitir notificações',
            notificacao
                ? 'Pronto. Quando este celular estiver imprimindo para o bar, aparece uma notificação fixa.'
                : 'Necessário para o aviso "este celular está cuidando da impressora".',
            feito: notificacao, botao: notificacao ? null : 'Permitir notificações', acao: () async {
          await Sistema.pedirNotificacao();
          await Sistema.pedirRedeLocal();
          await Future.delayed(const Duration(seconds: 1));
          _atualizar();
        }),
        if (xiaomi) ...[
          passo(++n, 'Xiaomi: ligar o "Início automático"',
              'Na tela que abrir, ache "Comandas Brasil" e ligue a chave. (Se não abrir: Configurações → Apps → Gerenciar apps → '
              'Comandas Brasil → Início automático.)',
              botao: 'Abrir início automático', acao: () async {
            if (!await Sistema.abrirAutoInicio()) await Sistema.abrirAppConfig();
          }),
          passo(++n, 'Xiaomi: economia de bateria "Sem restrições"',
              'Na tela do app: Economia de bateria → escolha "Sem restrições".',
              botao: 'Abrir configurações do app', acao: Sistema.abrirAppConfig),
          passo(++n, 'Xiaomi: travar o app nos recentes',
              'Abra a lista de apps recentes (quadradinho), segure o Comandas Brasil e toque no cadeado 🔒. Assim a limpeza '
              'de memória não fecha o app.'),
        ],
        if (samsung) ...[
          passo(++n, 'Samsung: bateria "Sem restrições"',
              'Na tela do app: Bateria → escolha "Sem restrições".',
              botao: 'Abrir configurações do app', acao: Sistema.abrirAppConfig),
          passo(++n, 'Samsung: tirar dos apps em suspensão',
              'Configurações → Cuidados com o dispositivo (ou Bateria) → Limites de uso em segundo plano: '
              'desligue "Colocar apps não usados em suspensão" e confira se o Comandas Brasil não está em "Apps em suspensão".'),
          passo(++n, 'Samsung: economia de energia',
              'Durante o expediente, evite o "Modo economia de energia": ele reduz a chance de este celular ser o líder.'),
        ],
        if (motorola) ...[
          passo(++n, 'Motorola: bateria "Sem restrições"',
              'Na tela do app: Bateria (ou "Uso de bateria do app") → escolha "Sem restrições" / "Irrestrito".',
              botao: 'Abrir configurações do app', acao: Sistema.abrirAppConfig),
        ],
        if (outros) ...[
          passo(++n, 'Bateria "Sem restrições"',
              'Na tela do app procure "Bateria" e escolha "Sem restrições" (ou "Não otimizar"). Se existir a opção '
              '"Início automático", ligue também.',
              botao: 'Abrir configurações do app', acao: () async {
            await Sistema.abrirAppConfig();
          }),
        ],
        passo(++n, 'No expediente',
            'Deixe o app aberto (pode apagar a tela). Não feche o app arrastando nos recentes. Se der, deixe o celular '
            'que imprime no carregador: ele vira o líder automaticamente.'),
        const SizedBox(height: 8),
        FilledButton.tonal(onPressed: () => Navigator.pop(context), child: const Text('Pronto')),
      ]),
    );
  }
}
