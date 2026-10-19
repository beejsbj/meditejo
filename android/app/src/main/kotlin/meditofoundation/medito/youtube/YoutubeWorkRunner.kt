package meditofoundation.medito.youtube

import java.util.concurrent.Future
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Runs blocking extraction on worker threads, each job under its own overall
 * deadline, and hands exactly one outcome to [deliver] (the platform thread on
 * Android). A job that overruns is reported as timed out and its thread
 * interrupted; the network calls underneath have their own, shorter timeouts,
 * so the thread is not held for long.
 */
class YoutubeWorkRunner(
    private val deliver: (Runnable) -> Unit,
    workers: Int = 2,
    queueCapacity: Int = 16,
) {
    private val threadNumber = AtomicInteger()
    private val disposed = AtomicBoolean(false)

    private val pool = ThreadPoolExecutor(
        workers, workers, 30L, TimeUnit.SECONDS, LinkedBlockingQueue(queueCapacity),
        { task ->
            // The extractor runs a JavaScript interpreter: give it a roomy stack.
            Thread(null, task, "youtube-extract-${threadNumber.incrementAndGet()}", STACK_BYTES).apply {
                isDaemon = true
                priority = Thread.NORM_PRIORITY - 1
            }
        },
    ).apply { allowCoreThreadTimeOut(true) }

    private val timer = ScheduledThreadPoolExecutor(1) { task ->
        Thread(task, "youtube-timeout").apply { isDaemon = true }
    }.apply { removeOnCancelPolicy = true }

    val isDisposed: Boolean get() = disposed.get()

    /**
     * Runs [work] and calls [callback] once with its result or a [YoutubeFailure].
     * Nothing is delivered after [dispose].
     */
    fun <T> run(timeoutMs: Long, work: () -> T, callback: (Result<T>) -> Unit) {
        if (disposed.get()) return
        val delivered = AtomicBoolean(false)
        val timeout = arrayOfNulls<Future<*>>(1)
        val job = arrayOfNulls<Future<*>>(1)

        fun finish(result: Result<T>) {
            if (!delivered.compareAndSet(false, true)) return
            timeout[0]?.cancel(false)
            if (!disposed.get()) deliver(Runnable { if (!disposed.get()) callback(result) })
        }

        try {
            job[0] = pool.submit(Runnable {
                val outcome = try {
                    Result.success(work())
                } catch (t: Throwable) {
                    Result.failure(YoutubeFailure.from(t))
                }
                finish(outcome)
            })
            timeout[0] = timer.schedule(Runnable {
                if (!delivered.get()) {
                    finish(Result.failure(YoutubeFailure.timedOut()))
                    job[0]?.cancel(true)
                }
            }, timeoutMs, TimeUnit.MILLISECONDS)
            // The job may have finished before the timeout existed.
            if (delivered.get()) timeout[0]?.cancel(false)
        } catch (e: RejectedExecutionException) {
            finish(Result.failure(YoutubeFailure.busy()))
        }
    }

    /** Stops accepting work, interrupts what is running and drops what is queued. */
    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        timer.shutdownNow()
        pool.shutdownNow()
    }

    private companion object {
        const val STACK_BYTES = 4L * 1024 * 1024
    }
}
