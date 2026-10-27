# The core (gomobile): its native library finds these classes and methods
# by name through JNI, so R8 must not rename or remove them.
-keep class go.** { *; }
-keep class com.tekvpn.tekcore.** { *; }
