[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
  param([string]$Message)
  $failures.Add($Message)
}

function Get-AttributeValue {
  param(
    [string]$Tag,
    [string]$Name
  )

  $pattern = '(?is)\b' + [regex]::Escape($Name) + '\s*=\s*(["''])(.*?)\1'
  $match = [regex]::Match($Tag, $pattern)
  if ($match.Success) { return $match.Groups[2].Value }
  return $null
}

function Resolve-LocalReference {
  param(
    [System.IO.FileInfo]$SourceFile,
    [string]$Reference
  )

  if ([string]::IsNullOrWhiteSpace($Reference) -or $Reference -eq '#') { return $null }
  if ($Reference -match '^(?i:https?:|mailto:|tel:|data:|about:|javascript:)') { return $null }

  $pathOnly = ($Reference -split '[?#]', 2)[0]
  if ([string]::IsNullOrWhiteSpace($pathOnly)) { return $SourceFile.FullName }
  $decoded = [System.Uri]::UnescapeDataString($pathOnly) -replace '/', [System.IO.Path]::DirectorySeparatorChar
  return [System.IO.Path]::GetFullPath((Join-Path $SourceFile.DirectoryName $decoded))
}

$textFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -File | Where-Object {
  $_.Extension -in @('.html', '.css', '.js', '.json', '.md', '.ps1') -and $_.FullName -notmatch '[\\/](?:node_modules|\.git)[\\/]'
}

foreach ($file in $textFiles) {
  $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
  if ($content -match '(?m)^(<<<<<<<|=======|>>>>>>>)') {
    Add-Failure "Merge-conflict marker found in $($file.FullName.Substring($projectRoot.Length + 1))."
  }
}

$htmlFiles = Get-ChildItem -LiteralPath $projectRoot -Recurse -Filter '*.html' -File
foreach ($file in $htmlFiles) {
  $relative = $file.FullName.Substring($projectRoot.Length + 1)
  $html = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8

  $ids = [regex]::Matches($html, '(?is)\bid\s*=\s*(["''])(.*?)\1') | ForEach-Object { $_.Groups[2].Value }
  $duplicates = $ids | Group-Object | Where-Object Count -gt 1
  foreach ($duplicate in $duplicates) {
    Add-Failure "Duplicate id '$($duplicate.Name)' found in $relative."
  }

  if ($html -notmatch '(?is)<html\b[^>]*\blang\s*=') { Add-Failure "Missing html lang attribute in $relative." }
  if ($html -notmatch '(?is)<meta\b[^>]*\bname\s*=\s*(["''])viewport\1') { Add-Failure "Missing viewport meta tag in $relative." }
  if ($html -notmatch '(?is)<title>\s*[^<]+\s*</title>') { Add-Failure "Missing descriptive title in $relative." }
  if ($html -match '(?is)tabindex\s*=\s*(["''])\+?[1-9]\d*\1') { Add-Failure "Positive tabindex found in $relative." }
  if ($html -match '(?is)href\s*=\s*(["''])#\1') { Add-Failure "Empty hash link found in $relative." }
  if ($html -match '(?is)<button\b[^>]*>(?:(?!</button>)[\s\S])*?<h[1-6]\b') { Add-Failure "Heading nested inside a button in $relative." }

  foreach ($imageMatch in [regex]::Matches($html, '(?is)<img\b[^>]*>')) {
    $tag = $imageMatch.Value
    $src = Get-AttributeValue -Tag $tag -Name 'src'
    if ($null -eq (Get-AttributeValue -Tag $tag -Name 'alt')) { Add-Failure "Image missing alt text in ${relative}: $tag" }
    if (-not [string]::IsNullOrWhiteSpace($src)) {
      if ($null -eq (Get-AttributeValue -Tag $tag -Name 'width') -or $null -eq (Get-AttributeValue -Tag $tag -Name 'height')) {
        Add-Failure "Static image missing width or height in ${relative}: $src"
      }
    }
  }

  foreach ($iframeMatch in [regex]::Matches($html, '(?is)<iframe\b[^>]*>')) {
    if ([string]::IsNullOrWhiteSpace((Get-AttributeValue -Tag $iframeMatch.Value -Name 'title'))) {
      Add-Failure "Iframe missing title in $relative."
    }
  }

  foreach ($anchorMatch in [regex]::Matches($html, '(?is)<a\b[^>]*>')) {
    $tag = $anchorMatch.Value
    if ((Get-AttributeValue -Tag $tag -Name 'target') -eq '_blank') {
      $rel = Get-AttributeValue -Tag $tag -Name 'rel'
      if ($rel -notmatch '(?i)(^|\s)noopener(\s|$)' -or $rel -notmatch '(?i)(^|\s)noreferrer(\s|$)') {
        Add-Failure "target=_blank link missing noopener noreferrer in ${relative}: $tag"
      }
    }
  }

  foreach ($attributeMatch in [regex]::Matches($html, '(?is)\b(?:src|href)\s*=\s*(["''])(.*?)\1')) {
    $reference = $attributeMatch.Groups[2].Value
    $resolved = Resolve-LocalReference -SourceFile $file -Reference $reference
    if ($resolved -and -not (Test-Path -LiteralPath $resolved)) {
      Add-Failure "Broken local reference '$reference' in $relative."
    }

    if ($reference.StartsWith('#')) {
      $fragment = $reference.Substring(1)
      if ($fragment -and $ids -notcontains $fragment) { Add-Failure "Broken fragment '$reference' in $relative." }
    }
  }
}

$cssFile = Get-Item -LiteralPath (Join-Path $projectRoot 'css\style.css')
$css = Get-Content -LiteralPath $cssFile.FullName -Raw -Encoding UTF8
$cssWithoutComments = [regex]::Replace($css, '(?s)/\*.*?\*/', '')
if (($cssWithoutComments.ToCharArray() | Where-Object { $_ -eq '{' }).Count -ne ($cssWithoutComments.ToCharArray() | Where-Object { $_ -eq '}' }).Count) {
  Add-Failure 'CSS opening and closing brace counts do not match.'
}
if ($css -match '(?i)academy') { Add-Failure 'Confirmed dead academy CSS remains.' }
foreach ($urlMatch in [regex]::Matches($css, '(?is)url\(\s*(["'']?)(.*?)\1\s*\)')) {
  $resolved = Resolve-LocalReference -SourceFile $cssFile -Reference $urlMatch.Groups[2].Value
  if ($resolved -and -not (Test-Path -LiteralPath $resolved)) {
    Add-Failure "Broken CSS asset reference '$($urlMatch.Groups[2].Value)'."
  }
}

$scriptFile = Get-Item -LiteralPath (Join-Path $projectRoot 'js\main.js')
$script = Get-Content -LiteralPath $scriptFile.FullName -Raw -Encoding UTF8
$caseImagePaths = [regex]::Matches($script, "(?m)src:\s*'([^']+\.(?:png|jpe?g|webp))'") | ForEach-Object {
  [System.Uri]::UnescapeDataString($_.Groups[1].Value) -replace '/', '\'
}
foreach ($path in $caseImagePaths) {
  if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $path))) { Add-Failure "Missing case-study image '$path'." }
}

$expectedCaseCounts = @{
  'images\Akwaaba House' = 7
  'images\GoldBar Fitness' = 12
  'images\wealthwise' = 6
}
foreach ($entry in $expectedCaseCounts.GetEnumerator()) {
  $actualFiles = (Get-ChildItem -LiteralPath (Join-Path $projectRoot $entry.Key) -File -Filter '*.png').Count
  $referencedFiles = ($caseImagePaths | Where-Object { $_.StartsWith($entry.Key, [System.StringComparison]::OrdinalIgnoreCase) }).Count
  if ($actualFiles -ne $entry.Value -or $referencedFiles -ne $actualFiles) {
    Add-Failure "Case-study image count mismatch for $($entry.Key): files=$actualFiles, referenced=$referencedFiles, expected=$($entry.Value)."
  }
}

$requiredNavLinks = @('#work', '#workspace', '#experience', '#contact', 'pages/cv.html', '#socials')
$indexHtml = Get-Content -LiteralPath (Join-Path $projectRoot 'index.html') -Raw -Encoding UTF8
foreach ($href in $requiredNavLinks) {
  $pattern = '(?is)<a\b[^>]*href\s*=\s*(["''])' + [regex]::Escape($href) + '\1'
  if ($indexHtml -notmatch $pattern) {
    Add-Failure "Required navigation link '$href' is missing."
  }
}

$expectedLiveUrls = @(
  'https://akwaabahouse.netlify.app/',
  'https://goldbarfitness.netlify.app/',
  'https://wealthwiselt.netlify.app/'
)
foreach ($url in $expectedLiveUrls) {
  if ($script -notmatch [regex]::Escape($url) -or $indexHtml -notmatch [regex]::Escape($url)) {
    Add-Failure "Live-project URL '$url' is not present in both data and markup."
  }
}

$psdPath = Join-Path $projectRoot 'images\Tablet.psd'
if (Test-Path -LiteralPath $psdPath) {
  $stream = [System.IO.File]::OpenRead($psdPath)
  try {
    $signatureBytes = New-Object byte[] 4
    [void]$stream.Read($signatureBytes, 0, 4)
    $signature = [System.Text.Encoding]::ASCII.GetString($signatureBytes)
    if ($signature -ne '8BPS') { Add-Failure 'Tablet.psd does not have a valid Photoshop signature.' }
  } finally {
    $stream.Dispose()
  }
}

if ($failures.Count -gt 0) {
  Write-Host "Validation failed with $($failures.Count) issue(s):" -ForegroundColor Red
  $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
  exit 1
}

Write-Host "Static validation passed: $($htmlFiles.Count) HTML files, local links/assets, IDs, image metadata, CSS structure, case-study counts, external-link safety, and PSD signature." -ForegroundColor Green
