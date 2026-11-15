package com.amaia23.hydracam.court

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * Scales camera frames to encoder surfaces. Used for phones whose camera cannot output 640x360 to
 * a MediaCodec surface (S7 edge, S9), and to split one camera stream into proxy and preview where
 * the camera only guarantees two streams at 4K (LIMITED). The camera writes [srcWidth]x[srcHeight]
 * at [srcFps] into a SurfaceTexture; each frame is drawn into every output whose fps takes it
 * (Bresenham, like the camera burst), with the sensor timestamp as PTS.
 */
@Suppress("MagicNumber") // EGL's interleaved vertex format and component counts.
class CourtPreviewFanout(
    private val outputs: List<Output>,
    val srcWidth: Int,
    val srcHeight: Int,
    private val srcFps: Int,
    private val rotationDeg: Int = 0,
    private val sensorOrientationDeg: Int = 0,
) : SurfaceTexture.OnFrameAvailableListener {
    class Output(val name: String, val surface: Surface, val width: Int, val height: Int, val fps: () -> Int) {
        internal var egl: EGLSurface = EGL14.EGL_NO_SURFACE
        val framesDrawn = AtomicLong()
    }

    val framesDrawn = AtomicLong()

    /** Frame-available callbacks that found no new frame (the GL thread fell behind). */
    val framesCoalesced = AtomicLong()
    private var frameIndex = 0L
    private var lastTimestamp = -1L

    @Volatile
    private var released = false
    private val drawUsTotal = AtomicLong()
    private val drawUsMax = AtomicLong()

    lateinit var inputSurface: Surface
        private set

    private val thread = HandlerThread("CourtPreviewFanout").apply { start() }
    private val handler = Handler(thread.looper)
    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private lateinit var texture: SurfaceTexture
    private var program = 0
    private var aPosition = 0
    private var aTexCoord = 0
    private var uTexMatrix = 0
    private val texMatrix = FloatArray(16)
    private val outputTexMatrix = FloatArray(16)
    private val quad = ByteBuffer.allocateDirect(QUAD.size * 4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply { put(QUAD).position(0) }

    fun start() {
        val ready = CountDownLatch(1)
        var error: Throwable? = null
        handler.post {
            runCatching { setUp() }.onFailure { error = it }
            ready.countDown()
        }
        check(ready.await(5, TimeUnit.SECONDS)) { "gl setup timed out" }
        error?.let { throw it }
    }

    fun stats(): Map<String, Any?> {
        val n = framesDrawn.get()
        return mapOf(
            "src" to "${srcWidth}x$srcHeight@$srcFps",
            "framesDrawn" to n,
            "framesCoalesced" to framesCoalesced.get(),
            "outputs" to
                outputs.associate { it.name to "${it.width}x${it.height}@${it.fps()} drawn ${it.framesDrawn.get()}" },
            "drawMsAvg" to if (n > 0) drawUsTotal.get() / n / 1_000.0 else null,
            "drawMsMax" to drawUsMax.get() / 1_000.0,
        )
    }

    fun release() {
        // Camera2 can still have an in-flight frame when close() returns. Invalidate callbacks
        // before queueing teardown; quitSafely may drain a callback queued after that teardown.
        released = true
        val done = CountDownLatch(1)
        val posted = handler.post {
            try {
                if (::texture.isInitialized) {
                    runCatching { texture.setOnFrameAvailableListener(null) }
                    runCatching { texture.release() }
                }
                if (::inputSurface.isInitialized) runCatching { inputSurface.release() }
                if (display != EGL14.EGL_NO_DISPLAY) {
                    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                    outputs.forEach { EGL14.eglDestroySurface(display, it.egl) }
                    EGL14.eglDestroyContext(display, context)
                    EGL14.eglTerminate(display)
                }
            } finally {
                done.countDown()
                thread.quitSafely()
            }
        }
        if (posted) done.await(2, TimeUnit.SECONDS)
    }

    override fun onFrameAvailable(surfaceTexture: SurfaceTexture) {
        if (!released) draw()
    }

    private fun setUp() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE,
        )
        check(EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, count, 0) && count[0] > 0) { "no EGL config" }
        context = EGL14.eglCreateContext(
            display,
            configs[0],
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        outputs.forEach {
            it.egl = EGL14.eglCreateWindowSurface(display, configs[0], it.surface, intArrayOf(EGL14.EGL_NONE), 0)
        }
        val first = outputs.first().egl
        check(EGL14.eglMakeCurrent(display, first, first, context)) { "eglMakeCurrent failed" }

        program = linkProgram(VERTEX, FRAGMENT)
        aPosition = GLES20.glGetAttribLocation(program, "aPosition")
        aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
        uTexMatrix = GLES20.glGetUniformLocation(program, "uTexMatrix")

        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex[0])
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        texture = SurfaceTexture(tex[0]).apply {
            setDefaultBufferSize(srcWidth, srcHeight)
            setOnFrameAvailableListener(this@CourtPreviewFanout, handler)
        }
        inputSurface = Surface(texture)
    }

    private fun draw() {
        val startUs = SystemClock.elapsedRealtimeNanos() / 1_000
        val first = outputs.first().egl
        check(EGL14.eglMakeCurrent(display, first, first, context)) { "eglMakeCurrent failed" }
        texture.updateTexImage()
        if (texture.timestamp == lastTimestamp) {
            framesCoalesced.incrementAndGet()
            return
        }
        lastTimestamp = texture.timestamp
        texture.getTransformMatrix(texMatrix)
        if (frameIndex == 0L) {
            Log.i(
                "CourtPreview",
                "sensorOrientation=$sensorOrientationDeg rotation=$rotationDeg texture=${texMatrix.toList()}",
            )
        }
        removeCameraRotation(texMatrix, sensorOrientationDeg)
        val index = frameIndex++
        outputs.filter { includes(it.fps(), index) }.forEach { drawTo(it) }
        val us = SystemClock.elapsedRealtimeNanos() / 1_000 - startUs
        framesDrawn.incrementAndGet()
        drawUsTotal.addAndGet(us)
        if (us > drawUsMax.get()) drawUsMax.set(us)
    }

    private fun includes(fps: Int, index: Long): Boolean {
        val pattern = PreviewBurst.pattern(srcFps, fps)
        return pattern[(index % pattern.size).toInt()]
    }

    private fun drawTo(output: Output) {
        EGL14.eglMakeCurrent(display, output.egl, output.egl, context)
        GLES20.glViewport(0, 0, output.width, output.height)
        GLES20.glUseProgram(program)
        quad.position(0)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(aPosition)
        quad.position(2)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        outputTextureMatrix(texMatrix, outputTexMatrix, output.name, rotationDeg)
        GLES20.glUniformMatrix4fv(uTexMatrix, 1, false, outputTexMatrix, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        // Camera SurfaceTexture timestamps are sensor timestamps, so encoder PTS stay sensor time.
        EGLExt.eglPresentationTimeANDROID(display, output.egl, texture.timestamp)
        check(EGL14.eglSwapBuffers(display, output.egl)) { "eglSwapBuffers failed" }
        output.framesDrawn.incrementAndGet()
    }

    private fun linkProgram(vertex: String, fragment: String): Int {
        fun compile(type: Int, source: String) = GLES20.glCreateShader(type).also {
            GLES20.glShaderSource(it, source)
            GLES20.glCompileShader(it)
            val ok = IntArray(1)
            GLES20.glGetShaderiv(it, GLES20.GL_COMPILE_STATUS, ok, 0)
            check(ok[0] != 0) { "shader: ${GLES20.glGetShaderInfoLog(it)}" }
        }
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, compile(GLES20.GL_VERTEX_SHADER, vertex))
            GLES20.glAttachShader(it, compile(GLES20.GL_FRAGMENT_SHADER, fragment))
            GLES20.glLinkProgram(it)
            val ok = IntArray(1)
            GLES20.glGetProgramiv(it, GLES20.GL_LINK_STATUS, ok, 0)
            check(ok[0] != 0) { "link: ${GLES20.glGetProgramInfoLog(it)}" }
        }
    }

    companion object {
        /** Court 1.4.1 previews stay raw in every mode; recording tiers retain the mount turn. */
        internal fun outputTextureMatrix(raw: FloatArray, output: FloatArray, name: String, rotationDeg: Int) {
            raw.copyInto(output)
            if (name != "preview" && rotationDeg == CapturePlanner.HALF_TURN) rotateHalfTurn(output)
        }

        /**
         * Camera2's SurfaceTexture matrix includes sensor rotation; direct encoder buffers do not.
         * Compose its inverse around (0.5, 0.5), retaining the actual texture crop and GL flip.
         * The resulting raster matches the direct master before applying the requested mount turn.
         */
        internal fun removeCameraRotation(matrix: FloatArray, sensorOrientationDeg: Int) {
            when (sensorOrientationDeg) {
                0 -> Unit
                180 -> rotateHalfTurn(matrix)
                90, 270 -> for (row in 0..3) {
                    val x = matrix[row]
                    val y = matrix[4 + row]
                    val clockwise = sensorOrientationDeg == 90
                    matrix[12 + row] += if (clockwise) y else x
                    matrix[row] = if (clockwise) -y else y
                    matrix[4 + row] = if (clockwise) x else -x
                }
                else -> error("Invalid sensor orientation $sensorOrientationDeg")
            }
        }

        /** Compose the camera crop/flip with (s, t) -> (1-s, 1-t), without allocating per frame. */
        internal fun rotateHalfTurn(matrix: FloatArray) {
            for (row in 0..3) {
                matrix[12 + row] += matrix[row] + matrix[4 + row]
                matrix[row] = -matrix[row]
                matrix[4 + row] = -matrix[4 + row]
            }
        }

        private const val EGL_RECORDABLE_ANDROID = 0x3142

        /** x, y, s, t for a full-screen triangle strip. */
        private val QUAD = floatArrayOf(
            -1f, -1f, 0f, 0f,
            1f, -1f, 1f, 0f,
            -1f, 1f, 0f, 1f,
            1f, 1f, 1f, 1f,
        )

        private const val VERTEX = """
            attribute vec4 aPosition;
            attribute vec4 aTexCoord;
            uniform mat4 uTexMatrix;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = (uTexMatrix * aTexCoord).xy;
            }
        """

        private const val FRAGMENT = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vTexCoord);
            }
        """
    }
}
