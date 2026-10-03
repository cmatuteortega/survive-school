package com.cmatute.loveads;

import android.app.Activity;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;

import androidx.annotation.NonNull;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.UserMessagingPlatform;

import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Survive School's rewarded ads: Google's consent form (UMP) and one AdMob
 * rewarded unit, and nothing else -- no banners, no interstitials.
 *
 * Called from liads.cpp, and so from Lua (src/ads.lua) through LuaJIT's FFI, on
 * LÖVE's game thread. Everything the SDKs do happens on the UI thread, and the
 * two sides share nothing but a queue: every result becomes one tab-separated
 * line in {@link #events}, and Lua drains it once a frame through {@link #poll}.
 * The same shape as love-iap's LoveIap, on purpose -- one way of talking to the
 * phone in this game, not two.
 *
 * Events: ready | none reason | reward placement | closed placement |
 * failed placement reason | privacy 0/1 | unavailable reason
 */
public final class LoveAds {
    // Google's own rewarded test unit: what a build gets when the workflow is
    // given no unit of its own, so an unconfigured build can never serve (or be
    // paid for) a real ad.
    private static final String TEST_UNIT = "ca-app-pub-3940256099942544/5224354917";
    private static final String UNIT_KEY = "com.cmatute.loveads.REWARDED_ID";

    private static final ConcurrentLinkedQueue<String> events = new ConcurrentLinkedQueue<>();
    private static final AtomicBoolean started = new AtomicBoolean(false);
    private static final AtomicBoolean adsUp = new AtomicBoolean(false);

    private static volatile RewardedAd loaded;
    private static volatile boolean loading;
    private static volatile String unit = TEST_UNIT;
    private static volatile ConsentInformation consent;
    private static volatile Activity activity;
    private static Handler main;
    private static int failures;

    private LoveAds() {}

    // --- Called from native ------------------------------------------------

    public static void start(final Activity act) {
        if (!started.compareAndSet(false, true)) return;
        activity = act;
        unit = readUnit(act);
        main = new Handler(Looper.getMainLooper());

        act.runOnUiThread(() -> {
            consent = UserMessagingPlatform.getConsentInformation(act);
            ConsentRequestParameters params = new ConsentRequestParameters.Builder().build();
            consent.requestConsentInfoUpdate(act, params,
                () -> UserMessagingPlatform.loadAndShowConsentFormIfRequired(act, err -> {
                    privacyStatus();
                    if (consent.canRequestAds()) startAds();
                    else emit("unavailable", "consent");
                }),
                err -> {
                    // No answer from the consent service (offline, say): ads are
                    // only asked for if an earlier answer already allows them.
                    if (consent.canRequestAds()) startAds();
                    else emit("unavailable", "consent " + clean(err.getMessage()));
                });
            // An answer from an earlier launch counts straight away, rather than
            // waiting on the network round trip above.
            if (consent.canRequestAds()) startAds();
        });
    }

    public static void show(final Activity act, final String placement) {
        act.runOnUiThread(() -> {
            RewardedAd ad = loaded;
            if (ad == null) {
                emit("failed", placement, "not_ready");
                return;
            }
            loaded = null;
            emit("none", "shown");

            ad.setFullScreenContentCallback(new FullScreenContentCallback() {
                @Override
                public void onAdDismissedFullScreenContent() {
                    emit("closed", placement);
                    load();
                }

                @Override
                public void onAdFailedToShowFullScreenContent(@NonNull AdError error) {
                    emit("failed", placement, clean(error.getMessage()));
                    load();
                }
            });
            ad.show(act, item -> emit("reward", placement));
        });
    }

    /** The consent form again, which the GDPR requires a way back to. */
    public static void privacy(final Activity act) {
        act.runOnUiThread(() -> {
            if (consent == null) return;
            UserMessagingPlatform.showPrivacyOptionsForm(act, err -> {
                privacyStatus();
                if (consent.canRequestAds()) startAds();
            });
        });
    }

    public static String poll() {
        return events.poll();
    }

    // --- Inside ------------------------------------------------------------

    private static void startAds() {
        if (!adsUp.compareAndSet(false, true)) return;
        final Activity act = activity;
        // Off the UI thread, as Google asks: initialisation does disk work.
        new Thread(() -> MobileAds.initialize(act, status -> main.post(LoveAds::load))).start();
    }

    private static void load() {
        if (loaded != null || loading) return;
        loading = true;
        RewardedAd.load(activity, unit, new AdRequest.Builder().build(), new RewardedAdLoadCallback() {
            @Override
            public void onAdLoaded(@NonNull RewardedAd ad) {
                loading = false;
                failures = 0;
                loaded = ad;
                emit("ready");
            }

            @Override
            public void onAdFailedToLoad(@NonNull LoadAdError error) {
                loading = false;
                loaded = null;
                emit("none", clean(error.getMessage()));
                // Backed off to five minutes: no fill is usually no fill for a while.
                failures = Math.min(failures + 1, 6);
                main.postDelayed(LoveAds::load, Math.min(300000L, 5000L << failures));
            }
        });
    }

    private static void privacyStatus() {
        boolean needed = consent != null && consent.getPrivacyOptionsRequirementStatus()
            == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED;
        emit("privacy", needed ? "1" : "0");
    }

    private static String readUnit(Activity act) {
        try {
            ApplicationInfo info = act.getPackageManager()
                .getApplicationInfo(act.getPackageName(), PackageManager.GET_META_DATA);
            Bundle meta = info.metaData;
            String id = meta == null ? null : meta.getString(UNIT_KEY);
            if (id != null && !id.isEmpty()) return id;
        } catch (PackageManager.NameNotFoundException ignored) {
        }
        return TEST_UNIT;
    }

    private static String clean(String s) {
        return s == null ? "" : s.replace('\t', ' ').replace('\n', ' ');
    }

    private static void emit(String... fields) {
        events.add(TextUtils.join("\t", fields));
    }
}
