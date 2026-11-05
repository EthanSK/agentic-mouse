import Foundation

/// The environment for app-owned utility children. VS Code's macOS launcher
/// copies environment values into `open --env` arguments, so filtering logs
/// alone cannot protect credentials inherited from the agent that launched us.
public enum ChildProcessEnvironment {
    public static var minimal: [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName(), "LOGNAME": NSUserName(),
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "LC_ALL": "C", "LANG": "C", "TZ": "UTC",
        ]
    }
}
