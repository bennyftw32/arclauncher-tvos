package com.omeda.arc;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

/**
 * Gives the remote's Home button the Apple TV behaviour: a tap goes Home as usual, holding it
 * opens Arc TV's Control Center. Only active when the user enables it in Accessibility settings.
 *
 * Home can't be re-injected by an app, so the service consumes the Home key and performs the
 * system Home action itself for a short press.
 */
public class ArcAccessibilityService extends AccessibilityService {
    static final String EXTRA_OPEN_CONTROL_CENTER = "com.omeda.arc.OPEN_CONTROL_CENTER";
    private static final long LONG_PRESS_MS = 600;

    private static ArcAccessibilityService instance;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private boolean homeDown = false;
    private boolean longPressFired = false;

    private final Runnable openControlCenter = () -> {
        longPressFired = true;
        Intent intent = new Intent(this, MainActivity.class)
                .putExtra(EXTRA_OPEN_CONTROL_CENTER, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        startActivity(intent);
    };

    /** The running service, or null when the user hasn't enabled it. */
    static ArcAccessibilityService getInstance() {
        return instance;
    }

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        instance = this;
    }

    @Override
    public boolean onUnbind(Intent intent) {
        instance = null;
        handler.removeCallbacks(openControlCenter);
        return super.onUnbind(intent);
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        if (event.getKeyCode() != KeyEvent.KEYCODE_HOME) {
            return false;
        }
        switch (event.getAction()) {
            case KeyEvent.ACTION_DOWN:
                if (event.getRepeatCount() == 0) {
                    homeDown = true;
                    longPressFired = false;
                    handler.postDelayed(openControlCenter, LONG_PRESS_MS);
                } else if (event.isLongPress() && !longPressFired) {
                    // Remotes (and `input keyevent --longpress`) mark held keys with FLAG_LONG_PRESS.
                    handler.removeCallbacks(openControlCenter);
                    openControlCenter.run();
                }
                return true;
            case KeyEvent.ACTION_UP:
                handler.removeCallbacks(openControlCenter);
                if (homeDown && !longPressFired) {
                    performGlobalAction(GLOBAL_ACTION_HOME);
                }
                homeDown = false;
                return true;
            default:
                return true;
        }
    }

    /** Puts the device to sleep (Control Center's Sleep button). */
    boolean sleepNow() {
        return performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN);
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
    }

    @Override
    public void onInterrupt() {
    }
}
