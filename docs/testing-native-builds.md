# Test a native V2 Lens build

These portable test builds include the Racket runtime. **Do not install Racket.**
Download the archive for your operating system and processor, together with its
`.sha256` file, from a successful **Native packages** workflow run. Extract the
entire archive before opening the application; keep its contents together.

| System | Archive | Open after extraction |
| --- | --- | --- |
| Mac, Apple Silicon | `macos-arm64.zip` | `V2 Lens.app` |
| Mac, Intel | `macos-x64.zip` | `V2 Lens.app` |
| Windows, Intel/AMD 64-bit | `windows-x64.zip` | `V2-Lens.exe` |
| Linux, Intel/AMD 64-bit | `linux-x64.tar.gz` | `bin/v2-lens` |

The complete filenames include the release version. CI tests Mac builds on
macOS 14 (Apple Silicon) and macOS 15 (Intel), Windows builds on Windows Server
2022, and Linux builds on Ubuntu 22.04. Other OS versions require testing.
Linux needs a graphical desktop and GTK 3 system libraries (on Ubuntu,
`sudo apt install libgtk-3-0`). It does not need Racket or Python to run the app.

Mac builds are ad-hoc signed, not Developer ID signed or notarized. Windows
builds are unsigned. Your OS or organization may require approval to open
these test builds. On Mac, after attempting to open the app, use the specific
app's **Open Anyway** option in System Settings → Privacy & Security if your
policy permits. Do not disable system-wide protection. Report an opening block
if your device policy does not allow the build.

To check the download, compare `shasum -a 256 <archive>` (Mac),
`sha256sum <archive>` (Linux), or `Get-FileHash <archive> -Algorithm SHA256`
(PowerShell) with the supplied checksum. Checksums detect damaged downloads;
they are not publisher signatures.

## First test

Use synthetic messages only. Paste this example (one segment per line):

```text
MSH|^~\&|TEST|DEMO|||202609241200||ORU^R01|TEST-1|P|2.5.1
OBX|1|NM|TEST^Synthetic observation||42|units
```

1. Open the app without a development environment installed.
2. Paste the example and click **Parse**. Check that two segments appear.
3. Select the observation value and confirm the corresponding Raw Source text
   is highlighted. Switch back to Readable report.
4. Toggle **Show empty fields** and confirm the app responds.
5. Save the example as a UTF-8 `.hl7` file and open it using **Open…**.
6. Confirm that parsing a large input can be cancelled and that inputs beyond
   the documented limits stay available as raw text instead of freezing.
7. Close and reopen the app. Previously entered message content should not return.

The desktop parse limit is 5 MiB, the file-open limit is 100 MiB, and the
structural limit is 50,000 possible delimiters. See the main README for scope.

Report the release, commit, platform and architecture from `build-info.json`,
your OS version, steps, and expected/actual behavior through
https://github.com/CodeDraig/v2-lens/issues. Do not attach patient data.
