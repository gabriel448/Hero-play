package com.iptv.iptv_app

import android.os.Bundle
import android.provider.Settings
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Tela cheia no estilo Expo: a barra de navegacao (rodape) fica escondida e,
 * ao arrastar de baixo pra cima, reaparece como um overlay TRANSPARENTE sobre o
 * conteudo (sem redimensionar o app) e some sozinha apos alguns segundos. A
 * barra de status (topo) continua visivel.
 *
 * Feito de forma nativa de proposito: o modo `manual` do Flutter tem um bug de
 * layout shift (a tela "pula") ao revelar a barra. Usar
 * WindowInsetsControllerCompat com BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE evita
 * isso porque a barra transitoria nao consome os insets.
 */
class MainActivity : FlutterActivity() {
    /** Canal usado por `lib/services/dispositivo.dart` para obter o ANDROID_ID. */
    private val canalDispositivo = "heroplay/dispositivo"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configurarTelaCheia()
    }

    /**
     * ANDROID_ID: identificador estavel do aparelho (por app + usuario). E o
     * analogo do LGUDID que o app de TV usa — sobrevive a reinstalar o app,
     * entao o MAC/Key derivado dele NAO muda e a ativacao nao se perde.
     * Nao requer permissao. Zera em reset de fabrica, que e o comportamento
     * esperado (aparelho "novo").
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canalDispositivo)
            .setMethodCallHandler { call, resultado ->
                if (call.method == "androidId") {
                    val id = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID,
                    )
                    resultado.success(id)
                } else {
                    resultado.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        // O Flutter chama SystemChrome.setEnabledSystemUIMode(edgeToEdge) no
        // main(), o que REEXIBE a barra de navegacao depois do nosso hide do
        // onCreate. Reaplicar aqui garante que ela volte a ficar escondida
        // (aparecendo so no swipe de baixo pra cima).
        configurarTelaCheia()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // Reaplica quando a janela recupera o foco (resume, fechar um dialogo do
        // sistema, etc.) — a barra transitoria some sozinha, mas o Flutter pode
        // tentar reexibi-la no boot via edgeToEdge; aqui garantimos que ela
        // volte a ficar escondida.
        if (hasFocus) configurarTelaCheia()
    }

    private fun configurarTelaCheia() {
        // Edge-to-edge: o conteudo desenha por baixo das barras do sistema.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        // Esconde APENAS a barra de navegacao; a de status (topo) permanece.
        controller.hide(WindowInsetsCompat.Type.navigationBars())
        // Swipe revela a barra como overlay transitorio sobre o conteudo e ela
        // se esconde sozinha depois — sem mexer no layout do app.
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
    }
}
