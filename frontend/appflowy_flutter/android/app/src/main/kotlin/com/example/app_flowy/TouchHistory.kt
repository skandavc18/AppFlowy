package io.appflowy.appflowy

import android.view.InputDevice
import android.view.MotionEvent

/**
 * Flutter's Android embedding reads only the newest sample of a touch
 * [MotionEvent]. When moves pile up (the app was busy for a moment, or Android
 * held a new touch back, as Waydroid does while it waits for its phantom
 * stylus), Android hands them over as one ACTION_MOVE carrying the older
 * samples in its history: Flutter jumps straight to the newest and measures the
 * finger's speed for the fling from too few points. Each historical sample is
 * dispatched first, as a move of its own at its own time, then the event
 * itself, whose history Flutter ignores.
 */
internal object TouchHistory {
    fun dispatch(event: MotionEvent, dispatch: (MotionEvent) -> Boolean): Boolean {
        val history = event.historySize
        if (history == 0 ||
            event.actionMasked != MotionEvent.ACTION_MOVE ||
            !event.isFromSource(InputDevice.SOURCE_TOUCHSCREEN)
        ) {
            return dispatch(event)
        }
        val count = event.pointerCount
        val properties = Array(count) { MotionEvent.PointerProperties() }
        val coords = Array(count) { MotionEvent.PointerCoords() }
        for (p in 0 until count) event.getPointerProperties(p, properties[p])
        for (h in 0 until history) {
            for (p in 0 until count) event.getHistoricalPointerCoords(p, h, coords[p])
            val sample = MotionEvent.obtain(
                event.downTime,
                event.getHistoricalEventTime(h),
                MotionEvent.ACTION_MOVE,
                count,
                properties,
                coords,
                event.metaState,
                event.buttonState,
                event.xPrecision,
                event.yPrecision,
                event.deviceId,
                event.edgeFlags,
                event.source,
                event.flags,
            )
            try {
                dispatch(sample)
            } finally {
                sample.recycle()
            }
        }
        return dispatch(event)
    }
}
