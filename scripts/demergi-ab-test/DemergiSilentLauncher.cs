using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class DemergiSilentLauncher
{
    private static int Main(string[] args)
    {
        string baseDir = AppDomain.CurrentDomain.BaseDirectory;

        try
        {
            string exePath = Process.GetCurrentProcess().MainModule.FileName;
            string exeName = Path.GetFileNameWithoutExtension(exePath).ToLowerInvariant();
            string scriptName = exeName.StartsWith("stop-demergi", StringComparison.OrdinalIgnoreCase)
                ? "stop-demergi-windows.ps1"
                : "run-demergi-normal-chrome.ps1";
            string scriptPath = Path.Combine(baseDir, scriptName);

            if (!File.Exists(scriptPath))
            {
                throw new FileNotFoundException("PowerShell script was not found.", scriptPath);
            }

            string windowsDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string powershellPath = Path.Combine(windowsDir, @"System32\WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershellPath))
            {
                powershellPath = "powershell.exe";
            }

            string arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "
                + Quote(scriptPath)
                + BuildForwardedArguments(args);

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = powershellPath;
            startInfo.Arguments = arguments;
            startInfo.WorkingDirectory = baseDir;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;

            Process.Start(startInfo);
            return 0;
        }
        catch (Exception ex)
        {
            WriteErrorLog(baseDir, ex);
            return 1;
        }
    }

    private static string BuildForwardedArguments(string[] args)
    {
        if (args == null || args.Length == 0)
        {
            return string.Empty;
        }

        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < args.Length; i++)
        {
            builder.Append(' ');
            builder.Append(Quote(args[i]));
        }
        return builder.ToString();
    }

    private static string Quote(string value)
    {
        if (value == null)
        {
            return "\"\"";
        }

        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void WriteErrorLog(string baseDir, Exception ex)
    {
        try
        {
            string logPath = Path.Combine(baseDir, "silent-launcher-error.log");
            string text = DateTime.UtcNow.ToString("u") + Environment.NewLine
                + ex.ToString() + Environment.NewLine + Environment.NewLine;
            File.AppendAllText(logPath, text, Encoding.UTF8);
        }
        catch
        {
            // Keep the launcher silent even when writing the diagnostic log fails.
        }
    }
}
