[CmdletBinding()]
param(
  [string]$BrowserPath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$indexPath = Join-Path $projectRoot 'index.html'
$reportRoot = Join-Path $projectRoot 'reports'
$failures = [System.Collections.Generic.List[string]]::new()
$auditSummary = [System.Collections.Generic.List[string]]::new()
$script:messageId = 0
$script:socket = $null
$script:events = [System.Collections.Generic.List[object]]::new()

function Add-Failure {
  param([string]$Message)
  $failures.Add($Message)
}

function Assert-Audit {
  param(
    [bool]$Condition,
    [string]$Message
  )
  if (-not $Condition) { Add-Failure $Message }
}

function Receive-CdpMessage {
  $buffer = New-Object byte[] 65536
  $builder = [System.Text.StringBuilder]::new()
  do {
    $segment = [ArraySegment[byte]]::new($buffer)
    $readTimeout = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(30))
    try {
      $received = $script:socket.ReceiveAsync($segment, $readTimeout.Token).GetAwaiter().GetResult()
    } catch [System.OperationCanceledException] {
      throw 'Timed out waiting for a browser debugging response.'
    } finally {
      $readTimeout.Dispose()
    }
    if ($received.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
      throw 'The browser debugging connection closed unexpectedly.'
    }
    [void]$builder.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $received.Count))
  } while (-not $received.EndOfMessage)
  return ($builder.ToString() | ConvertFrom-Json)
}

function Invoke-Cdp {
  param(
    [string]$Method,
    [hashtable]$Params = @{}
  )

  $script:messageId += 1
  $id = $script:messageId
  $payload = @{ id = $id; method = $Method; params = $Params } | ConvertTo-Json -Compress -Depth 20
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
  $segment = [ArraySegment[byte]]::new($bytes)
  [void]$script:socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

  while ($true) {
    $message = Receive-CdpMessage
    if ($message.id -eq $id) {
      if ($message.error) { throw "CDP $Method failed: $($message.error.message)" }
      return $message.result
    }
    if ($message.method) { $script:events.Add($message) }
  }
}

function Invoke-PageScript {
  param([string]$Expression)
  $response = Invoke-Cdp -Method 'Runtime.evaluate' -Params @{
    expression = $Expression
    awaitPromise = $true
    returnByValue = $true
    userGesture = $true
  }
  if ($response.exceptionDetails) {
    throw "Browser script failed: $($response.exceptionDetails.text)"
  }
  return $response.result.value
}

function Wait-DocumentReady {
  for ($attempt = 0; $attempt -lt 100; $attempt += 1) {
    try {
      if ((Invoke-PageScript -Expression 'document.readyState') -eq 'complete') { return }
    } catch {
      # A navigation can briefly replace the JavaScript execution context.
    }
    Start-Sleep -Milliseconds 100
  }
  throw 'Timed out waiting for the portfolio document to load.'
}

function Set-ViewportAndLoad {
  param(
    [int]$Width,
    [int]$Height,
    [string]$Url
  )
  [void](Invoke-Cdp -Method 'Emulation.setDeviceMetricsOverride' -Params @{
    width = $Width
    height = $Height
    deviceScaleFactor = 1
    mobile = $false
  })
  [void](Invoke-Cdp -Method 'Page.navigate' -Params @{ url = "${Url}?viewport=$Width" })
  Wait-DocumentReady
  Start-Sleep -Milliseconds 350
}

function Save-CurrentScreenshot {
  param([string]$Name)
  $capture = Invoke-Cdp -Method 'Page.captureScreenshot' -Params @{ format = 'png'; fromSurface = $true; captureBeyondViewport = $false }
  [System.IO.File]::WriteAllBytes((Join-Path $reportRoot "$Name.png"), [Convert]::FromBase64String($capture.data))
}

function Save-ViewportScreenshot {
  param([int]$Width)
  [void](Invoke-PageScript -Expression 'window.scrollTo(0, 0); true')
  Start-Sleep -Milliseconds 150
  Save-CurrentScreenshot -Name "viewport-$Width"
}

function Test-AccessibilityTree {
  param([string]$Context)
  $tree = Invoke-Cdp -Method 'Accessibility.getFullAXTree'
  $interactiveRoles = @('button', 'link', 'textbox')
  $unnamed = @($tree.nodes | Where-Object {
    -not $_.ignored -and $_.role.value -in $interactiveRoles -and [string]::IsNullOrWhiteSpace($_.name.value)
  })
  Assert-Audit ($unnamed.Count -eq 0) "$Context has $($unnamed.Count) unnamed interactive accessibility-tree node(s)."
  return @($tree.nodes | Where-Object { -not $_.ignored } | ForEach-Object { $_.role.value })
}

if (-not (Test-Path -LiteralPath $BrowserPath)) {
  throw "Microsoft Edge was not found at '$BrowserPath'."
}

New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
$profilePath = Join-Path ([System.IO.Path]::GetTempPath()) ("portfolio-edge-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $profilePath | Out-Null
$debugPort = Get-Random -Minimum 9300 -Maximum 9899
$browserProcess = $null
$browserStdoutPath = Join-Path $reportRoot 'browser-process.stdout.log'
$browserStderrPath = Join-Path $reportRoot 'browser-process.stderr.log'

try {
  $browserArguments = @(
    '--headless=new',
    "--remote-debugging-port=$debugPort",
    "--user-data-dir=$profilePath",
    '--no-first-run',
    '--disable-default-apps',
    '--disable-background-networking',
    '--allow-file-access-from-files',
    'about:blank'
  )
  $browserProcess = Start-Process -FilePath $BrowserPath -ArgumentList $browserArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $browserStdoutPath -RedirectStandardError $browserStderrPath

  $targets = $null
  for ($attempt = 0; $attempt -lt 80; $attempt += 1) {
    if ($browserProcess.HasExited) {
      $browserErrors = if (Test-Path -LiteralPath $browserStderrPath) { (Get-Content -LiteralPath $browserStderrPath -Tail 8) -join ' ' } else { 'No stderr output was captured.' }
      throw "The browser exited before its debugging endpoint was ready (exit code $($browserProcess.ExitCode)): $browserErrors"
    }
    try {
      $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json/list" -TimeoutSec 2
      if ($targets) { break }
    } catch {
      Start-Sleep -Milliseconds 100
    }
  }
  if (-not $targets) { throw 'Could not connect to the Edge debugging endpoint.' }

  $pageTarget = $targets | Where-Object type -eq 'page' | Select-Object -First 1
  $script:socket = [System.Net.WebSockets.ClientWebSocket]::new()
  [void]$script:socket.ConnectAsync([uri]$pageTarget.webSocketDebuggerUrl, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

  [void](Invoke-Cdp -Method 'Page.enable')
  [void](Invoke-Cdp -Method 'Runtime.enable')
  [void](Invoke-Cdp -Method 'Log.enable')
  [void](Invoke-Cdp -Method 'Accessibility.enable')
  [void](Invoke-Cdp -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{
    source = @'
window.__portfolioAuditErrors = [];
window.addEventListener('error', event => window.__portfolioAuditErrors.push(String(event.message || event.error)));
window.addEventListener('unhandledrejection', event => window.__portfolioAuditErrors.push(String(event.reason)));
'@
  })

  $pageUrl = ([uri]$indexPath).AbsoluteUri
  $viewports = @(
    @{ Width = 320; Height = 700 },
    @{ Width = 375; Height = 812 },
    @{ Width = 430; Height = 850 },
    @{ Width = 768; Height = 900 },
    @{ Width = 1024; Height = 900 },
    @{ Width = 1280; Height = 900 },
    @{ Width = 1440; Height = 900 },
    @{ Width = 1920; Height = 1080 }
  )

  foreach ($viewport in $viewports) {
    $width = [int]$viewport.Width
    $height = [int]$viewport.Height
    Write-Host "Checking $width px viewport..."
    Set-ViewportAndLoad -Width $width -Height $height -Url $pageUrl

    $layout = Invoke-PageScript -Expression @'
(() => {
  const root = document.documentElement;
  const overflowers = [...document.querySelectorAll('body *')].filter(element => {
    const rect = element.getBoundingClientRect();
    return rect.right > innerWidth + 1 || rect.left < -1;
  }).slice(0, 8).map(element => element.id || element.className || element.tagName);
  const stage = document.querySelector('.workspace-stage');
  const mobileLinks = document.querySelector('.mobile-project-links');
  const footer = document.querySelector('.footer-bar').getBoundingClientRect();
  return {
    scrollWidth: root.scrollWidth,
    clientWidth: root.clientWidth,
    overflowers,
    stageDisplay: getComputedStyle(stage).display,
    mobileLinksDisplay: getComputedStyle(mobileLinks).display,
    footerLeft: footer.left,
    footerRight: footer.right,
    errors: window.__portfolioAuditErrors || []
  };
})()
'@

    Assert-Audit ($layout.scrollWidth -le ($layout.clientWidth + 1)) "$width px viewport has horizontal overflow ($($layout.scrollWidth) > $($layout.clientWidth)); candidates: $($layout.overflowers -join ', ')."
    Assert-Audit ($layout.footerLeft -ge -1 -and $layout.footerRight -le ($width + 1)) "$width px footer extends beyond the viewport."
    Assert-Audit (@($layout.errors).Count -eq 0) "$width px viewport reported JavaScript errors: $(@($layout.errors) -join '; ')."

    if ($width -le 820) {
      Assert-Audit ($layout.stageDisplay -eq 'none') "$width px viewport still displays the iframe device."
      Assert-Audit ($layout.mobileLinksDisplay -ne 'none') "$width px viewport does not display direct live-project links."
    } else {
      Assert-Audit ($layout.stageDisplay -ne 'none') "$width px viewport hides the desktop laptop presentation."
      Assert-Audit ($layout.mobileLinksDisplay -eq 'none') "$width px viewport displays mobile live-project links."
    }

    Save-ViewportScreenshot -Width $width

    if ($width -in @(320, 768, 1440)) {
      foreach ($section in @(
        @{ Name = 'projects'; Selector = '#work' },
        @{ Name = 'workspace'; Selector = '#workspace' },
        @{ Name = 'footer'; Selector = 'footer' }
      )) {
        $selectorJson = $section.Selector | ConvertTo-Json -Compress
        [void](Invoke-PageScript -Expression "document.documentElement.style.scrollBehavior='auto'; document.querySelector($selectorJson).scrollIntoView({block:'start'}); true")
        Start-Sleep -Milliseconds 750
        Save-CurrentScreenshot -Name "viewport-$width-$($section.Name)"
      }
    }
  }

  Write-Host 'Checking desktop interactions...'
  Set-ViewportAndLoad -Width 1280 -Height 900 -Url $pageUrl
  $structure = Invoke-PageScript -Expression @'
(() => {
  const ids = [...document.querySelectorAll('[id]')].map(element => element.id);
  const duplicateIds = ids.filter((id, index) => ids.indexOf(id) !== index);
  const blankRelIssues = [...document.querySelectorAll('a[target="_blank"]')].filter(link => {
    const rel = link.rel.split(/\s+/);
    return !rel.includes('noopener') || !rel.includes('noreferrer');
  }).length;
  return {
    duplicateIds,
    emptyLinks: document.querySelectorAll('a[href="#"]').length,
    positiveTabindex: [...document.querySelectorAll('[tabindex]')].filter(element => element.tabIndex > 0).length,
    missingImageAlts: [...document.images].filter(image => !image.hasAttribute('alt')).length,
    missingIframeTitles: [...document.querySelectorAll('iframe')].filter(frame => !frame.title.trim()).length,
    blankRelIssues,
    localSheetRules: [...document.styleSheets].filter(sheet => sheet.href && sheet.href.includes('/css/style.css')).map(sheet => sheet.cssRules.length),
    initialCaseHidden: document.querySelector('#real-work-detail').hidden,
    marqueeGroups: [...document.querySelectorAll('.marquee-group')].map(group => group.getBoundingClientRect().width),
    marqueeGap: Math.abs(document.querySelectorAll('.marquee-group')[1].getBoundingClientRect().left - document.querySelectorAll('.marquee-group')[0].getBoundingClientRect().right),
    navHrefs: [...document.querySelectorAll('#nav-menu a')].map(link => link.getAttribute('href'))
  };
})()
'@
  Assert-Audit (@($structure.duplicateIds).Count -eq 0) "Rendered page has duplicate IDs: $(@($structure.duplicateIds) -join ', ')."
  Assert-Audit ($structure.emptyLinks -eq 0) 'Rendered page has empty hash links.'
  Assert-Audit ($structure.positiveTabindex -eq 0) 'Rendered page has positive tabindex values.'
  Assert-Audit ($structure.missingImageAlts -eq 0) 'Rendered page has images without alt attributes.'
  Assert-Audit ($structure.missingIframeTitles -eq 0) 'Rendered page has iframes without titles.'
  Assert-Audit ($structure.blankRelIssues -eq 0) 'Rendered target=_blank links are missing rel protections.'
  Assert-Audit (@($structure.localSheetRules).Count -eq 1 -and $structure.localSheetRules[0] -gt 0) 'The local stylesheet did not parse into CSS rules.'
  Assert-Audit ([bool]$structure.initialCaseHidden) 'Case-study detail is visible before a project is selected.'
  Assert-Audit ([math]::Abs($structure.marqueeGroups[0] - $structure.marqueeGroups[1]) -lt 1) 'Ticker duplicate groups have different widths.'
  Assert-Audit ($structure.marqueeGap -lt 1) "Ticker has a visible inter-group gap of $($structure.marqueeGap) px."
  Assert-Audit (($structure.navHrefs -join ',') -eq '#workspace,#work,#process,#experience,#contact') "Navigation href order or targets are incorrect: $($structure.navHrefs -join ',')."

  $toggles = Invoke-PageScript -Expression @'
(() => {
  const theme = document.querySelector('#theme-toggle');
  const rain = document.querySelector('#rain-toggle');
  const marquee = document.querySelector('#marquee-toggle');
  const initialTheme = document.documentElement.dataset.theme;
  theme.click();
  const themeChanged = document.documentElement.dataset.theme !== initialTheme && theme.getAttribute('aria-pressed') === 'true';
  const initialRain = rain.getAttribute('aria-pressed');
  rain.click();
  const rainChanged = rain.getAttribute('aria-pressed') !== initialRain;
  marquee.click();
  const marqueePaused = marquee.getAttribute('aria-pressed') === 'true' && document.querySelector('.marquee-track').classList.contains('is-paused');
  marquee.click();
  return {
    themeChanged,
    rainChanged,
    marqueePaused,
    cardObjectFit:[...document.querySelectorAll('.real-work-thumb img')].map(image => getComputedStyle(image).objectFit),
    featuredObjectFit:getComputedStyle(document.querySelector('#real-work-featured-image')).objectFit,
    contactLabel:document.querySelector('label[for="contact-message"]')?.textContent.trim(),
    contactRequired:document.querySelector('#contact-message').required
  };
})()
'@
  Assert-Audit ($toggles.themeChanged -and $toggles.rainChanged -and $toggles.marqueePaused) 'Theme, rain, or scrolling-ticker controls did not update their accessible state.'
  Assert-Audit (@($toggles.cardObjectFit | Where-Object { $_ -ne 'contain' }).Count -eq 0 -and $toggles.featuredObjectFit -eq 'contain') 'One or more project images use a cropping object-fit value.'
  Assert-Audit (-not [string]::IsNullOrWhiteSpace($toggles.contactLabel) -and $toggles.contactRequired) 'Contact textarea label or required state is missing.'

  $roles = Test-AccessibilityTree -Context 'Desktop page'
  foreach ($requiredRole in @('banner', 'navigation', 'main', 'contentinfo')) {
    Assert-Audit ($roles -contains $requiredRole) "Accessibility tree is missing the '$requiredRole' landmark."
  }

  $navResult = Invoke-PageScript -Expression @'
(async () => {
  document.documentElement.style.scrollBehavior = 'auto';
  const tests = [['work','work'], ['workspace','workspace'], ['process','process'], ['experience','experience'], ['contact','contact']];
  const states = [];
  window.scrollTo(0, 0);
  await new Promise(resolve => setTimeout(resolve, 80));
  states.push({target:'about', active:[...document.querySelectorAll('#nav-menu .is-active')].map(link => link.dataset.nav)});
  for (const [id, expected] of tests) {
    document.getElementById(id).scrollIntoView({block:'start'});
    window.dispatchEvent(new Event('scroll'));
    await new Promise(resolve => requestAnimationFrame(() => setTimeout(resolve, 80)));
    states.push({target:id, expected, active:[...document.querySelectorAll('#nav-menu .is-active')].map(link => link.dataset.nav), current:[...document.querySelectorAll('#nav-menu [aria-current="location"]')].map(link => link.dataset.nav)});
  }
  return states;
})()
'@
  foreach ($state in $navResult) {
    if ($state.target -eq 'about') {
      Assert-Audit (@($state.active).Count -eq 0) 'A navigation item is highlighted in the unlabelled hero section.'
    } else {
      Assert-Audit (@($state.active).Count -eq 1 -and $state.active[0] -eq $state.expected) "Active navigation is wrong for $($state.target)."
      Assert-Audit (@($state.current).Count -eq 1 -and $state.current[0] -eq $state.expected) "aria-current is wrong for $($state.target)."
    }
  }

  $caseResult = Invoke-PageScript -Expression @'
(async () => {
  document.documentElement.style.scrollBehavior = 'auto';
  const trigger = document.querySelector('[data-case-study="akwaaba"]');
  trigger.click();
  await new Promise(resolve => setTimeout(resolve, 120));
  const opened = {
    hidden: document.querySelector('#real-work-detail').hidden,
    title: document.querySelector('#real-work-title').textContent,
    expanded: trigger.getAttribute('aria-expanded'),
    focus: document.activeElement.id
  };
  document.querySelector('#real-work-next').click();
  const nextCount = document.querySelector('#real-work-image-counter').textContent;
  document.querySelector('#real-work-prev').click();
  const previousCount = document.querySelector('#real-work-image-counter').textContent;
  document.querySelector('#real-work-featured').click();
  await new Promise(resolve => setTimeout(resolve, 60));
  const dialogOpened = document.querySelector('#gallery-lightbox').open;
  const lightboxStart = document.querySelector('#gallery-lightbox-image').src;
  document.querySelector('#gallery-lightbox-next').click();
  const lightboxChanged = document.querySelector('#gallery-lightbox-image').src !== lightboxStart;
  document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}));
  const dialogClosed = !document.querySelector('#gallery-lightbox').open;
  const lightboxFocusReturn = document.activeElement.id;
  document.querySelector('#real-work-detail-close').click();
  const closed = document.querySelector('#real-work-detail').hidden;
  return {opened, nextCount, previousCount, dialogOpened, lightboxChanged, dialogClosed, lightboxFocusReturn, closed, closeFocus:document.activeElement.dataset.caseStudy};
})()
'@
  Assert-Audit (-not $caseResult.opened.hidden -and $caseResult.opened.title -eq 'Akwaaba House') 'Akwaaba House case study did not open correctly.'
  Assert-Audit ($caseResult.opened.expanded -eq 'true' -and $caseResult.opened.focus -eq 'real-work-title') 'Case-study open focus or aria-expanded state is incorrect.'
  Assert-Audit ($caseResult.nextCount -eq '2 / 7' -and $caseResult.previousCount -eq '1 / 7') 'Case-study previous/next controls or image count are incorrect.'
  Assert-Audit ($caseResult.dialogOpened -and $caseResult.lightboxChanged -and $caseResult.dialogClosed) 'Expanded image dialog did not open, navigate, and close correctly.'
  Assert-Audit ($caseResult.lightboxFocusReturn -eq 'real-work-featured') 'Expanded image dialog did not return focus to its opener.'
  Assert-Audit ($caseResult.closed -and $caseResult.closeFocus -eq 'akwaaba') 'Case-study close did not hide the detail and return focus.'

  $counts = Invoke-PageScript -Expression @'
(() => {
  const output = {};
  for (const key of ['akwaaba','goldbar','wealthwise']) {
    document.querySelector(`[data-case-study="${key}"]`).click();
    output[key] = document.querySelector('#real-work-image-counter').textContent;
    document.querySelector('#real-work-detail-close').click();
  }
  return output;
})()
'@
  Assert-Audit ($counts.akwaaba -eq '1 / 7') "Akwaaba House image total is incorrect: $($counts.akwaaba)."
  Assert-Audit ($counts.goldbar -eq '1 / 12') "GoldBar Fitness image total is incorrect: $($counts.goldbar)."
  Assert-Audit ($counts.wealthwise -eq '1 / 6') "WealthWise image total is incorrect: $($counts.wealthwise)."

  $workspace = Invoke-PageScript -Expression @'
(async () => {
  const stage = document.querySelector('#workspace-stage');
  const total = Math.max(stage.offsetHeight - innerHeight, 1);
  window.scrollTo(0, stage.offsetTop + total * .45);
  window.dispatchEvent(new Event('scroll'));
  await new Promise(resolve => requestAnimationFrame(() => setTimeout(resolve, 120)));
  const ready = document.querySelector('#workspace-device').classList.contains('is-ready');
  document.querySelector('#workspace-turn-on').click();
  const output = {ready, powered:document.querySelector('#workspace-device').classList.contains('is-powered'), projects:{}};
  for (const key of ['akwaaba','goldbar','wealthwise']) {
    const launcher = document.querySelector(`.desktop-icon[data-project="${key}"]`);
    launcher.click();
    await new Promise(resolve => setTimeout(resolve, 40));
    output.projects[key] = {
      title: document.querySelector('#project-window-title').textContent,
      frame: document.querySelector('#project-frame').getAttribute('src'),
      open: document.querySelector('#project-browser-open').href,
      frameTitle: document.querySelector('#project-frame').title,
      visible: document.querySelector('#project-window').classList.contains('is-visible')
    };
    document.querySelector('#project-window-close').click();
  }
  const goldbarLauncher = document.querySelector('.desktop-icon[data-project="goldbar"]');
  goldbarLauncher.click();
  document.querySelector('#project-window-minimize').click();
  output.minimizedFocus = document.activeElement.dataset.project;
  goldbarLauncher.click();
  document.querySelector('#project-window-expand').click();
  output.expanded = document.querySelector('#project-window').classList.contains('is-expanded') && document.querySelector('#project-window-expand').getAttribute('aria-pressed') === 'true';
  document.querySelector('#project-window-close').click();
  output.closeFocus = document.activeElement.dataset.project;
  document.querySelector('#workspace-power').click();
  output.poweredOff = !document.querySelector('#workspace-device').classList.contains('is-powered') && document.activeElement.id === 'workspace-turn-on';
  return output;
})()
'@
  Assert-Audit ($workspace.ready -and $workspace.powered) 'Desktop laptop did not become ready and power on.'
  $expectedProjects = @{
    akwaaba = @{ Title = 'Akwaaba House'; Url = 'https://akwaabahouse.netlify.app/' }
    goldbar = @{ Title = 'GoldBar Fitness'; Url = 'https://goldbarfitness.netlify.app/' }
    wealthwise = @{ Title = 'WealthWise'; Url = 'https://wealthwiselt.netlify.app/' }
  }
  foreach ($key in $expectedProjects.Keys) {
    $actual = $workspace.projects.$key
    $expected = $expectedProjects[$key]
    Assert-Audit ($actual.visible -and $actual.title -eq $expected.Title -and $actual.frame -eq $expected.Url -and $actual.open -eq $expected.Url) "$($expected.Title) live project opened with incorrect data."
    Assert-Audit ($actual.frameTitle -eq "$($expected.Title) live website preview") "$($expected.Title) iframe title was not updated."
  }
  Assert-Audit ($workspace.minimizedFocus -eq 'goldbar' -and $workspace.expanded -and $workspace.closeFocus -eq 'goldbar') 'Project window minimize/expand/close state or focus return is incorrect.'
  Assert-Audit ($workspace.poweredOff) 'Power-off did not return focus to the Turn On control.'

  [void](Invoke-PageScript -Expression @'
(async () => {
  document.documentElement.dataset.theme = 'dark';
  const stage = document.querySelector('#workspace-stage');
  const total = Math.max(stage.offsetHeight - innerHeight, 1);
  window.scrollTo(0, stage.offsetTop + total * .45);
  window.dispatchEvent(new Event('scroll'));
  await new Promise(resolve => requestAnimationFrame(() => setTimeout(resolve, 150)));
  document.querySelector('#workspace-turn-on').click();
  document.querySelector('.desktop-icon[data-project="akwaaba"]').click();
  await new Promise(resolve => setTimeout(resolve, 1800));
  return true;
})()
'@)
  Save-CurrentScreenshot -Name 'workspace-open-1280-dark'

  Write-Host 'Checking mobile interactions...'
  Set-ViewportAndLoad -Width 375 -Height 812 -Url $pageUrl
  $mobile = Invoke-PageScript -Expression @'
(async () => {
  const toggle = document.querySelector('#nav-toggle');
  const menu = document.querySelector('#nav-menu');
  toggle.click();
  await new Promise(resolve => requestAnimationFrame(resolve));
  const opened = menu.classList.contains('is-open') && toggle.getAttribute('aria-expanded') === 'true' && document.activeElement === menu.querySelector('a');
  toggle.click();
  const hamburgerClosed = !menu.classList.contains('is-open');
  toggle.click();
  document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}));
  const escapeClosed = !menu.classList.contains('is-open') && document.activeElement === toggle;
  toggle.click();
  document.querySelector('main').dispatchEvent(new PointerEvent('pointerdown', {bubbles:true}));
  const outsideClosed = !menu.classList.contains('is-open');
  toggle.click();
  menu.querySelector('a[href="#contact"]').click();
  await new Promise(resolve => setTimeout(resolve, 80));
  const linkClosed = !menu.classList.contains('is-open');
  const directLinks = [...document.querySelectorAll('.mobile-project-link')].map(link => link.href);
  document.querySelector('[data-case-study="goldbar"]').click();
  await new Promise(resolve => setTimeout(resolve, 80));
  const dynamicOverflow = document.documentElement.scrollWidth > document.documentElement.clientWidth + 1;
  return {opened, hamburgerClosed, escapeClosed, outsideClosed, linkClosed, directLinks, dynamicOverflow};
})()
'@
  Assert-Audit ($mobile.opened) 'Mobile menu did not open with focus on its first link.'
  Assert-Audit ($mobile.hamburgerClosed -and $mobile.escapeClosed -and $mobile.outsideClosed -and $mobile.linkClosed) 'One or more mobile-menu closing methods failed.'
  Assert-Audit (($mobile.directLinks -join ',') -eq 'https://akwaabahouse.netlify.app/,https://goldbarfitness.netlify.app/,https://wealthwiselt.netlify.app/') 'Mobile direct live-project URLs are incorrect.'
  Assert-Audit (-not $mobile.dynamicOverflow) 'Opening a mobile case study creates horizontal overflow.'
  [void](Test-AccessibilityTree -Context 'Mobile page with a case study open')

  Write-Host 'Checking axe-core in dark and light themes...'
  $axeVersion = Invoke-PageScript -Expression @'
(async () => {
  if (window.axe) return window.axe.version;
  return await new Promise(resolve => {
    const script = document.createElement('script');
    const timer = setTimeout(() => resolve('unavailable'), 20000);
    script.src = 'https://unpkg.com/axe-core@latest/axe.min.js';
    script.onload = () => { clearTimeout(timer); resolve(window.axe?.version || 'unavailable'); };
    script.onerror = () => { clearTimeout(timer); resolve('unavailable'); };
    document.head.appendChild(script);
  });
})()
'@
  if ($axeVersion -ne 'unavailable') {
    $axeResult = Invoke-PageScript -Expression @'
(async () => {
  const options = {runOnly:{type:'tag', values:['wcag2a','wcag2aa','wcag21aa','wcag22aa']}};
  const collect = async theme => {
    const result = await axe.run(document, options);
    return {
      theme,
      violations:result.violations.map(item => ({id:item.id, impact:item.impact, targets:item.nodes.map(node => node.target.join(' '))})),
      incomplete:result.incomplete.map(item => ({id:item.id, targets:item.nodes.map(node => node.target.join(' '))}))
    };
  };
  document.documentElement.dataset.theme = 'dark';
  const dark = await collect('dark');
  document.documentElement.dataset.theme = 'light';
  const light = await collect('light');
  return [dark, light];
})()
'@
    foreach ($themeResult in $axeResult) {
      foreach ($violation in $themeResult.violations) {
        Add-Failure "axe $axeVersion $($themeResult.theme)-theme violation '$($violation.id)' ($($violation.impact)): $($violation.targets -join ', ')."
      }
      $incompleteSummary = @($themeResult.incomplete | ForEach-Object { "$($_.id): $($_.targets -join ', ')" }) -join '; '
      $axeSummary = "axe-core $axeVersion $($themeResult.theme) theme completed with $(@($themeResult.violations).Count) violation(s) and $(@($themeResult.incomplete).Count) incomplete check(s). $incompleteSummary"
      $auditSummary.Add($axeSummary)
      Write-Host $axeSummary
    }
  } else {
    $auditSummary.Add('axe-core could not be loaded from its CDN; accessibility-tree and DOM checks still ran.')
    Write-Warning 'axe-core could not be loaded from its CDN; accessibility-tree and DOM checks still ran.'
  }

  $designPageUrl = ([uri](Join-Path $projectRoot 'pages\design-process.html')).AbsoluteUri
  foreach ($designViewport in @(@{Width=320;Height=700}, @{Width=1440;Height=900})) {
    Write-Host "Checking design-process page at $($designViewport.Width) px..."
    Set-ViewportAndLoad -Width $designViewport.Width -Height $designViewport.Height -Url $designPageUrl
    $designPage = Invoke-PageScript -Expression @'
(() => ({
  title:document.title,
  h1:document.querySelector('h1')?.textContent.trim(),
  scrollWidth:document.documentElement.scrollWidth,
  clientWidth:document.documentElement.clientWidth,
  backHref:document.querySelector('.process-page-back')?.getAttribute('href'),
  errors:window.__portfolioAuditErrors || []
}))()
'@
    Assert-Audit ($designPage.title -eq 'Design Process | Leslie Tannor' -and -not [string]::IsNullOrWhiteSpace($designPage.h1)) "$($designViewport.Width) px design-process page has invalid title or heading."
    Assert-Audit ($designPage.scrollWidth -le ($designPage.clientWidth + 1)) "$($designViewport.Width) px design-process page has horizontal overflow."
    Assert-Audit ($designPage.backHref -eq '../index.html#process') 'Design-process back link is incorrect.'
    Assert-Audit (@($designPage.errors).Count -eq 0) "$($designViewport.Width) px design-process page reported JavaScript errors."
    Save-CurrentScreenshot -Name "design-process-$($designViewport.Width)"
  }

  $runtimeExceptions = @($script:events | Where-Object { $_.method -eq 'Runtime.exceptionThrown' })
  $severeLogs = @($script:events | Where-Object { $_.method -eq 'Log.entryAdded' -and $_.params.entry.level -eq 'error' })
  Assert-Audit ($runtimeExceptions.Count -eq 0) "Browser emitted $($runtimeExceptions.Count) uncaught runtime exception(s)."
  Assert-Audit ($severeLogs.Count -eq 0) "Browser log emitted $($severeLogs.Count) error(s)."

  if ($failures.Count -gt 0) {
    $auditSummary.Add("Browser validation failed with $($failures.Count) issue(s).")
    $failures | ForEach-Object { $auditSummary.Add("FAIL: $_") }
    $auditSummary | Set-Content -LiteralPath (Join-Path $reportRoot 'browser-summary.txt') -Encoding utf8
    Write-Host "Browser validation failed with $($failures.Count) issue(s):" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
  }

  $passSummary = 'Browser validation passed across 320, 375, 430, 768, 1024, 1280, 1440, and 1920 px, including navigation, focus, menus, case studies, galleries, live projects, layout, and accessibility-tree checks.'
  $auditSummary.Add($passSummary)
  $auditSummary | Set-Content -LiteralPath (Join-Path $reportRoot 'browser-summary.txt') -Encoding utf8
  Write-Host $passSummary -ForegroundColor Green
} finally {
  if ($script:socket -and $script:socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try { [void](Invoke-Cdp -Method 'Browser.close') } catch {}
    $script:socket.Dispose()
  }
  if ($browserProcess -and -not $browserProcess.HasExited) {
    Stop-Process -Id $browserProcess.Id -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $profilePath) {
    Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue
  }
}
