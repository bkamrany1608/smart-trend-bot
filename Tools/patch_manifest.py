import re, sys
p = "android/app/src/main/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()
perms = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
"""
svc = """        <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="dataSync" android:exported="false" android:stopWithTask="false"/>
"""
if "FOREGROUND_SERVICE_DATA_SYNC" not in s:
    s = s.replace("<application", perms + "    <application", 1)
    s = s.replace("</application>", svc + "    </application>", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Smart Trend Bot"', s, count=1)
open(p, "w", encoding="utf-8").write(s)
print("manifest patched")
