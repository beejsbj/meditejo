package meditofoundation.medito.youtube

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class YoutubeWorkRunnerTest {
    private val runners = mutableListOf<YoutubeWorkRunner>()

    private fun runner(workers: Int = 2, queue: Int = 4): YoutubeWorkRunner =
        YoutubeWorkRunner(deliver = { it.run() }, workers = workers, queueCapacity = queue).also { runners += it }

    @After
    fun tearDown() = runners.forEach { it.dispose() }

    private fun <T> outcome(runner: YoutubeWorkRunner, timeoutMs: Long = 5_000, work: () -> T): Result<T> {
        val results = LinkedBlockingQueue<Result<T>>()
        runner.run(timeoutMs, work) { results.add(it) }
        return results.poll(10, TimeUnit.SECONDS) ?: error("no outcome")
    }

    @Test
    fun deliversTheResultOnce() {
        val calls = AtomicInteger()
        val results = LinkedBlockingQueue<Result<Int>>()
        runner().run(5_000, { 42 }) { calls.incrementAndGet(); results.add(it) }
        assertEquals(42, results.poll(5, TimeUnit.SECONDS)?.getOrNull())
        Thread.sleep(100)
        assertEquals(1, calls.get())
    }

    @Test
    fun deliversATypedFailureForAnyThrowable() {
        val ioFailure = outcome(runner()) { throw IOException("secret https://x.example") }.exceptionOrNull() as YoutubeFailure
        assertEquals("network", ioFailure.code)
        val other = outcome(runner()) { throw IllegalStateException("boom") }.exceptionOrNull() as YoutubeFailure
        assertEquals("unavailable", other.code)
        val error = outcome(runner()) { throw StackOverflowError() }.exceptionOrNull() as YoutubeFailure
        assertEquals("unavailable", error.code)
    }

    @Test
    fun anOverrunningJobTimesOutOnceAndIsInterrupted() {
        val interrupted = CountDownLatch(1)
        val calls = AtomicInteger()
        val results = LinkedBlockingQueue<Result<Int>>()
        runner().run(100, {
            try {
                Thread.sleep(30_000)
            } catch (e: InterruptedException) {
                interrupted.countDown()
                throw e
            }
            1
        }) { calls.incrementAndGet(); results.add(it) }
        val failure = results.poll(5, TimeUnit.SECONDS)?.exceptionOrNull() as YoutubeFailure
        assertEquals("rate-limited", failure.code)
        assertTrue("the worker was not interrupted", interrupted.await(5, TimeUnit.SECONDS))
        Thread.sleep(100)
        assertEquals(1, calls.get())
    }

    @Test
    fun workRunsOffTheCallingThread() {
        val caller = Thread.currentThread()
        val worker = outcome(runner()) { Thread.currentThread() }.getOrThrow()
        assertFalse(worker === caller)
        assertTrue(worker.name.startsWith("youtube-extract-"))
        assertTrue(worker.isDaemon)
    }

    @Test
    fun aFullQueueAnswersBusyInsteadOfWaiting() {
        val runner = runner(workers = 1, queue = 1)
        val gate = CountDownLatch(1)
        val started = CountDownLatch(1)
        val results = LinkedBlockingQueue<Result<Int>>()
        runner.run(30_000, { started.countDown(); gate.await(); 1 }) { results.add(it) }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        runner.run(30_000, { 2 }) { results.add(it) } // queued
        runner.run(30_000, { 3 }) { results.add(it) } // rejected
        val busy = results.poll(5, TimeUnit.SECONDS)?.exceptionOrNull() as YoutubeFailure
        assertEquals("rate-limited", busy.code)
        gate.countDown()
        assertEquals(1, results.poll(5, TimeUnit.SECONDS)?.getOrNull())
        assertEquals(2, results.poll(5, TimeUnit.SECONDS)?.getOrNull())
    }

    @Test
    fun resultsGoThroughTheDeliveryHook() {
        val hooked = AtomicInteger()
        val runner = YoutubeWorkRunner(deliver = { hooked.incrementAndGet(); it.run() }).also { runners += it }
        outcome(runner) { 1 }
        assertEquals(1, hooked.get())
    }

    @Test
    fun disposeInterruptsWorkAndSilencesLaterResults() {
        val runner = runner()
        val interrupted = CountDownLatch(1)
        val started = CountDownLatch(1)
        val calls = AtomicInteger()
        runner.run(30_000, {
            started.countDown()
            try {
                Thread.sleep(30_000)
            } catch (e: InterruptedException) {
                interrupted.countDown()
            }
            1
        }) { calls.incrementAndGet() }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        runner.dispose()
        assertTrue(runner.isDisposed)
        assertTrue(interrupted.await(5, TimeUnit.SECONDS))
        runner.run(100, { 2 }) { calls.incrementAndGet() }
        Thread.sleep(300)
        assertEquals(0, calls.get())
        runner.dispose() // idempotent
    }
}
