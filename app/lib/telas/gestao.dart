import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app.dart';
import 'comum.dart';

/// Gerente: painel de gestão (o mesmo do navegador) aberto dentro do app.
/// Entra sozinho com um link de uso único; ao sair, apaga a sessão do navegador interno.
class TelaGestao extends StatefulWidget {
  const TelaGestao({super.key});
  @override
  State<TelaGestao> createState() => _TelaGestaoState();
}

class _TelaGestaoState extends State<TelaGestao> {
  WebViewController? _web;
  String? _erro;
  int _progresso = 0;
  late final String _host = Uri.parse(App.i.servidor).host;

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  @override
  void dispose() {
    // o próximo a usar o celular pode ser um garçom: não deixa o painel logado
    WebViewCookieManager().clearCookies();
    super.dispose();
  }

  Future<void> _abrir() async {
    setState(() => _erro = null);
    try {
      final link = await App.i.linkGestao();
      final web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (p) => mounted ? setState(() => _progresso = p) : null,
          onNavigationRequest: _pode,
        ))
        ..loadRequest(link);
      setState(() => _web = web);
    } catch (e) {
      setState(() => _erro = e.toString());
    }
  }

  NavigationDecision _pode(NavigationRequest r) {
    if (!r.isMainFrame) return NavigationDecision.navigate;
    final u = Uri.parse(r.url);
    if (u.host != _host) {
      aviso(context, 'Este link não abre dentro do app.', erro: true);
      return NavigationDecision.prevent;
    }
    if (u.queryParameters['formato'] == 'csv') {
      aviso(context, 'A planilha só baixa pelo painel no navegador do computador.', erro: true, segundos: 5);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  /// Botão voltar do celular: volta página no painel; na primeira página, volta ao app.
  Future<void> _voltar() async {
    final web = _web;
    if (web != null && await web.canGoBack()) {
      await web.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (saiu, _) {
        if (!saiu) _voltar();
      },
      child: Scaffold(
        appBar: AppBar(
          leadingWidth: 150,
          leading: TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Voltar ao app'),
          ),
          title: const Text('Gestão'),
          actions: [
            if (web != null) IconButton(tooltip: 'Recarregar', icon: const Icon(Icons.refresh), onPressed: web.reload),
          ],
          bottom: web != null && _progresso < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progresso / 100, minHeight: 3))
              : null,
        ),
        body: _erro != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
                    const SizedBox(height: 12),
                    Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: _abrir, icon: const Icon(Icons.refresh), label: const Text('Tentar de novo')),
                  ]),
                ),
              )
            : web == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: web),
      ),
    );
  }
}
