{{flutter_js}}
{{flutter_build_config}}

// A boot asset load cut off mid-flight (a network change aborts it) would
// leave a blank page; reload instead, at most twice per tab session.
const bootRetries = 'fg-boot-retries';
function retryBoot(error) {
  console.error('Flutter boot failed:', error);
  const tries = Number(sessionStorage.getItem(bootRetries) ?? 0);
  if (tries >= 2) throw error;
  sessionStorage.setItem(bootRetries, String(tries + 1));
  location.reload();
}

// With onEntrypointLoaded the loader does not watch its script tag, so
// catch a failed main.dart.js here (load errors only reach capture listeners).
let started = false;
window.addEventListener('error', (event) => {
  if (!started && event.target instanceof HTMLScriptElement) {
    retryBoot(new Error(`failed to load ${event.target.src}`));
  }
}, true);

_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      started = true;
      sessionStorage.removeItem(bootRetries);
    } catch (error) {
      retryBoot(error);
    }
  },
}).catch(retryBoot);
