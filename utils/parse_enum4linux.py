#!/usr/bin/env python3
# Parse enum4linux-ng output into a short, per-host summary of useful findings.
# It throws away the noise ([-] failures, [*] progress chatter, generic headers)
# and keeps only the true positives you actually act on.
#
# Usage:  python3 parse_enum.py enum4linux_out.txt

import sys


def main():
    input_file = sys.argv[1]
    with open(input_file) as file_handle:
        full_text = file_handle.read()

    # Each host's run starts with this banner line, so we split on it.
    host_blocks = full_text.split("ENUM4LINUX - next generation")

    for block in host_blocks:
        if "Target ........" not in block:
            continue
        summarize_host(block)


def get_field(block, label):
    """Return the text that comes after 'label' on the first line containing it."""
    for line in block.splitlines():
        if label in line:
            return line.split(label, 1)[1].strip()
    return None


def summarize_host(block):
    lines = block.splitlines()
    target_ip = get_field(block, "Target ...........")

    # Gate: if neither SMB nor LDAP answered, the host is dead to us.
    smb_up = "SMB is accessible" in block
    ldap_up = "LDAP is accessible on 389" in block
    if not smb_up and not ldap_up:
        print("[{}]  DOWN  (no SMB/LDAP) -- skipped".format(target_ip))
        print("-" * 64)
        return

    print("[{}]  UP".format(target_ip))

    # ---- Identity ----
    hostname = get_field(block, "NetBIOS computer name:")
    fqdn = get_field(block, "FQDN:")
    dns_domain = get_field(block, "DNS domain:")
    operating_system = get_field(block, "OS: ")
    is_domain_controller = "Appears to be root/parent DC" in block
    signing_required = "SMB signing required: true" in block

    if hostname:
        print("    hostname : {}".format(hostname))
    if fqdn and fqdn != hostname:
        print("    fqdn     : {}".format(fqdn))
    if dns_domain and dns_domain not in ("''", hostname):
        print("    domain   : {}".format(dns_domain))
    if operating_system:
        print("    os       : {}".format(operating_system))
    if is_domain_controller:
        print("    role     : DOMAIN CONTROLLER")
    print("    signing  : {}".format("required" if signing_required else "NOT required"))

    # ---- Sessions that actually worked (the part that matters most) ----
    allowed_logins = []
    for line in lines:
        if "Server allows authentication via username" in line:
            allowed_logins.append(line.split("[+]", 1)[1].strip())
    if allowed_logins:
        print("    sessions :")
        for entry in allowed_logins:
            print("        + {}".format(entry))

    # ---- Users / groups, but only if a non-zero count was found ----
    for line in lines:
        if "user(s)" in line and "Found 0 user" not in line and "[+]" in line:
            print("    users    : {}".format(line.split("[+]", 1)[1].strip()))
        if "group(s)" in line and "Found 0 group" not in line and "[+]" in line:
            print("    groups   : {}".format(line.split("[+]", 1)[1].strip()))

    # ---- Shares: name, comment, and whether you can list it ----
    shares = parse_shares(lines)
    if shares:
        print("    shares   :")
        for share_line in shares:
            print("        - {}".format(share_line))

    print("-" * 64)


def parse_shares(lines):
    """Pull share name + comment from the 'Shares via RPC' block,
    then tag each share with its access result (listable or not)."""
    share_comments = {}
    share_access = {}

    capturing_list = False
    current_name = None

    for line in lines:
        # Start capturing once we hit the "Found N share(s):" line.
        if "share(s):" in line:
            capturing_list = True
            continue

        if capturing_list:
            # Stop at the first "Testing share" or the next section border.
            if "Testing share" in line or line.startswith(" ===="):
                capturing_list = False
            else:
                stripped = line.strip()
                if stripped.endswith(":") and not stripped.startswith("["):
                    current_name = stripped.rstrip(":")
                    share_comments[current_name] = ""
                elif stripped.startswith("comment:") and current_name:
                    share_comments[current_name] = stripped.split("comment:", 1)[1].strip()

        # Access results appear later as "Testing share X" then "Mapping/Listing".
        if "Testing share" in line:
            current_name = line.split("Testing share", 1)[1].strip()
        if "Listing: OK" in line and current_name:
            share_access[current_name] = "LISTABLE"

    results = []
    for name, comment in share_comments.items():
        access = share_access.get(name, "")
        label = name
        if access:
            label += "  [{}]".format(access)
        if comment:
            label += "  ({})".format(comment)
        results.append(label)
    return results


if __name__ == "__main__":
    main()