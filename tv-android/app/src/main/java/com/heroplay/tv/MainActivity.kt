package com.heroplay.tv

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.provider.Settings
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
import android.view.inputmethod.InputMethodManager
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

    companion object {
        /** `--bg` do tv-app (styles.css). Tem que ser o MESMO valor. */
        private const val COR_FUNDO = 0xFF0F0E0D.toInt()

        /**
         * Fracao de cada borda reservada contra o overscan da TV.
         *
         * DESLIGADA (0f). Ficou 2% por uma versao e o resultado foi pior que o
         * problema: a TV testada NAO corta nada, entao a margem virou so uma
         * moldura preta em volta do app. Fica aqui, documentada, pra quando
         * aparecer uma TV que realmente corte — e ai basta 0.02f.
         */
        private const val MARGEM_SEGURA = 0f
    }

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
        // COR DE FUNDO DO APP, nao preto puro. Enquanto o video nativo toca, a
        // pagina inteira fica transparente (e a unica forma de o video, que esta
        // ATRAS do WebView, aparecer) — e o que se ve por tras dela e este
        // container. Com preto puro a tela de canais trocava de cor no instante
        // em que o canal comecava a tocar. A tela cheia continua preta de
        // verdade: quem pinta ali e o PlayerView, que tem fundo proprio.
        raiz.setBackgroundColor(COR_FUNDO)
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
        aplicarMargemDeSeguranca()
        web.loadUrl("file:///android_asset/www/index.html")

        // Botao VOLTAR do controle: o app ja trata a navegacao por history +
        // popstate (foi assim que resolvemos o Back na LG), entao devolvemos o
        // evento para o JS em vez de fechar a Activity na cara do usuario.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Teclado do SISTEMA aberto? O Back fecha ELE primeiro — como faria
                // em qualquer app Android. Sem isto o usuario ficava preso: o Back
                // ia direto pro JS, o IME continuava por cima e nao havia saida.
                if (fecharTecladoDoSistema()) return
                web.evaluateJavascript("window.history.back()", null)
            }
        })
    }

    /**
     * Fecha o teclado do sistema, se ele estiver ligado a algum campo.
     *
     * `isAcceptingText` = existe conexao de entrada ativa. Junto com o
     * `clearFocus` do WebView a conexao cai, entao o proximo Back segue o
     * caminho normal — no pior caso engolimos UM toque, nunca prendemos.
     *
     * Na pratica isto quase nunca dispara: a web app nao deixa mais o campo
     * receber foco nativo no Android (ver setFocus em spatial-nav.js), justo
     * pra o IME nao abrir sozinho. Fica como rede de seguranca.
     */
    private fun fecharTecladoDoSistema(): Boolean {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return false
        if (!imm.isAcceptingText) return false
        try { imm.hideSoftInputFromWindow(web.windowToken, 0) } catch (e: Throwable) { Log.e("HeroPlay", "ime", e) }
        web.clearFocus()
        return true
    }

    /**
     * OVERSCAN: quase toda TV corta as bordas do sinal HDMI (uns 2%), e ai a
     * sidebar fica colada no canto e o lado direito some. Numa LG/Samsung isso
     * nao acontece porque o app E da TV — aqui o app chega por HDMI.
     *
     * A solucao e uma margem de seguranca no CONTAINER: o WebView encolhe, a
     * pagina continua com a MESMA viewport (o Chromium reescala o layout, sem
     * borrar — nada de `transform: scale`) e o video nativo, que e irmao do
     * WebView dentro do mesmo padding, acompanha automaticamente.
     *
     * Se a TV estiver com "Just Scan"/"Tela 100%" ligado, isto so deixa uma
     * borda preta de 2% que some no fundo do app.
     */
    private fun aplicarMargemDeSeguranca() {
        if (MARGEM_SEGURA <= 0f) return
        // O video IGNORA a margem (ver `PlayerNativo.area`): filme em tela cheia
        // nunca pode ganhar borda preta nossa — quem decide o enquadramento e o
        // proprio filme. Por isso o container nao recorta o que passa do padding.
        raiz.clipToPadding = false
        raiz.post {
            if (raiz.width <= 0 || raiz.height <= 0) return@post
            val px = (raiz.width * MARGEM_SEGURA).toInt()
            val py = (raiz.height * MARGEM_SEGURA).toInt()
            raiz.setPadding(px, py, px, py)
        }
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

    /**
     * App saiu da tela (Home do controle, troca de app): ENCERRA a reproducao.
     *
     * Sem isto o stream continua aberto em segundo plano e o provedor segue
     * contando aquela "tela" ocupada — o usuario nao esta nem vendo. Depois de
     * algumas idas e voltas o servidor recusa com 403.
     */
    override fun onStop() {
        super.onStop()
        try { nativo.parar() } catch (e: Throwable) { Log.e("HeroPlay", "parar", e) }
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

        /**
         * ID ESTAVEL do aparelho — o MAC/Key da ativacao sao derivados dele.
         *
         * Sem isto o app caia num MAC sorteado e guardado em localStorage: o
         * WebView perde o localStorage ao DESINSTALAR, entao reinstalar gerava
         * outro MAC e exigia nova ativacao. O ANDROID_ID e amarrado ao
         * aparelho + chave de assinatura do APK: reinstalar o MESMO app
         * devolve o MESMO valor. So muda em reset de fabrica, que e o
         * comportamento esperado ("aparelho novo"). Nao exige permissao.
         */
        @JavascriptInterface
        fun idDispositivo(): String =
            try {
                Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
            } catch (_: Throwable) { "" }

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

        /**
         * Retangulo onde o video deve aparecer, em CSS px, acompanhado do
         * tamanho da viewport (tambem em CSS px) — e a viewport que da o fator
         * de conversao para pixels de verdade. Ver `PlayerNativo.area`.
         */
        @JavascriptInterface
        fun area(x: Float, y: Float, w: Float, h: Float, larguraCss: Float, alturaCss: Float) =
            naUi { nativo.area(x, y, w, h, larguraCss, alturaCss) }

        /** JSON: posicao, duracao, tocando, buffering. Lido em polling pelo JS. */
        @JavascriptInterface
        fun estado(): String =
            try { nativo.estado() } catch (_: Throwable) { """{"pos":0,"dur":0,"tocando":false,"buffering":false}""" }
    }
}
