/// Dados que vêm da VPS (bootstrap) e ficam guardados no celular.
class BarCfg {
  final int id;
  final String nome, slug, rodape, codificacao, impressora;
  final int colunas, maxComanda, versaoCardapio;
  final bool cortar;
  final double taxaServico;

  BarCfg.json(Map<String, dynamic> j)
      : id = j['id'],
        nome = j['nome'] ?? '',
        slug = j['slug'] ?? '',
        rodape = j['rodape'] ?? '',
        codificacao = j['codificacao'] ?? 'ascii',
        impressora = j['impressora'] ?? '',
        colunas = j['colunas_papel'] ?? 48,
        maxComanda = j['max_comanda'] ?? 200,
        versaoCardapio = j['versao_cardapio'] ?? 0,
        cortar = j['cortar_papel'] ?? true,
        taxaServico = (j['taxa_servico'] ?? 0).toDouble();
}

class Usuario {
  final int id;
  final String nome, papel, pinHash;
  Usuario.json(Map<String, dynamic> j)
      : id = j['id'],
        nome = j['nome'],
        papel = j['papel'],
        pinHash = j['pin_hash'] ?? '';
  bool get gerente => papel == 'gerente';
  Map<String, dynamic> json() => {'id': id, 'nome': nome, 'papel': papel, 'pin_hash': pinHash};
}

class Setor {
  final int id;
  final String nome, impressora;
  Setor.json(Map<String, dynamic> j)
      : id = j['id'],
        nome = j['nome'],
        impressora = j['impressora'] ?? '';
}

class Variante {
  final int id, preco;
  final String nome;
  Variante.json(Map<String, dynamic> j)
      : id = j['id'],
        nome = j['nome'] ?? '',
        preco = j['preco'];
}

class Produto {
  final int id;
  final String nome, descricao, setor;
  final bool esgotado, imprime;
  final List<Variante> variantes;
  late final String categoria;
  Produto.json(Map<String, dynamic> j)
      : id = j['id'],
        nome = j['nome'],
        descricao = j['descricao'] ?? '',
        setor = j['setor'] ?? '',
        esgotado = j['esgotado'] ?? false,
        imprime = j['imprime'] ?? false,
        variantes = [for (final v in j['variantes']) Variante.json(v)];
}

class Categoria {
  final int id;
  final String nome;
  final List<Produto> produtos;
  Categoria.json(Map<String, dynamic> j)
      : id = j['id'],
        nome = j['nome'],
        produtos = [for (final p in j['produtos']) Produto.json(p)] {
    for (final p in produtos) {
      p.categoria = nome;
    }
  }
}

class Bootstrap {
  final Map<String, dynamic> bruto;
  final BarCfg bar;
  final String pinSalt, lanKey;
  final List<Usuario> usuarios;
  final List<Setor> setores;
  final List<Categoria> cardapio;

  Bootstrap.json(Map<String, dynamic> j)
      : bruto = j,
        bar = BarCfg.json(j['bar']),
        pinSalt = j['pin_salt'],
        lanKey = j['lan_key'] ?? '',
        usuarios = [for (final u in j['usuarios']) Usuario.json(u)],
        setores = [for (final s in j['setores']) Setor.json(s)],
        cardapio = [for (final c in j['cardapio']) Categoria.json(c)];

  /// Impressora de um setor (vazio = padrão do bar).
  String impressoraDoSetor(String setor) {
    for (final s in setores) {
      if (s.nome == setor && s.impressora.isNotEmpty) return s.impressora;
    }
    return bar.impressora;
  }
}
