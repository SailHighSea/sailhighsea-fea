# google_mlkit_text_recognition references the optional script-specific recognisers
# (Chinese, Japanese, Korean, Devanagari). Only the Latin one is bundled, so R8 must not fail on
# the missing classes.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
