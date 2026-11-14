package io.appflowy.appflowy

import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private var officeEditorBundle: OfficeEditorBundle? = null
    private var secureSecretChannel: SecureSecretChannel? = null
    private var backgroundSyncChannel: BackgroundSyncChannel? = null

    override fun dispatchTouchEvent(event: MotionEvent): Boolean =
        TouchHistory.dispatch(event) { super.dispatchTouchEvent(it) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        BackgroundSyncCoordinator.awaitHeadlessIdle()
        // Registers the generated plugins.
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        officeEditorBundle = OfficeEditorBundle(this, messenger)
        secureSecretChannel = SecureSecretChannel(this, messenger)
        backgroundSyncChannel = BackgroundSyncChannel(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        backgroundSyncChannel?.dispose()
        backgroundSyncChannel = null
        secureSecretChannel?.dispose()
        secureSecretChannel = null
        officeEditorBundle?.dispose()
        officeEditorBundle = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
