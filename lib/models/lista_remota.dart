/// Definicao de uma lista guardada na nuvem (Supabase), pertencente a uma conta.
///
/// Diferente de [ListaM3U], aqui NAO guardamos os canais — apenas a "receita"
/// da lista (nome + URL da M3U + URL do EPG). O app baixa e faz o parse da
/// M3U localmente e mantem os canais em cache no Hive. Assim o banco fica leve
/// e a sincronizacao entre aparelhos transmite poucos bytes.
class ListaRemota {
  /// Id (uuid) da linha no Supabase.
  final String id;

  /// Nome amigavel escolhido pelo usuario.
  final String nome;

  /// URL da lista M3U — tambem e a chave logica que casa com [ListaM3U.fonte].
  final String fonteUrl;

  /// URL do guia de programacao (XMLTV), opcional.
  final String? epgUrl;

  const ListaRemota({
    required this.id,
    required this.nome,
    required this.fonteUrl,
    this.epgUrl,
  });

  factory ListaRemota.fromMap(Map<String, dynamic> map) => ListaRemota(
        id: map['id'] as String,
        nome: (map['nome'] as String?) ?? 'Lista sem nome',
        fonteUrl: map['fonte_url'] as String,
        epgUrl: map['epg_url'] as String?,
      );
}
