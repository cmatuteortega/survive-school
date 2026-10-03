// The native half of the rewarded ads: five C functions src/ads.lua calls
// through LuaJIT's FFI, each forwarding to a static method on
// com.cmatute.loveads.LoveAds. Built by love-android's lua-modules mechanism
// into libliads.so (android/ads.sh puts it there).
//
// The same shape as love-iap's liap.cpp, and for the same reasons:
//
// - No lua.h and nothing of LÖVE's linked, so it does not care which engine
//   build it lands in. SDL is reached at run time by dlsym for the JNIEnv and
//   the activity, under SDL3's names (LÖVE 12) or SDL2's (LÖVE 11).
// - The game thread is a native thread attached to the VM, so FindClass there
//   only sees the system class loader. The class is loaded once through the
//   activity's own loader and kept as a global reference.
// - These calls come from Lua rather than from a Java native method, so no JNI
//   frame ever returns to free local references; every entry point pushes a
//   local frame and pops it on the way out.

#include <jni.h>
#include <dlfcn.h>

#include <string>

#define LIADS_API extern "C" __attribute__((visibility("default")))

namespace
{

typedef void *(*Getter)(void);

Getter envOf = nullptr;
Getter activityOf = nullptr;

jclass adsClass = nullptr;
jmethodID mStart, mShow, mPrivacy, mPoll;

std::string event;
std::string error;

bool findSDL()
{
	if (envOf && activityOf)
		return true;

	const char *names[] = { "libSDL3.so", "libSDL2.so" };
	for (const char *name : names)
	{
		void *lib = dlopen(name, RTLD_NOW | RTLD_NOLOAD);
		if (!lib)
			lib = dlopen(name, RTLD_NOW);
		if (!lib)
			continue;

		envOf = (Getter) dlsym(lib, "SDL_GetAndroidJNIEnv");
		activityOf = (Getter) dlsym(lib, "SDL_GetAndroidActivity");
		if (!envOf || !activityOf)
		{
			envOf = (Getter) dlsym(lib, "SDL_AndroidGetJNIEnv");
			activityOf = (Getter) dlsym(lib, "SDL_AndroidGetActivity");
		}
		if (envOf && activityOf)
			return true;
	}

	envOf = activityOf = nullptr;
	error = "SDL's JNI accessors were not found";
	return false;
}

bool threw(JNIEnv *env)
{
	if (!env->ExceptionCheck())
		return false;
	env->ExceptionDescribe();
	env->ExceptionClear();
	return true;
}

// Inside a pushed local frame.
bool findClass(JNIEnv *env)
{
	if (adsClass)
		return true;

	jobject activity = (jobject) activityOf();
	if (!activity)
	{
		error = "no activity";
		return false;
	}

	jclass loaderType = env->FindClass("java/lang/ClassLoader");
	jmethodID loadClass = env->GetMethodID(loaderType, "loadClass",
		"(Ljava/lang/String;)Ljava/lang/Class;");
	jmethodID getLoader = env->GetMethodID(env->GetObjectClass(activity),
		"getClassLoader", "()Ljava/lang/ClassLoader;");
	jobject loader = env->CallObjectMethod(activity, getLoader);
	jclass found = (jclass) env->CallObjectMethod(loader, loadClass,
		env->NewStringUTF("com.cmatute.loveads.LoveAds"));

	if (threw(env) || !found)
	{
		error = "class com.cmatute.loveads.LoveAds is not in the APK";
		return false;
	}

	mStart = env->GetStaticMethodID(found, "start", "(Landroid/app/Activity;)V");
	mShow = env->GetStaticMethodID(found, "show", "(Landroid/app/Activity;Ljava/lang/String;)V");
	mPrivacy = env->GetStaticMethodID(found, "privacy", "(Landroid/app/Activity;)V");
	mPoll = env->GetStaticMethodID(found, "poll", "()Ljava/lang/String;");

	if (threw(env) || !mStart || !mShow || !mPrivacy || !mPoll)
	{
		error = "LoveAds is missing a method (Java and native out of step?)";
		return false;
	}

	adsClass = (jclass) env->NewGlobalRef(found);
	return true;
}

// Every entry point starts here and, given an env, ends in PopLocalFrame.
JNIEnv *enter()
{
	if (!findSDL())
		return nullptr;
	JNIEnv *env = (JNIEnv *) envOf();
	if (!env)
		return nullptr;
	if (env->PushLocalFrame(16) != 0)
	{
		threw(env);
		return nullptr;
	}
	if (!findClass(env))
	{
		env->PopLocalFrame(nullptr);
		return nullptr;
	}
	return env;
}

} // namespace

LIADS_API int liads_start(void)
{
	JNIEnv *env = enter();
	if (!env)
		return 0;

	env->CallStaticVoidMethod(adsClass, mStart, (jobject) activityOf());
	bool ok = !threw(env);
	if (!ok)
		error = "LoveAds.start threw";

	env->PopLocalFrame(nullptr);
	return ok ? 1 : 0;
}

LIADS_API void liads_show(const char *placement)
{
	JNIEnv *env = enter();
	if (!env)
		return;

	env->CallStaticVoidMethod(adsClass, mShow, (jobject) activityOf(),
		env->NewStringUTF(placement ? placement : ""));
	threw(env);
	env->PopLocalFrame(nullptr);
}

LIADS_API void liads_privacy(void)
{
	JNIEnv *env = enter();
	if (!env)
		return;

	env->CallStaticVoidMethod(adsClass, mPrivacy, (jobject) activityOf());
	threw(env);
	env->PopLocalFrame(nullptr);
}

// Valid until the next call; src/ads.lua copies it with ffi.string at once.
LIADS_API const char *liads_poll(void)
{
	JNIEnv *env = enter();
	if (!env)
		return nullptr;

	const char *out = nullptr;
	jstring line = (jstring) env->CallStaticObjectMethod(adsClass, mPoll);
	if (!threw(env) && line)
	{
		const char *utf = env->GetStringUTFChars(line, nullptr);
		if (utf)
		{
			event = utf;
			env->ReleaseStringUTFChars(line, utf);
			out = event.c_str();
		}
	}

	env->PopLocalFrame(nullptr);
	return out;
}

LIADS_API const char *liads_error(void)
{
	return error.c_str();
}
