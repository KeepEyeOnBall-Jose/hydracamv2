package com.amaia23.hydracam.court

import com.fasterxml.jackson.databind.ObjectMapper
import com.networknt.schema.JsonSchema
import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SpecVersion
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.LinkedBlockingQueue

/**
 * K1 against the vendored court-contracts C1 package (`scripts/vendor_court_contracts.sh`):
 * every good fixture matches its JSON Schema and every bad one is refused, by the schema or, for
 * the range rules the schema cannot express, by K1 itself. A contract change shows up here red.
 */
class CourtContractsConformanceTest {
    private val root: File = File(requireNotNull(javaClass.classLoader?.getResource(ROOT)).toURI())
    private val mapper = ObjectMapper()
    private val schemas = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012)
    private val replies = LinkedBlockingQueue<C1Envelope>()
    private val table = CourtCommandTable(PARSERS, { replies.put(it) })

    @After
    fun tearDown() {
        table.shutdown()
    }

    @Test
    fun vendoredCopyMatchesTheManifest() {
        val lines = File(root, MANIFEST).readLines()
        assertTrue(lines.first(), lines.first().startsWith("# source: KeepEyeOnBall-Jose/media-timeline@"))
        val expected = lines.drop(1).associate { line ->
            val (hash, path) = line.split("  ", limit = 2)
            path to hash
        }
        val actual = root.walkTopDown().filter { it.isFile && it.name != MANIFEST }.associate { file ->
            file.relativeTo(root).invariantSeparatorsPath to sha256(file)
        }

        assertEquals("Vendored court-contracts drifted; re-run scripts/vendor_court_contracts.sh.", expected, actual)
    }

    @Test
    fun targetsContractVersionAndListsEverySchema() {
        val index = JSONObject(File(root, "json-schema/index.json").readText())
        val listed = index.getJSONObject("schemas").getJSONArray("c1").let { keys ->
            (0 until keys.length()).map { keys.getString(it) }.toSet()
        }
        val files = File(root, "json-schema/c1").list().orEmpty().map { it.removeSuffix(SCHEMA_SUFFIX) }.toSet()

        assertEquals(CONTRACT_VERSION, index.getString("contractVersion"))
        assertEquals(listed, files)
    }

    @Test
    fun everyGoodFixtureMatchesItsSchema() {
        val good = fixtures("good")
        assertTrue(good.size >= MIN_GOOD)

        good.forEach { fixture ->
            val errors = schemaFor(fixture).validate(mapper.readTree(fixture))
            assertTrue("${fixture.name}: $errors", errors.isEmpty())
        }
    }

    @Test
    fun everyBadFixtureIsRefused() {
        val bad = fixtures("bad")
        assertTrue(bad.size >= MIN_BAD)

        bad.filter { rule(it) !in RANGE_RULES }.forEach { fixture ->
            assertTrue(fixture.name, schemaFor(fixture).validate(mapper.readTree(fixture)).isNotEmpty())
        }
        val ranges = bad.filter { rule(it) in RANGE_RULES }
        assertEquals(RANGE_RULES, ranges.map(::rule).toSet())
        ranges.forEach { fixture ->
            assertEquals(fixture.name, C1NackCode.BAD_RANGE, dispatch(fixture).body.getString("code"))
        }
    }

    @Test
    fun k1AcksEveryGoodCommandItParses() {
        val commands = fixtures("good").filter { key(it) in PARSERS }
        assertEquals(PARSERS.keys, commands.map(::key).toSet())

        commands.forEach { fixture ->
            val reply = dispatch(fixture)
            assertEquals("${fixture.name}: ${reply.body}", C1.ACK, reply.type)
        }
    }

    @Test
    fun k1RefusesBadCommandsItParsesExceptKnownLenientOnes() {
        val accepted = fixtures("bad").filter { key(it) in PARSERS }.filterNot(::k1Refuses).map { it.name }.toSet()

        assertEquals(K1_LENIENT, accepted)
    }

    @Test
    fun k1NackCodesAreContractCodes() {
        val enum = JSONObject(File(root, "json-schema/c1/nack-code$SCHEMA_SUFFIX").readText()).getJSONArray("enum")
        val contract = (0 until enum.length()).map { enum.getString(it) }.toSet()
        val k1 = C1NackCode::class.java.declaredFields
            .filter { it.type == String::class.java }
            .map { it.get(null) as String }
            .toSet()

        assertTrue(k1.isNotEmpty())
        assertTrue("K1 codes outside the contract: ${k1 - contract}", contract.containsAll(k1))
    }

    /** Refused when the envelope does not decode or the table nacks it. */
    private fun k1Refuses(fixture: File): Boolean =
        runCatching { decode(fixture) }.getOrNull()?.let { reply(it).type == C1.NACK } ?: true

    private fun dispatch(fixture: File): C1Envelope = reply(decode(fixture))

    /** Fixtures share one envelope id, which the table would answer from its replay cache. */
    private fun decode(fixture: File): C1Envelope = C1Envelope.decode(fixture.readText()).copy(id = fixture.name)

    private fun reply(envelope: C1Envelope): C1Envelope {
        table.dispatch(envelope)
        return replies.await().also { assertEquals(envelope.id, it.body.getString("ref")) }
    }

    private fun fixtures(kind: String): List<File> =
        File(root, "fixtures/c1/$kind").listFiles().orEmpty().sortedBy { it.name }

    private fun schemaFor(fixture: File): JsonSchema =
        schemas.getSchema(File(root, "json-schema/c1/${key(fixture)}$SCHEMA_SUFFIX").readText())

    private companion object {
        const val ROOT = "court-contracts"
        const val MANIFEST = "MANIFEST.sha256"
        const val SCHEMA_SUFFIX = ".schema.json"
        const val CONTRACT_VERSION = "1.9"
        const val MIN_GOOD = 40
        const val MIN_BAD = 130
        val RANGE_RULES = setOf("end-before-start", "empty-range")

        /**
         * Bad bodies K1's own parsers still ack (the schema refuses them). Shrink this list as K1
         * tightens; a new entry means K1 started accepting something the contract forbids.
         */
        val K1_LENIENT = setOf(
            "masters.upload--wrong-type--body.sessionId.json",
            "record.prepare--unknown-enum--body.profile.masterRes.json",
            "record.prepare--wrong-type--body.sessionId.json",
            "record.start--unknown-enum--body.gestures.0.json",
            "record.start--wrong-type--body.sessionId.json",
            "record.stop--wrong-type--body.sessionId.json",
            "signal.emit--out-of-range--body.atServerMs.json",
            "signal.emit--unknown-enum--body.signal.json",
            "upload.policy--missing--body.windows.json",
            "upload.policy--wrong-type--body.windows.json",
        )

        /** The C1 commands K1 parses into its own types; an ack only means the body parsed. */
        val PARSERS = mapOf(
            C1.RECORD_PREPARE to parses(RecordPrepare::fromJson),
            C1.RECORD_START to parses(RecordStart::fromJson),
            C1.RECORD_STOP to parses(RecordStop::fromJson),
            C1.SIGNAL_EMIT to parses(SignalEmit::fromJson),
            C1.UPLOAD_POLICY to parses(UploadPolicy::fromJson),
            C1.MASTERS_UPLOAD to parses(MastersUpload::fromJson),
        )

        fun parses(parse: (JSONObject) -> Any): CommandHandler = CommandHandler { envelope ->
            parse(envelope.body)
            CommandResult.Ack
        }

        /** `<key>[--<variant>].json` (good) or `<key>--<rule>--<path>.json` (bad). */
        fun key(fixture: File): String = fixture.name.removeSuffix(".json").substringBefore("--")

        fun rule(fixture: File): String = fixture.name.split("--")[1]

        fun sha256(file: File): String =
            MessageDigest.getInstance("SHA-256").digest(file.readBytes()).joinToString("") { "%02x".format(it) }
    }
}
