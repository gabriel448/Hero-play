import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/canal.dart';
import '../models/serie.dart';
import '../services/tmdb_service.dart';
import '../state/iptv_provider.dart';
import '../state/preferencias_provider.dart';
import '../theme/app_theme.dart';
import '../utils/layout.dart';
import '../widgets/skeleton.dart';
import 'tela_player.dart';

// Pôster — mobile/tablet.
const double _kPosterW = 132.0;
const double _kPosterH = 198.0; // proporcao 2:3
// Pôster — desktop (maior, vira o "herói" do layout de duas colunas).
const double _kPosterWDesktop = 300.0;
const double _kPosterHDesktop = 450.0;
const double _kMaxLarguraDesktop = 1120.0;

/// Tela intermediaria de detalhes de um filme ou serie.
///
/// Abre instantaneamente com o banner ja visivel. Sinopse, ano e elenco
/// chegam de forma assincrona — enquanto o TMDB responde, os textos
/// aparecem como skeleton/shimmer, sem travar a interface.
///
/// Layout adapta: no desktop usa duas colunas (poster grande + conteudo);
/// no mobile/tablet, layout empilhado.
class TelaDetalhes extends StatefulWidget {
  final Canal? filme;
  final Serie? serie;

  const TelaDetalhes.filme(Canal this.filme, {super.key}) : serie = null;
  const TelaDetalhes.serie(Serie this.serie, {super.key}) : filme = null;

  bool get ehSerie => serie != null;

  @override
  State<TelaDetalhes> createState() => _TelaDetalhesState();
}

/// Resultado do agrupamento de episodios por temporada.
typedef _EpisodiosAgrupados = ({
  Map<int, List<Canal>> porTemporada,
  List<int> temporadas,
  List<Object> itens, // int = marcador de temporada, Canal = episodio
});

class _TelaDetalhesState extends State<TelaDetalhes> {
  late final Future<TmdbInfo> _infoFuture;
  Future<String?>? _posterSerieFuture;
  String get _nome => widget.ehSerie ? widget.serie!.nome : widget.filme!.nome;

  @override
  void initState() {
    super.initState();
    final tmdb = context.read<TmdbService>();
    final idioma = context.read<PreferenciasProvider>().idiomaEfetivo.codigo;

    // Disparado uma unica vez — a tela ja foi montada, isto roda em paralelo.
    _infoFuture = tmdb.info(
      nome: _nome,
      ehSerie: widget.ehSerie,
      idioma: idioma,
    );
    // Series: poster do TMDB (normalmente ja em cache, vindo do carrossel).
    if (widget.ehSerie) {
      _posterSerieFuture = tmdb.posterSerie(widget.serie!.nome);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_nome, overflow: TextOverflow.ellipsis)),
      body: isDesktop(context)
          ? _buildDesktop(context)
          : tabletBody(
              context,
              widget.ehSerie ? _buildSerieMobile() : _buildFilmeMobile(),
            ),
    );
  }

  // ─── Agrupamento de episodios (compartilhado) ────────────────────────────

  _EpisodiosAgrupados _agruparEpisodios(Serie serie) {
    final porTemporada = <int, List<Canal>>{};
    for (final ep in serie.episodios) {
      (porTemporada[Serie.seasonOf(ep)] ??= []).add(ep);
    }
    final temporadas = porTemporada.keys.toList()..sort();

    final itens = <Object>[];
    for (final t in temporadas) {
      itens.add(t);
      itens.addAll(porTemporada[t]!);
    }
    return (porTemporada: porTemporada, temporadas: temporadas, itens: itens);
  }

  // ─── Layout MOBILE / TABLET (empilhado) ──────────────────────────────────

  Widget _buildFilmeMobile() {
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        _Cabecalho(
          nome: _nome,
          banner: _BannerFilme(url: widget.filme!.logoUrl),
          infoFuture: _infoFuture,
          acao: _AcaoFilme(filme: widget.filme!),
        ),
        const _Divisoria(),
        _SecaoSinopse(infoFuture: _infoFuture),
        _SecaoElenco(infoFuture: _infoFuture),
      ],
    );
  }

  Widget _buildSerieMobile() {
    final serie = widget.serie!;
    final agrup = _agruparEpisodios(serie);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _Cabecalho(
                nome: _nome,
                banner: _BannerSerie(
                  posterFuture: _posterSerieFuture,
                  logoM3U: serie.logoUrl,
                ),
                infoFuture: _infoFuture,
                acao: _AcaoSerie(serie: serie),
                subtitulo: _descricaoSerie(
                  agrup.temporadas.length,
                  serie.totalEpisodios,
                ),
              ),
              const _Divisoria(),
              _SecaoSinopse(infoFuture: _infoFuture),
              _SecaoElenco(infoFuture: _infoFuture),
              const _TituloSecao('Episódios'),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: agrup.itens.length,
          itemBuilder: (_, i) {
            final item = agrup.itens[i];
            if (item is int) {
              return _HeaderTemporada(
                numero: item,
                total: agrup.porTemporada[item]!.length,
              );
            }
            return _ItemEpisodio(episodio: item as Canal);
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }

  // ─── Layout DESKTOP (duas colunas) ───────────────────────────────────────

  Widget _buildDesktop(BuildContext context) {
    final serie = widget.serie;
    final agrup = serie != null ? _agruparEpisodios(serie) : null;

    // Pôster grande com sombra suave.
    final banner = Container(
      width: _kPosterWDesktop,
      height: _kPosterHDesktop,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.base),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: widget.ehSerie
          ? _BannerSerie(
              posterFuture: _posterSerieFuture,
              logoM3U: serie!.logoUrl,
            )
          : _BannerFilme(url: widget.filme!.logoUrl),
    );

    // Coluna de conteudo ao lado do poster.
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _nome,
          style: Theme.of(context).textTheme.headlineMedium,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LinhaMeta(
          infoFuture: _infoFuture,
          subtitulo: agrup != null
              ? _descricaoSerie(agrup.temporadas.length, serie!.totalEpisodios)
              : null,
        ),
        const SizedBox(height: AppSpacing.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: widget.ehSerie
              ? _AcaoSerie(serie: serie!)
              : _AcaoFilme(filme: widget.filme!),
        ),
        const SizedBox(height: AppSpacing.xl),
        _SecaoSinopse(infoFuture: _infoFuture, padH: 0),
        _SecaoElenco(infoFuture: _infoFuture, padH: 0),
      ],
    );

    final cabecalho = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        banner,
        const SizedBox(width: AppSpacing.xxl),
        Expanded(child: info),
      ],
    );

    // Filme: rolagem simples do cabeçalho.
    if (agrup == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxLarguraDesktop),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: cabecalho,
          ),
        ),
      );
    }

    // Série: cabeçalho + lista de episódios por temporada.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxLarguraDesktop),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.xxl,
                AppSpacing.xxl,
                0,
              ),
              sliver: SliverToBoxAdapter(child: cabecalho),
            ),
            const SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              sliver: SliverToBoxAdapter(
                child: _TituloSecao('Episódios', padH: 0),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              sliver: SliverList.builder(
                itemCount: agrup.itens.length,
                itemBuilder: (_, i) {
                  final item = agrup.itens[i];
                  if (item is int) {
                    return _HeaderTemporada(
                      numero: item,
                      total: agrup.porTemporada[item]!.length,
                      padH: 0,
                    );
                  }
                  return _ItemEpisodio(episodio: item as Canal, padH: 0);
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  static String _descricaoSerie(int t, int e) {
    final ts = t == 1 ? '1 temporada' : '$t temporadas';
    final es = e == 1 ? '1 episódio' : '$e episódios';
    return '$ts · $es';
  }
}

// ─── Cabecalho mobile (banner + titulo + ano + botoes empilhados) ──────────

class _Cabecalho extends StatelessWidget {
  final String nome;
  final Widget banner;
  final Future<TmdbInfo> infoFuture;
  final Widget acao;
  final String? subtitulo;

  const _Cabecalho({
    required this.nome,
    required this.banner,
    required this.infoFuture,
    required this.acao,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: _kPosterW, height: _kPosterH, child: banner),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _LinhaMeta(infoFuture: infoFuture, subtitulo: subtitulo),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          acao,
        ],
      ),
    );
  }
}

/// Linha "ano · subtitulo". O ano chega do TMDB de forma assincrona.
class _LinhaMeta extends StatelessWidget {
  final Future<TmdbInfo> infoFuture;
  final String? subtitulo;

  const _LinhaMeta({required this.infoFuture, this.subtitulo});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        );
    return FutureBuilder<TmdbInfo>(
      future: infoFuture,
      builder: (context, snap) {
        final carregando = snap.connectionState != ConnectionState.done;
        // Sem subtitulo e ainda carregando -> nada para mostrar -> shimmer.
        if (carregando && subtitulo == null) {
          return const Shimmer(child: SkeletonBox(width: 64, height: 12));
        }
        final ano = snap.data?.ano;
        final partes = <String>[
          if (ano != null) '$ano',
          ?subtitulo,
        ];
        if (partes.isEmpty) return const SizedBox.shrink();
        return Text(partes.join('  ·  '), style: estilo);
      },
    );
  }
}

// ─── Acoes (Assistir / Continuar + Voltar) ─────────────────────────────────

class _AcaoFilme extends StatelessWidget {
  final Canal filme;
  const _AcaoFilme({required this.filme});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final progresso = provider.obterProgresso(filme);
    final continuar = progresso != null;

    return _BotoesAcao(
      label: continuar ? 'Continuar' : 'Assistir',
      onAssistir: () {
        provider.registrarVisualizacao(filme);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TelaPlayer(
              canal: filme,
              posicaoInicial: continuar
                  ? Duration(seconds: progresso.posicaoSeg)
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _AcaoSerie extends StatelessWidget {
  final Serie serie;
  const _AcaoSerie({required this.serie});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final retomada = _calcularRetomada(serie, provider);

    final label = retomada.continuar
        ? 'Continuar T${Serie.seasonOf(retomada.episodio)}'
            ':E${Serie.episodeOf(retomada.episodio)}'
        : 'Assistir';

    return _BotoesAcao(
      label: label,
      onAssistir: () {
        provider.registrarVisualizacao(retomada.episodio);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TelaPlayer(
              canal: retomada.episodio,
              posicaoInicial: retomada.posicao > Duration.zero
                  ? retomada.posicao
                  : null,
            ),
          ),
        );
      },
    );
  }
}

class _BotoesAcao extends StatelessWidget {
  final String label;
  final VoidCallback onAssistir;

  const _BotoesAcao({required this.label, required this.onAssistir});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onAssistir,
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: Text(label),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Voltar'),
        ),
      ],
    );
  }
}

/// Decisao de onde a serie deve retomar.
class _Retomada {
  final Canal episodio;
  final Duration posicao;

  /// `true` quando o usuario ja viu algo da serie (botao vira "Continuar").
  final bool continuar;

  const _Retomada({
    required this.episodio,
    required this.posicao,
    required this.continuar,
  });
}

/// Calcula em que episodio a serie deve abrir:
///  1. Ha episodio com progresso salvo -> retoma o de progresso mais recente.
///  2. Sem progresso, mas ha episodios no historico -> avanca para o
///     episodio seguinte ao mais avancado ja assistido.
///  3. Nada visto -> primeiro episodio ("Assistir").
_Retomada _calcularRetomada(Serie serie, IptvProvider provider) {
  // 1. Episodio com progresso mais recente.
  Canal? epProgresso;
  int posSeg = 0;
  DateTime? maisRecente;
  for (final ep in serie.episodios) {
    final p = provider.obterProgresso(ep);
    if (p == null) continue;
    if (maisRecente == null || p.atualizadoEm.isAfter(maisRecente)) {
      maisRecente = p.atualizadoEm;
      epProgresso = ep;
      posSeg = p.posicaoSeg;
    }
  }
  if (epProgresso != null) {
    return _Retomada(
      episodio: epProgresso,
      posicao: Duration(seconds: posSeg),
      continuar: true,
    );
  }

  // 2. Episodio mais avancado ja aberto (historico). episodios ja vem
  //    ordenados por (temporada, episodio), entao o ultimo match e o maior.
  final urlsHistorico = provider.historico.map((h) => h.canal.url).toSet();
  Canal? maisAvancado;
  for (final ep in serie.episodios) {
    if (urlsHistorico.contains(ep.url)) maisAvancado = ep;
  }
  if (maisAvancado != null) {
    final idx = serie.episodios.indexOf(maisAvancado);
    if (idx >= 0 && idx + 1 < serie.episodios.length) {
      return _Retomada(
        episodio: serie.episodios[idx + 1],
        posicao: Duration.zero,
        continuar: true,
      );
    }
    // Ja viu o ultimo episodio: reabre nele mesmo.
    return _Retomada(
      episodio: maisAvancado,
      posicao: Duration.zero,
      continuar: true,
    );
  }

  // 3. Nada visto.
  return _Retomada(
    episodio: serie.episodios.first,
    posicao: Duration.zero,
    continuar: false,
  );
}

// ─── Banners ───────────────────────────────────────────────────────────────

class _BannerFilme extends StatelessWidget {
  final String? url;
  const _BannerFilme({required this.url});

  @override
  Widget build(BuildContext context) {
    return _MolduraBanner(
      child: (url != null && url!.isNotEmpty)
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _BannerFallback(),
            )
          : const _BannerFallback(),
    );
  }
}

class _BannerSerie extends StatelessWidget {
  final Future<String?>? posterFuture;
  final String? logoM3U;

  const _BannerSerie({required this.posterFuture, required this.logoM3U});

  @override
  Widget build(BuildContext context) {
    return _MolduraBanner(
      child: FutureBuilder<String?>(
        future: posterFuture,
        builder: (context, snap) {
          final temLogoM3U = logoM3U != null && logoM3U!.isNotEmpty;
          final carregando = snap.connectionState != ConnectionState.done;

          // Ainda buscando o poster e sem logo da M3U -> skeleton.
          if (carregando && !temLogoM3U) {
            return const Shimmer(
              child: SkeletonBox(width: _kPosterW, height: _kPosterH),
            );
          }

          final url = (snap.data != null && snap.data!.isNotEmpty)
              ? snap.data
              : (temLogoM3U ? logoM3U : null);
          if (url == null) return const _BannerFallback();

          return Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const _BannerFallback(),
          );
        },
      ),
    );
  }
}

class _MolduraBanner extends StatelessWidget {
  final Widget child;
  const _MolduraBanner({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.base),
      child: ColoredBox(
        color: AppColors.surface2,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          size: 36,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

// ─── Secoes (sinopse / elenco) ─────────────────────────────────────────────

class _SecaoSinopse extends StatelessWidget {
  final Future<TmdbInfo> infoFuture;
  final double padH;

  const _SecaoSinopse({required this.infoFuture, this.padH = AppSpacing.lg});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloSecao('Sinopse', padH: padH),
        Padding(
          padding: EdgeInsets.fromLTRB(padH, 0, padH, AppSpacing.base),
          child: FutureBuilder<TmdbInfo>(
            future: infoFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SkeletonLinhas(linhas: 4);
              }
              final sinopse = snap.data?.sinopse;
              if (sinopse == null) {
                return Text(
                  'Sinopse não disponível.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                );
              }
              return Text(
                sinopse,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SecaoElenco extends StatelessWidget {
  final Future<TmdbInfo> infoFuture;
  final double padH;

  const _SecaoElenco({required this.infoFuture, this.padH = AppSpacing.lg});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloSecao('Elenco', padH: padH),
        Padding(
          padding: EdgeInsets.fromLTRB(padH, 0, padH, AppSpacing.base),
          child: FutureBuilder<TmdbInfo>(
            future: infoFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Shimmer(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      SkeletonBox(width: 110, height: 30),
                      SkeletonBox(width: 88, height: 30),
                      SkeletonBox(width: 124, height: 30),
                      SkeletonBox(width: 96, height: 30),
                      SkeletonBox(width: 104, height: 30),
                    ],
                  ),
                );
              }
              final elenco = snap.data?.elenco ?? const <String>[];
              if (elenco.isEmpty) {
                return Text(
                  'Elenco não disponível.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                );
              }
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final ator in elenco) _ChipAtor(nome: ator),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChipAtor extends StatelessWidget {
  final String nome;
  const _ChipAtor({required this.nome});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        nome,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
      ),
    );
  }
}

// ─── Episodios da serie ────────────────────────────────────────────────────

class _HeaderTemporada extends StatelessWidget {
  final int numero;
  final int total;
  final double padH;

  const _HeaderTemporada({
    required this.numero,
    required this.total,
    this.padH = AppSpacing.lg,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padH, AppSpacing.base, padH, AppSpacing.xs),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              numero == 0 ? 'ESPECIAIS' : 'TEMPORADA $numero',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.accentBright,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$total ep.',
            style: tabular(
              Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemEpisodio extends StatelessWidget {
  final Canal episodio;
  final double padH;

  const _ItemEpisodio({required this.episodio, this.padH = AppSpacing.lg});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IptvProvider>();
    final progresso = provider.obterProgresso(episodio);
    return InkWell(
      onTap: () {
        provider.registrarVisualizacao(episodio);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TelaPlayer(
              canal: episodio,
              posicaoInicial: progresso != null
                  ? Duration(seconds: progresso.posicaoSeg)
                  : null,
            ),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: padH,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 80,
                height: 46,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _MiniaturaEpisodio(logoUrl: episodio.logoUrl),
                    if (progresso != null && progresso.fracao > 0)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: progresso.fracao,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.accent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.base),
            Expanded(
              child: Text(
                Serie.episodeLabel(episodio),
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          ],
        ),
      ),
    );
  }
}

/// Miniatura do episodio: usa o logo/banner que vem da lista M3U.
/// Cai no icone de play se nao houver imagem ou se o download falhar.
class _MiniaturaEpisodio extends StatelessWidget {
  final String? logoUrl;
  const _MiniaturaEpisodio({required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    if (logoUrl == null || logoUrl!.isEmpty) return const _MiniaturaVazia();
    return Image.network(
      logoUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _MiniaturaVazia(),
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : const _MiniaturaVazia(),
    );
  }
}

class _MiniaturaVazia extends StatelessWidget {
  const _MiniaturaVazia();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: AppColors.textTertiary,
          size: 22,
        ),
      ),
    );
  }
}

// ─── Auxiliares ────────────────────────────────────────────────────────────

class _TituloSecao extends StatelessWidget {
  final String texto;
  final double padH;

  const _TituloSecao(this.texto, {this.padH = AppSpacing.lg});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padH, AppSpacing.base, padH, AppSpacing.sm),
      child: Text(
        texto.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.6,
            ),
      ),
    );
  }
}

class _Divisoria extends StatelessWidget {
  const _Divisoria();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Divider(height: 1),
    );
  }
}
