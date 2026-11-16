package io.github.brokoskokoli.ramuri

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Weiche der Antworten auf Berechtigungsdialoge (MainActivity.onRequestPermissionsResult). */
class PermissionCallsTest {
    private val log = mutableListOf<String>()
    private val healthSeen = mutableListOf<Int>()

    private val calls = PermissionCalls(
        object : PermissionAnswers<String> {
            override fun success(result: String, value: Any?) { log.add("$result:$value") }
            override fun error(result: String, code: String) { log.add("$result!$code") }
        },
        health = { code -> healthSeen.add(code); code == HEALTH },
        states = linkedMapOf(
            LOCATION to { "precise" },
            NOTIFICATION to { "granted" },
            ACTIVITY to { "available" },
            CAMERA to { "ready" },
        ),
    )

    private fun openAll() {
        assertTrue(calls.open(LOCATION, "location"))
        assertTrue(calls.open(NOTIFICATION, "notifications"))
        assertTrue(calls.open(ACTIVITY, "activity"))
        assertTrue(calls.open(CAMERA, "camera"))
    }

    /** FR-0200: Der Code von Health Connect geht nur dorthin und beantwortet keinen anderen offenen Aufruf. */
    @Test fun healthCodeOnlyReachesHealthConnect() {
        openAll()
        calls.onRequestPermissionsResult(HEALTH)
        assertEquals(listOf(HEALTH), healthSeen)
        assertEquals(emptyList<String>(), log)
        // Die anderen bleiben offen.
        assertFalse(calls.open(LOCATION, "x"))
        assertFalse(calls.open(CAMERA, "x"))
    }

    /** Health Connect beansprucht einen Code, der sonst Standort wäre: Standort bleibt unbeantwortet. */
    @Test fun healthClaimWinsOverOwnCode() {
        val claimed = PermissionCalls(
            object : PermissionAnswers<String> {
                override fun success(result: String, value: Any?) { log.add("$result:$value") }
                override fun error(result: String, code: String) { log.add("$result!$code") }
            },
            health = { true },
            states = mapOf(LOCATION to { "precise" }),
        )
        assertTrue(claimed.open(LOCATION, "location"))
        claimed.onRequestPermissionsResult(LOCATION)
        assertEquals(emptyList<String>(), log)
    }

    @Test fun locationAnswersOnlyLocationAndResets() = answersOnly(LOCATION, "location:precise")

    @Test fun activityAnswersOnlyActivityAndResets() = answersOnly(ACTIVITY, "activity:available")

    @Test fun cameraAnswersOnlyCameraAndResets() = answersOnly(CAMERA, "camera:ready")

    @Test fun notificationAnswersOnlyNotificationsAndResets() = answersOnly(NOTIFICATION, "notifications:granted")

    private fun answersOnly(code: Int, expected: String) {
        openAll()
        calls.onRequestPermissionsResult(code)
        assertEquals(listOf(code), healthSeen)
        assertEquals(listOf(expected), log)
        // Zurückgesetzt: eine zweite Antwort beantwortet nichts mehr, ein neuer Aufruf ist möglich.
        calls.onRequestPermissionsResult(code)
        assertEquals(listOf(expected), log)
        assertTrue(calls.open(code, "again"))
        // Die übrigen sind weiter offen.
        listOf(LOCATION, NOTIFICATION, ACTIVITY, CAMERA).filter { it != code }.forEach {
            assertFalse(calls.open(it, "x"))
        }
    }

    @Test fun unknownCodeDoesNothing() {
        openAll()
        calls.onRequestPermissionsResult(UNKNOWN)
        assertEquals(emptyList<String>(), log)
        listOf(LOCATION, NOTIFICATION, ACTIVITY, CAMERA).forEach { assertFalse(calls.open(it, "x")) }
    }

    @Test fun noOpenCallDoesNotCrash() {
        listOf(HEALTH, LOCATION, NOTIFICATION, ACTIVITY, CAMERA, UNKNOWN).forEach {
            calls.onRequestPermissionsResult(it)
        }
        assertEquals(emptyList<String>(), log)
    }

    @Test fun secondOpenOfSameCodeIsBusy() {
        assertTrue(calls.open(CAMERA, "first"))
        assertFalse(calls.open(CAMERA, "second"))
        calls.onRequestPermissionsResult(CAMERA)
        assertEquals(listOf("first:ready"), log)
    }

    @Test fun detachEndsAllOpenCallsOnce() {
        assertTrue(calls.open(CAMERA, "camera"))
        assertTrue(calls.open(LOCATION, "location"))
        calls.detachAll()
        assertEquals(listOf("location!detached", "camera!detached"), log)
        calls.detachAll()
        calls.onRequestPermissionsResult(LOCATION)
        assertEquals(listOf("location!detached", "camera!detached"), log)
    }

    private companion object {
        const val HEALTH = 6005
        const val LOCATION = 6001
        const val NOTIFICATION = 6002
        const val ACTIVITY = 6003
        const val CAMERA = 6004
        const val UNKNOWN = 4242
    }
}
