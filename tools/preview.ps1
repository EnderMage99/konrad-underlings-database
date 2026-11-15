# Serves the site from this repo on http://localhost and opens the star chart
# in the default browser. Nothing to install: it uses Windows PowerShell's own
# HttpListener. Close the window (or press Ctrl+C) to stop it.
#
#   tools\preview.cmd                      Guerra, sandbox (the default)
#   tools\preview.cmd "starmap.html"       any page or query you like
param([string]$Page = "starmap.html?sys=guerra&sandbox", [switch]$NoOpen)

$root = Split-Path -Parent $PSScriptRoot
$types = @{
  ".html" = "text/html; charset=utf-8"; ".js" = "text/javascript"; ".css" = "text/css"; ".json" = "application/json"
  ".png" = "image/png"; ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"; ".webp" = "image/webp"; ".gif" = "image/gif"
  ".svg" = "image/svg+xml"; ".ico" = "image/x-icon"; ".mp3" = "audio/mpeg"; ".woff2" = "font/woff2"
}

# first free port from 8765 up
$listener = $null
foreach ($port in 8765..8785) {
  $l = New-Object System.Net.HttpListener
  $l.Prefixes.Add("http://localhost:$port/")
  try { $l.Start(); $listener = $l; break } catch { $l.Close() }
}
if (-not $listener) { Write-Host "No free port between 8765 and 8785."; exit 1 }

$url = "http://localhost:$port/$Page"
Write-Host ""
Write-Host "  Serving $root"
Write-Host "  Open:   $url"
Write-Host ""
Write-Host "  Other pages:"
Write-Host "    http://localhost:$port/starmap.html?sys=guerra&sandbox   Guerra, test orders"
Write-Host "    http://localhost:$port/starmap.html?sandbox              Invideis, test orders"
Write-Host "    http://localhost:$port/starmap.html?sys=guerra           Guerra, live (read only)"
Write-Host ""
Write-Host "  Close this window or press Ctrl+C to stop."
if (-not $NoOpen) { Start-Process $url }

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $res = $ctx.Response
    try {
      $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
      if ($rel -eq "") { $rel = "index.html" }
      $file = [IO.Path]::GetFullPath((Join-Path $root $rel))
      # only files inside the repo
      if ($file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path $file -PathType Leaf)) {
        $ext = [IO.Path]::GetExtension($file).ToLower()
        if ($types.ContainsKey($ext)) { $res.ContentType = $types[$ext] }
        $res.Headers.Add("Cache-Control", "no-store")
        $bytes = [IO.File]::ReadAllBytes($file)
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
      } else { $res.StatusCode = 404 }
    } catch { try { $res.StatusCode = 500 } catch {} }
    finally { $res.Close() }
  }
} finally { $listener.Stop() }
