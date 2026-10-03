# Not built from: CMakeLists.txt is. It is here because love-android's
# app/build.gradle only reads java.txt -- and so only compiles LoveAds.java --
# for a lua-modules folder that has an Android.mk.

LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := liads
LOCAL_SRC_FILES := liads.cpp
LOCAL_LDLIBS := -ldl
include $(BUILD_SHARED_LIBRARY)
