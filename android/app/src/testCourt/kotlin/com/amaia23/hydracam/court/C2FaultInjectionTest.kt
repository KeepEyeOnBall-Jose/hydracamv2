package com.amaia23.hydracam.court

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import kotlin.random.Random

/**
 * Uploader fault injection against a stateful fake C2 store: 5xx, lost responses, corrupted parts
 * (sha mismatch), clock jumps, out-of-order and duplicate enqueues, and process kill + restart.
 * Invariant: every segment ends verified exactly once with its original bytes, and its file is gone.
 */
class C2FaultInjectionTest : C2StoreTestBase() {
    override val http: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(5, TimeUnit.SECONDS)
        .retryOnConnectionFailure(false)
        .build()

    /** Simulated process death; an Error so the uploader's IOException handling cannot swallow it. */
    private class Killed : Error()

    private class KillingStore(private val delegate: UploadQueueStore, private val random: Random) :
        UploadQueueStore by delegate {
        var armed = true

        private fun maybeDie() {
            if (armed && random.nextInt(100) < 4) throw Killed()
        }

        override fun update(item: UploadItem) {
            maybeDie()
            delegate.update(item)
            maybeDie()
        }
    }

    private class FakeC2(
        private val random: Random,
        private val partSize: Long,
        private val partUrl: (String) -> String,
    ) : Dispatcher() {
        private class Upload(val key: String, val sha: String, val partCount: Int) {
            val parts = mutableMapOf<Int, ByteArray>()
            var state = "uploading"
        }

        val verified = mutableMapOf<String, ByteArray>()
        val verifications = mutableMapOf<String, Int>()
        private val shas = mutableMapOf<String, String>()
        private val uploads = mutableMapOf<String, Upload>()
        private var nextId = 0

        @Synchronized
        override fun dispatch(request: RecordedRequest): MockResponse {
            if (random.nextInt(100) < 8) return MockResponse().setResponseCode(503)
            val response = handle(request)
            // The server applied the request but the response never reaches the phone.
            return if (random.nextInt(100) <
                8
            ) {
                response.setSocketPolicy(SocketPolicy.DISCONNECT_AFTER_REQUEST)
            } else {
                response
            }
        }

        private fun handle(request: RecordedRequest): MockResponse {
            val path = request.path!!
            return when {
                request.method == "POST" && path == "/v2/uploads" -> init(JSONObject(request.body.readUtf8()))
                request.method == "PUT" && path.startsWith("/part/") -> part(path, request.body.readByteArray())
                request.method == "POST" && path.endsWith("/complete") -> complete(path.split("/")[3])
                request.method == "GET" && path.startsWith("/v2/uploads/") -> status(path.split("/")[3])
                else -> MockResponse().setResponseCode(404)
            }
        }

        private fun init(body: JSONObject): MockResponse {
            val key = "${body.getString("tier")}/${body.getLong("seq")}"
            val sha = body.getString("sha256")
            if (key in verified) {
                return if (shas[key] ==
                    sha
                ) {
                    json(200, JSONObject().put("uploadId", "done-$key"))
                } else {
                    json(409, JSONObject())
                }
            }
            val id = "u${nextId++}"
            val count = maxOf(1, ((body.getLong("bytes") + partSize - 1) / partSize).toInt())
            uploads[id] = Upload(key, sha, count)
            val parts = JSONArray((1..count).map { JSONObject().put("n", it).put("url", partUrl("/part/$id/$it")) })
            return json(201, JSONObject().put("uploadId", id).put("parts", parts))
        }

        private fun part(path: String, bytes: ByteArray): MockResponse {
            val segments = path.split("/")
            val id = segments[2]
            val n = segments[3]
            val upload = uploads[id] ?: return MockResponse().setResponseCode(404)
            val stored = if (random.nextInt(100) < 3 &&
                bytes.isNotEmpty()
            ) {
                bytes.copyOf().also { it[0] = (it[0] + 1).toByte() }
            } else {
                bytes
            }
            upload.parts[n.toInt()] = stored
            return MockResponse().setResponseCode(200).setHeader("ETag", "\"$id-$n\"")
        }

        private fun complete(id: String): MockResponse {
            val upload = uploads[id] ?: return MockResponse().setResponseCode(404)
            if (upload.state == "uploading") {
                val bytes = (1..upload.partCount).fold(ByteArray(0)) { all, n ->
                    all + (upload.parts[n] ?: ByteArray(0))
                }
                upload.state = if (sha256(bytes) == upload.sha) "verified" else "failed"
                if (upload.state == "verified") {
                    verifications.merge(upload.key, 1, Int::plus)
                    verified[upload.key] = bytes
                    shas[upload.key] = upload.sha
                }
            }
            return json(200, JSONObject().put("state", upload.state))
        }

        private fun status(id: String): MockResponse {
            val upload = uploads[id] ?: return MockResponse().setResponseCode(404)
            return json(200, JSONObject().put("state", if (upload.state == "uploading") "verifying" else upload.state))
        }

        private fun json(code: Int, body: JSONObject) =
            MockResponse().setResponseCode(code).setHeader("Content-Type", "application/json").setBody(body.toString())
    }

    @Test
    fun faultsAndRestartsLoseNothingAndDuplicateNothing() {
        startSession()
        for (seed in 0L until 12L) {
            run(seed)
        }
        assertTrue("no restart was exercised", kills > 0)
    }

    private var kills = 0

    private fun run(seed: Long) {
        val random = Random(seed)
        val fake = FakeC2(random, PART, server::url.let { url -> { path -> url(path).toString() } })
        server.dispatcher = fake
        val dir = temp.newFolder("seed$seed")
        val originals = mutableMapOf<String, ByteArray>()
        val segments = (0L until 6L).flatMap { seq ->
            listOf(C1.TIER_PROXY, C1.TIER_MASTER).map { tier ->
                val bytes = Random(seed * 100 + seq).nextBytes(random.nextInt(1, 300))
                val file = File(dir, "$tier-$seq.ts").apply { writeBytes(bytes) }
                originals["$tier/${seq + seed * 100}"] = bytes
                segment(tier, seq + seed * 100, bytes.size, dir).copy(file = file, sha256 = sha256(bytes))
            }
        }
        segments.forEach { it.file.writeBytes(originals["${it.tier}/${it.seq}"]!!) }
        val killing = KillingStore(store, random)
        var uploader =
            C2Uploader(http, killing, clock, logger = logger, partSizeBytes = PART, onAlert = { alerts += it })
        (segments + segments.shuffled(random).take(4)).shuffled(random).forEach { uploader.enqueue(it) }

        var steps = 0
        while (steps++ < MAX_STEPS) {
            try {
                if (random.nextInt(100) < 5) clock.now += random.nextLong(-5_000, 60_000)
                if (!uploader.runOnce(includeMasters = true)) {
                    val wake = store.nextWakeAtMs(includeMasters = true) ?: break
                    clock.now = maxOf(clock.now, wake)
                }
            } catch (expected: Killed) {
                kills++
                uploader =
                    C2Uploader(http, killing, clock, logger = logger, partSizeBytes = PART, onAlert = { alerts += it })
                // Boot recovery re-enqueues from the sidecars; existing rows are kept.
                segments.filter { it.file.exists() }.shuffled(random).forEach { uploader.enqueue(it) }
            }
        }
        killing.armed = false

        for (segment in segments) {
            val key = "${segment.tier}/${segment.seq}"
            val context = "seed $seed $key"
            assertEquals(
                context,
                UploadState.VERIFIED.name,
                store.item(UploadItem.keyOf("s1", segment.tier, segment.seq))!!.state,
            )
            assertEquals(context, 1, fake.verifications[key])
            assertArrayEquals(context, originals[key], fake.verified[key])
            assertFalse(context, segment.file.exists())
        }
    }

    private companion object {
        const val PART = 64L
        const val MAX_STEPS = 50_000

        fun sha256(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }
}
