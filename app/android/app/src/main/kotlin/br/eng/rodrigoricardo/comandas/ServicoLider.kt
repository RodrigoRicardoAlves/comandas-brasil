package br.eng.rodrigoricardo.comandas

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Serviço em primeiro plano do celular líder (só quando há 2+ celulares no bar).
 * Mantém o app vivo com a tela apagada, o processador acordado e o Wi-Fi ligado,
 * para continuar recebendo pedidos dos outros e mandando para a impressora.
 * Tipo "connectedDevice": o aparelho conectado é a impressora de rede.
 */
class ServicoLider : Service() {
    private var cpu: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val texto = intent?.getStringExtra("texto") ?: "Você está cuidando da impressora"
        val n = notificacao(texto)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(ID, n)
        }
        if (cpu == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            cpu = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "comandas:lider").apply {
                setReferenceCounted(false)
                acquire(14 * 60 * 60 * 1000L) // no máximo um turno
            }
        }
        if (wifi == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val modo = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifi = wm.createWifiLock(modo, "comandas:lider").apply { setReferenceCounted(false); acquire() }
        }
        return START_NOT_STICKY
    }

    private fun notificacao(texto: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CANAL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CANAL, "Celular líder", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Aparece enquanto este celular imprime os pedidos do bar"
                }
            )
        }
        val abrir = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CANAL) else @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setContentTitle("Comandas Brasil")
            .setContentText(texto)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setOngoing(true)
            .setContentIntent(abrir)
            .build()
    }

    override fun onDestroy() {
        cpu?.let { if (it.isHeld) it.release() }
        wifi?.let { if (it.isHeld) it.release() }
        cpu = null
        wifi = null
        super.onDestroy()
    }

    companion object {
        const val ID = 1
        const val CANAL = "lider"
    }
}
