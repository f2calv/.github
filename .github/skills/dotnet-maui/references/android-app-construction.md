# Android App Construction

Patterns for MAUI apps whose Android target signs a user in, hosts web content or takes settings on the
device. Each one fixed a defect that only appeared on Android, after the same code worked on Windows.

## Contents

- [Sign-In with MSAL](#sign-in-with-msal)
- [Settings Entered on the Device](#settings-entered-on-the-device)
- [HybridWebView](#hybridwebview)
- [Platform-Specific Values](#platform-specific-values)
- [Shell Pages](#shell-pages)
- [App Identity](#app-identity)

## Sign-In with MSAL

- Use the system browser (`WithUseEmbeddedWebView(false)`) and no authentication broker, so a
  device-management broker cannot replace the user's account.
- Use the application ID as the redirect scheme: `<application-id>://auth`. It needs no
  signature hash and no per-registration value; register it on the public client's mobile and
  desktop platform next to the Windows `http://localhost` loopback.
- Receive the redirect with an exported `BrowserTabActivity` subclass whose `IntentFilter` has
  `ActionView`, the `Browsable` and `Default` categories, `DataHost = "auth"` and the scheme above.
- Forward `OnActivityResult` from `MainActivity` to
  `AuthenticationContinuationHelper.SetAuthenticationContinuationEventArgs`.
- Pass `WithParentActivityOrWindow(Platform.CurrentActivity)` and run `AcquireTokenInteractive` on
  the main thread (`MainThread.InvokeOnMainThreadAsync`).
- Declare `<queries>` for `android.intent.action.VIEW` with `https` and for
  `android.support.customtabs.action.CustomTabsService`, so Android 11+ package visibility lets MSAL
  find a browser.
- MSAL keeps its token cache in app-private storage on Android; on Windows it is in memory unless
  you add cache serialization.

## Settings Entered on the Device

- A sideloaded or CI-built APK must carry no tenant, client or endpoint values. Store them in
  `Preferences` and expose them through a small `ConfigurationProvider` that is also an
  `IConfigurationSource`. Add it from the Android platform partial before options are bound, and
  call its reload after saving.
- `IOptions<T>.Value` is read once. A service that has already read a value keeps it, so tell the
  user to restart the app after changing settings, or use `IOptionsMonitor<T>` end to end.
- Never resolve a typed `HttpClient` whose options are validated from a page constructor: the first
  launch, before settings exist, throws `OptionsValidationException` while creating the window and
  the app crashes. Inject `Func<TClient>` (registered as `services => services.GetRequiredService<TClient>`)
  and resolve it when the user acts, inside the `try` that reports incomplete settings.
- Confirm a save visibly, for example with `DisplayAlertAsync`; a button press alone gives no feedback.

## HybridWebView

- When the project lists `MauiIcon` or `MauiSplashScreen` explicitly, also add
  `<MauiAsset Include="Resources\Raw\**" LogicalName="%(RecursiveDir)%(Filename)%(Extension)" />`.
  Without it the web view serves 404 and `InvokeJavaScriptAsync` never completes.
- Bound every `InvokeJavaScriptAsync` with `WaitAsync(timeout)`. Return `null` or `false` from
  JavaScript on failure rather than throwing; `HybridWebViewInvokeJavaScriptException` is internal.
- Android raises `RawMessageReceived` on a background thread; Windows raises it on the UI thread.
  Dispatch the handler body with `Dispatcher.Dispatch` before touching any view, or Android throws
  `CalledFromWrongThreadException` and the app exits.
- Microphone and autoplay, from the `WebViewInitialized` platform arguments:
  - Android: `Sender` is `Android.Webkit.WebView`. Set `Settings.MediaPlaybackRequiresUserGesture =
    false` and a `WebChromeClient` whose `OnPermissionRequest` grants only
    `PermissionRequest.ResourceAudioCapture` after `Permissions.RequestAsync<Permissions.Microphone>()`
    is granted, and denies everything else. Declare `RECORD_AUDIO` and `MODIFY_AUDIO_SETTINGS`.
  - Windows: `Sender` is `CoreWebView2`. Allow only `CoreWebView2PermissionKind.Microphone` in
    `PermissionRequested`, and set `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` to
    `--autoplay-policy=no-user-gesture-required` (plus `--remote-debugging-port=9222` in Debug for
    Chrome DevTools) before the app initializes.
- Report microphone activity from the page with a Web Audio `AnalyserNode` and hysteresis, and show it
  with text as well as colour.

## Platform-Specific Values

- Prefer partial members implemented in `Platforms/<Platform>` files over `#if`: a
  `private static partial string RedirectUri { get; }` or a partial method returning a value must
  be implemented by every target framework the project builds.
- The Windows target rejects a collection expression assigned to `IReadOnlyList<T>` with
  `CsWinRT1032`; use an array (`new[] { ... }`) or a concrete type.
- A self-hosted endpoint behind a private certificate authority needs
  `android:networkSecurityConfig` trusting `user` certificates as well as `system` ones, with
  `cleartextTrafficPermitted="false"`. Drop the user anchor once the endpoint has a public certificate.

## Shell Pages

With `FlyoutBehavior="Disabled"`, each `ShellContent` added straight to `Shell.Items` becomes its own
top-level item and only the first is reachable. Put the pages in a `TabBar` and add that instead.

## App Identity

Replace the template's `appicon.svg` and `appiconfg.svg` and the `MauiIcon` `Color` for every app, so
several sideloaded apps are distinguishable on one device. Keep foreground artwork inside the central
two-thirds of the 456-unit canvas, the adaptive-icon safe zone.
