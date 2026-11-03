<#
.SYNOPSIS
  Runs the documented Grafana Dashboard API cases against the local lab and writes a test record.

.DESCRIPTION
  Sends one request per documented case, compares the returned HTTP status with the
  expected status, and writes docs/API_Test_Record.md with the observed status and the
  error message Grafana returned. Works in Windows PowerShell 5.1 and PowerShell 7.

  The script creates and deletes one dashboard named "portfolio-api-check".
  It does not touch other dashboards.

.PARAMETER EditorToken
  Service account token with the Editor or Admin role.

.PARAMETER ViewerToken
  Optional service account token with the Viewer role. Needed only for the 403 case.

.PARAMETER FolderUid
  UID of the folder where the test dashboard is created. Give the Editor service account
  Edit permission and the Viewer service account View permission on this folder.
  Without a folder, Grafana 13.3.0 in the lab returned 403 (dashboards:read) when the
  Editor service account read a dashboard it had created at the root.

.EXAMPLE
  .\scripts\Test-GrafanaDashboardApi.ps1 -EditorToken $env:GRAFANA_EDITOR_TOKEN -ViewerToken $env:GRAFANA_VIEWER_TOKEN
#>
param(
  [Parameter(Mandatory = $true)][string]$EditorToken,
  [string]$ViewerToken,
  [string]$FolderUid,
  [string]$BaseUrl = "http://127.0.0.1:3000",
  [string]$Namespace = "default"
)

$ErrorActionPreference = "Stop"
$name = "portfolio-api-check"
$collection = "$BaseUrl/apis/dashboard.grafana.app/v1/namespaces/$Namespace/dashboards"
$item = "$collection/$name"

function Send-Request {
  param([string]$Method, [string]$Uri, [string]$Token, [string]$Body)
  $headers = @{ Accept = "application/json" }
  if ($Token) { $headers["Authorization"] = "Bearer $Token" }
  $params = @{ Method = $Method; Uri = $Uri; Headers = $headers; UseBasicParsing = $true }
  if ($Body) { $params["Body"] = $Body; $params["ContentType"] = "application/json" }
  try {
    $r = Invoke-WebRequest @params
    return @{ Status = [int]$r.StatusCode; Content = $r.Content }
  } catch {
    $resp = $_.Exception.Response
    if ($null -eq $resp) { throw }
    $content = $_.ErrorDetails.Message
    return @{ Status = [int]$resp.StatusCode; Content = $content }
  }
}

function Get-Message([string]$Content) {
  if (-not $Content) { return "" }
  try { $j = $Content | ConvertFrom-Json } catch { return ($Content -replace "\s+", " ").Substring(0, [Math]::Min(120, $Content.Length)) }
  if ($j.message) { return $j.message }
  if ($j.reason) { return "$($j.status): $($j.reason)" }
  if ($j.status) { return $j.status }
  if ($j.database) { return "database=$($j.database), version=$($j.version)" }
  return ""
}

$metadata = @{ name = $name }
if ($FolderUid) { $metadata["annotations"] = @{ "grafana.app/folder" = $FolderUid } }
$valid = @{ metadata = $metadata; spec = @{ title = "Portfolio API check"; schemaVersion = 41 } } | ConvertTo-Json -Depth 5

$cases = @(
  @{ Id = 1;  Case = "Health check without a token";           Method = "GET";    Uri = "$BaseUrl/api/health"; Token = $null;          Body = $null;        Expect = 200 },
  @{ Id = 2;  Case = "List dashboards without a token";        Method = "GET";    Uri = $collection;           Token = $null;          Body = $null;        Expect = 401 },
  @{ Id = 3;  Case = "List dashboards with a mistyped token";  Method = "GET";    Uri = $collection;           Token = "glsa_invalid"; Body = $null;        Expect = 401 },
  @{ Id = 4;  Case = "Create with malformed JSON";             Method = "POST";   Uri = $collection;           Token = $EditorToken;   Body = '{"metadata":'; Expect = 400 },
  @{ Id = 5;  Case = "Create a dashboard";                     Method = "POST";   Uri = $collection;           Token = $EditorToken;   Body = $valid;       Expect = 201 },
  @{ Id = 6;  Case = "Create the same name again";             Method = "POST";   Uri = $collection;           Token = $EditorToken;   Body = $valid;       Expect = 409 },
  @{ Id = 7;  Case = "Get the dashboard";                      Method = "GET";    Uri = $item;                 Token = $EditorToken;   Body = $null;        Expect = 200 },
  @{ Id = 8;  Case = "Get a dashboard that does not exist";    Method = "GET";    Uri = "$collection/no-such-dashboard"; Token = $EditorToken; Body = $null; Expect = 404 }
)
if ($ViewerToken) {
  $cases += @{ Id = 9; Case = "Delete with a Viewer token"; Method = "DELETE"; Uri = $item; Token = $ViewerToken; Body = $null; Expect = 403 }
}
$cases += @(
  @{ Id = 10; Case = "Delete the dashboard";                   Method = "DELETE"; Uri = $item;                 Token = $EditorToken;   Body = $null;        Expect = 200 },
  @{ Id = 11; Case = "Get the dashboard after deletion";       Method = "GET";    Uri = $item;                 Token = $EditorToken;   Body = $null;        Expect = 404 }
)

$results = foreach ($c in $cases) {
  $r = Send-Request -Method $c.Method -Uri $c.Uri -Token $c.Token -Body $c.Body
  [pscustomobject]@{
    Id       = $c.Id
    Case     = $c.Case
    Request  = "$($c.Method) $($c.Uri.Replace($BaseUrl, ''))"
    Expected = $c.Expect
    Observed = $r.Status
    Result   = $(if ($r.Status -eq $c.Expect) { "Pass" } else { "Fail" })
    Message  = (Get-Message $r.Content) -replace "\|", "/"
  }
}

$results | Format-Table Id, Case, Expected, Observed, Result -AutoSize

$version = (Send-Request -Method GET -Uri "$BaseUrl/api/health").Content | ConvertFrom-Json
$folderNote = ""
if ($FolderUid) { $folderNote = ", folder ``$FolderUid``" }
$lines = @(
  "# Grafana Dashboard API test record",
  "",
  "Run on $(Get-Date -Format 'MMMM d, yyyy') against Grafana $($version.version) at ``$BaseUrl``, namespace ``$Namespace``$folderNote.",
  "Generated by [Test-GrafanaDashboardApi.ps1](../scripts/Test-GrafanaDashboardApi.ps1). Tokens are not recorded.",
  "",
  "| # | Case | Request | Expected | Observed | Result | Message returned |",
  "| --- | --- | --- | --- | --- | --- | --- |"
)
foreach ($r in $results) {
  $lines += "| $($r.Id) | $($r.Case) | ``$($r.Request)`` | $($r.Expected) | $($r.Observed) | $($r.Result) | $($r.Message) |"
}
$out = Join-Path $PSScriptRoot "..\docs\API_Test_Record.md"
$lines -join "`n" | Set-Content -Path $out -Encoding utf8
Write-Host "Test record written to $out"

if ($results.Result -contains "Fail") { exit 1 }
