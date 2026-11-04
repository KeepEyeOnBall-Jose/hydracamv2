package com.amaia23.hydracam.court

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/** C4 v1.7 budget rule: uploads + measured preview stay within maxKbps, and uploads never stall. */
class PreviewBudgetPropertyTest {
    @Test
    fun uploadsPlusPreviewStayWithinThePolicyAndNeverStall() {
        val random = Random(7)
        repeat(5_000) {
            val policy = random.nextInt(1, 50_000)
            val preview = random.nextInt(-10, 60_000)
            val budget = UploadThrottle.budgetKbps(policy, preview)
            val context = "policy=$policy preview=$preview budget=$budget"

            assertTrue(context, budget >= minOf(policy, UploadThrottle.MIN_SHARED_KBPS))
            if (policy - preview >= UploadThrottle.MIN_SHARED_KBPS) {
                assertTrue(context, budget + preview.coerceAtLeast(0) <= policy)
            }
            assertTrue(context, budget <= policy)
        }
    }

    @Test
    fun aPolicyBelowTheFloorIsNeverRaised() {
        assertEquals(32, UploadThrottle.budgetKbps(policyKbps = 32, measuredPreviewKbps = 0))
        assertEquals(32, UploadThrottle.budgetKbps(policyKbps = 32, measuredPreviewKbps = 100))
        assertEquals(1, UploadThrottle.budgetKbps(policyKbps = 1, measuredPreviewKbps = 0))
        assertEquals(
            UploadThrottle.MIN_SHARED_KBPS,
            UploadThrottle.budgetKbps(policyKbps = 1_000, measuredPreviewKbps = 2_000),
        )
        assertEquals(0, UploadThrottle.budgetKbps(policyKbps = 0, measuredPreviewKbps = 500))

        val throttle = UploadThrottle(maxKbps = 32)
        throttle.shareWithPreview(policyKbps = 32, measuredPreviewKbps = 0)
        assertEquals(32, throttle.maxKbps)
    }

    @Test
    fun unlimitedPolicyStaysUnlimitedAndStoppingThePreviewRestoresThePolicy() {
        val throttle = UploadThrottle(maxKbps = 2_000)
        throttle.shareWithPreview(policyKbps = 0, measuredPreviewKbps = 900)
        assertEquals(0, throttle.maxKbps)

        throttle.shareWithPreview(policyKbps = 4_000, measuredPreviewKbps = 960)
        assertEquals(3_040, throttle.maxKbps)
        throttle.shareWithPreview(policyKbps = 4_000, measuredPreviewKbps = 0)
        assertEquals(4_000, throttle.maxKbps)
    }
}
