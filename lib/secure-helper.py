#!/usr/bin/env python3
"""Secure cache opener and end-to-end supervisor for sleeper-matchup."""

from __future__ import annotations

import ctypes
import errno
import os
import signal
import stat
import subprocess
import sys
import time


MAX_DEADLINE_SECONDS = 90
TERM_GRACE_SECONDS = 2
KILL_REAP_SECONDS = 2
PR_SET_CHILD_SUBREAPER = 36


class HelperError(RuntimeError):
    pass


class StopRequested(BaseException):
    def __init__(self, signum: int) -> None:
        self.signum = signum


def fail(message: str) -> "None":
    raise HelperError(message)


def cache_path() -> str:
    cache_root = os.environ.get("XDG_CACHE_HOME")
    if not cache_root:
        home = os.environ.get("HOME")
        if not home:
            fail("HOME is required")
        cache_root = os.path.join(home, ".cache")
    path = os.path.normpath(os.path.join(cache_root, "oma-sleeper"))
    if not os.path.isabs(path) or len(os.fsencode(path)) > 4096:
        fail("cache path must be a bounded absolute path")
    return path


def verify_directory(
    fd: int, uid: int, system_uid: int, label: str, final: bool
) -> os.stat_result:
    info = os.fstat(fd)
    if not stat.S_ISDIR(info.st_mode):
        fail(f"{label} is not a directory")
    mode = stat.S_IMODE(info.st_mode)
    if final:
        if info.st_uid != uid:
            fail("cache directory is not owned by the current user")
    elif info.st_uid not in (system_uid, uid):
        fail(f"unsafe owner on cache ancestor {label}")
    if mode & 0o022:
        root_sticky = info.st_uid == system_uid and bool(mode & stat.S_ISVTX)
        if not root_sticky:
            fail(f"unsafe writable cache ancestor {label}")
    return info


def open_cache_directory() -> int:
    """Walk and open the cache without ever following a pathname symlink."""
    path = cache_path()
    uid = os.getuid()
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    held_fds: list[int] = []
    current_fd = os.open("/", flags)
    held_fds.append(current_fd)
    system_uid = os.fstat(current_fd).st_uid
    verify_directory(current_fd, uid, system_uid, "/", False)

    components = [part for part in path.split("/") if part]
    try:
        for index, component in enumerate(components):
            if component in (".", "..") or len(os.fsencode(component)) > 255:
                fail("unsafe cache path component")
            final = index == len(components) - 1
            try:
                next_fd = os.open(component, flags, dir_fd=current_fd)
            except FileNotFoundError:
                parent = os.fstat(current_fd)
                if parent.st_uid != uid:
                    fail("refusing to create a cache directory under an unowned parent")
                try:
                    os.mkdir(component, mode=0o700, dir_fd=current_fd)
                except FileExistsError:
                    pass
                next_fd = os.open(component, flags, dir_fd=current_fd)
            except OSError as error:
                if error.errno in (errno.ELOOP, errno.ENOTDIR):
                    fail("cache path component is not a directory or is a symbolic link")
                raise
            held_fds.append(next_fd)
            verify_directory(
                next_fd,
                uid,
                system_uid,
                "/" + "/".join(components[: index + 1]),
                final,
            )
            current_fd = next_fd

        # The final object is already pinned and owner-verified. Change and
        # verify permissions through that descriptor, never through its path.
        os.fchmod(current_fd, 0o700)
        final_info = os.fstat(current_fd)
        if final_info.st_uid != uid or stat.S_IMODE(final_info.st_mode) != 0o700:
            fail("opened cache directory permissions could not be secured")
        os.set_inheritable(current_fd, True)
        for ancestor_fd in held_fds[:-1]:
            os.close(ancestor_fd)
        return current_fd
    except BaseException:
        for fd in held_fds:
            try:
                os.close(fd)
            except OSError:
                pass
        raise


def deadline_seconds() -> int:
    raw = os.environ.get("OMA_SLEEPER_DEADLINE_SECONDS", "")
    if raw.isdecimal():
        return max(1, min(int(raw), MAX_DEADLINE_SECONDS))
    return MAX_DEADLINE_SECONDS


def enable_subreaper() -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0:
        error = ctypes.get_errno()
        fail(f"could not enable child reaping: {os.strerror(error)}")


def signal_group(pid: int, signum: int) -> None:
    try:
        os.killpg(pid, signum)
    except ProcessLookupError:
        pass


def reap_adopted_children(until: float) -> None:
    while time.monotonic() < until:
        reaped_any = False
        while True:
            try:
                pid, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                return
            if pid == 0:
                break
            reaped_any = True
        if not reaped_any:
            time.sleep(0.02)


def stop_process_group(process: subprocess.Popen[bytes]) -> None:
    signal_group(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=TERM_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        pass
    # The leader may have exited while a TERM-ignoring descendant remains.
    # Always escalate against the original process group after the grace time.
    signal_group(process.pid, signal.SIGKILL)
    try:
        process.wait(timeout=KILL_REAP_SECONDS)
    except subprocess.TimeoutExpired:
        pass
    reap_adopted_children(time.monotonic() + KILL_REAP_SECONDS)


def supervise(script: str, arguments: list[str]) -> int:
    enable_subreaper()

    def request_stop(signum: int, _frame: object) -> None:
        raise StopRequested(signum)

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    command = [sys.executable, os.path.abspath(__file__), "--open-cache", script, *arguments]
    process = subprocess.Popen(command, start_new_session=True)
    deadline = deadline_seconds()
    try:
        return process.wait(timeout=deadline)
    except subprocess.TimeoutExpired:
        print(f"sleeper-matchup: refresh exceeded {deadline} seconds", file=sys.stderr)
        stop_process_group(process)
        return 124
    except StopRequested as request:
        stop_process_group(process)
        return 128 + request.signum


def open_cache_and_exec(script: str, arguments: list[str]) -> "None":
    cache_fd = open_cache_directory()
    environment = os.environ.copy()
    environment["OMA_SLEEPER_WORKER"] = "1"
    environment["OMA_SLEEPER_CACHE_FD"] = str(cache_fd)
    os.execve(script, [script, *arguments], environment)


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in ("--supervise", "--open-cache"):
        fail("invalid secure-helper invocation")
    mode, script, arguments = sys.argv[1], os.path.abspath(sys.argv[2]), sys.argv[3:]
    if mode == "--supervise":
        return supervise(script, arguments)
    open_cache_and_exec(script, arguments)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HelperError as error:
        print(f"sleeper-matchup: {error}", file=sys.stderr)
        raise SystemExit(1)
    except OSError as error:
        print(f"sleeper-matchup: secure helper failed: {error}", file=sys.stderr)
        raise SystemExit(1)
