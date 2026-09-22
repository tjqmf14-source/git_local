using System.Diagnostics;
using System.Windows.Forms;

namespace GitLocal;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var root = AppContext.BaseDirectory;
        var script = Path.Combine(root, "src", "GitLocal.App.ps1");
        var module = Path.Combine(root, "src", "GitLocal.Core.psm1");
        var icon = Path.Combine(root, "assets", "GitLocal.ico");

        if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
        {
            if (!File.Exists(script) || !File.Exists(module) || !File.Exists(icon))
                return 2;

            using var probe = Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"Import-Module '{module.Replace("'", "''")}'; Resolve-GitLocalGitExecutable | Out-Null\"",
                UseShellExecute = false,
                CreateNoWindow = true
            });

            if (probe is null) return 3;
            probe.WaitForExit();
            return probe.ExitCode;
        }

        if (!File.Exists(script))
        {
            MessageBox.Show(
                "필수 파일을 찾을 수 없습니다. 압축 파일의 폴더 구조를 유지한 채 실행하세요.",
                "Git Local",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 4;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -STA -File \"{script}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = root
            });
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "Git Local - 실행 오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 5;
        }
    }
}
