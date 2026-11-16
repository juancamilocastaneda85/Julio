package com.juan.fpicon

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.CheckBox
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import kotlin.concurrent.thread

class MainActivity : Activity() {

    private lateinit var preview: ImageView
    private lateinit var log: TextView
    private lateinit var scroll: ScrollView
    private lateinit var btnPick: Button
    private lateinit var btnApply: Button
    private lateinit var btnRemove: Button
    private lateinit var btnReboot: Button
    private lateinit var chkColor: CheckBox
    private var picked: File? = null

    private val envPrefix =
        "export PATH=/data/data/com.termux/files/usr/bin:\$PATH; " +
        "export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib; " +
        "export HOME=/data/data/com.termux/files/home; " +
        "export TMPDIR=/data/local/tmp; unset LD_PRELOAD; "

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val d = resources.displayMetrics.density
        val pad = (16 * d).toInt()

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad * 2, pad, pad)
            setBackgroundColor(Color.parseColor("#121212"))
        }

        root.addView(TextView(this).apply {
            text = "Icono de huella"
            textSize = 24f
            setTypeface(null, Typeface.BOLD)
            setTextColor(Color.WHITE)
        })
        root.addView(TextView(this).apply {
            text = "Solo para S20 FE (VoltageOS). Requiere root."
            textSize = 13f
            setTextColor(Color.parseColor("#9E9E9E"))
        })

        preview = ImageView(this).apply {
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.parseColor("#1E1E1E"))
        }
        root.addView(preview, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, (220 * d).toInt()
        ).apply { topMargin = pad; bottomMargin = pad })

        btnPick = Button(this).apply {
            text = "1. Elegir foto"
            setOnClickListener {
                startActivityForResult(
                    Intent(Intent.ACTION_GET_CONTENT).apply { type = "image/*" }, 1
                )
            }
        }
        chkColor = CheckBox(this).apply {
            text = "Colores originales (experimental)"
            setTextColor(Color.WHITE)
        }
        btnApply = Button(this).apply {
            text = "2. Aplicar"
            isEnabled = false
            setOnClickListener { apply() }
        }
        btnReboot = Button(this).apply {
            text = "3. Reiniciar"
            visibility = View.GONE
            setOnClickListener { thread { run("reboot") } }
        }
        btnRemove = Button(this).apply {
            text = "Quitar icono personalizado"
            setOnClickListener { remove() }
        }
        root.addView(btnPick)
        root.addView(chkColor)
        root.addView(btnApply)
        root.addView(btnReboot)
        root.addView(btnRemove)

        log = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.parseColor("#B0BEC5"))
            typeface = Typeface.MONOSPACE
            gravity = Gravity.START
        }
        scroll = ScrollView(this).apply { addView(log) }
        root.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ).apply { topMargin = pad })

        setContentView(root)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri: Uri = data?.data ?: return
        if (requestCode != 1 || resultCode != RESULT_OK) return
        try {
            val f = File(cacheDir, "in.img")
            contentResolver.openInputStream(uri)!!.use { i -> f.outputStream().use { o -> i.copyTo(o) } }
            picked = f
            preview.setImageURI(uri)
            btnApply.isEnabled = true
            say("Foto lista.")
        } catch (e: Exception) {
            say("No pude leer la foto: ${e.message}")
        }
    }

    private fun apply() {
        val img = picked ?: return
        val mode = if (chkColor.isChecked) "bg" else "icon"
        btnApply.isEnabled = false
        btnReboot.visibility = View.GONE
        log.text = ""
        say("Procesando, tarda unos segundos...")
        thread {
            val script = File(cacheDir, "fpicon.sh")
            assets.open("fpicon.sh").use { i -> script.outputStream().use { o -> i.copyTo(o) } }
            val ok = run(
                "cp ${img.absolutePath} /data/local/tmp/fp_in.img && " +
                "cp ${script.absolutePath} /data/local/tmp/fpicon.sh && " +
                "chmod 755 /data/local/tmp/fpicon.sh && " +
                envPrefix +
                "/data/data/com.termux/files/usr/bin/bash /data/local/tmp/fpicon.sh /data/local/tmp/fp_in.img 8 130 $mode"
            )
            runOnUiThread {
                btnApply.isEnabled = true
                if (ok) btnReboot.visibility = View.VISIBLE
            }
        }
    }

    private fun remove() {
        thread {
            run("mount -o rw,remount /product; rm -f /product/overlay/FpIconOverlay.apk && echo 'Quitado. Reinicia el telefono.'")
            runOnUiThread { btnReboot.visibility = View.VISIBLE }
        }
    }

    private fun run(cmd: String): Boolean {
        return try {
            val p = ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start()
            p.inputStream.bufferedReader().forEachLine { say(it) }
            val code = p.waitFor()
            if (code != 0) say("Termino con error (codigo $code).")
            code == 0
        } catch (e: Exception) {
            say("Error: ${e.message}. Revisa que la app tenga permiso root.")
            false
        }
    }

    private fun say(s: String) {
        runOnUiThread {
            log.append(s + "\n")
            scroll.post { scroll.fullScroll(View.FOCUS_DOWN) }
        }
    }
}
