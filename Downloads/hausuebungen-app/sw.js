const CACHE = "hu-shell-v9";
const SHELL = ["./", "./index.html", "./style.css", "./config.js", "./manifest.json", "./icon.jpg"];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL).catch(() => {})).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  const isShell = url.pathname.endsWith(".html") || url.pathname === "/" || url.pathname.endsWith("/") ||
    url.pathname.endsWith(".css") || url.pathname.endsWith(".js");
  event.respondWith(
    (isShell
      ? fetch(req).then(res => {
          if (res && res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
          }
          return res;
        }).catch(() => caches.match(req))
      : caches.match(req).then(cached => {
          const network = fetch(req).then(res => {
            if (res && res.ok && (url.pathname.endsWith(".json") || url.pathname.endsWith(".jpg"))) {
              const copy = res.clone();
              caches.open(CACHE).then(c => c.put(req, copy)).catch(() => {});
            }
            return res;
          }).catch(() => cached);
          return cached || network;
        })
    )
  );
});

self.addEventListener("push", event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch {}
  const title = data.title || "Hausübungen";
  const options = {
    body: data.body || "Es gibt eine neue Hausübung.",
    icon: "icon.jpg",
    badge: "icon.jpg",
    tag: data.tag || "hausuebungen",
    data: { url: data.url || "./" },
    renotify: true
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const url = new URL(event.notification.data?.url || "./", self.location.origin).href;
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then(list => {
      for (const client of list) {
        if ("focus" in client) {
          client.navigate(url);
          return client.focus();
        }
      }
      return clients.openWindow(url);
    })
  );
});
