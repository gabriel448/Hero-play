package com.heroplay.tv

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
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
class MainActivity : AppCompatActivity() {

    private lateinit var web: WebView

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

        setContentView(web)
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
        web.destroy()
        super.onDestroy()
    }

    /** Ponte minima para o JS. Ver `sairDoApp()` em `tv-app/app.js`. */
    inner class Ponte {
        /** `window.close()` nao encerra uma Activity — isto encerra. */
        @JavascriptInterface
        fun sair() {
            runOnUiThread { finish() }
        }
    }
}
