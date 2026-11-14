package io.appflowy.appflowy

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Coordinates foreground and headless background sync on Android so RocksDB is
 * never opened by two Flutter engines simultaneously.
 */
object BackgroundSyncCoordinator {
    const val CHANNEL = "appflowy/background_sync"
    private const val JOB_ID = 0xAF59
    private const val PERIODIC_INTERVAL_MS = 15L * 60L * 1000L

    @Volatile
    var foregroundChannel: MethodChannel? = null

    @Volatile
    var activeHeadlessLatch: CountDownLatch? = null

    fun schedulePeriodic(context: Context, enabled: Boolean): Boolean {
        val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
            ?: return false
        if (!enabled) {
            scheduler.cancel(JOB_ID)
            return true
        }
        if (scheduler.getPendingJob(JOB_ID) != null) {
            return true
        }
        val component = ComponentName(context, SyncJobService::class.java)
        val info = JobInfo.Builder(JOB_ID, component)
            .setPeriodic(PERIODIC_INTERVAL_MS)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true)
            .build()
        return scheduler.schedule(info) == JobScheduler.RESULT_SUCCESS
    }

    /**
     * Ensures any in-flight headless `SyncJobService` round has released its
     * native RocksDB handles before `MainActivity` starts its UI engine.
     */
    fun awaitHeadlessIdle(timeoutMs: Long = 15_000L) {
        val latch = activeHeadlessLatch ?: return
        try {
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
}

class BackgroundSyncChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, BackgroundSyncCoordinator.CHANNEL)

    init {
        channel.setMethodCallHandler(this)
        BackgroundSyncCoordinator.foregroundChannel = channel
    }

    fun dispose() {
        if (BackgroundSyncCoordinator.foregroundChannel === channel) {
            BackgroundSyncCoordinator.foregroundChannel = null
        }
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setPeriodicSyncEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") == true
                result.success(BackgroundSyncCoordinator.schedulePeriodic(appContext, enabled))
            }
            else -> result.notImplemented()
        }
    }
}

/**
 * Periodic Android `JobService` that keeps synced workspaces up to date when
 * AppFlowy is in the background or closed.
 */
class SyncJobService : JobService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var headlessEngine: FlutterEngine? = null
    private var secretChannel: SecureSecretChannel? = null
    private var syncChannel: MethodChannel? = null
    private var timeoutRunnable: Runnable? = null
    private var currentParams: JobParameters? = null

    override fun onStartJob(params: JobParameters?): Boolean {
        if (params == null) {
            return false
        }
        // When the UI engine is already alive, trigger a sync round directly on
        // it instead of opening a second engine over the same RocksDB folder.
        val liveForeground = BackgroundSyncCoordinator.foregroundChannel
        if (liveForeground != null) {
            liveForeground.invokeMethod(
                "triggerSyncNow",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        jobFinished(params, false)
                    }

                    override fun error(code: String, msg: String?, details: Any?) {
                        jobFinished(params, false)
                    }

                    override fun notImplemented() {
                        jobFinished(params, false)
                    }
                },
            )
            return true
        }

        if (BackgroundSyncCoordinator.activeHeadlessLatch != null) {
            return false
        }

        val latch = CountDownLatch(1)
        BackgroundSyncCoordinator.activeHeadlessLatch = latch
        currentParams = params

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(applicationContext)
            }
            loader.ensureInitializationComplete(applicationContext, null)

            val engine = FlutterEngine(applicationContext)
            GeneratedPluginRegistrant.registerWith(engine)
            val messenger = engine.dartExecutor.binaryMessenger
            secretChannel = SecureSecretChannel(applicationContext, messenger)
            val channel = MethodChannel(messenger, BackgroundSyncCoordinator.CHANNEL)
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "headlessDone" -> {
                        result.success(null)
                        finishHeadless(reschedule = false)
                    }
                    "setPeriodicSyncEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        result.success(
                            BackgroundSyncCoordinator.schedulePeriodic(applicationContext, enabled),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
            syncChannel = channel
            headlessEngine = engine

            val timeout = Runnable {
                Log.w(TAG, "Headless background sync timed out; cleaning up.")
                finishHeadless(reschedule = true)
            }
            timeoutRunnable = timeout
            mainHandler.postDelayed(timeout, HEADLESS_TIMEOUT_MS)

            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:appflowy/main.dart",
                "appflowyBackgroundSyncMain",
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)
            return true
        } catch (error: Throwable) {
            Log.e(TAG, "Failed to start headless background sync", error)
            finishHeadless(reschedule = false)
            return false
        }
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        finishHeadless(reschedule = true)
        return true
    }

    private fun finishHeadless(reschedule: Boolean) {
        mainHandler.post {
            timeoutRunnable?.let { mainHandler.removeCallbacks(it) }
            timeoutRunnable = null
            syncChannel?.setMethodCallHandler(null)
            syncChannel = null
            secretChannel?.dispose()
            secretChannel = null
            try {
                headlessEngine?.destroy()
            } catch (error: Throwable) {
                Log.w(TAG, "Error destroying headless sync engine", error)
            }
            headlessEngine = null
            val latch = BackgroundSyncCoordinator.activeHeadlessLatch
            BackgroundSyncCoordinator.activeHeadlessLatch = null
            latch?.countDown()
            currentParams?.let {
                currentParams = null
                jobFinished(it, reschedule)
            }
        }
    }

    companion object {
        private const val TAG = "AppFlowySyncJob"
        private const val HEADLESS_TIMEOUT_MS = 90_000L
    }
}
