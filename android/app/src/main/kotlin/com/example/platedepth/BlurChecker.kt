package com.example.platedepth

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import kotlin.math.pow

/**
 * Utility class for calculating blur/sharpness using Laplacian variance.
 * Higher variance = sharper image, lower variance = blurrier image.
 */
object BlurChecker {
    
    /**
     * Calculate Laplacian variance for blur detection.
     * Uses a 3x3 Laplacian kernel to detect edges, then calculates variance.
     */
    fun laplacianVariance(bitmap: Bitmap): Double {
        // Convert to grayscale and apply Laplacian filter
        val width = bitmap.width
        val height = bitmap.height
        
        // Get grayscale values
        val grayscale = Array(height) { IntArray(width) }
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                // Standard grayscale conversion
                val gray = (0.299 * Color.red(pixel) + 
                           0.587 * Color.green(pixel) + 
                           0.114 * Color.blue(pixel)).toInt()
                grayscale[y][x] = gray
            }
        }
        
        // Apply Laplacian kernel:
        // [-1, -1, -1]
        // [-1,  8, -1]
        // [-1, -1, -1]
        val laplacian = mutableListOf<Double>()
        
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                val value = (
                    -grayscale[y-1][x-1] - grayscale[y-1][x] - grayscale[y-1][x+1] +
                    -grayscale[y][x-1]   + 8 * grayscale[y][x] - grayscale[y][x+1] +
                    -grayscale[y+1][x-1] - grayscale[y+1][x] - grayscale[y+1][x+1]
                ).toDouble()
                laplacian.add(value)
            }
        }
        
        if (laplacian.isEmpty()) return 0.0
        
        // Calculate variance
        val mean = laplacian.average()
        val variance = laplacian.map { (it - mean).pow(2) }.average()
        
        return variance
    }
    
    /**
     * Calculate Laplacian variance from JPEG bytes.
     */
    fun laplacianVariance(jpegBytes: ByteArray): Double {
        val bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
            ?: return 0.0
        val result = laplacianVariance(bitmap)
        bitmap.recycle()
        return result
    }
}

