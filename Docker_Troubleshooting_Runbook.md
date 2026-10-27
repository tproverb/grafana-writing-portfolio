# Diagnose and recover a local Docker application

Tim Suleyman | Technical writing portfolio | Validated October 27, 2026

Use this runbook when a local Grafana instance running in Docker does not respond, a container cannot claim its host port, or Grafana exits during startup. Identify the failure from container state, port mappings, logs, and an application health request; then verify recovery.

## Scope and prerequisites

This runbook covers a personal Windows lab using PowerShell, Docker Desktop with WSL 2, Docker CLI 29.9.2, and Grafana 13.3.0. Docker Desktop must be running and the `docker` command must be available in PowerShell.

The existing application container is `grafana-portfolio`. It publishes container TCP port 3000 at `127.0.0.1:3000` and uses the named volume `grafana-portfolio-data` at `/var/lib/grafana`. See the [setup tutorial](Grafana_Windows_Portfolio_Tutorial.md) to create it.

The two additional container names below are reserved for disposable exercises. Confirm they are not being used for other work before creating or removing them. The test containers do not mount the original application's named volume. Do not remove `grafana-portfolio` or its volume as part of these procedures.

This is a tested lab procedure, not an approved production operating procedure. Production recovery requires the service owner's configuration, data protection, and change controls.

## Quick diagnosis

Start with these read-only checks:

```powershell
docker ps -a --filter "name=grafana-portfolio"
docker port grafana-portfolio
docker logs --tail 40 grafana-portfolio
Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health"
```

| Evidence | Interpretation | Follow-up |
| --- | --- | --- |
| `Exited` and health request cannot connect | The application container is stopped. The exit code and logs help explain why. | Follow case 1 if it was deliberately stopped. Investigate error logs if it exited unexpectedly. |
| Docker reports `port is already allocated` | The requested host address and port are unavailable. | Follow case 2. |
| `Exited (1)` and logs identify an invalid setting | The application failed during startup. | Follow case 3 for the tested invalid-port setting. |
| Container is `Up` but health request fails | Container execution alone does not establish application readiness. | Allow startup time, then check recent logs and published port. If failure persists, retain the evidence and investigate further. |

A successful baseline health response in this lab was:

```text
database version commit
-------- ------- ------
ok       13.3.0  6f8ce3c693b493043ebcd4787566d2b6b118b0f0
```

The response confirms that the endpoint is reachable and Grafana reports its database as healthy. It does not validate every dashboard, plugin, or external data source.

## Case 1: Stopped container

### Symptom and evidence

A health request returned:

```text
Invoke-RestMethod : Unable to connect to the remote server
```

The container listing showed `Exited (0)` after the deliberate stop. In this test, exit code 0 was consistent with the requested shutdown. It is not a universal explanation for every stopped container.

### Reproduce in the lab

This step interrupts the local Grafana instance until recovery:

```powershell
docker stop grafana-portfolio
docker ps -a --filter "name=grafana-portfolio"
Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health"
```

Expected result: the container is exited and the health request fails to connect.

### Recover and verify

```powershell
docker start grafana-portfolio
docker ps -a --filter "name=grafana-portfolio"
```

Confirm the listing shows `Up` and the mapping `127.0.0.1:3000->3000/tcp`. Allow Grafana a few seconds to initialize, then run:

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health"
```

Success criterion: the request returns Grafana's version and database `ok`. If it does not, inspect the logs rather than repeatedly assuming the application has started:

```powershell
docker logs --tail 40 grafana-portfolio
```

During the successful recovery, the logs included these messages, shown here without timestamps and additional fields:

```text
msg="All modules healthy"
msg="HTTP Server Listen" address=[::]:3000 protocol=http
```

These indicate module health and a listening web server at the time logged. Use the current health request to confirm access through Windows. The server's internal listening address is distinct from Docker's host port mapping.

The captured logs also contained plugin `process exited` messages during updates, followed by successful installation and registration. Interpret such lines in context before treating them as an application crash.

## Case 2: Host port already allocated

### Starting condition

Keep `grafana-portfolio` running on host port 3000. Confirm its mapping:

```powershell
docker port grafana-portfolio
```

Observed output:

```text
3000/tcp -> 127.0.0.1:3000
```

### Reproduce in a disposable container

```powershell
docker run -d --name grafana-port-test -p 127.0.0.1:3000:3000 grafana/grafana
```

Docker printed a container ID followed by a networking error containing:

```text
Bind for 127.0.0.1:3000 failed: port is already allocated
```

A printed container ID alone does not prove successful startup. Here, Docker created a container but could not establish the requested host port mapping.

### Recover and verify

Remove the failed test container and create a replacement using host port 3001:

```powershell
docker rm grafana-port-test
docker run -d --name grafana-port-test -p 127.0.0.1:3001:3000 grafana/grafana
```

The mapping format is `HOST_ADDRESS:HOST_PORT:CONTAINER_PORT`. The application still listens on port 3000 inside its container; Windows accesses this second instance on port 3001. Binding to `127.0.0.1` limits the published endpoint to the local host in this setup.

Allow startup time, then run:

```powershell
docker port grafana-port-test
Invoke-RestMethod -Uri "http://127.0.0.1:3001/api/health"
```

Success criteria:

- The port command returns `3000/tcp -> 127.0.0.1:3001`.
- The health request returns database `ok`.

### Clean up and confirm the original application

```powershell
docker stop grafana-port-test
docker rm grafana-port-test
Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health"
```

Expected result: both cleanup commands return the test container name, and the original application's health endpoint reports database `ok`.

## Case 3: Invalid application configuration

### Reproduce in a disposable container

Supply an invalid value for Grafana's HTTP port:

```powershell
docker run -d --name grafana-startup-test -e GF_SERVER_HTTP_PORT=invalid grafana/grafana
```

After startup has been attempted, inspect its state and logs:

```powershell
docker ps -a --filter "name=grafana-startup-test"
docker logs --tail 30 grafana-startup-test
```

### Diagnose

The container showed `Exited (1)`. The log identified the failure:

```text
msg="Invalid root_url." url=http://localhost:invalid/
error="server.root_url: parse \"http://localhost:invalid/\": invalid port \":invalid\" after host"
```

The environment variable supplied an invalid HTTP port, which appeared in the derived root URL. The log establishes the cause for this test. An exit code of 1 by itself would not identify that setting.

### Recover and verify

Recreate the disposable container with a valid internal port and an available host port:

```powershell
docker rm grafana-startup-test
docker run -d --name grafana-startup-test -e GF_SERVER_HTTP_PORT=3000 -p 127.0.0.1:3001:3000 grafana/grafana
```

Allow startup time, then run:

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:3001/api/health"
```

Success criterion: database `ok` is returned. The corrected test container uses disposable application data; this procedure does not demonstrate preserving data while replacing a production container.

### Clean up and confirm the original application

```powershell
docker stop grafana-startup-test
docker rm grafana-startup-test
Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/health"
```

Expected result: the temporary container is stopped and removed, and the original Grafana instance reports database `ok`.

## If recovery fails

Stop at the failing verification step. Record the command, error, container state, port mapping, and relevant recent log entries. Do not delete the original application container or storage to work around an unexplained failure. For this personal lab, review the evidence before choosing another change. In a managed environment, pass it to the service owner under the applicable support process.

## Validation record

The author performed these checks on October 27, 2026, during a guided session and supplied the command output used in this runbook.

| Scenario | Observed failure | Recovery verified | Cleanup verified |
| --- | --- | --- | --- |
| Stopped original container | `Exited (0)` and failed health request | Start followed by database `ok` on port 3000 | Original left running |
| Duplicate host port | Networking error stating port already allocated | Mapping changed to 3001; database `ok` | Test stopped and removed; original database `ok` |
| Invalid HTTP port | `Exited (1)` and invalid root URL log | Valid setting; database `ok` on port 3001 | Test stopped and removed; original database `ok` |

The commands used the locally available `grafana/grafana` image, whose application reported version 13.3.0. The untagged image name selects `latest` and can produce different behavior on another machine or after an image update. This record covers one Windows environment; it does not establish production readiness, recovery from data loss, or compatibility with every release.

## References

- [Docker container logs](https://docs.docker.com/reference/cli/docker/container/logs/)
- [Docker port publishing and mapping](https://docs.docker.com/engine/network/port-publishing/)
- [Grafana configuration](https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/)

The procedures and observations above reflect the tested session. Reference documentation may change independently.
