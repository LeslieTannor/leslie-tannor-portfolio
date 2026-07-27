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
    $readTimeout = [System.Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(60))
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
    $description = $response.exceptionDetails.exception.description
    $location = if ($response.exceptionDetails.lineNumber -ne $null) { " at line $($response.exceptionDetails.lineNumber)" } else { '' }
    throw "Browser script failed$location`: $($response.exceptionDetails.text) $description"
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
  [void](Invoke-Cdp -Method 'Page.navigate' -Params @{ url = "${Url}?viewport=$Width&browser-audit=1" })
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
window.__portfolioAuditCLS = 0;
window.__portfolioAuditLongTasks = 0;
window.addEventListener('error', event => window.__portfolioAuditErrors.push(String(event.message || event.error)));
window.addEventListener('unhandledrejection', event => window.__portfolioAuditErrors.push(String(event.reason)));
try {
  new PerformanceObserver(list => {
    for (const entry of list.getEntries()) {
      if (!entry.hadRecentInput) window.__portfolioAuditCLS += entry.value;
    }
  }).observe({type:'layout-shift', buffered:true});
  new PerformanceObserver(list => {
    for (const entry of list.getEntries()) window.__portfolioAuditLongTasks += entry.duration;
  }).observe({type:'longtask', buffered:true});
} catch {}
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
  const device = document.querySelector('#workspace-device');
  const reveal = document.querySelector('#workspace-reveal');
  const mobileLinks = document.querySelector('.mobile-project-links');
  const footer = document.querySelector('.footer-bar').getBoundingClientRect();
  return {
    scrollWidth: root.scrollWidth,
    clientWidth: root.clientWidth,
    overflowers,
    stageDisplay: getComputedStyle(stage).display,
    stageRevealed: stage.classList.contains('is-revealed'),
    deviceHidden: device.getAttribute('aria-hidden'),
    deviceInert: device.inert,
    revealDisplay: getComputedStyle(reveal).display,
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
      Assert-Audit ($layout.revealDisplay -eq 'none') "$width px viewport still displays the desktop reveal control."
      Assert-Audit ($layout.mobileLinksDisplay -ne 'none') "$width px viewport does not display direct live-project links."
    } else {
      Assert-Audit ($layout.stageDisplay -ne 'none') "$width px viewport hides the desktop laptop presentation."
      Assert-Audit (-not $layout.stageRevealed -and $layout.deviceHidden -eq 'true' -and $layout.deviceInert -and $layout.revealDisplay -ne 'none') "$width px viewport does not keep the laptop concealed behind its reveal control."
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

  $auditSummary.Add('Responsive viewport matrix completed.')

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
    footerArtCount:document.querySelectorAll('.footer-art-image').length,
    themeControlCount:document.querySelectorAll('.floating-tools .tool-btn').length,
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
  Assert-Audit ($structure.footerArtCount -eq 2 -and $structure.themeControlCount -eq 1) 'Footer art or the single theme control is incorrect.'
  Assert-Audit ([math]::Abs($structure.marqueeGroups[0] - $structure.marqueeGroups[1]) -lt 1) 'Ticker duplicate groups have different widths.'
  Assert-Audit ($structure.marqueeGap -lt 1) "Ticker has a visible inter-group gap of $($structure.marqueeGap) px."
  Assert-Audit (($structure.navHrefs -join ',') -eq '#workspace,#work,#process,#experience,#contact') "Navigation href order or targets are incorrect: $($structure.navHrefs -join ',')."

  $toggles = Invoke-PageScript -Expression @'
(() => {
  const theme = document.querySelector('#theme-toggle');
  const marquee = document.querySelector('#marquee-toggle');
  const initialTheme = document.documentElement.dataset.theme;
  theme.click();
  const themeChanged = document.documentElement.dataset.theme !== initialTheme && theme.getAttribute('aria-pressed') === 'true';
  marquee.click();
  const marqueePaused = marquee.getAttribute('aria-pressed') === 'true' && document.querySelector('.marquee-track').classList.contains('is-paused');
  marquee.click();
  return {
    themeChanged,
    marqueePaused,
    cardObjectFit:[...document.querySelectorAll('.real-work-thumb img')].map(image => getComputedStyle(image).objectFit),
    featuredObjectFit:getComputedStyle(document.querySelector('#real-work-featured-image')).objectFit,
    contactLabel:document.querySelector('label[for="contact-message"]')?.textContent.trim(),
    contactRequired:document.querySelector('#contact-message').required,
    heroBootColor:getComputedStyle(document.querySelector('.hero-boot-state p')).color,
    workspaceBootColor:getComputedStyle(document.querySelector('.workspace-boot-title')).color
  };
})()
'@
  Assert-Audit ($toggles.themeChanged -and $toggles.marqueePaused) 'Theme or scrolling-ticker controls did not update their accessible state.'
  Assert-Audit (@($toggles.cardObjectFit | Where-Object { $_ -ne 'contain' }).Count -eq 0 -and $toggles.featuredObjectFit -eq 'contain') 'One or more project images use a cropping object-fit value.'
  Assert-Audit (-not [string]::IsNullOrWhiteSpace($toggles.contactLabel) -and $toggles.contactRequired) 'Contact textarea label or required state is missing.'
  Assert-Audit ($toggles.heroBootColor -eq 'rgb(246, 247, 242)' -and $toggles.workspaceBootColor -eq 'rgb(244, 247, 251)') 'Fixed dark-device typography loses contrast in light mode.'
  Save-CurrentScreenshot -Name 'viewport-1280-light'
  $auditSummary.Add('Desktop structure and persistent controls completed.')

  $contactForm = Invoke-PageScript -Expression @'
(() => {
  const form = document.querySelector('.contact-form');
  const name = document.querySelector('#contact-name');
  const email = document.querySelector('#contact-email');
  const message = document.querySelector('#contact-message');
  form.dispatchEvent(new SubmitEvent('submit', {bubbles:true, cancelable:true}));
  const blank = {
    focus:document.activeElement.id,
    invalid:[name, email, message].map(field => field.getAttribute('aria-invalid')),
    errors:[...document.querySelectorAll('.form-error')].map(error => error.textContent.trim())
  };
  name.value = 'Portfolio visitor';
  email.value = 'visitor@example.com';
  message.value = 'A concise project request with enough context.';
  for (const field of [name, email, message]) field.dispatchEvent(new Event('input', {bubbles:true}));
  return {
    blank,
    valid:form.checkValidity(),
    noValidate:form.noValidate,
    autocomplete:[name.autocomplete, email.autocomplete],
    describedBy:[name, email, message].map(field => field.getAttribute('aria-describedby')),
    selectStyles:(() => {
      const select = document.querySelector('#contact-project-type');
      const option = select.options[0];
      return {color:getComputedStyle(select).color, optionColor:getComputedStyle(option).color, optionBackground:getComputedStyle(option).backgroundColor};
    })(),
    submitHeight:form.querySelector('button[type="submit"]').getBoundingClientRect().height,
    disclosure:document.querySelector('#contact-instructions').textContent.trim()
  };
})()
'@
  Assert-Audit ($contactForm.blank.focus -eq 'contact-name' -and @($contactForm.blank.invalid | Where-Object { $_ -ne 'true' }).Count -eq 0) 'Blank contact submission did not focus and mark the first invalid field.'
  Assert-Audit (@($contactForm.blank.errors | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) 'Contact form did not provide a visible error for every required field.'
  Assert-Audit ($contactForm.valid -and $contactForm.noValidate -and ($contactForm.autocomplete -join ',') -eq 'name,email') 'Contact form validity, custom-validation, or autocomplete metadata is incorrect.'
  Assert-Audit (@($contactForm.describedBy | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) 'A contact field is not associated with instructions or an error message.'
  Assert-Audit ($contactForm.selectStyles.optionColor -ne $contactForm.selectStyles.optionBackground -and $contactForm.selectStyles.optionColor -eq 'rgb(20, 25, 35)') 'Contact dropdown options do not use a visible light-theme text colour.'
  Assert-Audit ($contactForm.submitHeight -ge 44 -and $contactForm.disclosure -match 'email draft') 'Contact action is too small or its truthful mail-draft disclosure is missing.'
  $auditSummary.Add('Contact-form validation completed.')

  $performance = Invoke-PageScript -Expression @'
(() => {
  const navigation = performance.getEntriesByType('navigation')[0];
  const resources = performance.getEntriesByType('resource');
  const fcp = performance.getEntriesByName('first-contentful-paint')[0];
  return {
    domContentLoaded:Math.round(navigation?.domContentLoadedEventEnd || 0),
    load:Math.round(navigation?.loadEventEnd || 0),
    fcp:Math.round(fcp?.startTime || 0),
    cls:Number((window.__portfolioAuditCLS || 0).toFixed(4)),
    longTasks:Math.round(window.__portfolioAuditLongTasks || 0),
    resources:resources.length,
    transferred:resources.reduce((total, entry) => total + (entry.transferSize || 0), 0),
    domNodes:document.querySelectorAll('*').length
  };
})()
'@
  $auditSummary.Add("Observed local-load diagnostics at 1280 px: FCP=$($performance.fcp) ms, DOMContentLoaded=$($performance.domContentLoaded) ms, load=$($performance.load) ms, CLS=$($performance.cls), long tasks=$($performance.longTasks) ms, DOM nodes=$($performance.domNodes), resources=$($performance.resources), transferred bytes=$($performance.transferred).")
  Assert-Audit ($performance.cls -lt 0.1) "Observed cumulative layout shift is $($performance.cls), above the 0.1 audit threshold."

  [void](Invoke-PageScript -Expression "document.documentElement.style.scrollBehavior='auto'; document.querySelector('footer').scrollIntoView({behavior:'instant', block:'start'}); true")
  Start-Sleep -Milliseconds 300
  Save-CurrentScreenshot -Name 'viewport-1280-footer-light'

  $roles = Test-AccessibilityTree -Context 'Desktop page'
  foreach ($requiredRole in @('banner', 'navigation', 'main', 'contentinfo')) {
    Assert-Audit ($roles -contains $requiredRole) "Accessibility tree is missing the '$requiredRole' landmark."
  }

  $navResult = Invoke-PageScript -Expression @'
(async () => {
  document.documentElement.style.scrollBehavior = 'auto';
  document.activeElement?.blur();
  const tests = [['work','work'], ['workspace','workspace'], ['process','process'], ['experience','experience'], ['contact','contact']];
  const states = [];
  const activeKeys = () => [...document.querySelectorAll('#nav-menu .is-active')].map(link => link.dataset.nav);
  const currentKeys = () => [...document.querySelectorAll('#nav-menu [aria-current="location"]')].map(link => link.dataset.nav);
  const layoutTop = element => {
    let top = 0;
    for (let current = element; current; current = current.offsetParent) top += current.offsetTop || 0;
    return top;
  };
  const settle = async expected => {
    for (let attempt = 0; attempt < 36; attempt += 1) {
      await new Promise(resolve => setTimeout(resolve, 50));
      const active = activeKeys();
      if (expected ? active.length === 1 && active[0] === expected : active.length === 0) return;
    }
  };
  window.scrollTo({top:0, behavior:'instant'});
  await settle(null);
  states.push({target:'about', active:activeKeys()});
  for (const [id, expected] of tests) {
    window.scrollTo({top:layoutTop(document.getElementById(id)), behavior:'instant'});
    window.dispatchEvent(new Event('scroll'));
    await settle(expected);
    states.push({target:id, expected, active:activeKeys(), current:currentKeys()});
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

  $showcase = Invoke-PageScript -Expression @'
(async () => {
  const track = document.querySelector('#showcase-track');
  const cards = [...track.querySelectorAll('.real-work-card')];
  const position = document.querySelector('#showcase-position');
  const previous = document.querySelector('#showcase-prev');
  const next = document.querySelector('#showcase-next');
  const initial = {
    position:position.textContent,
    current:track.querySelector('.is-current')?.dataset.caseStudyCard,
    previousDisabled:previous.disabled,
    scrollable:track.scrollWidth > track.clientWidth,
    cardViewportRatio:Number((cards[0].getBoundingClientRect().width / innerWidth).toFixed(2)),
    backgrounds:cards.map(card => getComputedStyle(card).backgroundImage)
  };
  next.click();
  await new Promise(resolve => setTimeout(resolve, 600));
  const second = {position:position.textContent, current:track.querySelector('.is-current')?.dataset.caseStudyCard, scrollLeft:track.scrollLeft};
  track.dispatchEvent(new KeyboardEvent('keydown', {key:'ArrowRight', bubbles:true}));
  await new Promise(resolve => setTimeout(resolve, 600));
  const third = {position:position.textContent, current:track.querySelector('.is-current')?.dataset.caseStudyCard, nextDisabled:next.disabled};
  previous.click();
  previous.click();
  await new Promise(resolve => setTimeout(resolve, 600));
  return {initial, second, third};
})()
'@
  Assert-Audit ($showcase.initial.position -eq '01 / 03' -and $showcase.initial.current -eq 'akwaaba' -and $showcase.initial.previousDisabled) 'Horizontal project showcase did not initialise on the first project.'
  Assert-Audit ($showcase.initial.scrollable -and $showcase.initial.cardViewportRatio -ge .7 -and @($showcase.initial.backgrounds | Select-Object -Unique).Count -eq 3) 'Project showcase is not full-width, horizontally scrollable, or visually distinct.'
  Assert-Audit ($showcase.second.position -eq '02 / 03' -and $showcase.second.current -eq 'goldbar' -and $showcase.second.scrollLeft -gt 0) 'Project showcase next control did not move to GoldBar Fitness.'
  Assert-Audit ($showcase.third.position -eq '03 / 03' -and $showcase.third.current -eq 'wealthwise' -and $showcase.third.nextDisabled) 'Project showcase keyboard navigation did not reach WealthWise.'

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

  [void](Invoke-PageScript -Expression @'
(async () => {
  document.querySelector('[data-case-study="wealthwise"]').click();
  await new Promise(resolve => setTimeout(resolve, 500));
  return true;
})()
'@)
  Save-CurrentScreenshot -Name 'case-study-1280-dark'
  [void](Invoke-PageScript -Expression "document.querySelector('#real-work-detail-close').click(); true")

  $workspace = Invoke-PageScript -Expression @'
(async () => {
  const stage = document.querySelector('#workspace-stage');
  const device = document.querySelector('#workspace-device');
  const reveal = document.querySelector('#workspace-reveal');
  document.documentElement.style.scrollBehavior = 'auto';
  const initial = {
    revealed:stage.classList.contains('is-revealed'),
    hidden:device.getAttribute('aria-hidden'),
    inert:device.inert,
    expanded:reveal.getAttribute('aria-expanded')
  };
  reveal.click();
  await new Promise(resolve => setTimeout(resolve, 1250));
  const ready = device.classList.contains('is-ready');
  const laptopRect = document.querySelector('#workspace-laptop').getBoundingClientRect();
  const output = {
    initial,
    ready,
    powered:device.classList.contains('is-powered'),
    revealed:stage.classList.contains('is-revealed'),
    hidden:device.getAttribute('aria-hidden'),
    inert:device.inert,
    expanded:reveal.getAttribute('aria-expanded'),
    laptopRect:{top:laptopRect.top, bottom:laptopRect.bottom, height:laptopRect.height, viewportHeight:innerHeight},
    closeLabel:document.querySelector('#workspace-power span')?.textContent.trim(),
    projects:{}
  };
  for (const key of ['akwaaba','goldbar','wealthwise']) {
    const launcher = document.querySelector(`.desktop-icon[data-project="${key}"]`);
    launcher.click();
    await new Promise(resolve => setTimeout(resolve, 40));
    output.projects[key] = {
      title: document.querySelector('#project-window-title').textContent,
      frame: document.querySelector('#project-frame').dataset.requestedSrc || document.querySelector('#project-frame').getAttribute('src'),
      open: document.querySelector('#project-browser-open').href,
      frameTitle: document.querySelector('#project-frame').title,
      visible: document.querySelector('#project-window').classList.contains('is-visible'),
      closeWorkspaceVisible:(() => {
        const control = document.querySelector('#workspace-power');
        const style = getComputedStyle(control);
        return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity) > .99;
      })()
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
  await new Promise(resolve => setTimeout(resolve, 180));
  output.poweredOff = !device.classList.contains('is-powered') && !stage.classList.contains('is-revealed') && device.getAttribute('aria-hidden') === 'true' && device.inert && reveal.getAttribute('aria-expanded') === 'false' && document.activeElement.id === 'workspace-reveal' && document.querySelector('#project-frame').getAttribute('src') === 'about:blank';
  return output;
})()
'@
  Assert-Audit (-not $workspace.initial.revealed -and $workspace.initial.hidden -eq 'true' -and $workspace.initial.inert -and $workspace.initial.expanded -eq 'false') 'Desktop laptop is not concealed before the reveal action.'
  Assert-Audit ($workspace.ready -and $workspace.powered -and $workspace.revealed -and $workspace.hidden -eq 'false' -and -not $workspace.inert -and $workspace.expanded -eq 'true') "Desktop laptop did not reveal, open, and power on: $($workspace | ConvertTo-Json -Compress -Depth 3)."
  Assert-Audit ($workspace.laptopRect.top -ge -1 -and $workspace.laptopRect.bottom -le ($workspace.laptopRect.viewportHeight + 1) -and $workspace.closeLabel -eq 'Close workspace') "Revealed laptop is clipped or its close action is ambiguous: $($workspace.laptopRect | ConvertTo-Json -Compress)."
  $expectedProjects = @{
    akwaaba = @{ Title = 'Akwaaba House'; Url = 'https://akwaabahouse.netlify.app/' }
    goldbar = @{ Title = 'GoldBar Fitness'; Url = 'https://goldbarfitness.netlify.app/' }
    wealthwise = @{ Title = 'WealthWise'; Url = 'https://wealthwiselt.netlify.app/' }
  }
  foreach ($key in $expectedProjects.Keys) {
    $actual = $workspace.projects.$key
    $expected = $expectedProjects[$key]
    Assert-Audit ($actual.visible -and $actual.closeWorkspaceVisible -and $actual.title -eq $expected.Title -and $actual.frame -eq $expected.Url -and $actual.open -eq $expected.Url) "$($expected.Title) live project opened with incorrect data or hid the Close workspace control."
    Assert-Audit ($actual.frameTitle -eq "$($expected.Title) live website preview") "$($expected.Title) iframe title was not updated."
  }
  Assert-Audit ($workspace.minimizedFocus -eq 'goldbar' -and $workspace.expanded -and $workspace.closeFocus -eq 'goldbar') 'Project window minimize/expand/close state or focus return is incorrect.'
  Assert-Audit ($workspace.poweredOff) 'Power-off did not close the laptop, clear its preview, and return focus to the reveal control.'

  [void](Invoke-PageScript -Expression @'
(async () => {
  document.documentElement.dataset.theme = 'dark';
  document.querySelector('#workspace-reveal').click();
  await new Promise(resolve => setTimeout(resolve, 900));
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
  const openedState = {menuOpen:menu.classList.contains('is-open'), expanded:toggle.getAttribute('aria-expanded'), focusTag:document.activeElement?.tagName, focusHref:document.activeElement?.getAttribute?.('href')};
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
  return {opened, openedState, hamburgerClosed, escapeClosed, outsideClosed, linkClosed, directLinks, dynamicOverflow};
})()
'@
  Assert-Audit ($mobile.opened) "Mobile menu did not open with focus on its first link: $($mobile | ConvertTo-Json -Compress -Depth 3)."
  Assert-Audit ($mobile.hamburgerClosed -and $mobile.escapeClosed -and $mobile.outsideClosed -and $mobile.linkClosed) 'One or more mobile-menu closing methods failed.'
  Assert-Audit (($mobile.directLinks -join ',') -eq 'https://akwaabahouse.netlify.app/,https://goldbarfitness.netlify.app/,https://wealthwiselt.netlify.app/') 'Mobile direct live-project URLs are incorrect.'
  Assert-Audit (-not $mobile.dynamicOverflow) 'Opening a mobile case study creates horizontal overflow.'
  [void](Invoke-PageScript -Expression "document.querySelector('#real-work-detail').scrollIntoView({block:'start', behavior:'instant'}); true")
  Start-Sleep -Milliseconds 350
  $mobileTargets = Invoke-PageScript -Expression @'
(() => [...document.querySelectorAll('#nav-toggle, #theme-toggle, #real-work-detail-close, #real-work-prev, #real-work-next')]
  .filter(element => getComputedStyle(element).display !== 'none')
  .map(element => ({name:element.id, width:Math.round(element.getBoundingClientRect().width), height:Math.round(element.getBoundingClientRect().height)})))()
'@
  foreach ($target in $mobileTargets) {
    Assert-Audit ($target.width -ge 44 -and $target.height -ge 44) "Mobile control $($target.name) is only $($target.width) x $($target.height) px."
  }
  Save-CurrentScreenshot -Name 'case-study-375-dark'
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

  Write-Host 'Checking reduced-motion behavior...'
  [void](Invoke-Cdp -Method 'Emulation.setEmulatedMedia' -Params @{ features = @(@{ name = 'prefers-reduced-motion'; value = 'reduce' }) })
  Set-ViewportAndLoad -Width 1280 -Height 900 -Url $pageUrl
  $reducedMotion = Invoke-PageScript -Expression @'
(async () => {
  const stage = document.querySelector('#workspace-stage');
  const device = document.querySelector('#workspace-device');
  const result = {
    matches:matchMedia('(prefers-reduced-motion: reduce)').matches,
    heroStickyPosition:getComputedStyle(document.querySelector('.hero-sticky')).position,
    footerArtAnimation:getComputedStyle(document.querySelector('.footer-art-image--clarity')).animationName,
    alternateFooterArtDisplay:getComputedStyle(document.querySelector('.footer-art-image--direction')).display,
    marqueeAnimation:getComputedStyle(document.querySelector('.marquee-track')).animationName,
    duplicateTickerDisplay:getComputedStyle(document.querySelector('.marquee-group[aria-hidden="true"]')).display,
    hiddenReveals:[...document.querySelectorAll('.reveal')].filter(element => Number(getComputedStyle(element).opacity) < .99).length,
    workspaceInitialHeight:stage.getBoundingClientRect().height,
    workspaceInitialHidden:device.getAttribute('aria-hidden')
  };
  document.querySelector('#workspace-reveal').click();
  await new Promise(resolve => setTimeout(resolve, 60));
  result.workspaceRevealed = stage.classList.contains('is-revealed') && device.classList.contains('is-powered') && device.getAttribute('aria-hidden') === 'false';
  result.errors = window.__portfolioAuditErrors || [];
  return result;
})()
'@
  Assert-Audit ($reducedMotion.matches -and $reducedMotion.heroStickyPosition -eq 'relative') 'Reduced-motion preference did not disable the sticky cinematic hero.'
  Assert-Audit ($reducedMotion.footerArtAnimation -eq 'none' -and $reducedMotion.alternateFooterArtDisplay -eq 'none' -and $reducedMotion.marqueeAnimation -eq 'none' -and $reducedMotion.duplicateTickerDisplay -eq 'none') 'Reduced-motion preference left decorative or looping motion active.'
  Assert-Audit ($reducedMotion.workspaceInitialHeight -eq 0 -and $reducedMotion.workspaceInitialHidden -eq 'true' -and $reducedMotion.workspaceRevealed) 'Reduced-motion mode exposes an empty laptop stage or prevents the explicit reveal.'
  Assert-Audit ($reducedMotion.hiddenReveals -eq 0 -and @($reducedMotion.errors).Count -eq 0) 'Reduced-motion mode hides content or emitted a runtime error.'
  [void](Invoke-Cdp -Method 'Emulation.setEmulatedMedia' -Params @{ features = @(@{ name = 'prefers-reduced-motion'; value = 'no-preference' }) })

  Write-Host 'Checking 200% reflow equivalent...'
  Set-ViewportAndLoad -Width 640 -Height 450 -Url $pageUrl
  $zoomReflow = Invoke-PageScript -Expression @'
(() => ({
  scrollWidth:document.documentElement.scrollWidth,
  clientWidth:document.documentElement.clientWidth,
  menuButtonVisible:getComputedStyle(document.querySelector('#nav-toggle')).display !== 'none',
  desktopDeviceHidden:getComputedStyle(document.querySelector('.workspace-stage')).display === 'none',
  errors:window.__portfolioAuditErrors || []
}))()
'@
  Assert-Audit ($zoomReflow.scrollWidth -le ($zoomReflow.clientWidth + 1) -and $zoomReflow.menuButtonVisible -and $zoomReflow.desktopDeviceHidden) 'The 1280 px layout did not reflow cleanly at a 200% equivalent CSS viewport.'
  Assert-Audit (@($zoomReflow.errors).Count -eq 0) 'The 200% reflow-equivalent check emitted JavaScript errors.'
  $auditSummary.Add('200% reflow equivalent passed at a 640 CSS-pixel viewport for a 1280 px display.')

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

  $passSummary = 'Browser validation passed across 320, 375, 430, 768, 1024, 1280, 1440, and 1920 px, including navigation, focus, menus, forms, case studies, galleries, live projects, reduced motion, 200% reflow, layout, and accessibility-tree checks.'
  $auditSummary.Add($passSummary)
  $auditSummary | Set-Content -LiteralPath (Join-Path $reportRoot 'browser-summary.txt') -Encoding utf8
  Write-Host $passSummary -ForegroundColor Green
} catch {
  $fatalMessage = "Browser audit aborted: $($_.Exception.Message)"
  $auditSummary.Add($fatalMessage)
  $auditSummary | Set-Content -LiteralPath (Join-Path $reportRoot 'browser-summary.txt') -Encoding utf8
  Write-Host $fatalMessage -ForegroundColor Red
  throw
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
