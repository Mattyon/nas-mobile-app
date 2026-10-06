// Web Push from the NAS gateway (ai-gateway web_push.py), used from Dart through
// window.nasPush (lib/web_push_web.dart). Same origin as the API, so /push/... works.
(function () {
  const SW = 'push-sw.js';   // relative to <base href="/app/">: /app/push-sw.js, scope /app/

  const supported = () =>
    'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  // iOS only offers Web Push to a site added to the Home Screen and opened from there.
  const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone = () => window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true;

  function bytes(b64url) {
    const pad = '='.repeat((4 - (b64url.length % 4)) % 4);
    const raw = atob((b64url + pad).replace(/-/g, '+').replace(/_/g, '/'));
    return Uint8Array.from(raw, (c) => c.charCodeAt(0));
  }
  async function current() {
    if (!supported()) return null;
    const reg = await navigator.serviceWorker.getRegistration('./');
    return reg ? reg.pushManager.getSubscription() : null;
  }
  async function api(path, token, body) {
    const r = await fetch(path, {
      method: body ? 'POST' : 'GET',
      headers: { 'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!r.ok) throw new Error(path + ': HTTP ' + r.status);
    return r.json();
  }

  window.nasPush = {
    // 'unsupported' | 'needs-home-screen' | 'denied' | 'on' | 'off'
    async state() {
      if (isIOS() && !standalone()) return 'needs-home-screen';
      if (!supported()) return 'unsupported';
      if (Notification.permission === 'denied') return 'denied';
      return (await current()) ? 'on' : 'off';
    },
    // Must start inside the tap that called it: iOS only asks for permission then.
    async enable(token, lang) {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') return perm === 'denied' ? 'denied' : 'off';
      const reg = await navigator.serviceWorker.register(SW, { scope: './' });
      await navigator.serviceWorker.ready;
      const { key } = await api('/push/public-key', token);
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: bytes(key) });
      }
      await api('/push/subscribe', token, { subscription: sub.toJSON(), lang: lang });
      return 'on';
    },
    async disable(token) {
      const sub = await current();
      if (sub) {
        try { await api('/push/unsubscribe', token, { endpoint: sub.endpoint }); } catch (_) {}
        await sub.unsubscribe();
      }
      return 'off';
    },
  };
})();
