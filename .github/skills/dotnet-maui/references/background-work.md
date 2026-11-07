# Android Background Work

Run deferrable Android work, such as a media backup, from a .NET MAUI app with WorkManager. Android
starts the process on demand, so design every run to start cold, resume safely and never need a
screen.

## Package

Add `Xamarin.AndroidX.Work.Runtime` to the Android target only. Its AndroidX dependencies must fit
inside the exact version ranges that `Microsoft.Maui.Controls` pins; a newer WorkManager fails
restore with `NU1608` for `Xamarin.AndroidX.Lifecycle.*` or `Collection.*`. Read each release's
dependency group from the NuGet registration, choose the newest release whose `Xamarin.AndroidX.Core`
and `Lifecycle.*` match those already in `project.assets.json`, and note in the central package file
that it moves only with `Microsoft.Maui.Controls`.

## Worker

- Subclass `AndroidX.Work.Worker` with a `(Context, WorkerParameters)` constructor and a fixed
  `[Register("<application-id>.<WorkerName>")]` Java name. WorkManager persists the class name with
  every request, and the default generated name changes with the namespace or assembly.
- Resolve services through `IPlatformApplication.Current?.Services`; the `MauiApplication` builds the
  host for every process start, including one started by WorkManager. When it is unavailable, retry.
- `DoWork` runs on a background thread, so blocking on one async call is acceptable. Cancel a
  `CancellationTokenSource` from `OnStopped`, and return `Result.InvokeSuccess()` or
  `Result.InvokeRetry()`.
- Re-apply schedules in `MainApplication.OnCreate` from the saved settings, with `Keep` for one-time
  work and `Update` for periodic work, so an update or a settings change takes effect.
- Never prompt from a worker. Make token providers fail with a sign-in-required error in unattended
  runs, and post a notification asking the user to open the app instead.
- Check runtime permissions without requesting them; a worker cannot show a dialog. Request
  `POST_NOTIFICATIONS` from the UI, for example when the user enables the feature.
- Serialize manual and background runs with one lock in the shared service.
- Ordinary work stops after about ten minutes. Make runs resumable, or use expedited or foreground
  work with a matching foreground service type when one unit of work can outlast that.

## Media Triggers

- `Constraints.Builder.AddContentUriTrigger` on the MediaStore image and video collections starts a
  run when media changes. Set an update delay and a maximum delay to batch bursts.
- A content trigger fires once, and a retried trigger request waits for another change. Re-arm the
  trigger at the end of each run by enqueueing a fresh request under the same unique name with
  `ExistingWorkPolicy.Replace`, and hand a failed run to a separate one-time catch-up request.
- Never re-arm by appending to the trigger's own chain. Finished links stay because their successor is
  unfinished; their stale job records make WorkManager reconcile on every cold start. That reschedules
  every request with its existing job ID, which stops the job that has just started the process, so
  background runs silently stop happening.
- Do not rescan the whole library per trigger. Record a checkpoint of each volume's
  `MediaStore.GetVersion` and `MediaStore.GetGeneration`, taken before discovery. Then query only rows
  whose `generation_modified` is newer, and read a volume in full when its version changed. Advance the
  checkpoint only after a run that read every changed item.

## Test on an Emulator

- Read schedules and constraints with `adb shell dumpsys jobscheduler <package>`: a waiting trigger
  shows `Unsatisfied constraints: CONTENT_TRIGGER`.
- Send the app home with `adb shell input keyevent KEYCODE_HOME` and confirm the launcher is on top
  before killing anything; a foreground app restarts immediately.
- Simulate process death with `adb shell run-as <package> kill -9 <pid>` on a debuggable build. Do not
  use `am kill` or `am force-stop`: WorkManager treats both as a force-stop and cancels and reschedules
  all work, which hides the behavior under test.
- `Microsoft.Extensions.Logging.Debug` output does not reach logcat. Follow runs through WorkManager's
  `WM-` tags and the notification list from `adb shell dumpsys notification --noredact`.
- Inspect WorkManager's state by copying `no_backup/androidx.work.workdb` (with its `-wal` and `-shm`
  files) through `adb exec-out run-as <package> cat`. Then query the `WorkSpec`, `WorkName` and
  `SystemIdInfo` tables, for example with Node's built-in `node:sqlite`. A `SystemIdInfo` row for
  finished work explains a reconcile on every cold start.
