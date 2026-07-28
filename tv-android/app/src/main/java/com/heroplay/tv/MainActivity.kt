package com.heroplay.tv

import android.annotation.SuppressLint
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.common.util.UnstableApi
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity

/**
 * Casca Android do app de TV.
 *
 * O `tv-app/` e uma web app completa (HTML/CSS/JS) ja feita para controle
 * remoto e para a regra dos 10 pes — ela e a MESMA base que roda na LG e na
 * Samsung. Aqui ela e embutida em `assets/www/` e servida localmente, entao o
 * app funciona sem depender de nenhum servidor.
 *
 * Alvo: Fire TV Stick, Android TV e TV Box.
 */
@UnstableApi
class MainActivity : AppCompatActivity() {

    private lateinit var web: WebView
    private lateinit var raiz: FrameLayout
    private lateinit var nativo: PlayerNativo

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        web = WebView(this)
        web.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        web.setBackgroundColor(0xFF000000.toInt())

        web.settings.apply {
            javaScriptEnabled = true
            // localStorage E IndexedDB: o app guarda perfis, favoritos, o cache
            // do catalogo e os metadados do TMDB. Sem isto ele reabre do zero.
            domStorageEnabled = true
            databaseEnabled = true
            // Canal ao vivo tem que comecar sozinho, sem "toque para tocar".
            mediaPlaybackRequiresUserGesture = false
            // Listas IPTV quase sempre sao http:// dentro de uma pagina local.
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            allowFileAccess = true
            loadWithOverviewMode = true
            useWideViewPort = true
            cacheMode = WebSettings.LOAD_DEFAULT
            // O app decide o "modo TV" (menos DOM, imagens virtualizadas, sem
            // preload do catalogo inteiro) pelo userAgent — ver EH_TV em app.js.
            // Sem este sufixo ele se acharia um desktop e estouraria a memoria
            // de um Fire Stick.
            userAgentString = "$userAgentString HeroPlayTV SmartTV/1.0"
        }

        web.webViewClient = WebViewClient()
        web.webChromeClient = WebChromeClient()
        web.addJavascriptInterface(Ponte(), "HeroPlayAndroid")
        web.isFocusableInTouchMode = true

        // O video nativo fica ATRAS e o WebView por cima, transparente: a web
        // app desenha os controles sobre a imagem. Sem o fundo transparente a
        // pagina cobriria o video.
        raiz = FrameLayout(this)
        raiz.setBackgroundColor(Color.BLACK)
        web.setBackgroundColor(Color.TRANSPARENT)
        raiz.addView(web)
        nativo = PlayerNativo(this, raiz)
        nativo.aoEvento = { evento ->
            runOnUiThread {
                web.evaluateJavascript(
                    "window.HeroPlayNativo && window.HeroPlayNativo.evento('" + evento + "')",
                    null,
                )
            }
        }

        setContentView(raiz)
        esconderBarras()
        web.loadUrl("file:///android_asset/www/index.html")

        // Botao VOLTAR do controle: o app ja trata a navegacao por history +
        // popstate (foi assim que resolvemos o Back na LG), entao devolvemos o
        // evento para o JS em vez de fechar a Activity na cara do usuario.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                web.evaluateJavascript("window.history.back()", null)
            }
        })
    }

    /** Tela cheia de verdade: sem barra de status nem de navegacao. */
    private fun esconderBarras() {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            )
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) esconderBarras()
    }

    override fun onPause() {
        super.onPause()
        web.onPause()
    }

    override fun onResume() {
        super.onResume()
        web.onResume()
        esconderBarras()
    }

    override fun onDestroy() {
        nativo.soltar()
        web.destroy()
        super.onDestroy()
    }

    /**
     * Ponte com o JS. Alem de sair do app, expoe o PLAYER NATIVO — e por aqui
     * que a web app toca MKV/HEVC/MPEG-TS, que o WebView sozinho nao abre.
     * Todo metodo salta para a UI thread: o ExoPlayer so aceita chamadas dela.
     */
    inner class Ponte {
        /**
         * Toda chamada do player passa por aqui: salta para a UI thread E
         * engole excecao. Um erro no player NAO pode fechar o app — foi o que
         * aconteceu quando o `area()` recebia LayoutParams do tipo errado.
         */
        private fun naUi(acao: () -> Unit) = runOnUiThread {
            try { acao() } catch (e: Throwable) { Log.e("HeroPlay", "player", e) }
        }

        /** `window.close()` nao encerra uma Activity — isto encerra. */
        @JavascriptInterface
        fun sair() {
            runOnUiThread { finish() }
        }

        /** `true` diz ao JS que existe player nativo disponivel. */
        @JavascriptInterface
        fun temPlayer(): Boolean = true

        @JavascriptInterface
        fun abrir(url: String, posicaoSeg: Double, mudo: Boolean) =
            naUi { nativo.abrir(url, posicaoSeg, mudo) }

        @JavascriptInterface
        fun parar() = naUi { nativo.parar() }

        @JavascriptInterface
        fun pausar() = naUi { nativo.pausar() }

        @JavascriptInterface
        fun retomar() = naUi { nativo.retomar() }

        @JavascriptInterface
        fun buscar(seg: Double) = naUi { nativo.buscar(seg) }

        @JavascriptInterface
        fun mudo(on: Boolean) = naUi { nativo.mudo(on) }

        /** Retangulo onde o video deve aparecer, em CSS px. */
        @JavascriptInterface
        fun area(x: Float, y: Float, w: Float, h: Float) = naUi { nativo.area(x, y, w, h) }

        /** JSON: posicao, duracao, tocando, buffering. Lido em polling pelo JS. */
        @JavascriptInterface
        fun estado(): String =
            try { nativo.estado() } catch (_: Throwable) { """{"pos":0,"dur":0,"tocando":false,"buffering":false}""" }
    }
}
