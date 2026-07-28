package com.heroplay.tv

import android.content.Context
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
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

    /** Chamado a cada evento relevante — a MainActivity repassa ao JS. */
    var aoEvento: ((String) -> Unit)? = null

    private fun garantir(): ExoPlayer {
        player?.let { return it }
        val p = ExoPlayer.Builder(ctx).build()
        val pv = PlayerView(ctx).apply {
            useController = false                       // os controles sao da web app
            resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            setShutterBackgroundColor(0xFF000000.toInt())
            setBackgroundColor(0xFF000000.toInt())
            this.player = p
        }
        // Indice 0 = atras do WebView.
        raiz.addView(pv, 0, FrameLayout.LayoutParams(0, 0))
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
                aoEvento?.invoke("error")
            }
        })
        player = p
        view = pv
        return p
    }

    fun abrir(url: String, posicaoSeg: Double, mudo: Boolean) {
        val p = garantir()
        p.volume = if (mudo) 0f else 1f
        p.setMediaItem(MediaItem.fromUri(url))
        p.prepare()
        if (posicaoSeg > 0) p.seekTo((posicaoSeg * 1000).toLong())
        p.playWhenReady = true
        aoEvento?.invoke("loadstart")
    }

    fun parar() {
        player?.stop()
        player?.clearMediaItems()
        area(0f, 0f, 0f, 0f)
    }

    fun soltar() {
        player?.release()
        player = null
        view?.let { raiz.removeView(it) }
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

    /** Estado atual em JSON — a web app le isto para a barra de progresso. */
    fun estado(): String {
        val p = player
        val pos = (p?.currentPosition ?: 0L) / 1000.0
        val durMs = p?.duration ?: 0L
        val dur = if (durMs > 0) durMs / 1000.0 else 0.0
        val tocando = p?.isPlaying == true
        val buff = p?.playbackState == Player.STATE_BUFFERING
        return """{"pos":$pos,"dur":$dur,"tocando":$tocando,"buffering":$buff}"""
    }
}
