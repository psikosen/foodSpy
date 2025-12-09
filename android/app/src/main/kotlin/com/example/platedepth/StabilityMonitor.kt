package com.example.platedepth

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.EventChannel
import kotlin.math.abs

/**
 * Monitors device stability using gyroscope data and streams status to Flutter.
 * Emits "stable" or "unstable" based on rotation rate threshold.
 */
class StabilityMonitor(private val context: Context) : EventChannel.StreamHandler, SensorEventListener {
    
    companion object {
        private const val ROTATION_THRESHOLD = 1.5
    }
    
    private var sensorManager: SensorManager? = null
    private var gyroscope: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isMonitoring = false
    
    fun start() {
        if (isMonitoring) return
        
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        gyroscope = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        
        // Always emit initial "stable" state so capture is enabled immediately
        isMonitoring = true
        eventSink?.success("stable")
        
        if (gyroscope != null) {
            sensorManager?.registerListener(
                this,
                gyroscope,
                SensorManager.SENSOR_DELAY_UI
            )
        }
        // If no gyroscope, we'll just stay "stable" (no further events needed)
    }
    
    fun stop() {
        if (!isMonitoring) return
        
        sensorManager?.unregisterListener(this)
        isMonitoring = false
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        start()
    }
    
    override fun onCancel(arguments: Any?) {
        stop()
        eventSink = null
    }
    
    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_GYROSCOPE) return
        
        val rotationX = event.values[0]
        val rotationY = event.values[1]
        val rotationZ = event.values[2]
        
        val rotationMagnitude = abs(rotationX) + abs(rotationY) + abs(rotationZ)
        val status = if (rotationMagnitude > ROTATION_THRESHOLD) "unstable" else "stable"
        
        eventSink?.success(status)
    }
    
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed for this implementation
    }
}

