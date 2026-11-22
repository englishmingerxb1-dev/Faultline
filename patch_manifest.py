"""Patch the Flutter-generated AndroidManifest for FaultLine:
internet permission, plain-HTTP access to the PC on the LAN, app name."""
import re
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()

if "android.permission.INTERNET" not in s:
    s = re.sub(r"(<manifest[^>]*>)",
               r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>'
               r'\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>'
               r'\n    <uses-permission android:name="android.permission.WAKE_LOCK"/>',
               s, count=1)

if "usesCleartextTraffic" not in s:
    s = s.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="FaultLine"', s, count=1)

open(path, "w", encoding="utf-8").write(s)
print(s)
