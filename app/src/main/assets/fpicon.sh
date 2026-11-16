#!/data/data/com.termux/files/usr/bin/bash
# Corre como root. Usa las herramientas de Termux (magick, potrace, aapt2, apksigner).
# Uso: fpicon.sh imagen [colores] [tamano_en_%]
set -e
IMG="$1"
NCOL="${2:-6}"      # cantidad de colores
PCT="${3:-130}"     # tamano del icono: 100 = normal, 130 = 30% mas grande
H=/data/data/com.termux/files/home
W="${FPWORK:-/data/local/tmp/fpwork}"

[ -f "$IMG" ] || { echo "Falta la imagen"; exit 1; }
if [ -z "$DRYRUN" ]; then
  [ -f "$H/framework-res.apk" ] || { echo "Falta $H/framework-res.apk"; exit 1; }
  [ -f "$H/rro.keystore" ] || { echo "Falta $H/rro.keystore"; exit 1; }
fi

dp() { echo "$(( $1*PCT/100 )).$(( ($1*PCT/10)%10 ))"; }
WDP=$(dp 46); HDP=$(dp 65)

rm -rf "$W"; mkdir -p "$W/res/drawable" "$W/res/drawable-v21"; cd "$W"

# Color del fondo de la foto (esquina superior izquierda): se vuelve transparente
BG=$(magick "$IMG" -alpha off -format '%[pixel:p{0,0}]' info:)

for S in 400 300 200 150; do
  H2=$((S*41/40))
  case $S in
    400) SC=0.0115;; 300) SC=0.015333;; 200) SC=0.023;; 150) SC=0.030667;;
  esac
  magick "$IMG" -alpha off -resize ${S}x${H2} -background "$BG" -gravity center -extent ${S}x${H2} +dither -colors "$NCOL" -type TrueColor q.png
  BGHEX=$(magick q.png -format '%[hex:p{0,0}]' info: | tr a-f A-F | cut -c1-6)
  : > body.txt
  for C in $(magick q.png -unique-colors txt:- | grep -o '#[0-9A-Fa-f]\{6\}' | tr a-f A-F | sort -u); do
    HEX=${C#\#}
    [ "$HEX" = "$BGHEX" ] && continue
    magick q.png -fuzz 0% -transparent "$C" -alpha extract -threshold 50% m.pbm
    potrace -s -t 4 -O 0.5 m.pbm -o m.svg
    sed -n '/<path/,$p' m.svg | tr '\n' ' ' \
      | sed "s/<path d=\"/<path android:fillColor=\"#FF$HEX\" android:pathData=\"/g; s/\" *\/>/\"\/>\n/g" \
      | grep '<path' >> body.txt || true
  done
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo "<vector xmlns:android=\"http://schemas.android.com/apk/res/android\" android:width=\"${WDP}dp\" android:height=\"${HDP}dp\" android:viewportWidth=\"46\" android:viewportHeight=\"65\"><group android:translateY=\"56.1\" android:scaleX=\"$SC\" android:scaleY=\"-$SC\">"
    cat body.txt
    echo '</group></vector>'
  } > ic.xml
  SIZE=$(wc -c < ic.xml)
  echo "Intento ${S}px, ${NCOL} colores -> ${SIZE} bytes"
  [ "$SIZE" -le 50000 ] && break
done
[ -s body.txt ] || { echo "No se genero ningun trazo. Prueba otra foto."; exit 1; }
[ "$SIZE" -le 70000 ] || { echo "Imagen demasiado compleja. Usa una mas simple."; exit 1; }

if [ -n "$DRYRUN" ]; then echo "DRYRUN: ic.xml listo en $W"; exit 0; fi

for d in drawable drawable-v21; do
  cp ic.xml res/$d/ic_fingerprint.xml
  cp ic.xml res/$d/cat_icon.xml
done
for n in unlock_to_fp fp_to_locked fp_to_unlock; do
  printf '<?xml version="1.0" encoding="utf-8"?>\n<animated-vector xmlns:android="http://schemas.android.com/apk/res/android" android:drawable="@drawable/cat_icon"/>\n' > res/drawable/$n.xml
done

printf '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.custom.fpicon">\n<overlay android:targetPackage="com.android.systemui" android:isStatic="true" android:priority="99"/>\n<application android:hasCode="false"/>\n</manifest>\n' > AndroidManifest.xml

aapt2 compile --dir res -o res.zip
aapt2 link -o un.apk -I "$H/framework-res.apk" --manifest AndroidManifest.xml res.zip
apksigner sign --ks "$H/rro.keystore" --ks-pass pass:123456 --out FpIconOverlay.apk un.apk

mount -o rw,remount /product || true
cp FpIconOverlay.apk /product/overlay/FpIconOverlay.apk
chmod 644 /product/overlay/FpIconOverlay.apk
chcon u:object_r:system_file:s0 /product/overlay/FpIconOverlay.apk
echo "LISTO. Reinicia el telefono."
