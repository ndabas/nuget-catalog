[CmdletBinding()]
param (
  [switch]
  $SkipVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$baseUrl = 'https://api.nuget.org/v3'
$baseUrlRegex = [regex]::Escape($baseUrl)

$catalogUrl = (Invoke-WebRequest "$baseUrl/index.json").Content |
ConvertFrom-Json |
Select-Object -ExpandProperty resources |
Where-Object { $_.'@type' -eq 'Catalog/3.0.0' } |
Select-Object -ExpandProperty '@id'

function GetUrl {
  param ( $url, $force )

  $localPath = $url -replace $baseUrlRegex, '.'
  $localPath = $localPath -replace 'data/(\d+\.\d+\.\d+)', 'data/$1/$1'
  $localPath = $localPath -replace '/', [io.path]::DirectorySeparatorChar
  New-Item -ItemType Directory -Force -Path (Split-Path $localPath) | Out-Null

  if ($force -or (-not (Test-Path $localPath))) {
    Write-Information "Downloading $url"
    try {
      Invoke-WebRequest $url -OutFile $localPath
    }
    catch {
      if (Test-Path $localPath) {
        Remove-Item $localPath
      }
      throw
    }
  }

  if (Test-Path $localPath) {
    Get-Content $localPath | ConvertFrom-Json -AsHashtable
  }
  else {
    Write-Error "Failed to download $url"
  }
}

$cursor = [datetime]'2000-01-01T00:00:00.0000000Z'
if (Test-Path 'cursor.txt') {
  $cursor = [datetime](Get-Content 'cursor.txt')
}

$catalog = GetUrl $catalogUrl $true
$pages = $catalog.items | Sort-Object commitTimeStamp

if ($SkipVerification) {
  $pages = $pages | Where-Object { [datetime]$_.commitTimeStamp -gt $cursor }
}

$pages | ForEach-Object {
  Write-Information ('Processing page: {0}' -f $_.'@id')
  $page = GetUrl $_.'@id' ([datetime]$_.commitTimeStamp -gt $cursor)

  $page.items | Where-Object { $_.'@type' -ne 'nuget:PackageDelete' } | Sort-Object commitTimeStamp | ForEach-Object {
    $package = GetUrl $_.'@id' ([datetime]$_.commitTimeStamp -gt $cursor)
    Write-Verbose ('{0}@{1}' -f $package.id, $package.version)

    if ([datetime]$_.commitTimeStamp -gt $cursor) {
      $cursor = [datetime]$_.commitTimeStamp
    }
  }

  $cursor.ToUniversalTime().ToString('o') | Set-Content 'cursor.txt'
}
