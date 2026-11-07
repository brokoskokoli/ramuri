package io.github.brokoskokoli.running_app

import android.content.Intent
import java.io.File
import java.io.IOException
import java.nio.file.Files
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
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

    /** Befund W: Pfadquellen nur unterhalb des Exportordners. */
    @Test fun resolveAcceptsOnlyRegularFilesBelowTheExportFolder() {
        val parent = tempDir()
        val dir = File(parent, ExportFiles.DIR).apply { mkdirs() }
        val direct = File(dir, "run.gpx").apply { writeText("x") }
        val nested = File(dir, "archiv/teil.zip").apply { parentFile.mkdirs(); writeText("x") }
        assertEquals(direct.canonicalFile, ExportFiles.resolve(dir, direct.path))
        assertEquals(nested.canonicalFile, ExportFiles.resolve(dir, nested.path))
        // Über ../ hinaus, auch wenn die Datei existiert.
        val outside = File(parent, "secret.db").apply { writeText("geheim") }
        assertTrue(outside.isFile)
        val sibling = File(parent, "${ExportFiles.DIR}2/x.gpx").apply { parentFile.mkdirs(); writeText("x") }
        val link = File(dir, "link.gpx")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        for (bad in listOf(
            "${dir.path}/../secret.db",
            "${dir.path}/archiv/../../secret.db",
            sibling.path,
            link.path,
            "${ExportFiles.DIR}/run.gpx",
            dir.path,
            File(dir, "archiv").path,
            File(dir, "fehlt.gpx").path,
            "",
        )) {
            assertEquals(bad, null, ExportFiles.resolve(dir, bad))
        }
        parent.deleteRecursively()
    }

    @Test fun adoptKeepsTheGivenFileAndClearsTheRest() {
        val parent = tempDir()
        val dir = File(parent, ExportFiles.DIR).apply { mkdirs() }
        File(dir, "old.gpx").writeText("alt")
        val file = File(dir, "archiv/teil.zip").apply { parentFile.mkdirs(); writeBytes(byteArrayOf(7)) }
        val adopted = ExportFiles.adopt(dir, file.path)
        assertEquals(file.canonicalFile, adopted)
        assertEquals(listOf("archiv"), dir.list()!!.toList())
        assertArrayEquals(byteArrayOf(7), adopted.readBytes())
        parent.deleteRecursively()
    }

    @Test fun adoptRejectsPathsOutsideWithoutTouchingFiles() {
        val parent = tempDir()
        val dir = File(parent, ExportFiles.DIR).apply { mkdirs() }
        File(dir, "keep.gpx").writeText("x")
        File(parent, "secret.db").writeText("geheim")
        try {
            ExportFiles.adopt(dir, "${dir.path}/../secret.db")
            fail()
        } catch (_: IllegalArgumentException) {
        }
        assertTrue(File(dir, "keep.gpx").exists())
        assertTrue(File(parent, "secret.db").exists())
        parent.deleteRecursively()
    }

    /** Befund 3: ein Schreib-Thread für den ganzen Prozess, auch über Activities hinweg. */
    @Test fun ioIsOneSharedSingleThread() {
        assertSame(ExportFiles.io, ExportFiles.io)
        val threads = (1..3).map { ExportFiles.io.submit<Thread> { Thread.currentThread() }.get() }
        assertEquals(1, threads.toSet().size)
    }

    @Test fun sourceRequiresThePathToBeNamedLikeFileName() {
        val dir = tempDir()
        val f = File(dir, "archiv.zip").apply { writeText("x") }
        val sub = File(dir, "teil").apply { mkdirs() }
        File(sub, "a.zip").writeText("x")
        val ok = ExportFiles.source(dir, "archiv.zip", null, f.path) as HandoffSource.Path
        assertEquals(f.canonicalFile, ok.file)
        assertEquals("a.zip", (ExportFiles.source(dir, "a.zip", null, File(sub, "a.zip").path) as HandoffSource.Path).file.name)
        // Anderer Name auf der Platte als angezeigt.
        assertNull(ExportFiles.source(dir, "anders.zip", null, f.path))
        assertNull(ExportFiles.source(dir, "zip", null, f.path))
        // Bytes ohne Pfad ja, beides oder nichts nein, Pfad außerhalb nein.
        assertTrue(ExportFiles.source(dir, "a.gpx", byteArrayOf(1), null) is HandoffSource.Bytes)
        assertNull(ExportFiles.source(dir, "archiv.zip", byteArrayOf(1), f.path))
        assertNull(ExportFiles.source(dir, "archiv.zip", null, null))
        val outside = File(tempDir(), "archiv.zip").apply { writeText("x") }
        assertNull(ExportFiles.source(dir, "archiv.zip", null, outside.path))
        dir.deleteRecursively()
        outside.parentFile.deleteRecursively()
    }

    @Test fun importCopiesTheStreamAfterClearingTheFolder() {
        val dir = File(tempDir(), ExportFiles.IMPORT_DIR)
        dir.mkdirs()
        File(dir, "old.bin").writeText("alt")
        File(dir, "sub").mkdirs()
        val data = ByteArray(300_000) { (it % 251).toByte() }
        val f = ExportFiles.importInto(dir, data.inputStream())
        assertEquals(listOf(ExportFiles.IMPORT_NAME), dir.list()!!.toList())
        assertArrayEquals(data, f.readBytes())
        assertEquals(dir.canonicalFile, f.parentFile)
        // Ordner fehlt: wird angelegt.
        dir.deleteRecursively()
        ExportFiles.importInto(dir, byteArrayOf(7).inputStream())
        assertArrayEquals(byteArrayOf(7), File(dir, ExportFiles.IMPORT_NAME).readBytes())
        dir.parentFile.deleteRecursively()
    }

    @Test fun importFailureRemovesThePartialCopyAndRethrows() {
        val dir = File(tempDir(), ExportFiles.IMPORT_DIR)
        val broken = object : java.io.InputStream() {
            var n = 0
            override fun read(): Int = if (n++ < 10) 1 else throw IOException("kaputt")
        }
        try {
            ExportFiles.importInto(dir, broken)
            fail()
        } catch (e: IOException) {
            assertEquals("kaputt", e.message)
        }
        assertEquals(emptyList<String>(), dir.list()!!.toList())
        dir.parentFile.deleteRecursively()
    }
}
