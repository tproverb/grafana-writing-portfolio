# Configure and verify a local Linux lab with Ansible

Tim Suleyman | Technical writing portfolio | Tested October 27, 2026

Use Ansible to create a directory and configuration file in Ubuntu, verify that repeating the playbook makes no further changes, and correct a deliberate manual edit. Preview a correction before applying it so you can distinguish predicted changes from completed changes.

## Audience and outcome

This tutorial is for readers comfortable pasting terminal commands who are new to Ansible. Ansible runs tasks described in a YAML playbook. An inventory identifies the machines that receive those tasks.

In this example, Ubuntu is both the machine running Ansible and its only target. You do not need SSH, a remote server, Docker, or cloud credentials. The managed file is a demonstration configuration, not a configuration consumed by a running service.

All commands below run in the Ubuntu WSL terminal, not Windows PowerShell.

## Prerequisites

- A working Ubuntu WSL environment and an internet connection for package installation.
- An Ubuntu account with permission to use `sudo` for installation.
- A home directory where you can create `ansible-portfolio` and `ansible-demo`.

Use a new `~/ansible-demo` directory for this exercise. The playbook manages the entire content of `lab.conf` and can replace manual edits to that file. Do not point it at an existing application configuration.

The tested environment was Ubuntu 26.04.1 LTS under WSL 2, Ansible core 2.20.1, and Python 3.14.4. Package versions may differ on another installation.

## 1. Install and verify Ansible

Check your distribution and available package:

```bash
cat /etc/os-release
sudo apt update
apt-cache policy ansible
```

The tested Ubuntu repository offered `13.1.0+dfsg-1ubuntu1` for the `ansible` package. Install it and inspect the installed engine:

```bash
sudo apt install ansible
ansible --version
```

Enter your Ubuntu password if prompted and confirm package installation. Password entry displays no characters. In the tested environment, the version command began with:

```text
ansible [core 2.20.1]
```

The package version and engine version identify different components, so their numbers need not match.

Verify local module execution:

```bash
ansible localhost -m ansible.builtin.ping -c local
```

Expected result: `SUCCESS`, `changed: false`, and `ping: pong`. This Ansible module checks module execution through Python; it is not an ICMP network ping.

A warning about no parsed inventory is expected for this initial command. The next step supplies an explicit inventory.

## 2. Create a workspace and inventory

```bash
mkdir -p ~/ansible-portfolio
cd ~/ansible-portfolio

cat > inventory.ini <<'EOF'
[local]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3
EOF
```

The `cat` block creates `inventory.ini` silently. Keep the closing `EOF` alone on its line. The group is called `local`; it contains one target, `localhost`. The connection setting runs tasks locally, and the interpreter setting selects Ubuntu's Python executable.

Test that inventory:

```bash
ansible -i inventory.ini local -m ansible.builtin.ping
```

Expected result:

```text
localhost | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

The earlier inventory warning should no longer appear.

## 3. Create the playbook

While still in `~/ansible-portfolio`, paste this complete block:

```bash
cat > configure-lab.yml <<'EOF'
---
- name: Configure a local documentation lab
  hosts: local
  gather_facts: true

  vars:
    lab_directory: "{{ ansible_facts['env']['HOME'] }}/ansible-demo"

  tasks:
    - name: Ensure the lab directory exists
      ansible.builtin.file:
        path: "{{ lab_directory }}"
        state: directory
        mode: '0755'

    - name: Ensure the lab configuration has the expected content
      ansible.builtin.copy:
        dest: "{{ lab_directory }}/lab.conf"
        content: |
          environment=local
          managed_by=ansible
          purpose=documentation-portfolio
        mode: '0644'
EOF
```

The command saves `configure-lab.yml` and returns to the prompt without a success message. Preserve the YAML indentation using spaces.

The playbook gathers information about the local environment, uses the target account's home directory, and manages two resources:

| Resource | Desired state |
| --- | --- |
| `~/ansible-demo` | Directory exists with permissions `0755`. |
| `~/ansible-demo/lab.conf` | File contains the three specified lines with permissions `0644`. |

Permission `0755` lets the owner read, write, and enter the directory; others can read and enter it. Permission `0644` lets the owner read and write the file; others can read it. These sample values are not suitable for secrets.

No privilege escalation is configured. Run the playbook as your regular Ubuntu account, without `sudo`.

## 4. Check syntax and apply the configuration

```bash
ansible-playbook -i inventory.ini configure-lab.yml --syntax-check
```

Expected result includes:

```text
playbook: configure-lab.yml
```

This checks playbook syntax without executing its tasks. It does not prove that execution will succeed.

Apply it:

```bash
ansible-playbook -i inventory.ini configure-lab.yml
```

With a new lab directory, the observed recap was:

```text
localhost : ok=3 changed=2 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

Gathering facts succeeded, and both resource tasks changed the system. `ok` includes successful tasks that made changes; it is not an additional count of unchanged tasks. Existing resources can produce a different change count.

## 5. Verify the result and repeat the run

Inspect the file and permissions independently:

```bash
cat ~/ansible-demo/lab.conf
stat -c '%a %n' ~/ansible-demo ~/ansible-demo/lab.conf
```

Expected content:

```text
environment=local
managed_by=ansible
purpose=documentation-portfolio
```

Expect directory permissions `755` and file permissions `644`, followed by their respective paths.

Run the playbook again:

```bash
ansible-playbook -i inventory.ini configure-lab.yml
```

Expected recap: `ok=3`, `changed=0`, `unreachable=0`, and `failed=0`. This demonstrates idempotence for the tested state: repeating the playbook makes no further changes once its requested state is satisfied.

If changes continue, run with `--diff` and inspect the output before declaring the test successful:

```bash
ansible-playbook -i inventory.ini configure-lab.yml --diff
```

An unchanged run with `changed=0` was observed during testing.

## 6. Correct configuration drift

Configuration drift is a difference between the requested state and the actual state. Introduce it by changing one value manually:

```bash
sed -i 's/environment=local/environment=modified/' ~/ansible-demo/lab.conf
cat ~/ansible-demo/lab.conf
```

Confirm the first line now says `environment=modified`.

Apply the playbook with a before-and-after comparison:

```bash
ansible-playbook -i inventory.ini configure-lab.yml --diff
```

The observed diff included:

```diff
-environment=modified
+environment=local
```

Expected recap: `changed=1`, `failed=0`, and `unreachable=0`. The directory already matches its desired state; the file task restores the content.

The playbook overwrites the managed file with its declared content. This example does not merge arbitrary manual changes or preserve extra lines.

## 7. Preview a correction without applying it

Introduce the same drift again, then use check mode:

```bash
sed -i 's/environment=local/environment=modified/' ~/ansible-demo/lab.conf
ansible-playbook -i inventory.ini configure-lab.yml --check --diff
cat ~/ansible-demo/lab.conf
```

Expected result: the preview reports `changed=1`, but the file still contains `environment=modified`. In check mode, that change count predicts a change rather than confirming one was applied. Both were confirmed in this test.

This preview was performed after the directory and file existed. Check mode depends on module support and task settings; do not assume every possible playbook is fully simulated or free of side effects.

## 8. Apply and confirm stability

```bash
ansible-playbook -i inventory.ini configure-lab.yml --diff
ansible-playbook -i inventory.ini configure-lab.yml
```

Expected and observed results:

| Run | Changed | Failed | Unreachable |
| --- | --- | --- | --- |
| Apply correction | 1 | 0 | 0 |
| Repeat after correction | 0 | 0 | 0 |

The first run restores the configuration. The second verifies that the requested state is stable. Leave the lab directory in place if you want to repeat these tests.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| File creation returns silently to the prompt | Expected for the `cat` blocks. Run the syntax check separately to obtain explicit feedback. |
| Inventory warning or targets do not match | Run from the workspace, supply `-i inventory.ini`, and check that the inventory group and `hosts: local` match. |
| Playbook or inventory cannot be found | Run `pwd` and `ls`. Change to `~/ansible-portfolio` before retrying. |
| YAML syntax error | Compare indentation with the sample. Use spaces and keep the closing shell `EOF` outside the YAML content. |
| Preview shows `changed=1` | Inspect the file. In this exercise, check mode predicts the correction while leaving the modified value intact. |
| Repeated normal runs still report changes | Inspect `--diff` output and the actual file and permissions. Resolve the discrepancy before claiming idempotence. |

## Validation record and limits

On October 27, 2026, the author tested local module execution, explicit inventory, syntax checking, initial creation, an unchanged repeat run, file content and permissions, drift correction, check-mode preview, and a final apply followed by an unchanged run. Commands and recaps were captured during a guided session; content and permission checks were confirmed by the author.

This sample manages one demonstration file on one local Ubuntu target. It does not demonstrate remote-host authentication, package or service management through a playbook, multi-host orchestration, or production automation. Installation and commands were tested in the versions listed above, not across all Ubuntu or Ansible releases.

## References

- [Ansible installation by operating system](https://docs.ansible.com/projects/ansible/latest/installation_guide/installation_distros.html)
- [Check mode and diff mode](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_checkmode.html)
- [File module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/file_module.html)
- [Copy module](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/copy_module.html)

## Included source files

- [Local inventory](ansible/inventory.ini)
- [Configuration playbook](ansible/configure-lab.yml)

These links assume this tutorial is stored at the repository root and the source files are stored in its `ansible` subdirectory. Copy those source files into a workspace inside Ubuntu's home directory when following the tutorial; all tested executions used the Linux filesystem.
