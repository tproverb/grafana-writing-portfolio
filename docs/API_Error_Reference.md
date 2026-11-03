# Grafana Dashboard API: error reference

Tim Suleyman | Technical writing portfolio

Use this page when a request to the Grafana Dashboard API fails. Each section names the status code, what Grafana is telling you, and what to change before you send the request again.

The endpoints are described in the [OpenAPI specification](../api/grafana-dashboards.openapi.yaml). The observed responses from the local lab are in the [test record](API_Test_Record.md).

## Before you start

- Grafana runs at `http://127.0.0.1:3000`. See the [setup tutorial](../Grafana_Windows_Portfolio_Tutorial.md).
- You have a service account token. In Grafana, open **Administration > Users and access > Service accounts**, create a service account with the **Editor** role, and add a token.
- Requests send the token in the `Authorization: Bearer <token>` header.
- Dashboards are created in a folder where the service account has **Edit** permission. See [403 on a dashboard you created](#403-on-a-dashboard-you-created).

## Find the cause quickly

| Status | Name | Meaning | First thing to check |
| --- | --- | --- | --- |
| 400 | Bad Request | Grafana could not process the request body. | JSON syntax and required fields. |
| 401 | Unauthorized | Grafana could not identify the caller. | Whether the token is present and correct. |
| 403 | Forbidden | Grafana identified the caller, but the caller lacks permission. | The role of the service account. |
| 404 | Not Found | The dashboard does not exist in this namespace. | The `metadata.name` value in the path. |
| 409 | Conflict | A dashboard with this name already exists. | Whether you meant to update instead of create. |

## 400 Bad Request

Grafana received the request but could not process its body. Typical causes are malformed JSON, a missing `metadata` or `spec` object, or a `spec` without a `title`.

Sending the same request again returns the same error. Validate the body first:

```powershell
$body | ConvertFrom-Json
```

If the command fails, fix the JSON syntax. If it succeeds, compare the fields with the `DashboardInput` schema in the specification.

## 401 Unauthorized

Grafana could not identify the caller. The request has no `Authorization` header, the token was mistyped, or the token was revoked or expired.

A 401 is about identity. Changing the role of the service account does not fix it. Check that the header is present and that the token still appears under the service account in Grafana. If it does not, create a new token.

## 403 Forbidden

Grafana identified the caller, but the service account does not have permission for the action. For example, a service account with the Viewer role can read dashboards but cannot delete them.

A 403 is about permission. A new token for the same service account returns the same error. Change the role of the service account, or use a service account that has the required role.

### 403 on a dashboard you created

In the lab (Grafana 13.3.0), a service account with the Editor role created a dashboard at the root level and received 201. Reading and deleting that same dashboard with the same token then returned 403. The legacy endpoint gave the reason:

```json
{"message":"You'll need additional permissions to perform this action. Permissions needed: dashboards:read","title":"Access denied"}
```

The new `dashboard.grafana.app/v1` API returned 403 with the status `Failure` and no explanation, so check the legacy endpoint when you need the missing permission name:

```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:3000/api/dashboards/uid/<name>" -Headers @{ Authorization = "Bearer $token" }
```

To fix it, create dashboards in a folder and grant the service account permission on that folder:

1. Go to **Dashboards > New > New folder** and create the folder.
2. Open **Folder actions > Manage permissions > Add a permission**.
3. Grant the Editor service account **Edit**. Grant a Viewer service account **View** if it needs to read the dashboards.
4. Copy the folder UID from the URL (the part after `/dashboards/f/`) and set it in the request:

```json
{ "metadata": { "name": "portfolio-lab", "annotations": { "grafana.app/folder": "<folder UID>" } }, "spec": { "title": "Portfolio Lab" } }
```

With the folder in place, the same token could read and delete the dashboard, and a Viewer token received 403 only for the delete.

## 404 Not Found

No dashboard with the requested name exists in the namespace. Check two things:

- The path uses `metadata.name`, not `metadata.uid`. The two values are different.
- The namespace is correct. The local lab uses `default`.

A 404 after a delete request is expected. It confirms that the dashboard is gone.

## 409 Conflict

A dashboard with the same `metadata.name` already exists. Choose a different name, or send `metadata.generateName` with a prefix so that Grafana creates a unique name.

## Verify the documented behavior

Run the verification script from the repository root. It creates and deletes one dashboard named `portfolio-api-check` and does not change other dashboards.

```powershell
.\scripts\Test-GrafanaDashboardApi.ps1 -EditorToken $env:GRAFANA_EDITOR_TOKEN -ViewerToken $env:GRAFANA_VIEWER_TOKEN -FolderUid <folder UID>
```

`-FolderUid` is the folder with permissions for both service accounts. The `-ViewerToken` parameter is optional and is needed only for the 403 case. The script writes the results to [API_Test_Record.md](API_Test_Record.md) and exits with code 1 if any observed status differs from the documented one.
