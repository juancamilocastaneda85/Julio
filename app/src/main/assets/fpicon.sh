#!/data/data/com.termux/files/usr/bin/bash
# Corre como root. Usa las herramientas de Termux (magick, potrace, aapt2, apksigner).
set -e
IMG="$1"
H=/data/data/com.termux/files/home
W=/data/local/tmp/fpwork

[ -f "$IMG" ] || { echo "Falta la imagen"; exit 1; }
[ -f "$H/framework-res.apk" ] || { echo "Falta $H/framework-res.apk"; exit 1; }
[ -f "$H/rro.keystore" ] || { echo "Falta $H/rro.keystore"; exit 1; }

rm -rf "$W"; mkdir -p "$W/res/drawable" "$W/res/drawable-v21"; cd "$W"

for S in 400 300 200 150; do
  H2=$((S*41/40))
  case $S in
    400) SC=0.0115;; 300) SC=0.015333;; 200) SC=0.023;; 150) SC=0.030667;;
  esac
  magick "$IMG" -resize ${S}x${H2} -background white -gravity center -extent ${S}x${H2} -threshold 50% p.pbm
  potrace -s p.pbm -o p.svg
  {
    echo '<?xml version="1.0" encoding="utf-8"?>'
    echo "<vector xmlns:android=\"http://schemas.android.com/apk/res/android\" android:width=\"46dp\" android:height=\"65dp\" android:viewportWidth=\"46\" android:viewportHeight=\"65\"><group android:translateY=\"56.1\" android:scaleX=\"$SC\" android:scaleY=\"-$SC\">"
    sed -n '/<path/,$p' p.svg | tr '\n' ' ' | sed 's/<path d="/<path android:fillColor="#FF000000" android:pathData="/g; s/" *\/>/"\/>\n/g' | grep '<path'
    echo '</group></vector>'
  } > ic.xml
  SIZE=$(wc -c < ic.xml)
  echo "Intento ${S}px -> ${SIZE} bytes"
  [ "$SIZE" -le 50000 ] && break
done
[ "$SIZE" -le 60000 ] || { echo "Imagen demasiado compleja. Usa una mas simple."; exit 1; }

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
