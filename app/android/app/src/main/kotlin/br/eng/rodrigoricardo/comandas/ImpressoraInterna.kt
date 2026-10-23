package br.eng.rodrigoricardo.comandas

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.sunmi.peripheral.printer.InnerPrinterCallback
import com.sunmi.peripheral.printer.InnerPrinterManager
import com.sunmi.peripheral.printer.InnerResultCallback
import com.sunmi.peripheral.printer.SunmiPrinterService

/**
 * Impressora embutida das maquininhas Sunmi (P2, V2...). Recebe os mesmos bytes ESC/POS
 * que vão para a impressora de rede. Em celular comum o serviço não existe e [existe] fica false.
 */
object ImpressoraInterna {
    private var servico: SunmiPrinterService? = null
    private var tentou = false
    private val principal = Handler(Looper.getMainLooper())

    fun ligar(ctx: Context) {
        if (tentou) return
        tentou = true
        try {
            InnerPrinterManager.getInstance().bindService(ctx.applicationContext, object : InnerPrinterCallback() {
                override fun onConnected(s: SunmiPrinterService) { servico = s }
                override fun onDisconnected() { servico = null; tentou = false }
            })
        } catch (_: Throwable) {
            // não é Sunmi
        }
    }

    val existe: Boolean get() = servico != null

    /** Situação da impressora em texto; null = pronta. */
    private fun problema(s: SunmiPrinterService): String? = when (val e = try { s.updatePrinterState() } catch (_: Throwable) { 1 }) {
        1 -> null
        2 -> "A impressora da maquininha está iniciando. Tente de novo."
        3 -> "Falha de comunicação com a impressora da maquininha"
        4 -> "A maquininha está sem papel"
        5 -> "A impressora da maquininha está quente demais. Espere esfriar."
        6 -> "A tampa do papel da maquininha está aberta"
        7 -> "O cortador de papel da maquininha travou"
        505 -> "Esta maquininha não tem impressora"
        else -> if (e in 8..9) null else "Impressora da maquininha com erro ($e)"
    }

    /** Imprime e devolve null quando deu certo, ou a mensagem de erro. */
    fun imprimir(dados: ByteArray, fim: (String?) -> Unit) {
        val s = servico
        if (s == null) { fim("Este aparelho não tem impressora embutida"); return }
        problema(s)?.let { fim(it); return }
        var respondeu = false
        val responder = { msg: String? ->
            principal.post { if (!respondeu) { respondeu = true; fim(msg) } }
        }
        principal.postDelayed({ responder("A impressora da maquininha não respondeu") }, 20000)
        try {
            // modo transação: só avisa quando o papel saiu (ou deu erro)
            s.enterPrinterBuffer(true)
            s.sendRAWData(dados, null)
            s.exitPrinterBufferWithCallback(true, object : InnerResultCallback() {
                override fun onRunResult(ok: Boolean) {}
                override fun onReturnString(r: String?) {}
                override fun onRaiseException(codigo: Int, msg: String?) {
                    responder("Impressora da maquininha: ${msg ?: codigo}")
                }
                override fun onPrintResult(codigo: Int, msg: String?) {
                    responder(if (codigo == 0) null else (problema(s) ?: "Impressora da maquininha: ${msg ?: codigo}"))
                }
            })
        } catch (e: Throwable) {
            responder("Impressora da maquininha: ${e.message ?: e}")
        }
    }
}
