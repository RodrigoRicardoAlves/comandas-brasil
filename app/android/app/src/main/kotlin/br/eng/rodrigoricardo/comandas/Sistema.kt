package br.eng.rodrigoricardo.comandas

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.ComponentName
import android.net.Uri
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Coisas do Android que o Flutter não tem pronto: serviço do líder, descoberta mDNS (NSD),
 * modo economia de bateria, sinal do Wi-Fi e trava de multicast (para receber broadcast UDP).
 */
object Sistema {
    private const val TIPO = "_comandas._tcp."
    private var canal: MethodChannel? = null
    private var activity: Activity? = null
    private lateinit var ctx: Context
    private val principal = Handler(Looper.getMainLooper())

    private var multicast: WifiManager.MulticastLock? = null
    private var nsd: NsdManager? = null
    private var registro: NsdManager.RegistrationListener? = null
    private var busca: NsdManager.DiscoveryListener? = null
    private val paraResolver = ArrayDeque<NsdServiceInfo>()
    private var resolvendo = false

    fun ligar(act: Activity, motor: FlutterEngine) {
        activity = act
        ctx = act.applicationContext
        val c = MethodChannel(motor.dartExecutor.binaryMessenger, "comandas/sistema")
        canal = c
        c.setMethodCallHandler { call, res ->
            try {
                when (call.method) {
                    "estado" -> res.success(estado())
                    "multicast" -> { multicast(call.argument<Boolean>("ligar") == true); res.success(true) }
                    "servico" -> res.success(servico(call.argument<Boolean>("ligar") == true, call.argument<String>("texto") ?: ""))
                    "pedirNotificacao" -> { pedirNotificacao(); res.success(true) }
                    "nsdIniciar" -> {
                        nsdIniciar(call.argument<Int>("porta")!!, call.argument<String>("bar")!!, call.argument<String>("id")!!)
                        res.success(true)
                    }
                    "nsdParar" -> { nsdParar(); res.success(true) }
                    "abrirBateria" -> { abrirBateria(); res.success(true) }
                    "pedirSemOtimizacao" -> res.success(pedirSemOtimizacao())
                    "abrirAppConfig" -> res.success(abrir(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + ctx.packageName))))
                    "abrirAutoInicio" -> res.success(abrirAutoInicio())
                    "abrirUrl" -> res.success(abrir(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!))))
                    "pedirRedeLocal" -> { pedirRedeLocal(); res.success(true) }
                    // identificador do Android: o mesmo depois de reinstalar o app
                    "idAparelho" -> res.success(Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ANDROID_ID))
                    else -> res.notImplemented()
                }
            } catch (e: Exception) {
                res.error("erro", e.message, null)
            }
        }
    }

    fun soltarActivity(act: Activity) {
        if (activity === act) activity = null
    }

    private fun estado(): Map<String, Any?> {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wifi = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val rssi = try { wifi.connectionInfo?.rssi } catch (_: Exception) { null }
        return mapOf(
            "economia" to pm.isPowerSaveMode,
            "rssi" to rssi,
            "otimizado" to !pm.isIgnoringBatteryOptimizations(ctx.packageName),
            "notificacao" to (Build.VERSION.SDK_INT < 33 ||
                ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED),
        )
    }

    private fun multicast(ligar: Boolean) {
        if (ligar) {
            if (multicast == null) {
                val wifi = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicast = wifi.createMulticastLock("comandas").apply { setReferenceCounted(false); acquire() }
            }
        } else {
            multicast?.release()
            multicast = null
        }
    }

    /** Liga/desliga o serviço com notificação fixa. Devolve false se o Android não deixou. */
    private fun servico(ligar: Boolean, texto: String): Boolean {
        val i = Intent(ctx, ServicoLider::class.java)
        if (!ligar) {
            ctx.stopService(i)
            return true
        }
        i.putExtra("texto", texto)
        return try {
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            true
        } catch (e: Exception) {
            false // ex.: app em segundo plano no Android 12+; tenta de novo quando voltar à tela
        }
    }

    private fun pedirNotificacao() {
        val a = activity ?: return
        if (Build.VERSION.SDK_INT >= 33 &&
            a.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            a.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 10)
        }
    }

    private fun abrir(i: Intent): Boolean = try {
        ctx.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    /** Janela do Android "Permitir que o app rode em segundo plano?" (um toque). */
    private fun pedirSemOtimizacao(): Boolean {
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (pm.isIgnoringBatteryOptimizations(ctx.packageName)) return true
        @Suppress("BatteryLife")
        val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + ctx.packageName))
        return abrir(i) || abrir(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
    }

    /** Tela de "início automático" de cada fabricante (Xiaomi, Oppo, Vivo, Huawei...). */
    private fun abrirAutoInicio(): Boolean {
        val telas = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
        )
        for ((pacote, tela) in telas) {
            if (abrir(Intent().setComponent(ComponentName(pacote, tela)))) return true
        }
        return false
    }

    /** Android 16+: permissão para falar com aparelhos da rede local (impressora e outros celulares). */
    private fun pedirRedeLocal() {
        val a = activity ?: return
        val p = "android.permission.ACCESS_LOCAL_NETWORK"
        if (Build.VERSION.SDK_INT >= 36 && a.checkSelfPermission(p) != PackageManager.PERMISSION_GRANTED) {
            a.requestPermissions(arrayOf(p), 11)
        }
    }

    private fun abrirBateria() {
        val i = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        ctx.startActivity(i)
    }

    // ------------------------------------------------------------------ mDNS (NSD)

    private fun nsdIniciar(porta: Int, bar: String, id: String) {
        nsdParar()
        val m = ctx.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd = m
        val info = NsdServiceInfo().apply {
            serviceName = "comandas-" + id.take(8)
            serviceType = TIPO
            port = porta
            setAttribute("bar", bar)
            setAttribute("id", id)
        }
        val r = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(s: NsdServiceInfo) {}
            override fun onRegistrationFailed(s: NsdServiceInfo, erro: Int) {}
            override fun onServiceUnregistered(s: NsdServiceInfo) {}
            override fun onUnregistrationFailed(s: NsdServiceInfo, erro: Int) {}
        }
        registro = r
        m.registerService(info, NsdManager.PROTOCOL_DNS_SD, r)

        val b = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(tipo: String) {}
            override fun onDiscoveryStopped(tipo: String) {}
            override fun onStartDiscoveryFailed(tipo: String, erro: Int) {}
            override fun onStopDiscoveryFailed(tipo: String, erro: Int) {}
            override fun onServiceLost(s: NsdServiceInfo) {}
            override fun onServiceFound(s: NsdServiceInfo) {
                if (s.serviceName.startsWith("comandas-")) principal.post { paraResolver.addLast(s); resolverProximo() }
            }
        }
        busca = b
        m.discoverServices(TIPO, NsdManager.PROTOCOL_DNS_SD, b)
    }

    // o Android só resolve um serviço por vez
    private fun resolverProximo() {
        val m = nsd ?: return
        if (resolvendo) return
        val s = paraResolver.removeFirstOrNull() ?: return
        resolvendo = true
        @Suppress("DEPRECATION")
        m.resolveService(s, object : NsdManager.ResolveListener {
            override fun onResolveFailed(s: NsdServiceInfo, erro: Int) {
                principal.post { resolvendo = false; resolverProximo() }
            }

            override fun onServiceResolved(s: NsdServiceInfo) {
                @Suppress("DEPRECATION")
                val ip = s.host?.hostAddress
                val attr = s.attributes
                val dados = mapOf(
                    "ip" to ip,
                    "porta" to s.port,
                    "bar" to attr["bar"]?.let { String(it) },
                    "id" to attr["id"]?.let { String(it) },
                )
                principal.post {
                    resolvendo = false
                    if (ip != null && !ip.contains(':')) canal?.invokeMethod("nsd", dados)
                    resolverProximo()
                }
            }
        })
    }

    private fun nsdParar() {
        val m = nsd ?: return
        try { registro?.let { m.unregisterService(it) } } catch (_: Exception) {}
        try { busca?.let { m.stopServiceDiscovery(it) } } catch (_: Exception) {}
        registro = null
        busca = null
        paraResolver.clear()
        resolvendo = false
    }
}
