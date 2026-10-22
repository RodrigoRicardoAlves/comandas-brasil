package br.eng.rodrigoricardo.comandas

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * O motor do Flutter fica guardado fora da tela: se o garçom apertar "voltar" ou a tela
 * for destruída, o app continua rodando (importante para o celular líder, que imprime
 * os pedidos dos outros). Ao abrir de novo, a tela se liga ao mesmo motor.
 */
class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(MOTOR)?.let { return it }
        val motor = FlutterEngine(context.applicationContext)
        motor.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        cache.put(MOTOR, motor)
        return motor
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Sistema.ligar(this, flutterEngine)
    }

    override fun onDestroy() {
        Sistema.soltarActivity(this)
        super.onDestroy()
    }

    companion object {
        const val MOTOR = "principal"
    }
}
