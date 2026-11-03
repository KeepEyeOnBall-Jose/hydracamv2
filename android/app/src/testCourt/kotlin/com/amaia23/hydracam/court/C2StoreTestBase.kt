package com.amaia23.hydracam.court

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Shared harness for [C2Uploader] tests: a fake C2 store (MockWebServer), an in-memory queue and a fake clock. */
abstract class C2StoreTestBase {
    @get:Rule
    val temp = TemporaryFolder()

    protected val server = MockWebServer()
    protected val clock = FakeClock()
    protected val store = InMemoryUploadQueueStore()
    protected val alerts = mutableListOf<String>()
    protected val allowed = AtomicBoolean(true)
    protected val logger = RecordingLogger()
    protected lateinit var grant: String

    protected open val http: OkHttpClient = OkHttpClient.Builder().callTimeout(5, TimeUnit.SECONDS).build()

    @Before
    fun startServer() {
        server.start()
    }

    @After
    fun stopServer() {
        server.shutdown()
    }

    protected fun startSession(
        tiers: List<String> = listOf(C1.TIER_PROXY, C1.TIER_MASTER),
        expSeconds: Long = 4_000_000_000L,
    ) {
        grant = testGrant("s1", tiers, expSeconds)
        val body = recordStartBody(grant = grant, ingestUrl = server.url("/").toString())
        store.upsertSession(UploadSession.from(RecordStart.fromJson(body), "A", clock.now))
    }

    protected fun uploader(
        throttle: UploadThrottle = UploadThrottle(maxKbps = 0),
        partSizeBytes: Long = C2Uploader.DEFAULT_PART_SIZE_BYTES,
        mastersAllowed: () -> Boolean = allowed::get,
    ) = C2Uploader(
        http,
        store,
        clock,
        logger = logger,
        partSizeBytes = partSizeBytes,
        throttle = throttle,
        onAlert = { alerts += it },
        mastersAllowed = mastersAllowed,
    )

    protected fun segment(tier: String, seq: Long, size: Int = 25, dir: File = temp.root): SegmentRecord {
        val file = File(dir, "$tier-$seq.ts")
        file.writeBytes(ByteArray(size) { (it + seq).toByte() })
        return SegmentRecord(
            "s1", "A", tier, seq, file, file.length(), "sha-$tier-$seq",
            BASE_MS + seq * 6_000, 6_000, 180, 0, -1,
        )
    }

    protected fun item(tier: String, seq: Long): UploadItem = store.item(UploadItem.keyOf("s1", tier, seq))!!

    protected fun json(code: Int, body: JSONObject) =
        MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())

    protected fun initCreated(uploadId: String, partCount: Int) = json(
        201,
        JSONObject()
            .put("uploadId", uploadId)
            .put(
                "parts",
                JSONArray(
                    (1..partCount).map {
                        JSONObject().put("n", it).put("url", server.url("/part/$it").toString())
                    },
                ),
            ),
    )

    protected fun partOk(etag: String) = MockResponse().setResponseCode(200).setHeader("ETag", etag)

    protected fun take(): RecordedRequest = server.takeRequest(3, TimeUnit.SECONDS)!!

    protected companion object {
        const val BASE_MS = 1_700_000_000_000L
    }
}
