package io.github.brokoskokoli.running_app

import android.content.Intent
import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class ExportFilesTest {
    private fun tempDir(): File = Files.createTempDirectory("exports").toFile()

    @Test fun safeNamesMatchCore() {
        for (ok in listOf("run-20300101-090000.gpx", "a_b.fit", "-x.tcx", "x".repeat(255))) {
            assertTrue(ok, ExportFiles.isSafeName(ok))
        }
        for (bad in listOf("", ".", "..", "../x.gpx", "a/b.gpx", "a\\b", ".hidden", "_x", "a b", "ä.gpx", "x".repeat(256))) {
            assertFalse(bad, ExportFiles.isSafeName(bad))
        }
        assertTrue(ExportFiles.isMimeType("application/vnd.garmin.tcx+xml"))
        assertFalse(ExportFiles.isMimeType("text/"))
        assertFalse(ExportFiles.isMimeType("*/*;x"))
    }

    @Test fun writeClearsOldExportsAndKeepsOnlyTheNewFile() {
        val dir = tempDir()
        File(dir, "old.gpx").writeText("alt")
        File(dir, "sub").mkdirs()
        File(dir, "sub/older.fit").writeText("alt")
        val f = ExportFiles.write(dir, "run.fit", byteArrayOf(1, 2, 3))
        assertEquals(listOf("run.fit"), dir.list()!!.toList())
        assertEquals(dir.canonicalFile, f.canonicalFile.parentFile)
        assertArrayEquals(byteArrayOf(1, 2, 3), f.readBytes())
        dir.deleteRecursively()
    }

    @Test fun writeCreatesTheDirectory() {
        val dir = File(tempDir(), ExportFiles.DIR)
        ExportFiles.write(dir, "run.gpx", byteArrayOf(9))
        assertTrue(File(dir, "run.gpx").isFile)
        dir.parentFile.deleteRecursively()
    }

    @Test fun writeRejectsUnsafeNamesWithoutTouchingFiles() {
        val parent = tempDir()
        val dir = File(parent, ExportFiles.DIR).apply { mkdirs() }
        File(dir, "keep.gpx").writeText("x")
        for (bad in listOf("../escape.gpx", "..", ".hidden")) {
            try {
                ExportFiles.write(dir, bad, byteArrayOf(1))
                fail(bad)
            } catch (_: IllegalArgumentException) {
            }
        }
        assertFalse(File(parent, "escape.gpx").exists())
        assertTrue(File(dir, "keep.gpx").exists())
        parent.deleteRecursively()
    }

    @Test fun clearEmptiesTheDirectoryAndToleratesMissingOne() {
        val dir = tempDir()
        File(dir, "a.gpx").writeText("x")
        File(dir, "b").mkdirs()
        assertTrue(ExportFiles.clear(dir))
        assertTrue(dir.isDirectory)
        assertEquals(0, dir.list()!!.size)
        assertTrue(ExportFiles.clear(File(dir, "missing")))
        dir.deleteRecursively()
    }

    @Test fun authorityMatchesManifest() {
        assertEquals("io.github.brokoskokoli.running_app.exports", ExportFiles.authority("io.github.brokoskokoli.running_app"))
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("android:authorities=\"\${applicationId}.${ExportFiles.DIR}\""))
    }

    @Test fun providerSharesOnlyTheExportFolder() {
        val paths = File("src/main/res/xml/file_paths.xml").readText()
        val entries = Regex("<([a-z-]+-path|root-path)\\b[^>]*>").findAll(paths).map { it.value }.toList()
        assertEquals(listOf("<cache-path name=\"exports\" path=\"${ExportFiles.DIR}/\"/>"), entries)
        val provider = Regex("<provider[\\s\\S]*?</provider>").find(File("src/main/AndroidManifest.xml").readText())!!.value
        assertTrue(provider.contains("android:exported=\"false\""))
        assertTrue(provider.contains("android:grantUriPermissions=\"true\""))
        assertTrue(provider.contains("@xml/file_paths"))
    }

    @Test fun shareIntentGrantsReadOnly() {
        val s = HandoffIntents.send("application/gpx+xml")
        assertEquals(Intent.ACTION_SEND, s.action)
        assertEquals("application/gpx+xml", s.mimeType)
        assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, s.flags)
        assertEquals(0, s.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        assertEquals(0, s.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
    }

    @Test fun saveIntentIsCreateDocumentWithTitle() {
        val s = HandoffIntents.createDocument("run.fit", "application/vnd.ant.fit")
        assertEquals(Intent.ACTION_CREATE_DOCUMENT, s.action)
        assertEquals(listOf(Intent.CATEGORY_OPENABLE), s.categories)
        assertEquals("run.fit", s.title)
        assertEquals("application/vnd.ant.fit", s.mimeType)
        assertEquals(0, s.flags)
    }
}
