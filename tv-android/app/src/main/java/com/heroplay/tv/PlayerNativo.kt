package com.heroplay.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import java.util.Locale

/**
 * Player NATIVO (ExoPlayer) que roda ATRAS do WebView.
 *
 * Por que existe: o `<video>` do WebView usa a pipeline do Chromium, que so abre
 * MP4/WebM. Filme 4K vem em MKV e canal ao vivo vem em MPEG-TS — nenhum dos dois
 * toca la, e foi por isso que no TV Box o canal ficava "instavel, trocando de
 * fonte" e o 4K nao saia do lugar. Na LG/Samsung o mesmo `<video>` e a pipeline
 * DO SISTEMA, que le tudo isso — dai a diferenca.
 *
 * O ExoPlayer abre MKV, HEVC, MPEG-TS e HLS. A interface continua sendo a web
 * app: ela desenha os controles POR CIMA (WebView transparente) e comanda a
 * reproducao pela ponte JS. Ver `PlayerNativo` em `tv-app/app.js`.
 */
@UnstableApi
class PlayerNativo(private val ctx: Context, private val raiz: FrameLayout) {

    private var player: ExoPlayer? = null
    private var view: PlayerView? = null

    // ⚠️ O ExoPlayer SO pode ser lido na thread principal. Os metodos da ponte
    // JS rodam na thread do JavaBridge do WebView, entao ler `currentPosition`
    // direto dali lanca IllegalStateException — e era isso que zerava a barra
    // de progresso e deixava o play/pause sem efeito (o JS recebia sempre
    // pos=0, dur=0, tocando=false). Solucao: um retrato atualizado NA THREAD
    // CERTA, que o JS so le.
    @Volatile
    private var retrato = ESTADO_VAZIO
    private val ui = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            atualizarRetrato()
            ui.postDelayed(this, 300)
        }
    }

    private fun atualizarRetrato() {
        val p = player
        val pos = (p?.currentPosition ?: 0L).coerceAtLeast(0L) / 1000.0
        val durMs = p?.duration ?: 0L
        val dur = if (durMs > 0) durMs / 1000.0 else 0.0
        val tocando = p?.isPlaying == true
        val buff = p?.playbackState == Player.STATE_BUFFERING
        retrato = """{"pos":$pos,"dur":$dur,"tocando":$tocando,"buffering":$buff}"""
    }

    // ── FAIXAS de audio e legenda ────────────────────────────────────────────
    //
    // Mesma restricao de thread do `retrato`: a lista de faixas SO pode ser lida
    // na thread principal, e o JS pergunta pela ponte. Entao mantemos um retrato
    // em JSON + o mapa de volta (indice plano -> grupo/faixa do ExoPlayer), os
    // dois refeitos em `onTracksChanged` (que roda na thread certa).
    private class Alvo(val tipo: Int, val grupo: TrackGroup, val indice: Int)

    @Volatile
    private var faixasJson = FAIXAS_VAZIO
    private var mapaAudio = listOf<Alvo>()
    private var mapaTexto = listOf<Alvo>()

    private fun atualizarFaixas() {
        val p = player
        if (p == null) { faixasJson = FAIXAS_VAZIO; mapaAudio = listOf(); mapaTexto = listOf(); return }
        val audio = mutableListOf<Alvo>()
        val texto = mutableListOf<Alvo>()
        val jsonAudio = StringBuilder()
        val jsonTexto = StringBuilder()
        for (g in p.currentTracks.groups) {
            val ehAudio = g.type == C.TRACK_TYPE_AUDIO
            val ehTexto = g.type == C.TRACK_TYPE_TEXT
            if (!ehAudio && !ehTexto) continue
            for (k in 0 until g.length) {
                // Faixa que este aparelho NAO decodifica nao entra na lista: o
                // usuario escolheria e nada aconteceria.
                if (!g.isTrackSupported(k)) continue
                val lista = if (ehAudio) audio else texto
                val json = if (ehAudio) jsonAudio else jsonTexto
                val i = lista.size
                lista.add(Alvo(g.type, g.mediaTrackGroup, k))
                if (json.isNotEmpty()) json.append(',')
                json.append("""{"i":$i,"rotulo":"${escapar(rotulo(g.getTrackFormat(k), i, ehAudio))}","sel":${g.isTrackSelected(k)}}""")
            }
        }
        mapaAudio = audio
        mapaTexto = texto
        faixasJson = """{"audio":[$jsonAudio],"texto":[$jsonTexto]}"""
    }

    /** Nome amigavel da faixa: rotulo do arquivo > idioma por extenso > numero. */
    private fun rotulo(f: Format, n: Int, ehAudio: Boolean): String {
        val label = f.label
        if (!label.isNullOrBlank()) return label
        val lang = f.language
        if (!lang.isNullOrBlank() && lang != "und") {
            val nome = Locale(lang).displayLanguage
            if (nome.isNotBlank() && !nome.equals(lang, true)) {
                return nome.replaceFirstChar { it.uppercase() }
            }
            return lang.uppercase()
        }
        return (if (ehAudio) "Audio " else "Legenda ") + (n + 1)
    }

    private fun escapar(s: String) = s.replace("\\", "\\\\").replace("\"", "\\\"")

    /** JSON das faixas disponiveis — lido em polling pelo JS (thread da ponte). */
    fun faixas(): String = faixasJson

    /**
     * Escolhe uma faixa. `tipo` = "audio" | "texto"; indice negativo em "texto"
     * DESLIGA a legenda. So pode rodar na thread principal (a ponte garante).
     */
    fun selecionarFaixa(tipo: String, indice: Int) {
        val p = player ?: return
        val ehTexto = tipo == "texto"
        if (ehTexto && indice < 0) {
            p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
            atualizarFaixas()
            return
        }
        val alvo = (if (ehTexto) mapaTexto else mapaAudio).getOrNull(indice) ?: return
        p.trackSelectionParameters = p.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(alvo.tipo, false)
            .setOverrideForType(TrackSelectionOverride(alvo.grupo, alvo.indice))
            .build()
        atualizarFaixas()
    }

    /** Chamado a cada evento relevante — a MainActivity repassa ao JS. */
    var aoEvento: ((String) -> Unit)? = null

    private fun garantir(): ExoPlayer {
        player?.let { return it }
        // ⚠️ User-Agent: MUITO servidor de IPTV recusa cliente desconhecido, e o
        // padrao do ExoPlayer e "ExoPlayerLib/...". O app mobile ja tinha
        // aprendido isso — a 1a estrategia dele e justamente o UA do VLC. Sem
        // trocar, o servidor devolve 403/404 e vira "erro de formato" na tela.
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent("VLC/3.0.20 LibVLC/3.0.20")
            .setAllowCrossProtocolRedirects(true)   // http -> https no meio do caminho
            .setConnectTimeoutMs(20000)
            .setReadTimeoutMs(20000)
        val p = ExoPlayer.Builder(ctx)
            .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(ctx, http)))
            .build()
        // A superficie e criada UMA vez e reaproveitada: o player pode ser
        // solto e recriado (ver `parar`) sem perder o lugar na tela.
        val pv = view ?: PlayerView(ctx).apply {
            useController = false                       // os controles sao da web app
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(0xFF000000.toInt())
            setBackgroundColor(0xFF000000.toInt())
            // Indice 0 = atras do WebView.
            raiz.addView(this, 0, FrameLayout.LayoutParams(0, 0))
            view = this
        }
        pv.player = p
        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> aoEvento?.invoke("waiting")
                    Player.STATE_READY -> aoEvento?.invoke("canplay")
                    Player.STATE_ENDED -> aoEvento?.invoke("ended")
                }
            }
            override fun onIsPlayingChanged(tocando: Boolean) {
                aoEvento?.invoke(if (tocando) "playing" else "pause")
            }
            // A lista de faixas so existe depois de o container ser lido, e muda
            // quando o usuario troca de faixa. Refeita AQUI porque este callback
            // roda na thread principal — a ponte JS nao poderia ler dali.
            override fun onTracksChanged(tracks: Tracks) {
                atualizarFaixas()
                aoEvento?.invoke("faixas")
            }
            override fun onPlayerError(error: PlaybackException) {
                // O codigo vai junto: e o que permite saber, olhando a TV, se
                // foi rede, HTTP, container ou codec.
                Log.e("HeroPlay", "player: " + error.errorCodeName, error)
                aoEvento?.invoke("error:" + error.errorCodeName)
            }
        })
        player = p
        return p
    }

    fun abrir(url: String, posicaoSeg: Double, mudo: Boolean) {
        val p = garantir()
        // Fecha a conexao anterior ANTES de abrir outra. Provedor de IPTV conta
        // SESSAO: se a antiga continuar de pe, trocar de canal/filme vai
        // somando "telas" ate o servidor devolver 403 (ERROR_CODE_IO_BAD_HTTP_STATUS).
        p.stop()
        p.clearMediaItems()
        p.volume = if (mudo) 0f else 1f
        p.setMediaItem(MediaItem.fromUri(url))
        p.prepare()
        if (posicaoSeg > 0) p.seekTo((posicaoSeg * 1000).toLong())
        p.playWhenReady = true
        ui.removeCallbacks(tick)
        ui.post(tick)
        aoEvento?.invoke("loadstart")
    }

    /**
     * Encerra a reproducao E a conexao com o servidor.
     *
     * `stop()` sozinho nao basta: o socket pode ficar no pool de keep-alive e o
     * provedor segue contando a sessao. Aqui soltamos o player inteiro — a
     * superficie fica, e o proximo `abrir` recria o player em milissegundos.
     */
    fun parar() {
        ui.removeCallbacks(tick)
        retrato = ESTADO_VAZIO
        faixasJson = FAIXAS_VAZIO
        mapaAudio = listOf(); mapaTexto = listOf()
        area(0f, 0f, 0f, 0f)
        player?.let {
            it.stop()
            it.clearMediaItems()
            it.release()
        }
        player = null
        view?.player = null
    }

    fun soltar() {
        ui.removeCallbacks(tick)
        player?.let { it.stop(); it.clearMediaItems(); it.release() }
        player = null
        view?.let { it.player = null; raiz.removeView(it) }
        view = null
    }

    fun pausar() { player?.playWhenReady = false }
    fun retomar() { player?.playWhenReady = true }
    fun buscar(seg: Double) { player?.seekTo((seg * 1000).toLong()) }
    fun mudo(on: Boolean) { player?.volume = if (on) 0f else 1f }

    /**
     * Posiciona a superficie de video no MESMO retangulo que a web app reservou
     * (preview da TV ao vivo ou tela cheia). Largura 0 esconde.
     *
     * `x/y/w/h` vem em CSS px, junto com o TAMANHO DA VIEWPORT em CSS px
     * (`larguraCss/alturaCss`) — e dai sai o fator exato de conversao.
     *
     * ⚠️ Antes isto usava `displayMetrics.density`, e so acertava por acaso: a
     * pagina tem viewport FIXA (ver o <meta viewport> do index.html), entao ela
     * NAO e medida em dp. Com a densidade errada a superficie saia deslocada e
     * esticada — o video da preview ia parar fora da moldura e a tela cheia
     * nascia torta. Medindo a area util real do container o fator fica certo em
     * qualquer TV, com qualquer densidade e com qualquer viewport.
     */
    @JvmOverloads
    fun area(x: Float, y: Float, w: Float, h: Float, larguraCss: Float = 0f, alturaCss: Float = 0f) {
        val pv = view ?: return
        val utilW = (raiz.width - raiz.paddingLeft - raiz.paddingRight).toFloat()
        val utilH = (raiz.height - raiz.paddingTop - raiz.paddingBottom).toFloat()
        val d = ctx.resources.displayMetrics.density
        // Antes do 1o layout `raiz.width` e 0: cai na densidade e o proximo tick
        // (a cada 500 ms, vindo do JS) corrige sozinho.
        val ex = if (larguraCss > 0f && utilW > 0f) utilW / larguraCss else d
        val ey = if (alturaCss > 0f && utilH > 0f) utilH / alturaCss else ex
        // Tela cheia: em vez de confiar na conta, casa com a area util INTEIRA.
        // Assim o filme em tela cheia nunca nasce com faixa preta de um lado.
        val cheio = larguraCss > 0f && alturaCss > 0f &&
            w >= larguraCss * 0.98f && h >= alturaCss * 0.98f
        // ⚠️ TEM que ser FrameLayout.LayoutParams. Com um MarginLayoutParams
        // "cru" o FrameLayout estoura ClassCastException no onMeasure e o app
        // FECHA no instante em que a midia comeca — foi exatamente esse o bug.
        val lp = if (cheio) {
            // Tela cheia = TELA inteira, inclusive por cima da margem de
            // seguranca do container (margens negativas): a borda preta so pode
            // vir do enquadramento do filme, nunca de nos.
            if (raiz.width > 0 && raiz.height > 0) {
                FrameLayout.LayoutParams(raiz.width, raiz.height).apply {
                    leftMargin = -raiz.paddingLeft
                    topMargin = -raiz.paddingTop
                }
            } else {
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                )
            }
        } else {
            FrameLayout.LayoutParams((w * ex).toInt(), (h * ey).toInt()).apply {
                leftMargin = (x * ex).toInt()
                topMargin = (y * ey).toInt()
            }
        }
        pv.layoutParams = lp
        pv.visibility = if (w <= 0f || h <= 0f) View.GONE else View.VISIBLE
        pv.requestLayout()
    }

    /**
     * Estado atual em JSON — a web app le isto para a barra de progresso.
     * Devolve o RETRATO (volatil), nunca o player: esta chamada vem da thread
     * do JavaBridge, e tocar no ExoPlayer dali estoura.
     */
    fun estado(): String = retrato

    companion object {
        private const val FAIXAS_VAZIO = """{"audio":[],"texto":[]}"""
        private const val ESTADO_VAZIO =
            """{"pos":0,"dur":0,"tocando":false,"buffering":false}"""
    }
}
