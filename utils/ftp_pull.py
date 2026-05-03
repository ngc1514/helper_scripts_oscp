#!/usr/bin/env python3
"""
FTP bulk downloader (authorized use).

Behavior:
- If --creds is provided: uses username:password pairs from file.
- Else if --userfile and --passfile are provided: uses 1:1 line-matched pairs.
- Else (no credential args): logs in as anonymous and downloads recursively.

Examples:
  python3 ftp_pull.py --host 10.10.10.10
  python3 ftp_pull.py --host 10.10.10.10 --anon
  python3 ftp_pull.py --host 10.10.10.10 --creds creds.txt --recursive
  python3 ftp_pull.py --host 10.10.10.10 --userfile users.txt --passfile passwords.txt
"""

import argparse
import ftplib
import os
import re
import sys
from itertools import zip_longest
from typing import List, Tuple, Optional


def read_lines(path: str) -> List[str]:
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        lines = []
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            lines.append(s)
        return lines


def parse_creds_file(path: str) -> List[Tuple[str, str]]:
    pairs: List[Tuple[str, str]] = []
    for i, line in enumerate(read_lines(path), start=1):
        if ":" not in line:
            raise ValueError(f"{path}:{i}: expected 'username:password'")
        user, pw = line.split(":", 1)
        user = user.strip()
        pw = pw.strip()
        if not user:
            raise ValueError(f"{path}:{i}: empty username")
        pairs.append((user, pw))
    return pairs


def parse_user_pass_files(userfile: str, passfile: str) -> List[Tuple[str, str]]:
    users = read_lines(userfile)
    pws = read_lines(passfile)

    pairs: List[Tuple[str, str]] = []
    for idx, (u, p) in enumerate(zip_longest(users, pws), start=1):
        if u is None or p is None:
            raise ValueError(
                f"Line count mismatch: {userfile} has {len(users)} lines, "
                f"{passfile} has {len(pws)} lines. They must match 1:1."
            )
        if not u:
            raise ValueError(f"{userfile}:{idx}: empty username")
        pairs.append((u, p))
    return pairs


def sanitize_folder(name: str) -> str:
    name = name.strip()
    name = re.sub(r"[^\w.\-@]+", "_", name)
    return name or "user"


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def connect_ftp(host: str, port: int, timeout: int) -> ftplib.FTP:
    ftp = ftplib.FTP()
    ftp.connect(host=host, port=port, timeout=timeout)
    return ftp


def try_login(ftp: ftplib.FTP, user: str, pw: str) -> None:
    """
    Some anonymous servers accept any password or require blank.
    """
    try:
        ftp.login(user=user, passwd=pw)
    except ftplib.error_perm:
        if user.lower() in ("anonymous", "ftp"):
            ftp.login(user=user, passwd="")
        else:
            raise


def list_dir_mlsd(ftp: ftplib.FTP):
    try:
        return list(ftp.mlsd())
    except (ftplib.error_perm, AttributeError):
        return None


def is_dir_by_cwd_probe(ftp: ftplib.FTP, name: str) -> bool:
    cur = ftp.pwd()
    try:
        ftp.cwd(name)
        ftp.cwd(cur)
        return True
    except ftplib.error_perm:
        return False


def download_file(ftp: ftplib.FTP, remote_name: str, local_path: str, overwrite: bool) -> None:
    if os.path.exists(local_path) and not overwrite:
        print(f"  [=] Skip (exists): {local_path}")
        return

    tmp_path = local_path + ".part"
    with open(tmp_path, "wb") as f:
        ftp.retrbinary(f"RETR {remote_name}", f.write)
    os.replace(tmp_path, local_path)
    print(f"  [+] Downloaded: {local_path}")


def download_dir(ftp: ftplib.FTP, local_dir: str, recursive: bool, overwrite: bool) -> None:
    ensure_dir(local_dir)

    mlsd_entries = list_dir_mlsd(ftp)
    if mlsd_entries is not None:
        for name, facts in mlsd_entries:
            if name in (".", ".."):
                continue

            entry_type = (facts.get("type") or "").lower()
            if entry_type == "dir":
                if recursive:
                    cur = ftp.pwd()
                    ftp.cwd(name)
                    download_dir(ftp, os.path.join(local_dir, name), recursive, overwrite)
                    ftp.cwd(cur)
                else:
                    print(f"  [>] Directory (skip, use --recursive): {name}")
            else:
                try:
                    download_file(ftp, name, os.path.join(local_dir, name), overwrite)
                except ftplib.error_perm:
                    if recursive and is_dir_by_cwd_probe(ftp, name):
                        cur = ftp.pwd()
                        ftp.cwd(name)
                        download_dir(ftp, os.path.join(local_dir, name), recursive, overwrite)
                        ftp.cwd(cur)
                    else:
                        print(f"  [!] Skip: {name}")
        return

    # Fallback: NLST + CWD probe
    try:
        names = ftp.nlst()
    except ftplib.error_perm as e:
        print(f"  [!] Failed to list directory: {e}")
        return

    for name in names:
        base = os.path.basename(name.rstrip("/"))
        if base in (".", "..") or not base:
            continue

        if recursive and is_dir_by_cwd_probe(ftp, base):
            cur = ftp.pwd()
            ftp.cwd(base)
            download_dir(ftp, os.path.join(local_dir, base), recursive, overwrite)
            ftp.cwd(cur)
        else:
            try:
                download_file(ftp, base, os.path.join(local_dir, base), overwrite)
            except ftplib.error_perm as e:
                print(f"  [!] Skip (cannot RETR): {base} ({e})")


def main() -> int:
    ap = argparse.ArgumentParser(description="FTP bulk downloader (credential pairs or anonymous).")
    ap.add_argument("--host", required=True, help="FTP server host/IP")
    ap.add_argument("--port", type=int, default=21, help="FTP port (default: 21)")
    ap.add_argument("--timeout", type=int, default=10, help="Connect timeout seconds (default: 10)")
    ap.add_argument("--remote-dir", default=".", help="Remote directory to start from (default: .)")
    ap.add_argument("--outdir", default=".", help="Local output directory (default: current directory)")
    ap.add_argument("--recursive", action="store_true", help="Recursively download directories")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing files")
    ap.add_argument("--anon", action="store_true", help="Force anonymous login (ignores creds/user/pass files)")

    ap.add_argument("--creds", help="Credentials file with 'username:password' per line")
    ap.add_argument("--userfile", help="Username list file (one per line)")
    ap.add_argument("--passfile", help="Password list file (one per line, line-matched to userfile)")

    args = ap.parse_args()

    # Decide auth mode
    has_list_mode = bool(args.creds or args.userfile or args.passfile)

    if args.anon or not has_list_mode:
        # Default: anonymous
        pairs: List[Tuple[str, str]] = [("anonymous", "anonymous@")]
        # In anonymous mode, default to recursive even if user didn't pass --recursive
        if not args.recursive:
            args.recursive = True
    else:
        if args.creds:
            if args.userfile or args.passfile:
                ap.error("Use either --creds OR (--userfile AND --passfile), not both.")
            pairs = parse_creds_file(args.creds)
        else:
            if not (args.userfile and args.passfile):
                ap.error("Provide both --userfile and --passfile (1:1 line mapping), or use --creds, or use --anon.")
            pairs = parse_user_pass_files(args.userfile, args.passfile)

    ensure_dir(args.outdir)

    for user, pw in pairs:
        user_dir = os.path.join(args.outdir, sanitize_folder(user))
        ensure_dir(user_dir)

        ftp: Optional[ftplib.FTP] = None
        try:
            print(f"[+] Connecting to {args.host}:{args.port} as {user!r} ...")
            ftp = connect_ftp(args.host, args.port, args.timeout)
            try_login(ftp, user, pw)

            ftp.cwd(args.remote_dir)
            print(f"    Remote PWD: {ftp.pwd()}")
            download_dir(ftp, user_dir, args.recursive, args.overwrite)

        except ftplib.error_perm as e:
            print(f"[!] Login/permission failed for {user!r}: {e}")
        except Exception as e:
            print(f"[!] Error for {user!r}: {e}")
        finally:
            if ftp is not None:
                try:
                    ftp.quit()
                except Exception:
                    try:
                        ftp.close()
                    except Exception:
                        pass

    return 0


if __name__ == "__main__":
    sys.exit(main())