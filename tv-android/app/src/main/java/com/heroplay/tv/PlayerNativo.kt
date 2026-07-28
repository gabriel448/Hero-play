package com.heroplay.tv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView

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
     * (preview da TV ao vivo ou tela cheia). Coordenadas em CSS px; aqui viram
     * pixels reais pela densidade da tela. Largura 0 esconde.
     */
    fun area(x: Float, y: Float, w: Float, h: Float) {
        val pv = view ?: return
        val d = ctx.resources.displayMetrics.density
        // ⚠️ TEM que ser FrameLayout.LayoutParams. Com um MarginLayoutParams
        // "cru" o FrameLayout estoura ClassCastException no onMeasure e o app
        // FECHA no instante em que a midia comeca — foi exatamente esse o bug.
        val lp = FrameLayout.LayoutParams((w * d).toInt(), (h * d).toInt())
        lp.leftMargin = (x * d).toInt()
        lp.topMargin = (y * d).toInt()
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
        private const val ESTADO_VAZIO =
            """{"pos":0,"dur":0,"tocando":false,"buffering":false}"""
    }
}
