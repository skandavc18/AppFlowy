package io.appflowy.appflowy

import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private var officeEditorBundle: OfficeEditorBundle? = null

    override fun dispatchTouchEvent(event: MotionEvent): Boolean =
        TouchHistory.dispatch(event) { super.dispatchTouchEvent(it) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Registers the generated plugins.
        super.configureFlutterEngine(flutterEngine)
        officeEditorBundle = OfficeEditorBundle(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        officeEditorBundle?.dispose()
        officeEditorBundle = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
