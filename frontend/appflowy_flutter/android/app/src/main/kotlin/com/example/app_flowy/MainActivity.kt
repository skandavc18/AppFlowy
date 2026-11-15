package io.appflowy.appflowy

import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private var officeEditorBundle: OfficeEditorBundle? = null
    private var secureSecretChannel: SecureSecretChannel? = null
    private var backgroundSyncChannel: BackgroundSyncChannel? = null
    private val focusHighlightSuppressor =
        ViewTreeObserver.OnGlobalFocusChangeListener { _, newFocus ->
            newFocus?.defaultFocusHighlightEnabled = false
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FlutterView is focusable across the full viewport; disable Android's
        // legacy view-level focus border in desktop/keyboard/freeform modes.
        disableDefaultFocusHighlights(window.decorView)
        window.decorView.viewTreeObserver.addOnGlobalFocusChangeListener(
            focusHighlightSuppressor,
        )
    }

    override fun setContentView(view: View?) {
        super.setContentView(view)
        if (view != null) {
            disableDefaultFocusHighlights(view)
        }
    }

    override fun onDestroy() {
        val observer = window.decorView.viewTreeObserver
        if (observer.isAlive) {
            observer.removeOnGlobalFocusChangeListener(focusHighlightSuppressor)
        }
        super.onDestroy()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean =
        TouchHistory.dispatch(event) { super.dispatchTouchEvent(it) }

    private fun disableDefaultFocusHighlights(view: View) {
        view.defaultFocusHighlightEnabled = false
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                disableDefaultFocusHighlights(view.getChildAt(i))
            }
        }
    }

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
