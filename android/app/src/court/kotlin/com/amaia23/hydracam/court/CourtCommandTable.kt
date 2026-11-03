package com.amaia23.hydracam.court

import java.util.concurrent.ExecutionException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

sealed class CommandResult {
    object Ack : CommandResult()

    data class Nack(val code: String, val reason: String? = null) : CommandResult()
}

fun interface CommandHandler {
    fun handle(envelope: C1Envelope): CommandResult
}

/**
 * C1 command dispatch: every cloud command is answered with ack/nack within the 5 s budget.
 *
 * - Commands run one at a time, in arrival order (record.start before record.stop).
 * - A repeated envelope id gets the cached reply again; the handler does not run twice.
 * - A handler slower than [deadlineMs] is answered with `nack timeout`.
 * - Handlers must stay fast: long work (opening the camera) is scheduled, not awaited.
 */
class CourtCommandTable(
    private val handlers: Map<String, CommandHandler>,
    private val reply: (C1Envelope) -> Unit,
    private val clock: CourtClock = CourtClock.SYSTEM,
    private val logger: CourtLogger = NoopCourtLogger,
    private val deadlineMs: Long = 4_000,
    private val cacheSize: Int = 512,
    private val dispatcher: ExecutorService = Executors.newSingleThreadExecutor(),
    private val worker: ExecutorService = Executors.newCachedThreadPool(),
) {
    private val replies = object : LinkedHashMap<String, C1Envelope?>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, C1Envelope?>?): Boolean =
            size > cacheSize
    }

    fun dispatch(envelope: C1Envelope) {
        dispatcher.execute { dispatchNow(envelope) }
    }

    fun shutdown() {
        dispatcher.shutdownNow()
        worker.shutdownNow()
    }

    private fun dispatchNow(envelope: C1Envelope) {
        if (replies.containsKey(envelope.id)) {
            val cached = replies[envelope.id]
            if (cached != null) {
                logger.info(TAG, "Duplicate ${envelope.type} id=${envelope.id}; re-sending ${cached.type}.")
                reply(cached)
            }
            return
        }
        replies[envelope.id] = null
        val result = run(envelope)
        val now = clock.nowMs()
        val replyEnvelope = when (result) {
            CommandResult.Ack -> C1Envelope.ack(envelope.id, now)
            is CommandResult.Nack -> C1Envelope.nack(envelope.id, result.code, result.reason, now)
        }
        replies[envelope.id] = replyEnvelope
        if (result is CommandResult.Nack) {
            logger.info(TAG, "nack ${envelope.type} id=${envelope.id} code=${result.code} ${result.reason ?: ""}")
        }
        reply(replyEnvelope)
    }

    private fun run(envelope: C1Envelope): CommandResult {
        val handler = handlers[envelope.type]
            ?: return CommandResult.Nack(C1NackCode.UNSUPPORTED, "Unsupported command ${envelope.type}.")
        val future = worker.submit<CommandResult> { handler.handle(envelope) }
        return try {
            future.get(deadlineMs, TimeUnit.MILLISECONDS)
        } catch (error: TimeoutException) {
            future.cancel(true)
            CommandResult.Nack(C1NackCode.TIMEOUT, "Handler exceeded ${deadlineMs} ms.")
        } catch (error: ExecutionException) {
            when (val cause = error.cause) {
                is C1ProtocolException -> CommandResult.Nack(C1NackCode.BAD_REQUEST, cause.message)
                else -> {
                    logger.warn(TAG, "Handler for ${envelope.type} failed.", cause)
                    CommandResult.Nack(C1NackCode.INTERNAL, cause?.javaClass?.simpleName)
                }
            }
        } catch (error: InterruptedException) {
            Thread.currentThread().interrupt()
            CommandResult.Nack(C1NackCode.INTERNAL, "Interrupted.")
        }
    }

    private companion object {
        const val TAG = "CourtCommands"
    }
}
