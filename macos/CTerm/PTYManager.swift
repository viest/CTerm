import Foundation

@_silgen_name("fork") private func c_fork() -> pid_t
@_silgen_name("setsid") private func c_setsid() -> pid_t

class PTYManager {
    private(set) var masterFd: Int32 = -1
    private(set) var slaveFd: Int32 = -1
    private(set) var childPid: pid_t = -1
    var onDataReceived: ((Data) -> Void)?
    var onProcessExit: ((Int32) -> Void)?

    func spawn(command: String = "/bin/zsh", args: [String] = [], environment: [String: String] = [:], workingDir: String? = nil, size: (rows: UInt16, cols: UInt16) = (24, 80)) {
        var winSize = winsize()
        winSize.ws_row = size.rows
        winSize.ws_col = size.cols

        var mfd: Int32 = -1
        var sfd: Int32 = -1
        guard openpty(&mfd, &sfd, nil, nil, &winSize) >= 0 else {
            print("CTerm: openpty failed"); return
        }
        self.masterFd = mfd
        self.slaveFd = sfd

        // ── Prepare ALL C strings BEFORE fork ──
        // argv
        let allArgs = [command] + args
        let cArgPtrs = allArgs.map { strdup($0)! }
        var cArgv = cArgPtrs + [nil]

        // env
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = "en_US.UTF-8"
        for (k, v) in environment { env[k] = v }
        let cEnvPtrs = env.map { strdup("\($0.key)=\($0.value)")! }
        var cEnvp = cEnvPtrs + [nil]

        // command path as C string
        let cCmd = strdup(command)!

        // workingDir as C string
        let cDir: UnsafeMutablePointer<CChar>? = workingDir.map { strdup($0)! }

        // fallback: /usr/bin/env
        let cEnvBin = strdup("/usr/bin/env")!
        let fallbackArgPtrs = [cEnvBin] + cArgPtrs
        var cFallbackArgv = fallbackArgPtrs + [nil]

        // ── Fork ──
        let pid = c_fork()
        if pid < 0 {
            print("CTerm: fork failed")
            close(mfd); close(sfd); return
        }

        if pid == 0 {
            // ── Child: only POSIX calls, no Swift runtime ──
            close(mfd)
            if c_setsid() < 0 { _exit(1) }
            if ioctl(sfd, TIOCSCTTY, 0) < 0 { _exit(1) }

            if dup2(sfd, STDIN_FILENO) < 0 { _exit(1) }
            if dup2(sfd, STDOUT_FILENO) < 0 { _exit(1) }
            if dup2(sfd, STDERR_FILENO) < 0 { _exit(1) }
            if sfd > STDERR_FILENO { close(sfd) }

            if let d = cDir, chdir(d) != 0 { _exit(1) }

            execve(cCmd, &cArgv, &cEnvp)
            // fallback
            execve(cEnvBin, &cFallbackArgv, &cEnvp)
            _exit(1)
        }

        // ── Parent ──
        self.childPid = pid
        close(sfd)
        self.slaveFd = -1

        // Free strdup'd memory (child has its own copy after fork)
        free(cCmd)
        if let d = cDir { free(d) }
        free(cEnvBin)
        for p in cArgPtrs { free(p) }
        for p in cEnvPtrs { free(p) }

        // Background reader
        let fd = mfd
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var buf = [UInt8](repeating: 0, count: 16384)
            while self?.masterFd == fd {
                let n = read(fd, &buf, buf.count)
                if n > 0 {
                    let data = Data(bytes: buf, count: n)
                    DispatchQueue.main.async { self?.onDataReceived?(data) }
                } else { break }
            }
        }

        // Child watcher
        DispatchQueue.global().async { [weak self] in
            var st: Int32 = 0
            waitpid(pid, &st, 0)
            DispatchQueue.main.async { self?.onProcessExit?(st) }
        }
    }

    func write(_ data: Data) {
        guard masterFd >= 0 else { return }
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                _ = Foundation.write(masterFd, base, ptr.count)
            }
        }
    }

    func writeString(_ string: String) {
        if let data = string.data(using: .utf8) { write(data) }
    }

    func resize(rows: UInt16, cols: UInt16) {
        guard masterFd >= 0 else { return }
        var ws = winsize()
        ws.ws_row = rows
        ws.ws_col = cols
        _ = ioctl(masterFd, TIOCSWINSZ, &ws)
    }

    func terminate() {
        let pid = childPid
        let fd = masterFd
        childPid = -1
        masterFd = -1
        if pid > 0 { kill(pid, SIGHUP); kill(pid, SIGKILL) }
        if fd >= 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { close(fd) }
        }
    }

    deinit { terminate() }
}
