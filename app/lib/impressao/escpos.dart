/// Monta os bytes ESC/POS de um cupom (mesma ideia da classe Ticket do sistema antigo).
library;

const _semAcento = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i',
  'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n', 'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Í': 'I',
  'Ó': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ú': 'U', 'Ü': 'U', 'Ç': 'C', 'Ñ': 'N', 'º': 'o', 'ª': 'a', '°': 'o',
  '–': '-', '—': '-', '“': '"', '”': '"', '‘': "'", '’': "'", '…': '...',
};

const _cp860 = {
  'á': 0xA0, 'à': 0x85, 'â': 0x83, 'ã': 0x84, 'é': 0x82, 'ê': 0x88, 'í': 0xA1, 'ó': 0xA2, 'ô': 0x93, 'õ': 0x94,
  'ú': 0xA3, 'ü': 0x81, 'ç': 0x87, 'Á': 0x86, 'À': 0x91, 'Â': 0x8F, 'Ã': 0x8E, 'É': 0x90, 'Ê': 0x89, 'Í': 0x8B,
  'Ó': 0x9F, 'Ô': 0x8C, 'Õ': 0x99, 'Ú': 0x96, 'Ü': 0x9A, 'Ç': 0x80, 'º': 0xA7, 'ª': 0xA6,
};

const _cp850 = {
  'á': 0xA0, 'à': 0x85, 'â': 0x83, 'ã': 0xC6, 'é': 0x82, 'ê': 0x88, 'í': 0xA1, 'ó': 0xA2, 'ô': 0x93, 'õ': 0xE4,
  'ú': 0xA3, 'ü': 0x81, 'ç': 0x87, 'Á': 0xB5, 'À': 0xB7, 'Â': 0xB6, 'Ã': 0xC7, 'É': 0x90, 'Ê': 0xD2, 'Í': 0xD6,
  'Ó': 0xE0, 'Ô': 0xE2, 'Õ': 0xE5, 'Ú': 0xE9, 'Ü': 0x9A, 'Ç': 0x80, 'º': 0xA7, 'ª': 0xA6,
};

String semAcentos(String s) => s.split('').map((c) => _semAcento[c] ?? c).join();

class Cupom {
  final int colunas;
  final String codificacao; // ascii | cp860 | cp850
  final bool cortar;
  int largura;
  final List<int> buf = [0x1B, 0x40]; // ESC @ (reinicia)

  Cupom({this.colunas = 48, this.codificacao = 'ascii', this.cortar = true}) : largura = colunas {
    if (codificacao == 'cp860') buf.addAll([0x1B, 0x74, 3]);
    if (codificacao == 'cp850') buf.addAll([0x1B, 0x74, 2]);
  }

  List<int> _codificar(String s) {
    final tabela = codificacao == 'cp860' ? _cp860 : (codificacao == 'cp850' ? _cp850 : null);
    final out = <int>[];
    for (final ch in s.runes.map(String.fromCharCode)) {
      final c = ch.codeUnitAt(0);
      if (c >= 0x20 && c < 0x7F) {
        out.add(c);
      } else if (tabela != null && tabela.containsKey(ch)) {
        out.add(tabela[ch]!);
      } else {
        final t = _semAcento[ch];
        out.addAll((t ?? '?').codeUnits);
      }
    }
    return out;
  }

  Cupom texto([String s = '']) {
    buf.addAll(_codificar(s));
    buf.add(0x0A);
    return this;
  }

  /// Quebra o texto em várias linhas que caibam no papel.
  Cupom quebrar(String s, {String recuo = '   '}) {
    final palavras = s.split(' ');
    var linha = '';
    var primeira = true;
    for (final w in palavras) {
      final tentativa = linha.isEmpty ? w : '$linha $w';
      if (tentativa.length > largura && linha.isNotEmpty) {
        texto(linha);
        primeira = false;
        linha = '$recuo$w';
      } else {
        linha = tentativa;
      }
    }
    if (linha.isNotEmpty || primeira) texto(linha);
    return this;
  }

  Cupom centro() => _raw([0x1B, 0x61, 1]);
  Cupom esquerda() => _raw([0x1B, 0x61, 0]);
  Cupom negrito([bool on = true]) => _raw([0x1B, 0x45, on ? 1 : 0]);

  Cupom tamanho([int l = 1, int a = 1]) {
    largura = colunas ~/ l;
    return _raw([0x1D, 0x21, ((l - 1) << 4) | (a - 1)]);
  }

  Cupom linha([String ch = '-']) => texto(ch * largura);

  /// Texto à esquerda e valor à direita na mesma linha.
  Cupom ladoALado(String esq, String dir) {
    final espaco = largura - dir.length - 1;
    if (esq.length <= espaco) return texto('${esq.padRight(espaco)} $dir');
    quebrar(esq);
    return texto(dir.padLeft(largura));
  }

  Cupom avancar([int n = 4]) => _raw([0x1B, 0x64, n]);
  Cupom corte() => cortar ? _raw([0x1D, 0x56, 0x42, 0x00]) : this;

  Cupom _raw(List<int> b) {
    buf.addAll(b);
    return this;
  }

  List<int> get bytes => List.unmodifiable(buf);
}
